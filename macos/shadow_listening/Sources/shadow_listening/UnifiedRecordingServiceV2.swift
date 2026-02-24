import AVFAudio
import Accelerate
import OSLog

// MARK: - UnifiedRecordingServiceV2

/// 통합 녹음 서비스 V2
///
/// UnifiedAudioService를 사용하여 Mic + System Audio를 통합 캡처
/// - 48kHz에서 믹싱 → 16kHz 리샘플링 (AECAudioService 패턴)
/// - 5초 고정 청크 단위 처리
/// - VAD로 음성 있는 청크만 필터링
/// - ASR과 Diarization 동시 처리
@available(macOS 14.0, *)
final class UnifiedRecordingServiceV2 {
    private let logger = Logger(subsystem: "shadow_listening", category: "UnifiedRecordingV2")

    // MARK: - Audio Services

    private var audioService: UnifiedAudioService?
    private var audioFileWriter: AudioFileWriter?

    // MARK: - Processing Services

    private var vadService: VADService?
    private var asrService: ASRServiceProtocol?
    private var diarizerService: FluidDiarizerService?

    // MARK: - Mic VAD (내가 말한 구간 추적)

    private var micVADService: VADService?
    private var lastMicSegmentCount: Int = 0

    // MARK: - Chunk Buffer

    private var chunkBuffer: [Float] = []
    private var chunkStartTime: Double = 0
    private let chunkDuration: Double = 5.0  // 5초 청크
    private let minChunkDuration: Double = 3.0  // 최소 3초
    private let sampleRate: Double = 16000

    // MARK: - Results

    private var transcriptions: [TranscriptionSegment] = []
    private var speakerSegments: [SpeakerSegment] = []
    private var recordedFileURL: URL?

    // MARK: - Tasks

    private var recordingTask: Task<Void, Never>?

    /// 현재 진행 중인 청크 처리 Task (ASR + Diarization)
    private var currentChunkTask: Task<Void, Never>?

    // MARK: - RMS (Volume Level)

    /// RMS 업데이트 콜백 (0.0 ~ 1.0, EMA 스무딩 적용)
    var onRMSUpdate: ((Float) -> Void)?

    /// EMA 스무딩용 이전 RMS 값
    private var smoothedRMS: Float = 0

    // MARK: - State

    private var isRecording: Bool = false
    private var isStopping: Bool = false
    private var isCancelled: Bool = false
    private var chunkIndex: Int = 0

    // MARK: - Configuration

    struct Config {
        var enableASR: Bool = true
        var enableDiarization: Bool = true
        var enableSystemAudio: Bool = true
        var asrEngine: String = "fluid"
        var chunkDuration: Double = 5.0
        var sessionId: String?
    }

    private var config: Config = Config()

    // MARK: - Initialization

    init() {
        logger.info("UnifiedRecordingServiceV2 created")
    }

    // MARK: - Public Methods

