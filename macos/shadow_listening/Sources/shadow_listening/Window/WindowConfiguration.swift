import AppKit

// MARK: - Window Position

/// Defines how a window should be positioned on screen
enum WindowPosition: Equatable {
    /// Center of the main screen
    case screenCenter

    /// Position relative to a screen edge/corner
    case screen(ScreenAnchor, offset: CGPoint)

    /// Position relative to the main Flutter window
    case flutterWindow(FlutterWindowAnchor, offset: CGPoint)

    /// Absolute position (origin = bottom-left corner in macOS coordinates)
    case absolute(CGPoint)
}

/// Screen anchor points for positioning
enum ScreenAnchor: String, Equatable {
    case topLeft
    case topCenter
    case topRight
    case centerLeft
    case center
    case centerRight
    case bottomLeft
    case bottomCenter
    case bottomRight
}

/// Anchor points relative to Flutter window
enum FlutterWindowAnchor: String, Equatable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case leftCenter
    case rightCenter
}

// MARK: - Window Style

/// Window appearance configuration
struct WindowStyle: Equatable {
    /// Window floats above other windows
    var isFloating: Bool

    /// Background is transparent (for custom shapes)
    var isTransparent: Bool

    /// Show titlebar
    var showsTitlebar: Bool

    /// Window level (floating, normal, etc.)
    var level: NSWindow.Level

    /// Can become key window (receive keyboard input)
    var canBecomeKey: Bool

    /// Window is movable by dragging background
    var isMovableByBackground: Bool

    /// Show window shadow
    var hasShadow: Bool

    // MARK: - Presets

    /// Floating transparent panel (default for overlay windows)
    static let floatingPanel = WindowStyle(
        isFloating: true,
        isTransparent: true,
        showsTitlebar: false,
        level: .floating,
        canBecomeKey: true,
        isMovableByBackground: true,
        hasShadow: false
    )

    /// Standard window with titlebar
    static let standard = WindowStyle(
        isFloating: false,
        isTransparent: false,
        showsTitlebar: true,
        level: .normal,
        canBecomeKey: true,
        isMovableByBackground: false,
        hasShadow: true
    )
}

// MARK: - Window Configuration

/// Complete configuration for creating a managed window
struct WindowConfiguration {
    /// Unique identifier for this window
    let identifier: String

    /// Window size
    var size: CGSize

    /// Position configuration
    var position: WindowPosition

    /// Visual style
    var style: WindowStyle

    /// Minimum size (optional)
    var minSize: CGSize?

    /// Maximum size (optional)
    var maxSize: CGSize?

    // MARK: - Default Configuration

    init(
        identifier: String,
        size: CGSize,
        position: WindowPosition = .screenCenter,
        style: WindowStyle = .floatingPanel,
        minSize: CGSize? = nil,
        maxSize: CGSize? = nil
    ) {
        self.identifier = identifier
        self.size = size
        self.position = position
        self.style = style
        self.minSize = minSize
        self.maxSize = maxSize
    }
}

// MARK: - Window Events

/// Events emitted by managed windows
enum WindowEvent: Equatable {
    case opened(windowId: String)
    case closed(windowId: String)
    case minimized(windowId: String)
    case restored(windowId: String)
    case moved(windowId: String, frame: CGRect)
    case resized(windowId: String, size: CGSize)

    /// Convert to dictionary for Flutter communication
    func toDictionary() -> [String: Any] {
        switch self {
        case .opened(let windowId):
            return ["event": "opened", "windowId": windowId]
        case .closed(let windowId):
            return ["event": "closed", "windowId": windowId]
        case .minimized(let windowId):
            return ["event": "minimized", "windowId": windowId]
        case .restored(let windowId):
            return ["event": "restored", "windowId": windowId]
        case .moved(let windowId, let frame):
            return [
                "event": "moved",
                "windowId": windowId,
                "frame": ["x": frame.origin.x, "y": frame.origin.y, "width": frame.width, "height": frame.height]
            ]
        case .resized(let windowId, let size):
            return [
                "event": "resized",
                "windowId": windowId,
                "size": ["width": size.width, "height": size.height]
            ]
        }
    }
}
