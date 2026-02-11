import AppKit
import OSLog
import ScreenCaptureKit

/// ScreenCaptureKit 기반 캡처 대상 탐색 서비스
///
/// 상태를 보유하지 않는 순수 서비스.
/// 호출 시 ScreenCaptureKit에서 최신 데이터를 가져와 반환.
final class ScreenshotCaptureService {
    private let logger = Logger(subsystem: "shadow_listening", category: "ScreenshotCaptureService")

    deinit {
        logger.info("ScreenshotCaptureService 해제")
    }

    // MARK: - Public API

    /// CaptureTarget 배열 생성 (autoCapture + noCapture + displays + windows)
    func buildCaptureTargets() async -> [CaptureTarget] {
        guard let content = try? await SCShareableContent.current else {
            logger.error("SCShareableContent 조회 실패")
            return [.autoCapture(nil), .noCapture]
        }

        let displays = content.displays.map { $0.toDisplayInfo() }
        let windows = content.windows
            .filter { WindowFilter.shouldInclude($0) }
            .map { $0.toWindowInfo() }

        logger.info("캡처 대상: 디스플레이 \(displays.count)개, 윈도우 \(windows.count)개")

        let displayTargets = displays.map { CaptureTarget.display($0) }
        let windowTargets = windows.map { CaptureTarget.window($0) }
        return [.autoCapture(nil), .noCapture] + displayTargets + windowTargets
    }

    /// 번들 ID로 앱 아이콘 가져오기
    static func getAppIcon(for bundleID: String?, size: CGFloat = 12) -> NSImage? {
        guard
            let bundleID,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: size, height: size)
        return icon
    }
}

// MARK: - Window Filter

/// 캡처 대상 윈도우 필터링 규칙
private enum WindowFilter {
    static let minSize: CGFloat = 50
    static let maxSize: CGFloat = 16000
    static let maxOrigin: CGFloat = 20000
    static let validLayerRange = 0...20

    static let excludedBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.wallpaper.agent",
        "com.apple.WindowManager",
        "com.apple.systemuiserver",
        "com.taperlabs.shadow"
    ]

    /// 윈도우가 캡처 대상에 포함되는지 판단
    static func shouldInclude(_ window: SCWindow) -> Bool {
        let bundleID = window.owningApplication?.bundleIdentifier ?? ""
        let title = window.title ?? ""
        let frame = window.frame

        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && window.isOnScreen
            && !bundleID.isEmpty
            && !excludedBundleIDs.contains(bundleID)
            && validLayerRange.contains(window.windowLayer)
            && frame.width >= minSize && frame.height >= minSize
            && frame.width <= maxSize && frame.height <= maxSize
            && abs(frame.origin.x) <= maxOrigin
            && abs(frame.origin.y) <= maxOrigin
    }
}
