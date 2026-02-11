import AVFAudio
import Foundation

// MARK: - Error Types

/// ASR 서비스 에러 타입
enum ASRServiceError: Error, LocalizedError {
    /// ASR 모델 파일을 찾을 수 없음
    case modelNotFound(path: String)

    /// 모델 로드 실패
    case modelLoadFailed(Error)

    /// ASR 처리 실패
    case processingFailed(Error)

    /// 서비스가 초기화되지 않음
    case notInitialized

    /// 잘못된 오디오 버퍼
    case invalidBuffer

    /// 지원하지 않는 모델
    case unsupportedModel(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "ASR model not found at: \(path)"
        case .modelLoadFailed(let error):
            return "Failed to load ASR model: \(error.localizedDescription)"
        case .processingFailed(let error):
            return "ASR processing failed: \(error.localizedDescription)"
        case .notInitialized:
            return "ASR service not initialized"
        case .invalidBuffer:
            return "Invalid audio buffer"
        case .unsupportedModel(let name):
            return "Unsupported ASR model: \(name)"
        }
    }
}

// MARK: - Transcription Types

/// 전사된 텍스트 세그먼트
struct TranscriptionSegment: Sendable, Equatable {
    /// 전사된 텍스트
    let text: String

    /// 녹음 시작 기준 시작 시간 (초)
    let startTime: Double

    /// 녹음 시작 기준 종료 시간 (초)
    let endTime: Double

    /// 신뢰도 점수 (0.0 - 1.0)
    let confidence: Float

    /// 최종 결과 여부 (false면 중간 결과)
    let isFinal: Bool

    /// 세그먼트 길이 (초)
    var duration: Double {
        endTime - startTime
    }
}

/// 토큰 레벨 타이밍 정보
struct ASRTokenTiming: Sendable, Equatable {
    /// 토큰 텍스트
    let token: String

    /// 토큰 ID
    let tokenId: Int

    /// 시작 시간 (초)
    let startTime: Double

    /// 종료 시간 (초)
    let endTime: Double

    /// 신뢰도 점수
    let confidence: Float
}

/// 상세 전사 결과 (토큰 타이밍 포함)
struct DetailedTranscription: Sendable {
    /// 기본 전사 세그먼트
    let segment: TranscriptionSegment

    /// 토큰별 타이밍 (옵션)
    let tokenTimings: [ASRTokenTiming]?

    /// 처리 시간 (초)
    let processingTime: Double

    /// RTFx (Real-Time Factor) - 실시간 대비 처리 속도
    var rtfx: Double {
        guard processingTime > 0 else { return 0 }
        return segment.duration / processingTime
    }
}

// MARK: - ASR Service Protocol

/// ASR 서비스 공통 프로토콜
///
/// Parakeet(FluidASR), Whisper 등 다양한 ASR 모델을 지원하기 위한 공통 인터페이스
protocol ASRServiceProtocol: AnyObject {

    // MARK: - Properties

    /// 초기화 완료 여부
    var isInitialized: Bool { get }

    // MARK: - Lifecycle

    /// 서비스 초기화 (모델 로드)
    /// - Throws: `ASRServiceError.modelNotFound`, `ASRServiceError.modelLoadFailed`
    func initialize() async throws

    // MARK: - Processing

    /// 음성 세그먼트 전사 (배치 모드)
    ///
    /// VAD에서 검출된 음성 구간을 전사합니다.
    ///
    /// - Parameters:
    ///   - samples: 16kHz Float32 오디오 샘플
    ///   - startTime: 세그먼트 시작 시간 (녹음 기준)
    ///   - endTime: 세그먼트 종료 시간 (녹음 기준)
    /// - Returns: 전사된 텍스트 세그먼트
    /// - Throws: `ASRServiceError.notInitialized`, `ASRServiceError.processingFailed`
    func processSegment(
        samples: [Float],
        startTime: Double,
        endTime: Double
    ) async throws -> TranscriptionSegment

    /// 오디오 버퍼 전사 (스트리밍 호환)
    ///
    /// AVAudioPCMBuffer를 직접 처리합니다.
    ///
    /// - Parameters:
    ///   - buffer: 16kHz mono Float32 PCM 버퍼
    ///   - startTime: 버퍼 시작 시간 (녹음 기준)
    /// - Returns: 전사된 텍스트 세그먼트
    /// - Throws: `ASRServiceError.notInitialized`, `ASRServiceError.invalidBuffer`
    func processBuffer(
        _ buffer: AVAudioPCMBuffer,
        startTime: Double
    ) async throws -> TranscriptionSegment

    // MARK: - State Management

    /// 서비스 상태 리셋 (새 녹음 시작 시)
    func reset() async

    /// 녹음 종료 시 호출 (남은 버퍼 처리)
    /// - Returns: 최종 전사 결과들
    func finalize() async throws -> [TranscriptionSegment]

    /// 누적된 모든 전사 결과 반환
    func getTranscriptions() -> [TranscriptionSegment]
}

// MARK: - Protocol Extensions

extension ASRServiceProtocol {

    /// 오디오 버퍼에서 Float 샘플 배열 추출
    func extractSamples(from buffer: AVAudioPCMBuffer) throws -> [Float] {
        guard let floatData = buffer.floatChannelData?[0] else {
            throw ASRServiceError.invalidBuffer
        }

        let frameCount = Int(buffer.frameLength)
        var samples = [Float](repeating: 0, count: frameCount)

        for i in 0..<frameCount {
            samples[i] = floatData[i]
        }

        return samples
    }

    /// 버퍼 처리의 기본 구현 (샘플 추출 후 processSegment 호출)
    func processBuffer(
        _ buffer: AVAudioPCMBuffer,
        startTime: Double
    ) async throws -> TranscriptionSegment {
        let samples = try extractSamples(from: buffer)
        let duration = Double(buffer.frameLength) / 16000.0
        return try await processSegment(
            samples: samples,
            startTime: startTime,
            endTime: startTime + duration
        )
    }
}
