import AVFAudio
import CoreML
import FluidAudio
import OSLog

// MARK: - FluidASRService

/// FluidAudio Parakeet TDT 기반 ASR 서비스
///
/// NVIDIA Parakeet TDT 모델을 CoreML로 변환한 FluidAudio 라이브러리를 사용합니다.
///
/// ## 추상화 개념
/// 1. **모델 로드**: AsrModels.load() → AsrManager.initialize()
/// 2. **오디오 피드**: 16kHz mono Float32 샘플 또는 AVAudioPCMBuffer
/// 3. **전사 결과**: ASRResult (text, confidence, tokenTimings)
///
/// ## 지원 모델
/// - v3 (Multilingual): 25개 유럽 언어, ~120x RTF on M4 Pro
/// - v2 (English-only): 영어 특화, 희귀 단어 인식 향상
///
/// ## 사용 예시
/// ```swift
/// let service = FluidASRService(version: .multilingual)
/// try await service.initialize()
/// let result = try await service.processSegment(samples: audioSamples, startTime: 0, endTime: 5)
/// print(result.text)
/// ```
final class FluidASRService: ASRServiceProtocol {

    // MARK: - Types

    /// 모델 버전
    enum ModelVersion: String, Sendable {
        /// 영어 전용 (v2) - 영어 정확도 최적화, 희귀 단어 인식 향상
        case english = "parakeet-tdt-0.6b-v2-coreml"

        /// 다국어 지원 (v3) - 25개 유럽 언어
        case multilingual = "parakeet-tdt-0.6b-v3-coreml"

        /// FluidAudio AsrModelVersion으로 변환
        var asrModelVersion: AsrModelVersion {
            switch self {
            case .english: return .v2
            case .multilingual: return .v3
            }
        }

        /// 디렉토리 이름
        var directoryName: String { rawValue }
    }

    // MARK: - Properties

    private let logger = Logger(subsystem: "shadow_listening", category: "FluidASR")

    /// 모델 버전
    private let modelVersion: ModelVersion

    /// FluidAudio ASR Manager - 모델 로드 및 전사 수행
    private var asrManager: AsrManager?

    /// 로드된 ASR 모델 번들
    private var asrModels: AsrModels?

    /// 오디오 변환기 (포맷 정규화용)
    private let audioConverter = AudioConverter()

    /// 초기화 완료 여부
    private(set) var isInitialized: Bool = false

    /// 누적된 전사 결과
    private var transcriptionSegments: [TranscriptionSegment] = []

    /// 샘플레이트 (Parakeet은 16kHz 사용)
    private let sampleRate: Double = 16000

    /// 최소 처리 오디오 길이 (초) - 1초 미만은 의미 있는 전사 어려움
    private let minAudioDuration: Double = 0.5

    // MARK: - Computed Properties

