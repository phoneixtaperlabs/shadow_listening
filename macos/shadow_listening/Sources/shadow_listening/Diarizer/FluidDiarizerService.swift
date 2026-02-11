import AVFAudio
import CoreML
import FluidAudio
import OSLog

// MARK: - FluidDiarizerService

/// FluidAudio 기반 Speaker Diarization 서비스
///
/// pyannote segmentation + WeSpeaker embedding을 사용하여
/// "누가 언제 말했는지" 분석합니다.
///
/// ## 모델 구성
/// - `pyannote_segmentation.mlmodelc`: VAD + 음성 세그멘테이션
/// - `wespeaker_v2.mlmodelc`: 화자 임베딩 추출
///
/// ## 사용 예시
/// ```swift
/// let service = FluidDiarizerService()
/// try await service.initialize()
/// let result = try await service.processFile(audioURL)
/// for segment in result.segments {
///     print("\(segment.speakerId): \(segment.startTime)s - \(segment.endTime)s")
/// }
/// ```
final class FluidDiarizerService: DiarizerServiceProtocol {

    // MARK: - Properties

    private let logger = Logger(subsystem: "shadow_listening", category: "FluidDiarizer")

    /// FluidAudio Diarizer Manager
    private var diarizerManager: DiarizerManager?

    /// 로드된 Diarizer 모델 번들
    private var diarizerModels: DiarizerModels?

    /// 오디오 변환기 (포맷 정규화용)
    private let audioConverter = AudioConverter()

    /// 초기화 완료 여부
    private(set) var isInitialized: Bool = false

    /// 누적된 화자 세그먼트
    private var accumulatedSegments: [SpeakerSegment] = []

    /// 샘플레이트 (Diarizer는 16kHz 사용)
    private let sampleRate: Double = 16000

    /// 최소 처리 오디오 길이 (초) - 3초 미만은 diarization 어려움
    private let minAudioDuration: Double = 3.0

    // MARK: - Streaming Properties

    /// 스트리밍용 청크 버퍼
    private var chunkBuffer: [Float] = []

    /// 현재 청크 시작 시간 (녹음 기준, 초)
    private var chunkStartTime: Double = 0

    /// 스트리밍 청크 크기 (초)
    private var streamingChunkDuration: Double = 5.0

    // MARK: - Computed Properties

