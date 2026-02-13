import AVFAudio
import CoreML
import FluidAudio
import OSLog

// MARK: - Error Types

enum VADServiceError: Error {
    /// VAD 모델 파일을 찾을 수 없음
    case modelNotFound(path: String)

    /// VAD 처리 실패
    case processingFailed(Error)

    /// 서비스가 초기화되지 않음
    case notInitialized

    /// 잘못된 오디오 버퍼
    case invalidBuffer
}

// MARK: - VADService

/// FluidAudio Silero VAD를 사용하여 마이크 오디오에서 음성 구간을 검출하는 서비스
///
/// 주요 기능:
/// - 로컬 CoreML 모델 로드
/// - 스트리밍 VAD 처리
/// - 음성 구간(Speech Segments) 저장 및 관리
/// - 절대 타임스탬프 추적
final class VADService {

    // MARK: - Types

    /// 검출된 음성 구간
    struct SpeechSegment: Sendable, Equatable {
        /// 녹음 시작 기준 절대 시간 (초)
        let startTime: Double

        /// 녹음 시작 기준 종료 시간 (초), nil이면 진행 중
        let endTime: Double?

        /// 음성 구간 길이 (초)
        var duration: Double? {
            guard let endTime = endTime else { return nil }
            return endTime - startTime
        }
    }

    // MARK: - Properties

    private var manager: VadManager?
    private var streamState: VadStreamState?
    private let logger = Logger(subsystem: "shadow_listening", category: "VAD")

    /// 모델 디렉토리 이름
    private let modelDirectoryName = "silero-vad-coreml"

    /// 모델 파일 이름
    private let modelFileName = "silero-vad-unified-256ms-v6.0.0.mlmodelc"

    /// VAD 설정 (threshold 0.5 - balanced)
    private let vadConfig = VadConfig(defaultThreshold: 0.5)

    /// Segmentation 설정
    private var segmentationConfig: VadSegmentationConfig = {
        var config = VadSegmentationConfig.default
        config.minSpeechDuration = 0.25  // 최소 0.25초 이상의 음성만 감지
        config.minSilenceDuration = 0.4  // 0.4초 침묵 시 세그먼트 종료
        config.speechPadding = 0.1       // 음성 전후 0.1초 패딩
        return config
    }()

    /// 검출된 음성 구간들
    private(set) var speechSegments: [SpeechSegment] = []

    /// 현재 진행 중인 음성 구간 (speechStart 후 speechEnd 전)
    private var currentSegment: SpeechSegment?

    /// 처리된 총 샘플 수 (절대 시간 계산용)
    private var processedSampleCount: Int = 0

    /// 샘플레이트 (VAD는 16kHz 사용)
    private let sampleRate: Double = 16000

    /// 1초 간격 로그용
    private var lastLogTime: CFAbsoluteTime = 0

    /// 초기화 완료 여부
    private(set) var isInitialized: Bool = false

    /// VAD 청크 크기 (256ms at 16kHz = 4096 samples)
    private let vadChunkSize = 4096

    /// 샘플 누적 버퍼
    private var sampleAccumulator: [Float] = []

    /// 마지막 VAD 결과 (누적 중일 때 반환용)
    private var lastResult: VadStreamResult?

    // MARK: - Initialization

    /// VADService 동기 초기화 (initialize()를 나중에 호출해야 함)
    init() {
        logger.info("VADService created (call initialize() to load model)")
    }

    /// 모델 로드 (비동기)
    func initialize() async throws {
        guard !isInitialized else { return }
        try await loadModel()
    }

    // MARK: - Model Loading

