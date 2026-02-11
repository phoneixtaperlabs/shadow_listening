import SwiftUI
import AppKit

/// Custom NSHostingView that accepts first mouse clicks even when window is inactive.
///
/// This allows users to interact with floating panels without first clicking to activate the window.
/// Essential for overlay/floating UI that should respond immediately to user interaction.
///
/// ## Usage
/// ```swift
/// let hostingView = FirstClickHostingView(rootView: MySwiftUIView())
/// window.contentView = hostingView
/// ```
public final class FirstClickHostingView<Content: View>: NSHostingView<Content> {

    /// Accept mouse clicks even when the window is not key (inactive).
    /// Returns `true` to allow immediate interaction without requiring window activation.
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    /// Allow the view to become first responder for keyboard events.
    public override var acceptsFirstResponder: Bool {
        return true
    }
}
