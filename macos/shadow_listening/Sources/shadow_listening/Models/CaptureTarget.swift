import AppKit
import ScreenCaptureKit

// MARK: - WindowInfo

/// 윈도우 정보 (SCWindow → Flutter 전달용)
struct WindowInfo: Identifiable, Equatable {
    var id: CGWindowID { windowID }

    let windowID: CGWindowID
    let title: String
    let appName: String
    let windowLayer: Int?
    let bundleID: String?
    let frame: CGRect
    let isOnScreen: Bool
    let isActive: Bool

    /// Flutter 전송용 딕셔너리
    func asDictionary() -> [String: Any] {
        [
            "type": "window",
            "windowID": Int(windowID),
            "title": title,
            "appName": appName,
            "windowLayer": windowLayer as Any,
            "bundleID": bundleID as Any,
            "x": Double(frame.origin.x),
            "y": Double(frame.origin.y),
            "width": Double(frame.size.width),
            "height": Double(frame.size.height),
            "isOnScreen": isOnScreen,
            "isActive": isActive
        ]
    }
}

// MARK: - DisplayInfo

/// 디스플레이 정보 (SCDisplay → Flutter 전달용)
struct DisplayInfo: Identifiable, Equatable {
    var id: Int { displayID }

    let displayID: Int
    let localizedName: String
    let frame: CGRect
    let width: Int
    let height: Int

    /// Flutter 전송용 딕셔너리
    func asDictionary() -> [String: Any] {
        [
            "type": "display",
            "displayID": displayID,
            "localizedName": localizedName,
            "x": Double(frame.origin.x),
            "y": Double(frame.origin.y),
            "width": width,
            "height": height
        ]
    }
}

// MARK: - CaptureTarget

/// 캡처 대상 (디스플레이 또는 윈도우)
enum CaptureTarget: Identifiable, Equatable {
    case autoCapture(WindowInfo?)
    case noCapture
    case display(DisplayInfo)
    case window(WindowInfo)

    var id: String {
        switch self {
        case .autoCapture: return "auto_capture"
        case .noCapture: return "no_capture"
        case .display(let info): return "display_\(info.displayID)"
        case .window(let info): return "window_\(info.windowID)"
        }
    }

    /// 표시 이름
    var name: String {
        switch self {
        case .autoCapture(let windowInfo):
            if let window = windowInfo {
                return "Meeting Screen (\(window.title))"
            }
            return "Meeting Screen (Auto)"
        case .noCapture: return "No Screenshots"
        case .display(let info): return info.localizedName
        case .window(let info): return "\(info.appName) — \(info.title)"
        }
    }

    /// SF Symbol 아이콘 이름 (View에서 바로 사용)
    var iconSystemName: String {
        switch self {
        case .autoCapture: return "sparkles"
        case .noCapture: return "xmark.circle"
        case .display: return "desktopcomputer"
        case .window: return "macwindow"
        }
    }

    /// 앱 아이콘 (window 타입만 해당, 나머지는 nil)
    var appIcon: NSImage? {
        switch self {
        case .window(let info):
            return ScreenshotCaptureService.getAppIcon(for: info.bundleID, size: 16)
        default:
            return nil
        }
    }

    /// Flutter 전송용 딕셔너리
    func asDictionary() -> [String: Any] {
        switch self {
        case .autoCapture(let windowInfo):
            if let window = windowInfo {
                var dict = window.asDictionary()
                dict["type"] = "autoCapture"
                return dict
            }
            return ["type": "autoCapture"]
        case .noCapture:
            return ["type": "noCapture"]
        case .display(let info):
            return info.asDictionary()
        case .window(let info):
            return info.asDictionary()
        }
    }
}

// MARK: - ScreenCaptureKit Extensions

extension SCWindow {
    /// SCWindow → WindowInfo 변환
    func toWindowInfo() -> WindowInfo {
        WindowInfo(
            windowID: windowID,
            title: title ?? "",
            appName: owningApplication?.applicationName ?? "Unknown App",
            windowLayer: windowLayer,
            bundleID: owningApplication?.bundleIdentifier,
            frame: frame,
            isOnScreen: isOnScreen,
            isActive: isActive
        )
    }
}

extension SCDisplay {
    /// SCDisplay → DisplayInfo 변환 (NSScreen 매칭으로 localizedName 포함)
    func toDisplayInfo() -> DisplayInfo {
        let name = NSScreen.screens.first { screen in
            screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == self.displayID
        }?.localizedName ?? "Unknown Display"

        return DisplayInfo(
            displayID: Int(self.displayID),
            localizedName: name,
            frame: self.frame,
            width: self.width,
            height: self.height
        )
    }
}