    func startRecording(
        config: Config,
        asrService: ASRServiceProtocol?,
        diarizerService: FluidDiarizerService?
    ) async throws -> URL {
        guard !isRecording else {
            logger.warning("[UnifiedRecordingV2] Already recording")
            throw AudioServiceError.alreadyInProgress
        }

        self.config = config
        self.asrService = asrService
        self.diarizerService = diarizerService

        // Reset state
        chunkBuffer.removeAll()
        chunkStartTime = 0
        chunkIndex = 0
        transcriptions.removeAll()
        speakerSegments.removeAll()
        isStopping = false
        isCancelled = false

        // Initialize UnifiedAudioService
        audioService = UnifiedAudioService()
        audioService?.enableSystemAudioMixing = config.enableSystemAudio

        // Initialize file writer
        do {
            audioFileWriter = try AudioFileWriter()
        } catch {
            FlutterBridge.shared.invokeError(code: .audioInitFailed, message: error.localizedDescription)
            throw error
        }

        // Initialize VAD (혼합 오디오용)
        do {
            vadService = VADService()
            try await vadService?.initialize()
            await vadService?.reset()
        } catch {
            FlutterBridge.shared.invokeError(code: .vadInitFailed, message: error.localizedDescription)
            throw error
        }

        // Initialize Mic VAD (내가 말한 구간 추적용)
        do {
            micVADService = VADService()
            try await micVADService?.initialize()
            await micVADService?.reset()
            lastMicSegmentCount = 0
        } catch {
            FlutterBridge.shared.invokeError(code: .vadInitFailed, message: error.localizedDescription)
            throw error
        }

        // Reset Diarizer (새 세션)
        if config.enableDiarization {
            await diarizerService?.reset()
        }

        // Start file writing
        let outputURL: URL
        if let sessionId = config.sessionId {
            outputURL = AudioFileWriter.outputURL(exactFilename: "\(sessionId)-MergedAudio")
        } else {
            outputURL = AudioFileWriter.defaultOutputURL(filename: "unified_v2_recording")
        }
        do {
            try audioFileWriter?.startWriting(to: outputURL)
        } catch {
            FlutterBridge.shared.invokeError(code: .audioWriteFailed, message: error.localizedDescription)
            throw error
        }
        recordedFileURL = outputURL

        // Start audio capture
        do {
            try audioService?.startListening()
        } catch {
            FlutterBridge.shared.invokeError(code: .audioInitFailed, message: error.localizedDescription)
            throw error
        }

        // Main processing loop
        recordingTask = Task { [weak self] in
            await self?.processAudioStream()
        }

        isRecording = true
        logger.info("[UnifiedRecordingV2] Started: ASR=\(config.enableASR), Diarization=\(config.enableDiarization), SysAudio=\(config.enableSystemAudio)")

        return outputURL
    }

