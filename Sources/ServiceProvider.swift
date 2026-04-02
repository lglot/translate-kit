import AppKit
import Foundation

final class ServiceProvider: NSObject {

    @objc func translate(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        print("[TranslateKit] ServiceProvider.translate called")
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            print("[TranslateKit] No text on pasteboard")
            return
        }
        print("[TranslateKit] Received text: \(text.prefix(100))")
        postNotification(text: text, mode: "show")
    }

    @objc func translateAndReplace(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        print("[TranslateKit] ServiceProvider.translateAndReplace called")
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return
        }
        postNotification(text: text, mode: "replace")
    }

    private func postNotification(text: String, mode: String) {
        NotificationCenter.default.post(
            name: .translateServiceTriggered,
            object: nil,
            userInfo: ["text": text, "mode": mode]
        )
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension NSNotification.Name {
    static let translateServiceTriggered = NSNotification.Name("TranslateKitServiceTriggered")
}
