import AppKit

/// All the rectangles the notch panel needs, in global screen coordinates.
///
/// The built-in display is the only one with a physical notch. We discover it
/// with `safeAreaInsets.top` plus the two auxiliary areas that macOS exposes
/// on either side of the cutout.
struct IslandGeometry {
    let screen: NSScreen
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let collapsedFrame: NSRect
    let expandedFrame: NSRect
    let hotZone: NSRect

    static func resolve() -> IslandGeometry? {
        guard let screen = NSScreen.screens.first(where: {
            $0.safeAreaInsets.top > 0
                && $0.auxiliaryTopLeftArea != nil
                && $0.auxiliaryTopRightArea != nil
        }) else {
            return nil
        }

        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else {
            return nil
        }

        let notchWidth = max(120, right.minX - left.maxX)
        let notchHeight = max(24, screen.safeAreaInsets.top)
        let centerX = (left.maxX + right.minX) / 2
        let topY = screen.frame.maxY

        // When idle the island should be indistinguishable from the hardware
        // cutout. Stay 1pt inside it so anti-aliasing can't bleed onto the
        // menu bar; the hover target still covers the notch.
        let collapsedWidth = max(120, notchWidth - 2)
        let collapsedHeight = max(20, notchHeight - 2)

        let expandedWidth = min(max(notchWidth + 220, 560), screen.frame.width - 80)
        let expandedHeight = notchHeight + 276

        let collapsedFrame = NSRect(
            x: (centerX - collapsedWidth / 2).rounded(),
            y: topY - collapsedHeight,
            width: collapsedWidth.rounded(),
            height: collapsedHeight
        )
        let expandedFrame = NSRect(
            x: (centerX - expandedWidth / 2).rounded(),
            y: topY - expandedHeight,
            width: expandedWidth.rounded(),
            height: expandedHeight
        )

        // Easy-to-hit hover target: the collapsed island plus a little margin,
        // especially below the notch where the pointer usually approaches.
        var hotZone = collapsedFrame
        hotZone.origin.y -= 12
        hotZone.size.height += 12
        hotZone = hotZone.insetBy(dx: -8, dy: 0)

        return IslandGeometry(
            screen: screen,
            notchWidth: notchWidth,
            notchHeight: notchHeight,
            collapsedFrame: collapsedFrame,
            expandedFrame: expandedFrame,
            hotZone: hotZone
        )
    }
}