    func stopRecording() async throws -> UnifiedRecordingResult {
        guard isRecording else {
            logger.warning("[UnifiedRecordingV2] Not recording")
            throw AudioServiceError.notInProgress
        }

        guard !isStopping else {
            logger.warning("[UnifiedRecordingV2] Stop already in progress, ignoring duplicate call")
            throw AudioServiceError.notInProgress
        }

        isStopping = true
        logger.info("[UnifiedRecordingV2] Stop requested, finishing queued chunks...")

        // 1) 새 버퍼 유입 중지 + 스트림 종료
        audioService?.stopListening()

        // 2) 스트림 소비 루프 종료 대기
        if let task = recordingTask {
            await task.value
        }
        recordingTask = nil

        // 3) 실제 녹음 길이 계산 (패딩 전)
        let totalDuration = chunkStartTime + Double(chunkBuffer.count) / sampleRate

        // 4) MicVAD finalize - 진행 중인 세그먼트 종료 (endTime 설정)
        micVADService?.finalize()
        

        
        // 5) 남은 버퍼를 큐에 추가 (무손실)
        let chunkSize = Int(chunkDuration * sampleRate)
        var lastEnqueuedAsFinal = false

        while chunkBuffer.count >= chunkSize {
            let chunk = Array(chunkBuffer.prefix(chunkSize))
            chunkBuffer.removeFirst(chunkSize)
            let startTime = chunkStartTime
            let chunkEndTime = startTime + chunkDuration
            logger.info("[UnifiedRecordingV2] Queueing remaining full chunk: \(String(format: "%.1f", startTime))s-\(String(format: "%.1f", chunkEndTime))s")
            enqueueChunkForProcessing(chunk, startTime: startTime, endTime: chunkEndTime)
            chunkStartTime = chunkEndTime
        }

        // 남은 버퍼 처리 (>= 1초면 처리)
        if !chunkBuffer.isEmpty {
            let remainingDuration = Double(chunkBuffer.count) / sampleRate
            if remainingDuration >= 1.0 {
                var finalChunk = chunkBuffer
                var finalDuration = remainingDuration

                if remainingDuration < minChunkDuration && config.enableDiarization {
                    let paddingNeeded = Int((minChunkDuration - remainingDuration) * sampleRate)
                    finalChunk.append(contentsOf: [Float](repeating: 0.0, count: paddingNeeded))
                    finalDuration = minChunkDuration
                    logger.info("[UnifiedRecordingV2] Padded final chunk: \(String(format: "%.2f", remainingDuration))s → \(String(format: "%.2f", finalDuration))s")
                } else {
                    logger.info("[UnifiedRecordingV2] Queueing final chunk: \(String(format: "%.2f", remainingDuration))s")
                }

                let startTime = chunkStartTime
                let endTime = startTime + finalDuration
                enqueueChunkForProcessing(finalChunk, startTime: startTime, endTime: endTime, isFinalChunk: true)
                lastEnqueuedAsFinal = true
                chunkStartTime = endTime
            } else {
                logger.info("[UnifiedRecordingV2] Discarding final chunk: \(String(format: "%.2f", remainingDuration))s (< 1s)")
            }
        }
        chunkBuffer.removeAll()

        // If no remainder was enqueued as final, send a standalone final signal
        if !lastEnqueuedAsFinal {
            let previousTask = currentChunkTask
            let sessionId = config.sessionId
            let finalNotifyTask = Task { [weak self] in
                if let previousTask { await previousTask.value }
                FlutterBridge.shared.invokeOnChunkProcessed(
                    chunkIndex: self?.chunkIndex ?? 0,
                    startTime: totalDuration,
                    endTime: totalDuration,
                    micVADSegments: [],
                    transcription: nil,
                    diarizations: [],
                    isFinalChunk: true,
                    sessionId: sessionId
                )
            }
            currentChunkTask = finalNotifyTask
        }

        // 6) 큐 전체 drain 대기
        if let chunkTask = currentChunkTask {
            logger.info("[UnifiedRecordingV2] Waiting for queued chunk tasks to complete...")
            await chunkTask.value
        }
        currentChunkTask = nil

        // 7) 파일 writer flush
        audioFileWriter?.stopWriting()

        // 결과 백업 (cleanup 전에 보존)
        let finalTranscriptions = transcriptions
        let finalSpeakerSegments = speakerSegments

        isRecording = false
        isStopping = false

        // Cleanup all resources
        audioService = nil
        audioFileWriter = nil
        vadService = nil
        micVADService = nil
        asrService = nil
        diarizerService = nil
        onRMSUpdate = nil
        smoothedRMS = 0

        // Clear result arrays
        transcriptions.removeAll()
        speakerSegments.removeAll()

        logger.info("[UnifiedRecordingV2] Completed: \(finalTranscriptions.count) transcriptions, \(finalSpeakerSegments.count) speaker segments, \(String(format: "%.1f", totalDuration))s total")

        return UnifiedRecordingResult(
            audioFilePath: recordedFileURL?.path ?? "",
            transcriptions: finalTranscriptions,
            speakerSegments: finalSpeakerSegments,
            totalDuration: totalDuration
        )
    }

    /// In-flight 작업(녹음 루프 + ASR/Diarization)이 완료될 때까지 대기.
    /// cancelRecording()과 독립적 — isCancelled 상태와 무관하게 안전하게 대기 가능.
    /// 모델 unload 전에 호출하여 whisper_full() 완료를 보장.
    func waitForInFlightTasks() async {
        if let task = recordingTask { await task.value }
        if let task = currentChunkTask { await task.value }
    }

    /// 녹음 취소 — 결과 폐기, Flutter로 청크 전송 중단
    func cancelRecording() async {
        guard !isCancelled else {
            logger.info("[UnifiedRecordingV2] cancelRecording ignored — already cancelled")
            return
        }

        isCancelled = true
        logger.info("[UnifiedRecordingV2] Cancel requested — hard stop")

        // Stop audio input
        audioService?.stopListening()

        // Wait for stream loop to end
        if let task = recordingTask { await task.value }
        recordingTask = nil

        // Wait for in-progress ASR to finish safely (do NOT cancel — whisper_full() is a
        // non-cancellable C call; cancelling the Task could let us proceed to resource cleanup
        // while the C engine is still running, causing use-after-free crashes).
        // The isCancelled flag above already prevents new chunks from being processed.
        if let task = currentChunkTask {
            logger.info("[UnifiedRecordingV2] Waiting for in-progress ASR to finish safely...")
            await task.value
        }
        currentChunkTask = nil

        // Discard remaining buffer
        chunkBuffer.removeAll()

        // Stop file writer
        audioFileWriter?.stopWriting()

        // Full cleanup
        isRecording = false
        isStopping = false
        audioService = nil
        audioFileWriter = nil
        vadService = nil
        micVADService = nil
        asrService = nil
        diarizerService = nil
        onRMSUpdate = nil
        smoothedRMS = 0
        transcriptions.removeAll()
        speakerSegments.removeAll()

        logger.info("[UnifiedRecordingV2] Cancel complete — all resources cleaned up")
    }

