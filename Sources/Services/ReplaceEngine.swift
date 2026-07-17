import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Reads and replaces text in whatever app currently has keyboard focus.
///
/// Strategy: Accessibility API first (precise, no clipboard), synthetic
/// keyboard events as fallback (works in Electron/Chromium apps whose AX tree
/// is incomplete). Both paths require the Accessibility permission.
@MainActor
final class ReplaceEngine {
    static let shared = ReplaceEngine()

    private struct LastReplacement {
        let original: String
        let translated: String
    }
    private var last: LastReplacement?

    private init() {}

    // MARK: - Public flows

    /// Read flow: returns the currently selected text, or throws `.noTextSelected`.
    func captureSelection() async throws -> String {
        if let element = focusedElement(),
           let selected = stringAttribute(element, kAXSelectedTextAttribute),
           !selected.isEmpty {
            return selected
        }
        guard let copied = await copySelectionViaKeyboard(), !copied.isEmpty else {
            throw TranslationError.noTextSelected
        }
        return copied
    }

    /// Write flow: translate the selection (or the whole focused field when
    /// nothing is selected) and replace it in place. Pressing the hotkey again
    /// right after a replacement restores the original text.
    func translateAndReplaceFocused() async throws {
        guard !IsSecureEventInputEnabled() else { throw TranslationError.secureInputActive }

        let capture = try await captureForReplace()
        let trimmed = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.noTextSelected }

        if let last, trimmed == last.translated.trimmingCharacters(in: .whitespacesAndNewlines) {
            try await write(last.original, over: capture)
            self.last = nil
            return
        }

        let result = try await TranslationCoordinator.translate(capture.text)
        try await write(result.translatedText, over: capture)
        last = LastReplacement(original: capture.text, translated: result.translatedText)
    }

    // MARK: - Capture

    private enum Capture {
        case axSelection(AXUIElement, text: String)
        case axValue(AXUIElement, text: String)
        case keyboardSelection(text: String)
        case keyboardWholeField(text: String)

        var text: String {
            switch self {
            case .axSelection(_, let text), .axValue(_, let text),
                 .keyboardSelection(let text), .keyboardWholeField(let text):
                return text
            }
        }
    }

    private func captureForReplace() async throws -> Capture {
        if let element = focusedElement() {
            if let selected = stringAttribute(element, kAXSelectedTextAttribute), !selected.isEmpty {
                if isSettable(element, kAXSelectedTextAttribute) {
                    return .axSelection(element, text: selected)
                }
                return .keyboardSelection(text: selected)
            }
            if let value = stringAttribute(element, kAXValueAttribute), !value.isEmpty {
                if isSettable(element, kAXValueAttribute) {
                    return .axValue(element, text: value)
                }
                return .keyboardWholeField(text: value)
            }
        }

        // No usable AX info: probe with Cmd-C, then Cmd-A + Cmd-C.
        if let selected = await copySelectionViaKeyboard(), !selected.isEmpty {
            return .keyboardSelection(text: selected)
        }
        postKey(CGKeyCode(kVK_ANSI_A), flags: .maskCommand)
        try? await Task.sleep(for: .milliseconds(80))
        if let whole = await copySelectionViaKeyboard(), !whole.isEmpty {
            return .keyboardWholeField(text: whole)
        }
        throw TranslationError.noTextSelected
    }

    // MARK: - Write back

    private func write(_ text: String, over capture: Capture) async throws {
        switch capture {
        case .axSelection(let element, _):
            let err = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
            if err != .success {
                await paste(text)
            }
        case .axValue(let element, let old):
            let err = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFString)
            let written = stringAttribute(element, kAXValueAttribute)
            if err != .success || written == old {
                // some apps (Chromium) accept the set call but ignore it
                postKey(CGKeyCode(kVK_ANSI_A), flags: .maskCommand)
                try? await Task.sleep(for: .milliseconds(80))
                await paste(text)
            }
        case .keyboardSelection:
            await paste(text)
        case .keyboardWholeField:
            postKey(CGKeyCode(kVK_ANSI_A), flags: .maskCommand)
            try? await Task.sleep(for: .milliseconds(80))
            await paste(text)
        }
    }

    // MARK: - Keyboard synthesis

    private func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Presses Cmd-C and returns the copied string, restoring the previous
    /// clipboard contents. Returns nil when nothing was copied (no selection).
    private func copySelectionViaKeyboard() async -> String? {
        let pasteboard = NSPasteboard.general
        let saved = savePasteboard(pasteboard)
        let before = pasteboard.changeCount

        postKey(CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
        let changed = await waitForPasteboardChange(from: before, timeout: 0.35)
        let text = changed ? pasteboard.string(forType: .string) : nil

        restorePasteboard(pasteboard, items: saved)
        return text
    }

    private func paste(_ text: String) async {
        let pasteboard = NSPasteboard.general
        let saved = savePasteboard(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        postKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        // give the target app time to read the pasteboard before restoring it
        try? await Task.sleep(for: .milliseconds(300))
        restorePasteboard(pasteboard, items: saved)
    }

    private func waitForPasteboardChange(from count: Int, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if NSPasteboard.general.changeCount != count { return true }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return false
    }

    private func savePasteboard(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private func restorePasteboard(_ pasteboard: NSPasteboard, items: [NSPasteboardItem]) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    // MARK: - Accessibility helpers

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value)
        guard err == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return settable.boolValue
    }
}

// MARK: - Accessibility permission

enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt asking the user to grant the permission.
    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
