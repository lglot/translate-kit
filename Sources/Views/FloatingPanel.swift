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