    // MARK: - Private Methods

    private func processAudioStream() async {
        guard let audioService = audioService,
              let writer = audioFileWriter else { return }

        let mixedStream = audioService.audioStream
        let micStream = audioService.micOnlyStream

        // 두 스트림을 병렬로 처리
        await withTaskGroup(of: Void.self) { group in
            // Mixed audio stream (파일 저장 + 청크 처리)
            group.addTask { [weak self] in
                guard let self = self else { return }

                for await buffer in mixedStream {
                    // 이미 믹싱된 16kHz 버퍼

                    // 1. Write to file
                    writer.write(buffer)

                    // 2. Extract samples
                    guard let floatData = buffer.floatChannelData?[0] else { continue }
                    let samples = Array(UnsafeBufferPointer(
                        start: floatData,
                        count: Int(buffer.frameLength)
                    ))

                    // 2.5. Update RMS (volume level)
                    self.updateRMS(from: samples)

                    // 3. Add to chunk buffer
                    self.chunkBuffer.append(contentsOf: samples)

                    // 4. Check if chunk is ready (5초)
                    let chunkSize = Int(self.chunkDuration * self.sampleRate)
                    while self.chunkBuffer.count >= chunkSize && !self.isStopping && !self.isCancelled {
                        let chunk = Array(self.chunkBuffer.prefix(chunkSize))
                        self.chunkBuffer.removeFirst(chunkSize)

                        let startTime = self.chunkStartTime
                        let endTime = startTime + self.chunkDuration
                        self.enqueueChunkForProcessing(chunk, startTime: startTime, endTime: endTime)
                        self.chunkStartTime = endTime
                    }
                }
            }

            // Mic-only stream (VAD 처리)
            group.addTask { [weak self] in
                guard let self = self else { return }

                for await micBuffer in micStream {
                    if let vad = self.micVADService {
                        try? await vad.processChunk(micBuffer)
                    }
                }
            }
        }
    }

    /// 청크 처리 큐에 작업 추가.
    /// 이전 작업이 끝난 뒤 실행하도록 체인하여 순서를 보장한다.
    private func enqueueChunkForProcessing(_ samples: [Float], startTime: Double, endTime: Double, isFinalChunk: Bool = false) {
        let previousTask = currentChunkTask
        let chunkTask = Task { [weak self] in
            if let previousTask = previousTask {
                await previousTask.value
            }
            guard let self = self else { return }
            await self.processChunk(samples, startTime: startTime, endTime: endTime, isFinalChunk: isFinalChunk)
        }
        currentChunkTask = chunkTask
    }

