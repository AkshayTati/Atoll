import AppKit

/// A borderless panel that can take clicks without activating the app or
/// stealing focus from whatever you are doing.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// AppKit otherwise pushes borderless windows below the menu bar. The
    /// notch panel needs to live in that strip.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
