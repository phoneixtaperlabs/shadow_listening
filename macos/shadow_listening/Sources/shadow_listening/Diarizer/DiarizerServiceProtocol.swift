import AVFAudio
import Foundation

// MARK: - Error Types

/// Diarizer 서비스 에러 타입
enum DiarizerServiceError: Error, LocalizedError {
    /// Diarizer 모델 파일을 찾을 수 없음
    case modelNotFound(path: String)

    /// 모델 로드 실패
    case modelLoadFailed(Error)

    /// Diarization 처리 실패
    case processingFailed(Error)

    /// 서비스가 초기화되지 않음
    case notInitialized

    /// 잘못된 오디오 버퍼
    case invalidBuffer

    /// 오디오 길이가 너무 짧음 (최소 3초 필요)
    case audioTooShort(duration: Double)

    /// 파일을 읽을 수 없음
    case fileReadFailed(path: String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "Diarizer model not found at: \(path)"
        case .modelLoadFailed(let error):
            return "Failed to load diarizer model: \(error.localizedDescription)"
        case .processingFailed(let error):
            return "Diarization processing failed: \(error.localizedDescription)"
        case .notInitialized:
            return "Diarizer service not initialized"
        case .invalidBuffer:
            return "Invalid audio buffer"
        case .audioTooShort(let duration):
            return "Audio too short for diarization: \(String(format: "%.2f", duration))s (minimum 3s required)"
        case .fileReadFailed(let path):
            return "Failed to read audio file: \(path)"
        }
    }
}

// MARK: - Diarization Types

/// 화자 세그먼트 정보
struct SpeakerSegment: Sendable, Equatable {
    /// 화자 ID (예: "Speaker_1", "Speaker_2")
    let speakerId: String

    /// 녹음 시작 기준 시작 시간 (초)
    let startTime: Double

    /// 녹음 시작 기준 종료 시간 (초)
    let endTime: Double

    /// 신뢰도 점수 (0.0 - 1.0)
    let confidence: Float

    /// 세그먼트 길이 (초)
    var duration: Double {
        endTime - startTime
    }
}

/// Diarization 결과
struct DiarizationResult: Sendable {
    /// 화자 세그먼트 목록
    let segments: [SpeakerSegment]

    /// 감지된 화자 수
    let speakerCount: Int

    /// 처리 시간 (초)
    let processingTime: Double

    /// 전체 오디오 길이 (초)
    let audioDuration: Double

    /// RTFx (Real-Time Factor) - 실시간 대비 처리 속도
    var rtfx: Double {
        guard processingTime > 0 else { return 0 }
        return audioDuration / processingTime
    }
}

// MARK: - Diarizer Service Protocol

/// Diarizer 서비스 공통 프로토콜
///
/// FluidAudio Diarizer를 사용하여 "누가 언제 말했는지" 분석합니다.
///
/// ## 사용 예시
/// ```swift
/// let service = FluidDiarizerService()
/// try await service.initialize()
/// let segments = try await service.processFile(url)
/// for segment in segments {
///     print("\(segment.speakerId): \(segment.startTime)s - \(segment.endTime)s")
/// }
/// ```
protocol DiarizerServiceProtocol: AnyObject {

    // MARK: - Properties

    /// 초기화 완료 여부
    var isInitialized: Bool { get }

    // MARK: - Lifecycle

    /// 서비스 초기화 (모델 로드)
    /// - Throws: `DiarizerServiceError.modelNotFound`, `DiarizerServiceError.modelLoadFailed`
    func initialize() async throws

    // MARK: - Processing

    /// 오디오 샘플 배열로 Diarization 수행
    ///
    /// - Parameters:
    ///   - samples: 16kHz mono Float32 오디오 샘플
    ///   - startTime: 세그먼트 시작 시간 (녹음 기준)
    ///   - endTime: 세그먼트 종료 시간 (녹음 기준)
    /// - Returns: 화자 세그먼트 배열
    /// - Throws: `DiarizerServiceError.notInitialized`, `DiarizerServiceError.audioTooShort`
    func processSegment(
        samples: [Float],
        startTime: Double,
        endTime: Double
    ) async throws -> [SpeakerSegment]

    /// 오디오 파일로 Diarization 수행
    ///
    /// - Parameter url: 16kHz mono Float32 WAV 파일 경로
    /// - Returns: Diarization 결과 (세그먼트, 화자 수, 처리 시간)
    /// - Throws: `DiarizerServiceError.notInitialized`, `DiarizerServiceError.fileReadFailed`
    func processFile(_ url: URL) async throws -> DiarizationResult

    // MARK: - State Management

    /// 서비스 상태 리셋 (새 세션 시작 시)
    /// 화자 ID 추적을 초기화합니다.
    func reset() async

    /// 세션 종료 시 호출 (최종 결과 반환)
    /// - Returns: 누적된 모든 화자 세그먼트
    func finalize() async throws -> [SpeakerSegment]

    /// 누적된 모든 화자 세그먼트 반환
    func getAllSegments() -> [SpeakerSegment]

    /// 리소스 정리
    func cleanup()
}

// MARK: - Protocol Extensions

extension DiarizerServiceProtocol {

    /// 오디오 버퍼에서 Float 샘플 배열 추출
    func extractSamples(from buffer: AVAudioPCMBuffer) throws -> [Float] {
        guard let floatData = buffer.floatChannelData?[0] else {
            throw DiarizerServiceError.invalidBuffer
        }

        let frameCount = Int(buffer.frameLength)
        var samples = [Float](repeating: 0, count: frameCount)

        for i in 0..<frameCount {
            samples[i] = floatData[i]
        }

        return samples
    }
}