    private func processChunk(_ samples: [Float], startTime: Double, endTime: Double, isFinalChunk: Bool = false) async {
        guard !isCancelled, !Task.isCancelled else { return }

        let hasSpeech = await checkSpeechInChunk(samples)

        if !hasSpeech {
            logger.info("[UnifiedRecordingV2] Chunk \(String(format: "%.1f", startTime))s-\(String(format: "%.1f", endTime))s: No speech, skipping")
            if isFinalChunk {
                // Still notify Flutter that this is the final chunk even though VAD skipped it
                sendChunkResultToFlutter(
                    chunkIndex: chunkIndex,
                    startTime: startTime,
                    endTime: endTime,
                    micVADSegments: [],
                    transcription: nil,
                    diarizations: [],
                    isFinalChunk: true
                )
                chunkIndex += 1
            }
            return
        }

        let currentChunkIndex = chunkIndex
        chunkIndex += 1

        logger.info("[UnifiedRecordingV2] Processing chunk#\(currentChunkIndex) \(String(format: "%.1f", startTime))s-\(String(format: "%.1f", endTime))s")

        var chunkTranscription: TranscriptionSegment?
        var chunkDiarizations: [SpeakerSegment] = []

        await withTaskGroup(of: ChunkProcessingResult.self) { group in
            if config.enableASR, let asr = asrService, asr.isInitialized {
                group.addTask {
                    return await self.processASRForChunk(samples: samples, startTime: startTime, endTime: endTime)
                }
            }

            if config.enableDiarization, let diarizer = diarizerService, diarizer.isInitialized {
                group.addTask {
                    return await self.processDiarizationForChunk(samples: samples, startTime: startTime, endTime: endTime)
                }
            }

            for await result in group {
                switch result {
                case .transcription(let segment):
                    chunkTranscription = segment
                    transcriptions.append(segment)
                case .diarization(let segments):
                    chunkDiarizations = segments
                    speakerSegments.append(contentsOf: segments)
                case .none:
                    break
                }
            }
        }

        // MicVAD 세그먼트 추출
        let micVADSegments = extractNewMicVADSegments(startTime: startTime, endTime: endTime)

        // Flutter로 청크 결과 전송
        sendChunkResultToFlutter(
            chunkIndex: currentChunkIndex,
            startTime: startTime,
            endTime: endTime,
            micVADSegments: micVADSegments,
            transcription: chunkTranscription,
            diarizations: chunkDiarizations,
            isFinalChunk: isFinalChunk
        )
    }

    /// MicVAD에서 새로 감지된 세그먼트 추출
    private func extractNewMicVADSegments(startTime: Double, endTime: Double) -> [(startTime: Double, endTime: Double)] {
        guard let vad = micVADService else { return [] }

        // 1. 완료된 세그먼트 (기존 로직)
        let allSegments = vad.getSpeechSegments()
        let newSegments = Array(allSegments.dropFirst(lastMicSegmentCount))
        lastMicSegmentCount = allSegments.count

        var result: [(startTime: Double, endTime: Double)] = newSegments.compactMap { segment in
            guard let end = segment.endTime else { return nil }
            if end >= startTime && segment.startTime <= endTime {
                return (startTime: segment.startTime, endTime: end)
            }
            return nil
        }

        // 2. 진행 중인 세그먼트: 유저가 현재 말하고 있으면
        //    청크 범위로 clamp해서 포함 (micVADSegments가 []인 문제 방지)
        if let current = vad.getCurrentSegment(), current.endTime == nil {
            if current.startTime <= endTime {
                let clampedStart = max(current.startTime, startTime)
                result.append((startTime: clampedStart, endTime: endTime))
            }
        }

        return result
    }

    private enum ChunkProcessingResult {
        case transcription(TranscriptionSegment)
        case diarization([SpeakerSegment])
        case none
    }

    private func processASRForChunk(samples: [Float], startTime: Double, endTime: Double) async -> ChunkProcessingResult {
        guard let asr = asrService else { return .none }

        do {
            let result = try await asr.processSegment(
                samples: samples,
                startTime: startTime,
                endTime: endTime
            )
            logger.info("[UnifiedRecordingV2] ASR: '\(result.text)' (\(String(format: "%.1f", startTime))s-\(String(format: "%.1f", endTime))s, conf: \(String(format: "%.2f", result.confidence)))")
            return .transcription(result)
        } catch {
            logger.error("[UnifiedRecordingV2] ASR failed: \(error.localizedDescription)")
            FlutterBridge.shared.invokeError(code: .asrProcessingFailed, message: error.localizedDescription)
            return .none
        }
    }

    private func processDiarizationForChunk(samples: [Float], startTime: Double, endTime: Double) async -> ChunkProcessingResult {
        guard let diarizer = diarizerService else { return .none }

        do {
            let segments = try await diarizer.processSegment(
                samples: samples,
                startTime: startTime,
                endTime: endTime
            )
            logger.info("[UnifiedRecordingV2] Diarization: \(segments.count) segments")
            for segment in segments {
                logger.debug("  \(segment.speakerId): \(String(format: "%.2f", segment.startTime))s - \(String(format: "%.2f", segment.endTime))s")
            }
            return .diarization(segments)
        } catch {
            logger.error("[UnifiedRecordingV2] Diarization failed: \(error.localizedDescription)")
            FlutterBridge.shared.invokeError(code: .diarizationProcessingFailed, message: error.localizedDescription)
            return .none
        }
    }

