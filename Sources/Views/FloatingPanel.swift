import AppKit
import SwiftUI

final class FloatingTranslationPanel: NSPanel, NSWindowDelegate {

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        delegate = self
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .transient]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        backgroundColor = .clear
        hasShadow = true
    }

    func presentNearCursor() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screenFrame = NSScreen.main?.visibleFrame else {
            center()
            orderFrontRegardless()
            return
        }

        let size = frame.size
        var x = mouseLocation.x - size.width / 2
        var y = mouseLocation.y - size.height - 16

        x = max(screenFrame.minX + 8, min(x, screenFrame.maxX - size.width - 8))
        y = max(screenFrame.minY + 8, min(y, screenFrame.maxY - size.height - 8))

        setFrameOrigin(NSPoint(x: x, y: y))
        orderFrontRegardless()
        makeKey()
    }

    /// Resizes the panel to fit its SwiftUI content, keeping the top-left
    /// corner anchored so the panel grows downward, then clamps the frame back
    /// inside the visible screen area.
    func updateContentSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != frame.size else { return }
        let topLeft = NSPoint(x: frame.minX, y: frame.maxY)
        setContentSize(size)
        setFrameTopLeftPoint(topLeft)

        guard let screenFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        var origin = frame.origin
        origin.x = max(screenFrame.minX + 8, min(origin.x, screenFrame.maxX - frame.width - 8))
        origin.y = max(screenFrame.minY + 8, min(origin.y, screenFrame.maxY - frame.height - 8))
        if origin != frame.origin {
            setFrameOrigin(origin)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Close when clicking outside
    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            close()
        } else {
            super.keyDown(with: event)
        }
    }
}
