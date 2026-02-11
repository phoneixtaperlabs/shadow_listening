import AVFAudio
import OSLog

/// Mic VAD 통합 서비스
///
/// MicAudioService에서 받은 오디오 버퍼를 VADService를 통해 처리하여
/// 녹음 시작 기준 음성 구간 타임스탬프를 관리합니다.
final class MicVADService {

    // MARK: - Types

    /// 음성 활동 타임스탬프
    struct VoiceActivityTimestamp: Sendable, Equatable {
        /// 녹음 시작 기준 시작 시간 (초)
        let startTime: Double

        /// 녹음 시작 기준 종료 시간 (초), nil이면 진행 중
        let endTime: Double?
    }

    enum MicVADError: Error {
        case vadNotInitialized
        case alreadyProcessing
        case notProcessing
    }

    // MARK: - Properties

    private var vadService: VADService?
    private let logger = Logger(subsystem: "shadow_listening", category: "MicVADService")

    /// 처리 상태
    private(set) var isProcessing: Bool = false

    /// 처리된 총 16kHz 프레임 수 (시간 검증용)
    private var totalFramesProcessed: Int64 = 0

    /// 샘플레이트 (VAD는 16kHz 사용)
    private let sampleRate: Double = 16000.0

    // MARK: - Initialization

    /// 서비스 초기화 (VAD 모델 로드)
    func initialize() async throws {
        guard vadService == nil else {
            logger.info("MicVADService already initialized")
            return
        }

        vadService = try await VADService()
        logger.info("MicVADService initialized successfully")
    }

    // MARK: - Processing Control

    /// 처리 시작 - 녹음 시작 시 호출
    ///
    /// VAD 상태를 초기화하고 시간 카운터를 0으로 리셋합니다.
    /// mic 스트림 소비 직전에 호출하여 시간 0을 동기화해야 합니다.
    func startProcessing() async throws {
        guard let vad = vadService else {
            throw MicVADError.vadNotInitialized
        }
        guard !isProcessing else {
            throw MicVADError.alreadyProcessing
        }

        // VAD 상태 및 프레임 카운터 리셋
        await vad.reset()
        totalFramesProcessed = 0
        isProcessing = true

        logger.info("MicVADService started processing")
    }

    /// 마이크 버퍼 처리
    ///
    /// - Parameter buffer: 16kHz mono Float32 포맷의 PCM 버퍼
    /// - Returns: 현재 청크의 음성 확률 (0.0 - 1.0), 누적 중이면 0.0
    @discardableResult
    func processBuffer(_ buffer: AVAudioPCMBuffer) async -> Float {
        guard isProcessing, let vad = vadService else {
            return 0.0
        }

        let frameCount = Int64(buffer.frameLength)

        // VAD 처리 (누적 중이면 에러 발생 가능, 무시)
        do {
            let result = try await vad.processChunk(buffer)
            totalFramesProcessed += frameCount
            return result.probability
        } catch {
            // 4096 샘플 누적 중 - 정상 동작
            totalFramesProcessed += frameCount
            return 0.0
        }
    }

    /// 처리 중지 - 녹음 종료 시 호출
    ///
    /// 진행 중인 음성 구간을 종료하고 최종 타임스탬프 배열을 반환합니다.
    /// - Returns: 검출된 모든 음성 구간 타임스탬프
    func stopProcessing() -> [VoiceActivityTimestamp] {
        guard isProcessing, let vad = vadService else {
            return []
        }

        // 진행 중인 음성 구간 종료
        vad.finalize()
        isProcessing = false

        // 시간 검증 로그
        let vadSampleCount = vad.speechSegments.reduce(0) { $0 + Int($1.endTime ?? 0) }
        let ourTime = Double(totalFramesProcessed) / sampleRate
        logger.info("MicVADService stopped. Total duration: \(String(format: "%.2f", ourTime))s")

        // SpeechSegment → VoiceActivityTimestamp 변환
        let timestamps = vad.getSpeechSegments().map { segment in
            VoiceActivityTimestamp(
                startTime: segment.startTime,
                endTime: segment.endTime
            )
        }

        // 결과 로그
        logger.info("Detected \(timestamps.count) voice segments")
        for (index, ts) in timestamps.enumerated() {
            let endStr = ts.endTime.map { String(format: "%.2f", $0) } ?? "ongoing"
            logger.info("[VAD Result] Segment \(index + 1): \(String(format: "%.2f", ts.startTime))s - \(endStr)s")
        }

        return timestamps
    }

    // MARK: - Public API

    /// 현재까지 검출된 음성 구간 반환 (녹음 중 호출 가능)
    func getVoiceActivityTimestamps() -> [VoiceActivityTimestamp] {
        guard let vad = vadService else { return [] }

        return vad.getSpeechSegments().map { segment in
            VoiceActivityTimestamp(
                startTime: segment.startTime,
                endTime: segment.endTime
            )
        }
    }

    /// 현재 음성 진행 중인지 확인
    func isCurrentlySpeaking() -> Bool {
        return vadService?.getCurrentSegment() != nil
    }

    /// 현재 처리된 시간 (초)
    func getCurrentTime() -> Double {
        return Double(totalFramesProcessed) / sampleRate
    }
}