    /// 모델 디렉토리 경로
    /// `~/Library/Application Support/com.taperlabs.shadow/shared/<model-version>/`
    private var modelDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        return appSupport
            .appendingPathComponent("com.taperlabs.shadow")
            .appendingPathComponent("shared")
            .appendingPathComponent(modelVersion.directoryName)
    }

    // MARK: - Initialization

    /// FluidASRService 초기화
    /// - Parameter version: 사용할 모델 버전
    ///   - `.multilingual` (v3): 다국어 지원, 기본값
    ///   - `.english` (v2): 영어만 필요할 때, 정확도 향상
    init(version: ModelVersion = .multilingual) {
        self.modelVersion = version
        logger.info("FluidASRService created with version: \(version.rawValue)")
    }

    // MARK: - ASRServiceProtocol Implementation

    /// 모델 로드 및 초기화
    ///
    /// 1. 모델 파일 존재 확인 (AsrModels.modelsExist)
    /// 2. CoreML 모델 번들 로드 (AsrModels.load)
    /// 3. ASR Manager 초기화 (AsrManager.initialize)
    func initialize() async throws {
        guard !isInitialized else {
            logger.info("FluidASRService already initialized")
            return
        }

        let totalStart = CFAbsoluteTimeGetCurrent()
        logger.info("Initializing FluidASRService...")
        logger.info("Model directory: \(self.modelDirectory.path)")

        // Step 1: 모델 파일 존재 확인
        let step1Start = CFAbsoluteTimeGetCurrent()
        guard AsrModels.modelsExist(at: modelDirectory) else {
            logger.error("ASR models not found at: \(self.modelDirectory.path)")
            throw ASRServiceError.modelNotFound(path: modelDirectory.path)
        }
        logger.info("[ASR Init] Step 1 - modelsExist: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - step1Start))s")

        // Step 2: CoreML 모델 번들 로드 (Manual Loading - 다운로드 없음)
        let step2Start = CFAbsoluteTimeGetCurrent()
        let configuration = AsrModels.defaultConfiguration()

        do {
            asrModels = try await AsrModels.load(
                from: modelDirectory,
                configuration: configuration,
                version: modelVersion.asrModelVersion
            )
            logger.info("[ASR Init] Step 2 - AsrModels.load: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - step2Start))s")
            logger.info("ASR models loaded: \(self.modelVersion.rawValue)")
        } catch {
            logger.error("Failed to load ASR models: \(error.localizedDescription)")
            throw ASRServiceError.modelLoadFailed(error)
        }

        // Step 3: ASR Manager 초기화
        let step3Start = CFAbsoluteTimeGetCurrent()
        do {
            asrManager = AsrManager(config: .default)
            try await asrManager?.initialize(models: asrModels!)
            logger.info("[ASR Init] Step 3 - AsrManager.initialize: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - step3Start))s")
            logger.info("ASR Manager initialized")
        } catch {
            logger.error("Failed to initialize ASR Manager: \(error.localizedDescription)")
            throw ASRServiceError.modelLoadFailed(error)
        }

        isInitialized = true
        logger.info("[ASR Init] Total: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - totalStart))s")
        logger.info("FluidASRService ready (version: \(self.modelVersion.rawValue))")
    }

    /// 오디오 샘플 배열로 전사
    ///
    /// - Important: 샘플은 반드시 16kHz mono Float32 포맷이어야 합니다.
    ///   AudioConverter를 사용하여 포맷 변환하세요.
    ///
    /// - Parameters:
    ///   - samples: 16kHz mono Float32 오디오 샘플
    ///   - startTime: 세그먼트 시작 시간 (녹음 기준, 초)
    ///   - endTime: 세그먼트 종료 시간 (녹음 기준, 초)
    /// - Returns: 전사 결과
    func processSegment(
        samples: [Float],
        startTime: Double,
        endTime: Double
    ) async throws -> TranscriptionSegment {
        guard isInitialized, let manager = asrManager else {
            throw ASRServiceError.notInitialized
        }

        let duration = endTime - startTime

        // 최소 길이 체크 - 너무 짧으면 의미 있는 전사 불가
        guard duration >= minAudioDuration else {
            logger.debug("Segment too short (\(String(format: "%.2f", duration))s), returning empty")
            return TranscriptionSegment(
                text: "",
                startTime: startTime,
                endTime: endTime,
                confidence: 0,
                isFinal: true
            )
        }

        logger.info("[ASR] Transcribing: \(String(format: "%.2f", startTime))s - \(String(format: "%.2f", endTime))s (\(samples.count) samples)")

        // FluidAudio ASR 전사
        do {
            let result = try await manager.transcribe(samples, source: .microphone)

            // tokenTimings에서 실제 음성 구간 추출
            var actualStartTime = startTime
            var actualEndTime = endTime

            if let timings = result.tokenTimings, !timings.isEmpty {
                // 첫 번째 토큰의 startTime + 청크 오프셋
                actualStartTime = startTime + timings.first!.startTime
                // 마지막 토큰의 endTime + 청크 오프셋
                actualEndTime = startTime + timings.last!.endTime

                logger.info("[ASR] Token timings: first=\(String(format: "%.2f", timings.first!.startTime))s, last=\(String(format: "%.2f", timings.last!.endTime))s → actual=\(String(format: "%.2f", actualStartTime))s-\(String(format: "%.2f", actualEndTime))s")
            }

            let segment = TranscriptionSegment(
                text: result.text,
                startTime: actualStartTime,
                endTime: actualEndTime,
                confidence: result.confidence,
                isFinal: true
            )

            transcriptionSegments.append(segment)

            logger.info("[ASR] Result: '\(result.text)' (conf: \(String(format: "%.2f", result.confidence)), RTFx: \(String(format: "%.1f", result.rtfx)), time: \(String(format: "%.2f", actualStartTime))s-\(String(format: "%.2f", actualEndTime))s)")

            return segment

        } catch {
            logger.error("[ASR] Transcription failed: \(error.localizedDescription)")
            throw ASRServiceError.processingFailed(error)
        }
    }

    /// AVAudioPCMBuffer로 전사
    ///
    /// 버퍼를 16kHz mono Float32로 변환 후 전사합니다.
    /// AudioConverter가 포맷 정규화를 처리합니다.
    func processBuffer(
        _ buffer: AVAudioPCMBuffer,
        startTime: Double
    ) async throws -> TranscriptionSegment {
        guard isInitialized, let manager = asrManager else {
            throw ASRServiceError.notInitialized
        }

        // AudioConverter로 포맷 정규화 (16kHz mono Float32)
        let samples: [Float]
        do {
            samples = try audioConverter.resampleBuffer(buffer)
        } catch {
            logger.error("[ASR] Buffer conversion failed: \(error.localizedDescription)")
            throw ASRServiceError.invalidBuffer
        }

        let duration = Double(samples.count) / sampleRate
        return try await processSegment(
            samples: samples,
            startTime: startTime,
            endTime: startTime + duration
        )
    }

    /// 파일 URL로 전사
    ///
    /// AsrManager.transcribe(_:source:)가 내부적으로 AudioConverter를 사용하여
    /// WAV, MP3, M4A, FLAC 등 다양한 포맷을 자동 변환합니다.
    ///
    /// - Parameters:
    ///   - url: 오디오 파일 경로
    ///   - source: 오디오 소스 타입
    /// - Returns: 전사 결과
    func transcribeFile(
        _ url: URL,
        source: AudioSource = .system
    ) async throws -> TranscriptionSegment {
        guard isInitialized, let manager = asrManager else {
            throw ASRServiceError.notInitialized
        }

        logger.info("[ASR] Transcribing file: \(url.lastPathComponent)")

        do {
            let result = try await manager.transcribe(url, source: source)

            let segment = TranscriptionSegment(
                text: result.text,
                startTime: 0,
                endTime: result.duration,
                confidence: result.confidence,
                isFinal: true
            )

            transcriptionSegments.append(segment)

            logger.info("[ASR] File result: '\(result.text)' (duration: \(String(format: "%.2f", result.duration))s, RTFx: \(String(format: "%.1f", result.rtfx)))")

            return segment

        } catch {
            logger.error("[ASR] File transcription failed: \(error.localizedDescription)")
            throw ASRServiceError.processingFailed(error)
        }
    }

    func reset() async {
        transcriptionSegments.removeAll()
        asrManager?.resetState()
        logger.info("[ASR] Service reset")
    }

    func finalize() async throws -> [TranscriptionSegment] {
        logger.info("[ASR] Finalized with \(self.transcriptionSegments.count) segments")
        return transcriptionSegments
    }

    func getTranscriptions() -> [TranscriptionSegment] {
        return transcriptionSegments
    }

    // MARK: - Resource Management

    /// 리소스 정리
    func cleanup() {
        asrManager?.cleanup()
        asrManager = nil
        asrModels = nil
        isInitialized = false
        transcriptionSegments.removeAll()
        logger.info("[ASR] Resources cleaned up")
    }

    // MARK: - Static Helpers

    /// 특정 버전의 모델 파일 존재 여부 확인
    static func modelsExist(for version: ModelVersion) -> Bool {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let modelDir = appSupport
            .appendingPathComponent("com.taperlabs.shadow")
            .appendingPathComponent("shared")
            .appendingPathComponent(version.directoryName)

        return AsrModels.modelsExist(at: modelDir)
    }

    /// 로컬에 존재하는 모델 버전 목록
    static func availableVersions() -> [ModelVersion] {
        var versions: [ModelVersion] = []
        if modelsExist(for: .multilingual) { versions.append(.multilingual) }
        if modelsExist(for: .english) { versions.append(.english) }
        return versions
    }
}
