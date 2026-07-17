import AppKit
import SwiftUI
import Translation

/// Runs Apple's `TranslationSession` outside any visible UI.
///
/// The Translation framework only exposes sessions through the SwiftUI
/// `.translationTask` modifier, so this provider hosts an invisible 1x1 window
/// whose view owns the session and drains a request queue.
@MainActor
final class AppleTranslationProvider: ObservableObject {
    static let shared = AppleTranslationProvider()

    @Published private(set) var configuration: TranslationSession.Configuration?

    private struct Request {
        let id: UUID
        let text: String
        let source: Language?
        let target: Language
        let continuation: CheckedContinuation<String, Error>
    }

    private var queue: [Request] = []
    private var timeouts: [UUID: Task<Void, Never>] = [:]
    private var currentPair: (source: Language?, target: Language)?
    private var hostWindow: NSWindow?

    private init() {}

    func translate(_ text: String, from source: Language?, to target: Language) async throws -> String {
        ensureHostWindow()

        if let source {
            let status = await LanguageAvailability().status(
                from: source.localeLanguage, to: target.localeLanguage)
            switch status {
            case .installed:
                break
            case .supported:
                throw TranslationError.modelNotDownloaded(source, target)
            case .unsupported:
                throw TranslationError.unsupportedLanguage(
                    "\(source.displayName) to \(target.displayName)")
            @unknown default:
                break
            }
        }

        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            queue.append(Request(id: id, text: text, source: source, target: target, continuation: continuation))
            scheduleTimeout(for: id)
            kickSessionIfNeeded()
        }
    }

    /// Called by the host view whenever the configuration produces a session.
    func drain(using session: TranslationSession) async {
        guard let pair = currentPair else { return }
        var index = 0
        while index < queue.count {
            guard queue[index].source == pair.source, queue[index].target == pair.target else {
                index += 1
                continue
            }
            let request = queue.remove(at: index)
            timeouts.removeValue(forKey: request.id)?.cancel()
            do {
                let response = try await session.translate(request.text)
                request.continuation.resume(returning: response.targetText)
            } catch {
                request.continuation.resume(throwing: error)
            }
        }
        currentPair = nil
        kickSessionIfNeeded()
    }

    private func kickSessionIfNeeded() {
        guard currentPair == nil, let next = queue.first else { return }
        currentPair = (next.source, next.target)
        if var config = configuration,
           config.source == next.source?.localeLanguage,
           config.target == next.target.localeLanguage {
            config.invalidate()
            configuration = config
        } else {
            configuration = TranslationSession.Configuration(
                source: next.source?.localeLanguage,
                target: next.target.localeLanguage)
        }
    }

    private func scheduleTimeout(for id: UUID) {
        // ponytail: timeout only covers waiting in queue; a translate() call that
        // hangs inside the session is not interrupted. Extend if it ever bites.
        timeouts[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if let index = self.queue.firstIndex(where: { $0.id == id }) {
                let request = self.queue.remove(at: index)
                request.continuation.resume(throwing: TranslationError.apiError("Apple Translation timed out"))
                if self.currentPair?.target == request.target, self.currentPair?.source == request.source {
                    self.currentPair = nil
                }
                self.kickSessionIfNeeded()
            }
            self.timeouts.removeValue(forKey: id)
        }
    }

    private func ensureHostWindow() {
        guard hostWindow == nil else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.contentView = NSHostingView(rootView: AppleTranslationHostView())
        window.orderBack(nil)
        hostWindow = window
    }
}

private struct AppleTranslationHostView: View {
    @ObservedObject var provider = AppleTranslationProvider.shared

    var body: some View {
        Color.clear
            .translationTask(provider.configuration) { session in
                await provider.drain(using: session)
            }
    }
}