    /// Application Support 디렉토리에서 모델 URL 가져오기
    private func getModelURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        return appSupport
            .appendingPathComponent("com.taperlabs.shadow")
            .appendingPathComponent("shared")
            .appendingPathComponent(modelDirectoryName)
            .appendingPathComponent(modelFileName)
    }

    /// 로컬 CoreML 모델 로드
    private func loadModel() async throws {
        let modelURL = getModelURL()

        logger.info("Loading VAD model from: \(modelURL.path)")

        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            logger.error("VAD model not found at: \(modelURL.path)")
            throw VADServiceError.modelNotFound(path: modelURL.path)
        }

        var configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly

        do {
            let vadModel = try MLModel(contentsOf: modelURL, configuration: configuration)
            self.manager = VadManager(config: vadConfig, vadModel: vadModel)
            self.streamState = await manager?.makeStreamState()
            self.isInitialized = true

            logger.info("VAD model loaded successfully (threshold: \(self.vadConfig.defaultThreshold))")
        } catch {
            logger.error("Failed to load VAD model: \(error.localizedDescription)")
            throw VADServiceError.processingFailed(error)
        }
    }

    // MARK: - Processing

    /// Float 배열을 VAD로 처리
    ///
    /// 샘플을 누적하여 4096 샘플 (256ms) 단위로 VAD 처리합니다.
    ///
    /// - Parameter samples: 16kHz, mono, Float32 포맷의 샘플 배열
    /// - Returns: VAD 처리 결과 (확률, 이벤트 포함). 누적 중이면 마지막 결과 반환
    /// - Throws: `VADServiceError.notInitialized`
    @discardableResult
    func processChunk(_ samples: [Float]) async throws -> VadStreamResult {
        guard let manager = manager, var state = streamState else {
            throw VADServiceError.notInitialized
        }

        // 샘플 누적
        sampleAccumulator.append(contentsOf: samples)

        // 4096 샘플 미만이면 마지막 결과 반환
        guard sampleAccumulator.count >= vadChunkSize else {
            if let last = lastResult {
                return last
            }
            // 초기 상태용 더미 결과 - 확률 0으로 반환
            return VadStreamResult(
                state: state,
                event: nil,
                probability: 0
            )
        }

        // 4096 샘플씩 처리
        var latestResult: VadStreamResult?

        while sampleAccumulator.count >= vadChunkSize {
            let chunk = Array(sampleAccumulator.prefix(vadChunkSize))
            sampleAccumulator.removeFirst(vadChunkSize)

            // 현재 절대 시간 계산 (청크 시작 시점)
            let absoluteTime = Double(processedSampleCount) / sampleRate
            processedSampleCount += vadChunkSize

            // VAD 스트리밍 처리
            let result: VadStreamResult
            do {
                result = try await manager.processStreamingChunk(
                    chunk,
                    state: state,
                    config: segmentationConfig,
                    returnSeconds: true,
                    timeResolution: 2
                )
            } catch {
                throw VADServiceError.processingFailed(error)
            }

            // 상태 업데이트
            state = result.state
            streamState = state
            latestResult = result
            lastResult = result

            // 이벤트 처리
            handleVadEvent(result.event, at: absoluteTime, probability: result.probability)

            // 1초 간격 로그
            logPeriodically(result: result)
        }

        return latestResult ?? lastResult!
    }

    /// 오디오 버퍼를 VAD로 처리
    ///
    /// 샘플을 누적하여 4096 샘플 (256ms) 단위로 VAD 처리합니다.
    ///
    /// - Parameter buffer: 16kHz, mono, Float32 포맷의 PCM 버퍼
    /// - Returns: VAD 처리 결과 (확률, 이벤트 포함). 누적 중이면 마지막 결과 반환
    /// - Throws: `VADServiceError.notInitialized`, `VADServiceError.invalidBuffer`
    @discardableResult
    func processChunk(_ buffer: AVAudioPCMBuffer) async throws -> VadStreamResult {
        guard let manager = manager, var state = streamState else {
            throw VADServiceError.notInitialized
        }

        guard let floatData = buffer.floatChannelData?[0] else {
            throw VADServiceError.invalidBuffer
        }

        let frameCount = Int(buffer.frameLength)

        // 샘플 누적
        for i in 0..<frameCount {
            sampleAccumulator.append(floatData[i])
        }

        // 4096 샘플 미만이면 마지막 결과 반환
        guard sampleAccumulator.count >= vadChunkSize else {
            if let last = lastResult {
                return last
            }
            // 초기 상태용 더미 결과
            throw VADServiceError.notInitialized
        }

        // 4096 샘플씩 처리
        var latestResult: VadStreamResult?

        while sampleAccumulator.count >= vadChunkSize {
            let chunk = Array(sampleAccumulator.prefix(vadChunkSize))
            sampleAccumulator.removeFirst(vadChunkSize)

            // 현재 절대 시간 계산 (청크 시작 시점)
            let absoluteTime = Double(processedSampleCount) / sampleRate
            processedSampleCount += vadChunkSize

            // VAD 스트리밍 처리
            let result: VadStreamResult
            do {
                result = try await manager.processStreamingChunk(
                    chunk,
                    state: state,
                    config: segmentationConfig,
                    returnSeconds: true,
                    timeResolution: 2
                )
            } catch {
                throw VADServiceError.processingFailed(error)
            }

            // 상태 업데이트
            state = result.state
            streamState = state
            latestResult = result
            lastResult = result

            // 이벤트 처리
            handleVadEvent(result.event, at: absoluteTime, probability: result.probability)

            // 1초 간격 로그
            logPeriodically(result: result)
        }

        return latestResult ?? lastResult!
    }

    /// VAD 이벤트 처리 (speechStart/speechEnd)
    private func handleVadEvent(
        _ event: VadStreamEvent?,
        at absoluteTime: Double,
        probability: Float
    ) {
        guard let event = event else { return }

        switch event.kind {
        case .speechStart:
            currentSegment = SpeechSegment(startTime: absoluteTime, endTime: nil)
            logger.info("[VAD] Speech started at \(String(format: "%.2f", absoluteTime))s (prob: \(String(format: "%.3f", probability)))")

        case .speechEnd:
            if let segment = currentSegment {
                let completed = SpeechSegment(
                    startTime: segment.startTime,
                    endTime: absoluteTime
                )
                speechSegments.append(completed)

                let duration = absoluteTime - segment.startTime
                logger.info("[VAD] Speech ended at \(String(format: "%.2f", absoluteTime))s (duration: \(String(format: "%.2f", duration))s)")

                currentSegment = nil
            }
        }
    }

    /// 1초 간격 로그
    private func logPeriodically(result: VadStreamResult) {
        let currentTime = CFAbsoluteTimeGetCurrent()
        if currentTime - lastLogTime >= 1.0 {
            lastLogTime = currentTime
            let absoluteTime = Double(processedSampleCount) / sampleRate
            let isSpeaking = currentSegment != nil ? "SPEAKING" : "silent"
            logger.info("[VAD] time=\(String(format: "%.1f", absoluteTime))s, prob=\(String(format: "%.3f", result.probability)), state=\(isSpeaking), segments=\(self.speechSegments.count)")
        }
    }

    // MARK: - Public Methods

    /// 검출된 모든 음성 구간 반환
    func getSpeechSegments() -> [SpeechSegment] {
        return speechSegments
    }

    /// 현재 진행 중인 음성 구간 반환 (있는 경우)
    func getCurrentSegment() -> SpeechSegment? {
        return currentSegment
    }

    /// 서비스 초기화 (새 녹음 시작 시)
    func reset() async {
        speechSegments.removeAll()
        currentSegment = nil
        processedSampleCount = 0
        lastLogTime = 0
        sampleAccumulator.removeAll()
        lastResult = nil

        // VAD 스트림 상태 재설정
        if let manager = manager {
            streamState = await manager.makeStreamState()
        }

        logger.info("[VAD] Service reset")
    }

    /// 녹음 종료 시 호출 (진행 중인 음성 구간 강제 종료)
    func finalize() {
        if let segment = currentSegment {
            let absoluteTime = Double(processedSampleCount) / sampleRate
            let completed = SpeechSegment(
                startTime: segment.startTime,
                endTime: absoluteTime
            )
            speechSegments.append(completed)
            currentSegment = nil

            logger.info("[VAD] Finalized ongoing segment at \(String(format: "%.2f", absoluteTime))s")
        }
    }
}
