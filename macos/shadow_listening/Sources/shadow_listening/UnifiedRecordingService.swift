import AVFAudio
import OSLog

// MARK: - UnifiedRecordingService

/// 통합 녹음 서비스
///
/// Mic + Sys → Mixer → 5초 청크 → VAD 체크 → ASR + Diarizer (동시 처리)
///
/// ## 주요 기능
/// - 마이크 + 시스템 오디오 믹싱
/// - 5초 고정 청크 단위 처리
/// - VAD로 음성 있는 청크만 필터링
/// - ASR과 Diarization 동시 처리
///
/// ## 사용 예시
/// ```swift
/// let service = UnifiedRecordingService()
/// let config = UnifiedRecordingService.Config(enableASR: true, enableDiarization: true)
/// let fileURL = try await service.startRecording(config: config, asrService: asr, diarizerService: diarizer)
/// // ... 녹음 진행 ...
/// let result = try await service.stopRecording()
/// ```
final class UnifiedRecordingService {
    private let logger = Logger(subsystem: "shadow_listening", category: "UnifiedRecording")

    // MARK: - Audio Services

    private var micService: MicAudioService?
    private var sysAudioService: SystemAudioService?
    private var audioMixer: AudioMixer?
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
    private var sysAudioStreamTask: Task<Void, Never>?

    /// 현재 진행 중인 청크 처리 Task (ASR + Diarization)
    private var currentChunkTask: Task<Void, Never>?

    // MARK: - State

    private var isRecording: Bool = false
    private var isStopping: Bool = false  // 중지 요청 플래그
    private var chunkIndex: Int = 0  // 청크 인덱스 (Flutter 전송용)

    // MARK: - Configuration

    struct Config {
        var enableASR: Bool = true
        var enableDiarization: Bool = true
        var asrEngine: String = "fluid"  // "whisper" or "fluid"
        var chunkDuration: Double = 5.0
    }

    private var config: Config = Config()

    // MARK: - Initialization

    init() {
        logger.info("UnifiedRecordingService created")
    }

    // MARK: - Public Methods

