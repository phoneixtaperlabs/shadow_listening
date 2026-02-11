import AVFAudio

/// 오디오 서비스 에러 정의
enum AudioServiceError: Error, LocalizedError {
    /// 잘못된 상태 전이 시도
    case invalidStateTransition(from: AudioStreamState, to: String)

    /// AudioUnit 초기화 실패
    case audioUnitInitializationFailed(OSStatus)

    /// 권한 거부됨
    case permissionDenied

    /// 디바이스 사용 불가
    case deviceNotAvailable

    /// 버퍼 생성 실패
    case bufferCreationFailed

    /// 잘못된 버퍼
    case invalidBuffer

    /// 이미 녹음 중
    case alreadyInProgress

    /// 녹음 중이 아님
    case notInProgress

    var errorDescription: String? {
        switch self {
        case .invalidStateTransition(let from, let to):
            return "Invalid state transition from \(from) to \(to)"
        case .audioUnitInitializationFailed(let status):
            return "AudioUnit initialization failed with status: \(status)"
        case .permissionDenied:
            return "Permission denied"
        case .deviceNotAvailable:
            return "Device not available"
        case .bufferCreationFailed:
            return "Buffer creation failed"
        case .invalidBuffer:
            return "Invalid audio buffer"
        case .alreadyInProgress:
            return "Recording is already in progress"
        case .notInProgress:
            return "No recording in progress"
        }
    }
}

/// 오디오 캡처 서비스를 위한 프로토콜
///
/// Mic과 System Audio 서비스가 공통으로 구현하는 인터페이스.
/// 각 서비스는 독립적으로 start/stop/pause 제어가 가능하다.
protocol AudioListenable: AnyObject {
    /// 현재 서비스 상태
    var state: AudioStreamState { get }

    /// 오디오 데이터 스트림 (16kHz, mono, Float32)
    ///
    /// - Note: listening 상태에서만 데이터가 yield됨
    /// - Note: paused 상태에서는 캡처는 계속되지만 데이터는 버려짐
    var audioStream: AsyncStream<AVAudioPCMBuffer> { get }

    /// 청취 시작
    ///
    /// - Throws: `AudioServiceError.invalidStateTransition` - idle/stopped 상태가 아닌 경우
    /// - Throws: `AudioServiceError.permissionDenied` - 권한이 없는 경우
    /// - Throws: `AudioServiceError.audioUnitInitializationFailed` - 오디오 유닛 초기화 실패
    func startListening() throws

    /// 청취 중지
    ///
    /// listening 또는 paused 상태에서 호출 가능.
    /// 모든 리소스를 해제하고 stopped 상태로 전이.
    func stopListening()

    /// 일시정지
    ///
    /// listening 상태에서만 호출 가능.
    /// 캡처는 계속되지만 데이터는 downstream에 전달되지 않음.
    func pauseListening()

    /// 재개
    ///
    /// paused 상태에서만 호출 가능.
    /// 데이터 전달을 다시 시작.
    func resumeListening()
}