    private func sendChunkResultToFlutter(
        chunkIndex: Int,
        startTime: Double,
        endTime: Double,
        micVADSegments: [(startTime: Double, endTime: Double)],
        transcription: TranscriptionSegment?,
        diarizations: [SpeakerSegment],
        isFinalChunk: Bool = false
    ) {
        guard !isCancelled else {
            logger.info("[UnifiedRecordingV2] Cancelled — dropping chunk#\(chunkIndex)")
            return
        }

        let micVADData = micVADSegments.map {
            FlutterBridge.MicVADSegmentData(startTime: $0.startTime, endTime: $0.endTime)
        }

        let transcriptionData: FlutterBridge.TranscriptionData?
        if let t = transcription {
            transcriptionData = FlutterBridge.TranscriptionData(
                text: t.text,
                startTime: t.startTime,
                endTime: t.endTime,
                confidence: t.confidence
            )
        } else {
            transcriptionData = nil
        }

        let diarizationData = diarizations.map {
            FlutterBridge.DiarizationData(
                speakerId: $0.speakerId,
                startTime: $0.startTime,
                endTime: $0.endTime,
                confidence: $0.confidence
            )
        }

        FlutterBridge.shared.invokeOnChunkProcessed(
            chunkIndex: chunkIndex,
            startTime: startTime,
            endTime: endTime,
            micVADSegments: micVADData,
            transcription: transcriptionData,
            diarizations: diarizationData,
            isFinalChunk: isFinalChunk,
            sessionId: config.sessionId
        )
    }

    /// 오디오 샘플에서 RMS 계산 → EMA 스무딩 → 콜백 전송
    ///
    /// - vDSP_rmsqv: SIMD 최적화 RMS 계산 (~2μs for 512 samples)
    /// - dB 정규화: -40dB→0.0, -10dB→1.0 (30dB range, 일반 대화 레벨에 최적화)
    /// - EMA α=0.3: 이전 값 70% 유지 → ~150ms 만에 90% 반영
    private func updateRMS(from samples: [Float]) {
        guard onRMSUpdate != nil else { return }

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))

        let db = 20 * log10(max(rms, 1e-8))
        // -40dB (silence) → 0.0, -10dB (loud speech) → 1.0
        let normalized = Float(max(0, min(1, (db + 40) / 30)))

        smoothedRMS = 0.3 * normalized + 0.7 * smoothedRMS
        onRMSUpdate?(smoothedRMS)
    }

    private func checkSpeechInChunk(_ samples: [Float]) async -> Bool {
        guard let vad = vadService else { return true }

        do {
            await vad.reset()

            let frameSize = 4096
            var speechFrameCount = 0
            var totalFrames = 0

            var offset = 0
            while offset + frameSize <= samples.count {
                let frame = Array(samples[offset..<(offset + frameSize)])
                let result = try await vad.processChunk(frame)

                if result.probability > 0.5 {
                    speechFrameCount += 1
                }
                totalFrames += 1
                offset += frameSize
            }

            let speechRatio = totalFrames > 0 ? Double(speechFrameCount) / Double(totalFrames) : 0
            let hasSpeech = speechRatio > 0.3

            logger.debug("[UnifiedRecordingV2] VAD: \(speechFrameCount)/\(totalFrames) frames (\(String(format: "%.0f", speechRatio * 100))%) → \(hasSpeech ? "SPEECH" : "silence")")

            return hasSpeech
        } catch {
            logger.warning("[UnifiedRecordingV2] VAD check failed: \(error.localizedDescription), processing anyway")
            FlutterBridge.shared.invokeError(code: .vadCheckFailed, message: error.localizedDescription)
            return true
        }
    }
}