    /// 통합 녹음 시작
    ///
    /// - Parameters:
    ///   - config: 녹음 설정 (ASR/Diarization ON/OFF 등)
    ///   - asrService: ASR 서비스 (미리 로드된 상태)
    ///   - diarizerService: Diarizer 서비스 (미리 로드된 상태)
    /// - Returns: 녹음 파일 URL
    func startRecording(
        config: Config,
        asrService: ASRServiceProtocol?,
        diarizerService: FluidDiarizerService?
    ) async throws -> URL {
        guard !isRecording else {
            logger.warning("[UnifiedRecording] Already recording")
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
        isStopping = false  // 중지 플래그 초기화

        // Initialize audio services
        audioMixer = try AudioMixer()
        audioFileWriter = try AudioFileWriter()
        micService = MicAudioService()
        sysAudioService = SystemAudioService()

        // Initialize VAD (혼합 오디오용)
        vadService = VADService()
        try await vadService?.initialize()
        await vadService?.reset()

        // Initialize Mic VAD (내가 말한 구간 추적용)
        micVADService = VADService()
        try await micVADService?.initialize()
        await micVADService?.reset()
        lastMicSegmentCount = 0

        // Reset Diarizer (새 세션)
        if config.enableDiarization {
            await diarizerService?.reset()
        }

        // Start system audio capture
        try sysAudioService?.startListening()

        // Start file writing
        let outputURL = AudioFileWriter.defaultOutputURL(filename: "unified_recording")
        try audioFileWriter?.startWriting(to: outputURL)
        recordedFileURL = outputURL

        // System Audio → RingBuffer
        sysAudioStreamTask = Task { [weak self] in
            guard let stream = self?.sysAudioService?.audioStream,
                  let mixer = self?.audioMixer else { return }
            for await buffer in stream {
                mixer.enqueueSysAudio(buffer)
            }
        }

        // Start mic capture
        try micService?.startListening()

        // Mic 시작과 동시에 System Audio 버퍼 리셋
        // System Audio가 먼저 쌓여있던 데이터를 버리고 동기화
        audioMixer?.reset()

        // Main processing loop
        recordingTask = Task { [weak self] in
            await self?.processAudioStream()
        }

        isRecording = true
        logger.info("[UnifiedRecording] Started: ASR=\(config.enableASR), Diarization=\(config.enableDiarization), engine=\(config.asrEngine)")

        return outputURL
    }

    /// 통합 녹음 중지 및 결과 반환
    ///
    /// - Returns: 녹음 결과 (전사 + 화자 세그먼트)
    func stopRecording() async throws -> UnifiedRecordingResult {
        guard isRecording else {
            logger.warning("[UnifiedRecording] Not recording")
            throw AudioServiceError.notInProgress
        }

        // 중지 플래그 설정 - 새로운 청크 처리 방지
        isStopping = true
        logger.info("[UnifiedRecording] Stop requested, waiting for current chunk processing...")

        // 진행 중인 청크 처리 완료 대기 (최대 10초)
        if let chunkTask = currentChunkTask {
            logger.info("[UnifiedRecording] Waiting for current chunk task to complete...")
            _ = await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await chunkTask.value
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)  // 10초 타임아웃
                }
                await group.next()  // 먼저 완료되는 것 대기
                group.cancelAll()
            }
            logger.info("[UnifiedRecording] Chunk task completed or timed out")
        }

        // Cancel streaming tasks (청크 처리 완료 후)
        recordingTask?.cancel()
        recordingTask = nil
        sysAudioStreamTask?.cancel()
        sysAudioStreamTask = nil
        currentChunkTask = nil

        // Stop services
        micService?.stopListening()
        sysAudioService?.stopListening()
        audioFileWriter?.stopWriting()
        audioMixer?.reset()

        // 진행 중인 마이크 음성 구간 강제 종료 및 최종 로깅
        micVADService?.finalize()
        let finalMicSegments = micVADService?.getSpeechSegments() ?? []
        if finalMicSegments.count > lastMicSegmentCount {
            let newSegments = Array(finalMicSegments[lastMicSegmentCount...])
            for segment in newSegments {
                let endTimeStr = segment.endTime != nil ? String(format: "%.2f", segment.endTime!) : "unknown"
                logger.info("[MicVAD] My speech (final): \(String(format: "%.2f", segment.startTime))s - \(endTimeStr)s")
            }
        }
        logger.info("[MicVAD] Total my speech segments: \(finalMicSegments.count)")

        // Process remaining buffer
        // 1. 먼저 5초 단위로 처리 가능한 청크들 처리
        let chunkSize = Int(chunkDuration * sampleRate)
        while chunkBuffer.count >= chunkSize {
            let chunk = Array(chunkBuffer.prefix(chunkSize))
            chunkBuffer.removeFirst(chunkSize)
            let chunkEndTime = chunkStartTime + chunkDuration
            logger.info("[UnifiedRecording] Processing remaining full chunk: \(String(format: "%.1f", self.chunkStartTime))s-\(String(format: "%.1f", chunkEndTime))s")
            await processChunk(chunk, startTime: chunkStartTime, endTime: chunkEndTime)
            chunkStartTime = chunkEndTime
        }

        // 2. 남은 버퍼 처리 (>= 1초면 처리)
        if !chunkBuffer.isEmpty {
            let remainingDuration = Double(chunkBuffer.count) / sampleRate
            if remainingDuration >= 1.0 {
                var finalChunk = chunkBuffer
                var finalDuration = remainingDuration

                // Diarization 최소 3초 요구 → silence 패딩
                let minDiarizationDuration = 3.0
                if remainingDuration < minDiarizationDuration && config.enableDiarization {
                    let paddingNeeded = Int((minDiarizationDuration - remainingDuration) * sampleRate)
                    finalChunk.append(contentsOf: [Float](repeating: 0.0, count: paddingNeeded))
                    finalDuration = minDiarizationDuration
                    logger.info("[UnifiedRecording] Padded final chunk: \(String(format: "%.2f", remainingDuration))s → \(String(format: "%.2f", finalDuration))s")
                } else {
                    logger.info("[UnifiedRecording] Processing final chunk: \(String(format: "%.2f", remainingDuration))s")
                }

                await processChunk(finalChunk, startTime: chunkStartTime, endTime: chunkStartTime + finalDuration)
            } else {
                logger.info("[UnifiedRecording] Discarding final chunk: \(String(format: "%.2f", remainingDuration))s (< 1s)")
            }
        }

        let totalDuration = chunkStartTime + Double(chunkBuffer.count) / sampleRate
        chunkBuffer.removeAll()

        isRecording = false
        isStopping = false  // 플래그 리셋

        logger.info("[UnifiedRecording] Completed: \(self.transcriptions.count) transcriptions, \(self.speakerSegments.count) speaker segments, \(String(format: "%.1f", totalDuration))s total")

        return UnifiedRecordingResult(
            audioFilePath: recordedFileURL?.path ?? "",
            transcriptions: transcriptions,
            speakerSegments: speakerSegments,
            totalDuration: totalDuration
        )
    }

    // MARK: - Private Methods

    private func processAudioStream() async {
        guard let stream = micService?.audioStream,
              let mixer = audioMixer,
              let writer = audioFileWriter else { return }

        for await micBuffer in stream {
            // 0. Mic VAD 처리 (믹싱 전에! - 내가 말한 구간 추적)
            try? await micVADService?.processChunk(micBuffer)

            // 1. Mix
            guard let mixed = mixer.mix(micBuffer: micBuffer) else { continue }

            // 2. Write to file (전체 오디오)
            writer.write(mixed)

            // 3. Extract samples
            guard let floatData = mixed.floatChannelData?[0] else { continue }
            let samples = Array(UnsafeBufferPointer(
                start: floatData,
                count: Int(mixed.frameLength)
            ))

            // 4. Add to chunk buffer
            chunkBuffer.append(contentsOf: samples)

            // 5. Check if chunk is ready (5초)
            let chunkSize = Int(chunkDuration * sampleRate)
            while chunkBuffer.count >= chunkSize && !isStopping {
                // Extract chunk
                let chunk = Array(chunkBuffer.prefix(chunkSize))
                chunkBuffer.removeFirst(chunkSize)

                let chunkEndTime = chunkStartTime + chunkDuration

                // Process chunk (async) - Task로 추적
                let chunkTask = Task {
                    await self.processChunk(chunk, startTime: self.chunkStartTime, endTime: chunkEndTime)
                }
                currentChunkTask = chunkTask
                await chunkTask.value  // 청크 처리 완료 대기
                currentChunkTask = nil

                chunkStartTime = chunkEndTime
            }
        }
    }

    private func processChunk(_ samples: [Float], startTime: Double, endTime: Double) async {
        // VAD Check: 이 청크에 음성이 있는가?
        let hasSpeech = await checkSpeechInChunk(samples)

        if !hasSpeech {
            logger.info("[UnifiedRecording] Chunk \(String(format: "%.1f", startTime))s-\(String(format: "%.1f", endTime))s: No speech, skipping (use voice to see events!)")
            return
        }

        let currentChunkIndex = chunkIndex
        chunkIndex += 1

        logger.info("[UnifiedRecording] Processing chunk#\(currentChunkIndex) \(String(format: "%.1f", startTime))s-\(String(format: "%.1f", endTime))s")

        // 결과 수집용 변수
        var chunkTranscription: TranscriptionSegment?
        var chunkDiarizations: [SpeakerSegment] = []

        // Parallel processing: ASR + Diarization (결과 수집)
        await withTaskGroup(of: ChunkProcessingResult.self) { group in
            // ASR Task
            if config.enableASR, let asr = asrService, asr.isInitialized {
                group.addTask {
                    return await self.processASRForChunk(samples: samples, startTime: startTime, endTime: endTime)
                }
            }

            // Diarization Task
            if config.enableDiarization, let diarizer = diarizerService, diarizer.isInitialized {
                group.addTask {
                    return await self.processDiarizationForChunk(samples: samples, startTime: startTime, endTime: endTime)
                }
            }

            // 결과 수집
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

        // MicVAD 세그먼트 수집
        let micVADSegments = collectNewMicSegments()

        // Flutter로 청크 결과 전송
        sendChunkResultToFlutter(
            chunkIndex: currentChunkIndex,
            startTime: startTime,
            endTime: endTime,
            micVADSegments: micVADSegments,
            transcription: chunkTranscription,
            diarizations: chunkDiarizations
        )
    }

    /// 청크 처리 결과 타입
    private enum ChunkProcessingResult {
        case transcription(TranscriptionSegment)
        case diarization([SpeakerSegment])
        case none
    }

    /// ASR 처리 (청크 결과 반환용)
    private func processASRForChunk(samples: [Float], startTime: Double, endTime: Double) async -> ChunkProcessingResult {
        guard let asr = asrService else { return .none }

        do {
            let result = try await asr.processSegment(
                samples: samples,
                startTime: startTime,
                endTime: endTime
            )
            logger.info("[UnifiedRecording] ASR: '\(result.text)' (\(String(format: "%.1f", startTime))s-\(String(format: "%.1f", endTime))s, conf: \(String(format: "%.2f", result.confidence)))")
            return .transcription(result)
        } catch {
            logger.error("[UnifiedRecording] ASR failed: \(error.localizedDescription)")
            return .none
        }
    }

    /// Diarization 처리 (청크 결과 반환용)
    private func processDiarizationForChunk(samples: [Float], startTime: Double, endTime: Double) async -> ChunkProcessingResult {
        guard let diarizer = diarizerService else { return .none }

        do {
            let segments = try await diarizer.processSegment(
                samples: samples,
                startTime: startTime,
                endTime: endTime
            )
            logger.info("[UnifiedRecording] Diarization: \(segments.count) segments")
            for segment in segments {
                logger.debug("  \(segment.speakerId): \(String(format: "%.2f", segment.startTime))s - \(String(format: "%.2f", segment.endTime))s")
            }
            return .diarization(segments)
        } catch {
            logger.error("[UnifiedRecording] Diarization failed: \(error.localizedDescription)")
            return .none
        }
    }

    /// 새로 감지된 MicVAD 세그먼트 수집
    private func collectNewMicSegments() -> [(startTime: Double, endTime: Double)] {
        guard let micVAD = micVADService else { return [] }

        let allSegments = micVAD.getSpeechSegments()
        var newCompletedSegments: [(startTime: Double, endTime: Double)] = []

        if allSegments.count > lastMicSegmentCount {
            let newSegments = Array(allSegments[lastMicSegmentCount...])
            lastMicSegmentCount = allSegments.count

            for segment in newSegments {
                if let endTime = segment.endTime {
                    newCompletedSegments.append((startTime: segment.startTime, endTime: endTime))
                    logger.info("[MicVAD] My speech: \(String(format: "%.2f", segment.startTime))s - \(String(format: "%.2f", endTime))s")
                } else {
                    logger.info("[MicVAD] My speech: \(String(format: "%.2f", segment.startTime))s - ongoing")
                }
            }
        }

        return newCompletedSegments
    }

    /// Flutter로 청크 결과 전송
    private func sendChunkResultToFlutter(
        chunkIndex: Int,
        startTime: Double,
        endTime: Double,
        micVADSegments: [(startTime: Double, endTime: Double)],
        transcription: TranscriptionSegment?,
        diarizations: [SpeakerSegment]
    ) {
        // MicVAD 변환
        let micVADData = micVADSegments.map {
            FlutterBridge.MicVADSegmentData(startTime: $0.startTime, endTime: $0.endTime)
        }

        // Transcription 변환
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

        // Diarization 변환
        let diarizationData = diarizations.map {
            FlutterBridge.DiarizationData(
                speakerId: $0.speakerId,
                startTime: $0.startTime,
                endTime: $0.endTime,
                confidence: $0.confidence
            )
        }

        // FlutterBridge로 전송
        FlutterBridge.shared.invokeOnChunkProcessed(
            chunkIndex: chunkIndex,
            startTime: startTime,
            endTime: endTime,
            micVADSegments: micVADData,
            transcription: transcriptionData,
            diarizations: diarizationData
        )
    }

    private func checkSpeechInChunk(_ samples: [Float]) async -> Bool {
        guard let vad = vadService else { return true }  // VAD 없으면 모든 청크 처리

        do {
            // VAD 상태 리셋 (청크별 독립 처리)
            await vad.reset()

            // VAD 처리 (전체 청크를 작은 프레임으로 나눠서)
            let frameSize = 4096  // 256ms @ 16kHz
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

            // 청크의 30% 이상이 음성이면 처리
            let speechRatio = totalFrames > 0 ? Double(speechFrameCount) / Double(totalFrames) : 0
            let hasSpeech = speechRatio > 0.3

            logger.debug("[UnifiedRecording] VAD: \(speechFrameCount)/\(totalFrames) frames (\(String(format: "%.0f", speechRatio * 100))%) → \(hasSpeech ? "SPEECH" : "silence")")

            return hasSpeech
        } catch {
            logger.warning("[UnifiedRecording] VAD check failed: \(error.localizedDescription), processing anyway")
            return true  // 에러 시 처리
        }
    }

}

// MARK: - Result Types

/// 통합 녹음 결과
struct UnifiedRecordingResult {
    /// 녹음된 오디오 파일 경로
    let audioFilePath: String

    /// ASR 전사 결과
    let transcriptions: [TranscriptionSegment]

    /// 화자 세그먼트 결과
    let speakerSegments: [SpeakerSegment]

    /// 총 녹음 시간 (초)
    let totalDuration: Double

    /// 고유 화자 수
    var speakerCount: Int {
        Set(speakerSegments.map { $0.speakerId }).count
    }

    /// Dictionary로 변환 (Flutter 반환용)
    func toDictionary() -> [String: Any] {
        return [
            "audioFilePath": audioFilePath,
            "transcriptions": transcriptions.map { [
                "text": $0.text,
                "startTime": $0.startTime,
                "endTime": $0.endTime,
                "confidence": $0.confidence
            ]},
            "speakerSegments": speakerSegments.map { [
                "speakerId": $0.speakerId,
                "startTime": $0.startTime,
                "endTime": $0.endTime,
                "confidence": $0.confidence
            ]},
            "speakerCount": speakerCount,
            "totalDuration": totalDuration
        ]
    }
}

