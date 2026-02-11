import Foundation

/// 오디오 서비스의 상태를 나타내는 enum
enum AudioStreamState: String, Equatable, Sendable {
    /// 초기 상태 - startListening() 호출 전
    case idle

    /// 캡처 중이며 데이터를 downstream에 전달하는 상태
    case listening

    /// 캡처는 계속되지만 데이터는 버려지는 상태
    case paused

    /// 완전히 중지된 상태 - 다시 startListening() 호출 가능
    case stopped
}