    /// 모델 디렉토리 경로
    /// `~/Library/Application Support/com.taperlabs.shadow/shared/speaker-diarization-coreml/`
    private var modelDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        return appSupport
            .appendingPathComponent("com.taperlabs.shadow")
            .appendingPathComponent("shared")
            .appendingPathComponent("speaker-diarization-coreml")
    }

    /// Segmentation 모델 경로
    private var segmentationModelPath: URL {
        modelDirectory.appendingPathComponent("pyannote_segmentation.mlmodelc")
    }

    /// Embedding 모델 경로
    private var embeddingModelPath: URL {
        modelDirectory.appendingPathComponent("wespeaker_v2.mlmodelc")
    }

    // MARK: - Initialization

    init() {
        logger.info("FluidDiarizerService created")
    }

    // MARK: - DiarizerServiceProtocol Implementation

    /// 모델 로드 및 초기화
    ///
    /// 1. 모델 파일 존재 확인
    /// 2. CoreML 모델 번들 로드 (DiarizerModels.load)
    /// 3. DiarizerManager 초기화
    func initialize() async throws {
        guard !isInitialized else {
            logger.info("FluidDiarizerService already initialized")
            return
        }

        logger.info("Initializing FluidDiarizerService...")
        logger.info("Model directory: \(self.modelDirectory.path)")

        // Step 1: 모델 파일 존재 확인
        guard FileManager.default.fileExists(atPath: segmentationModelPath.path) else {
            logger.error("Segmentation model not found at: \(self.segmentationModelPath.path)")
            throw DiarizerServiceError.modelNotFound(path: segmentationModelPath.path)
        }

        guard FileManager.default.fileExists(atPath: embeddingModelPath.path) else {
            logger.error("Embedding model not found at: \(self.embeddingModelPath.path)")
            throw DiarizerServiceError.modelNotFound(path: embeddingModelPath.path)
        }

        // Step 2: CoreML 모델 번들 로드 (Manual Loading - 다운로드 없음)
        do {
            diarizerModels = try await DiarizerModels.load(
                localSegmentationModel: segmentationModelPath,
                localEmbeddingModel: embeddingModelPath
            )
            logger.info("Diarizer models loaded successfully")
        } catch {
            logger.error("Failed to load diarizer models: \(error.localizedDescription)")
            throw DiarizerServiceError.modelLoadFailed(error)
        }

        // Step 3: DiarizerManager 초기화
        let config = DiarizerConfig(
            clusteringThreshold: 0.5,       // 0.7 → 0.5 (더 엄격한 화자 분리)
            minSpeechDuration: 0.5,         // 1.0 → 0.5 (짧은 발화도 새 화자로 인식)
            minEmbeddingUpdateDuration: 1.0, // 2.0 → 1.0 (더 자주 임베딩 업데이트)
            minSilenceGap: 0.3,             // 0.5 → 0.3 (빠른 화자 전환 감지)
            numClusters: -1,                // 자동 화자 수 감지
            minActiveFramesCount: 5.0,      // 10.0 → 5.0 (더 적은 프레임으로 세그먼트 인정)
            debugMode: true,                // 디버깅 활성화 (문제 해결 후 false로 변경)
            chunkDuration: 5.0,             // 10.0 → 5.0 (실제 사용 중인 청크 크기와 일치)
            chunkOverlap: 0.0
        )

        diarizerManager = DiarizerManager(config: config)
        diarizerManager?.initialize(models: diarizerModels!)

        isInitialized = true
        logger.info("FluidDiarizerService ready")
    }

    /// 오디오 샘플 배열로 Diarization 수행
    ///
    /// - Important: 샘플은 반드시 16kHz mono Float32 포맷이어야 합니다.
    ///
    /// - Parameters:
    ///   - samples: 16kHz mono Float32 오디오 샘플
    ///   - startTime: 세그먼트 시작 시간 (녹음 기준, 초)
    ///   - endTime: 세그먼트 종료 시간 (녹음 기준, 초)
    /// - Returns: 화자 세그먼트 배열
    func processSegment(
        samples: [Float],
        startTime: Double,
        endTime: Double
    ) async throws -> [SpeakerSegment] {
        guard isInitialized, let manager = diarizerManager else {
            throw DiarizerServiceError.notInitialized
        }

        let duration = endTime - startTime

        // 최소 길이 체크 - 3초 미만은 diarization 불가
        guard duration >= minAudioDuration else {
            logger.warning("Segment too short for diarization: \(String(format: "%.2f", duration))s (min: \(self.minAudioDuration)s)")
            throw DiarizerServiceError.audioTooShort(duration: duration)
        }

        logger.info("[Diarizer] Processing: \(String(format: "%.2f", startTime))s - \(String(format: "%.2f", endTime))s (\(samples.count) samples)")

        do {
            // FluidAudio Diarization 수행
            let result = try manager.performCompleteDiarization(samples, atTime: startTime)

            // FluidAudio TimedSpeakerSegment → SpeakerSegment 변환
            let segments = result.segments.map { segment in
                SpeakerSegment(
                    speakerId: segment.speakerId,
                    startTime: Double(segment.startTimeSeconds),
                    endTime: Double(segment.endTimeSeconds),
                    confidence: segment.qualityScore
                )
            }

            accumulatedSegments.append(contentsOf: segments)

            logger.info("[Diarizer] Found \(segments.count) speaker segments")
            for segment in segments {
                logger.debug("  \(segment.speakerId): \(String(format: "%.2f", segment.startTime))s - \(String(format: "%.2f", segment.endTime))s")
            }

            return segments

        } catch {
            logger.error("[Diarizer] Processing failed: \(error.localizedDescription)")
            throw DiarizerServiceError.processingFailed(error)
        }
    }

    /// 오디오 파일로 Diarization 수행
    ///
    /// - Parameter url: 오디오 파일 경로 (WAV, M4A, MP3 등)
    /// - Returns: Diarization 결과
    func processFile(_ url: URL) async throws -> DiarizationResult {
        guard isInitialized, let manager = diarizerManager else {
            throw DiarizerServiceError.notInitialized
        }

        logger.info("[Diarizer] Processing file: \(url.lastPathComponent)")

        // 오디오 파일 읽기 및 16kHz mono Float32로 변환
        let samples: [Float]
        let audioDuration: Double

        do {
            samples = try audioConverter.resampleAudioFile(url)
            audioDuration = Double(samples.count) / sampleRate
        } catch {
            logger.error("[Diarizer] Failed to read audio file: \(error.localizedDescription)")
            throw DiarizerServiceError.fileReadFailed(path: url.path)
        }

        // 최소 길이 체크
        guard audioDuration >= minAudioDuration else {
            logger.warning("Audio too short for diarization: \(String(format: "%.2f", audioDuration))s")
            throw DiarizerServiceError.audioTooShort(duration: audioDuration)
        }

        let processingStartTime = Date()

        do {
            // FluidAudio Diarization 수행
            let result = try manager.performCompleteDiarization(samples)

            let processingTime = Date().timeIntervalSince(processingStartTime)

            // FluidAudio TimedSpeakerSegment → SpeakerSegment 변환
            let segments = result.segments.map { segment in
                SpeakerSegment(
                    speakerId: segment.speakerId,
                    startTime: Double(segment.startTimeSeconds),
                    endTime: Double(segment.endTimeSeconds),
                    confidence: segment.qualityScore
                )
            }

            // 고유 화자 수 계산
            let uniqueSpeakers = Set(segments.map { $0.speakerId })
            let speakerCount = uniqueSpeakers.count

            accumulatedSegments.append(contentsOf: segments)

            let rtfx = audioDuration / processingTime
            logger.info("[Diarizer] Completed: \(segments.count) segments, \(speakerCount) speakers, RTFx: \(String(format: "%.1f", rtfx))")

            return DiarizationResult(
                segments: segments,
                speakerCount: speakerCount,
                processingTime: processingTime,
                audioDuration: audioDuration
            )

        } catch {
            logger.error("[Diarizer] File processing failed: \(error.localizedDescription)")
            throw DiarizerServiceError.processingFailed(error)
        }
    }

    func reset() async {
        accumulatedSegments.removeAll()
        // SpeakerManager 리셋 (새 세션 시작)
        diarizerManager?.speakerManager.reset()
        logger.info("[Diarizer] Service reset")
    }

    func finalize() async throws -> [SpeakerSegment] {
        logger.info("[Diarizer] Finalized with \(self.accumulatedSegments.count) segments")
        return accumulatedSegments
    }

    func getAllSegments() -> [SpeakerSegment] {
        return accumulatedSegments
    }

    // MARK: - Streaming Session Management

    /// 스트리밍 세션 시작
    /// - Parameter chunkDuration: 청크 크기 (초), 기본값 5.0, 최소 3.0
    func startStreamingSession(chunkDuration: Double = 5.0) async {
        self.streamingChunkDuration = max(minAudioDuration, chunkDuration)
        self.chunkBuffer.removeAll()
        self.chunkStartTime = 0
        self.accumulatedSegments.removeAll()

        // SpeakerManager 리셋 (새 세션 시작)
        diarizerManager?.speakerManager.reset()

        logger.info("[Diarizer] Streaming session started with chunk duration: \(self.streamingChunkDuration)s")
    }

    /// 오디오 샘플 추가 (버퍼링 + 자동 처리)
    /// - Parameter samples: 16kHz mono Float32 샘플
    /// - Returns: 청크 완료 시 새로 감지된 세그먼트, 그렇지 않으면 nil
    func appendSamples(_ samples: [Float]) async throws -> [SpeakerSegment]? {
        guard isInitialized else {
            throw DiarizerServiceError.notInitialized
        }

        chunkBuffer.append(contentsOf: samples)

        let chunkSize = Int(streamingChunkDuration * sampleRate)
        guard chunkBuffer.count >= chunkSize else { return nil }

        // 청크 추출
        let chunk = Array(chunkBuffer.prefix(chunkSize))
        chunkBuffer.removeFirst(chunkSize)

        let chunkEndTime = chunkStartTime + streamingChunkDuration

        // Diarization 수행
        let segments = try await processSegment(
            samples: chunk,
            startTime: chunkStartTime,
            endTime: chunkEndTime
        )

        chunkStartTime = chunkEndTime

        logger.info("[Diarizer] Chunk processed: \(segments.count) segments at \(String(format: "%.1f", chunkEndTime))s")

        return segments
    }

    /// 스트리밍 세션 종료 및 잔여 버퍼 처리
    /// - Returns: 전체 누적된 세그먼트
    func finishStreamingSession() async throws -> [SpeakerSegment] {
        // 잔여 버퍼 처리 - 마지막 청크는 길이에 상관없이 처리 시도
        if !chunkBuffer.isEmpty {
            let remainingDuration = Double(chunkBuffer.count) / sampleRate
            let endTime = chunkStartTime + remainingDuration

            logger.info("[Diarizer] Processing final chunk: \(String(format: "%.2f", remainingDuration))s (\(self.chunkBuffer.count) samples)")

            do {
                let segments = try await processSegment(
                    samples: chunkBuffer,
                    startTime: chunkStartTime,
                    endTime: endTime
                )
                logger.info("[Diarizer] Final chunk processed: \(segments.count) segments")
            } catch {
                // 마지막 청크가 너무 짧아서 실패해도 기존 결과는 유지
                logger.warning("[Diarizer] Final chunk failed (may be too short): \(error.localizedDescription)")
            }
        }

        chunkBuffer.removeAll()

        let totalSegments = accumulatedSegments
        logger.info("[Diarizer] Streaming session finished: \(totalSegments.count) total segments")

        return totalSegments
    }

    /// 현재 스트리밍 진행 시간 (초)
    var currentStreamingTime: Double {
        return chunkStartTime + Double(chunkBuffer.count) / sampleRate
    }

    // MARK: - Resource Management

    /// 리소스 정리
    func cleanup() {
        diarizerManager?.cleanup()
        diarizerManager = nil
        diarizerModels = nil
        isInitialized = false
        accumulatedSegments.removeAll()
        logger.info("[Diarizer] Resources cleaned up")
    }

    // MARK: - Static Helpers

    /// 모델 파일 존재 여부 확인
    static func modelsExist() -> Bool {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let modelDir = appSupport
            .appendingPathComponent("com.taperlabs.shadow")
            .appendingPathComponent("shared")
            .appendingPathComponent("speaker-diarization-coreml")

        let segmentationExists = FileManager.default.fileExists(
            atPath: modelDir.appendingPathComponent("pyannote_segmentation.mlmodelc").path
        )
        let embeddingExists = FileManager.default.fileExists(
            atPath: modelDir.appendingPathComponent("wespeaker_v2.mlmodelc").path
        )

        return segmentationExists && embeddingExists
    }

    /// 모델 디렉토리 경로 반환
    static func modelDirectoryPath() -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        return appSupport
            .appendingPathComponent("com.taperlabs.shadow")
            .appendingPathComponent("shared")
            .appendingPathComponent("speaker-diarization-coreml")
            .path
    }
}
