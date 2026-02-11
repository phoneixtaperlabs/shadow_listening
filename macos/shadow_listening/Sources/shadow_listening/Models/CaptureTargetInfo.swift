import Foundation

/// 캡처 대상을 나타내는 모델
///
/// ScreenshotCaptureService 마이그레이션 전 단계로, SF Symbol 아이콘 기반.
/// Service 연동 후 실제 WindowInfo/DisplayInfo와 매핑 예정.
struct CaptureTargetInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let iconSystemName: String

    /// "No Screenshots" 타겟
    static let noCapture = CaptureTargetInfo(
        id: "no_capture",
        name: "No Screenshots",
        iconSystemName: "xmark.circle"
    )

    /// "Meeting Screen (Auto)" 타겟
    static let autoCapture = CaptureTargetInfo(
        id: "auto_capture",
        name: "Meeting Screen (Auto)",
        iconSystemName: "sparkles"
    )

    /// Flutter 전송용 딕셔너리
    func asDictionary() -> [String: Any] {
        [
            "id": id,
            "name": name,
            "type": id.hasPrefix("display_") ? "display" : "window"
        ]
    }
}
