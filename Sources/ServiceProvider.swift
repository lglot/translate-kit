import AppKit
import Foundation

final class ServiceProvider: NSObject {

    @objc func translate(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        NotificationCenter.default.post(
            name: .translateServiceTriggered,
            object: nil,
            userInfo: ["text": text]
        )
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Synchronous replace: macOS substitutes the selection with whatever we
    /// leave on the pasteboard before returning, so we pump the run loop until
    /// the async translation completes.
    @objc func translateAndReplace(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }

        final class Box {
            var result: Result<String, Error>?
        }
        let box = Box()
        Task { @MainActor in
            do {
                box.result = .success(try await TranslationCoordinator.translate(text).translatedText)
            } catch {
                box.result = .failure(error)
            }
        }

        let deadline = Date().addingTimeInterval(20)
        while box.result == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        guard case .success(let translated) = box.result else {
            error.pointee = "TranslateKit: translation failed" as NSString
            return
        }
        pasteboard.clearContents()
        pasteboard.setString(translated, forType: .string)
    }
}

extension NSNotification.Name {
    static let translateServiceTriggered = NSNotification.Name("TranslateKitServiceTriggered")
}
