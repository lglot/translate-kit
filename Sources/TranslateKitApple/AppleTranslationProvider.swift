import AppKit
import SwiftUI
import Translation
import TranslateKitCore

struct AppleTranslationOutput: Sendable {
    let text: String
    let sourceLanguage: Language
}

struct HostedAppleTranslationSession {
    let generation: UUID
    let source: Language?
    let target: Language
    var configuration: TranslationSession.Configuration
}

/// Runs Apple's `TranslationSession` outside any visible UI.
///
/// The Translation framework only exposes sessions through the SwiftUI
/// `.translationTask` modifier, so this provider hosts an invisible 1x1 window
/// whose view owns the session and drains a request queue.
@MainActor
final class AppleTranslationProvider: ObservableObject {
    static let shared = AppleTranslationProvider()

    @Published private(set) var hostedSession: HostedAppleTranslationSession?

    private struct Pair: Equatable {
        let source: Language?
        let target: Language
    }

    private struct Request {
        let id: UUID
        let text: String
        let pair: Pair
        let continuation: CheckedContinuation<AppleTranslationOutput, Error>
    }

    typealias SessionTranslator = @MainActor (String) async throws -> AppleTranslationOutput

    private let requestTimeout: Duration
    private let hostsWindow: Bool
    private var requests: [UUID: Request] = [:]
    private var queue: [UUID] = []
    private var timeouts: [UUID: Task<Void, Never>] = [:]
    private var currentPair: Pair?
    private var currentGeneration: UUID?
    private var inFlightRequestID: UUID?
    private var currentDrain: (generation: UUID, task: Task<Void, Never>)?
    private var hostWindow: NSWindow?

    init(requestTimeout: Duration = .seconds(20), hostsWindow: Bool = true) {
        self.requestTimeout = requestTimeout
        self.hostsWindow = hostsWindow
    }

    func translate(
        _ text: String,
        from source: Language?,
        to target: Language
    ) async throws -> AppleTranslationOutput {
        if hostsWindow { ensureHostWindow() }

        if let source {
            let status = await LanguageAvailability().status(
                from: source.localeLanguage,
                to: target.localeLanguage
            )
            switch status {
            case .installed:
                break
            case .supported:
                throw TranslationError.modelNotDownloaded(source, target)
            case .unsupported:
                throw TranslationError.unsupportedLanguage(
                    "\(source.displayName) to \(target.displayName)"
                )
            @unknown default:
                break
            }
        }

        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let request = Request(
                    id: id,
                    text: text,
                    pair: Pair(source: source, target: target),
                    continuation: continuation
                )
                requests[id] = request
                queue.append(id)
                scheduleTimeout(for: id)
                kickSessionIfNeeded()
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancelRequest(id)
            }
        }
    }

    /// Called by the host view for the exact configuration generation that
    /// produced `session`. Stale callbacks are ignored before reading the queue.
    func runHostedSession(
        _ hosted: HostedAppleTranslationSession,
        translator: @escaping SessionTranslator
    ) async {
        guard currentGeneration == hosted.generation else { return }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.drain(hosted: hosted, translator: translator)
        }
        currentDrain = (hosted.generation, task)
        await task.value
        if currentDrain?.generation == hosted.generation {
            currentDrain = nil
        }
    }

    private func drain(
        hosted: HostedAppleTranslationSession,
        translator: @escaping SessionTranslator
    ) async {
        let pair = Pair(source: hosted.source, target: hosted.target)
        guard currentGeneration == hosted.generation, currentPair == pair else { return }

        while currentGeneration == hosted.generation,
              let queueIndex = queue.firstIndex(where: { id in
                  requests[id]?.pair == pair
              }) {
            let id = queue.remove(at: queueIndex)
            guard let request = requests[id] else { continue }
            inFlightRequestID = id

            let result: Result<AppleTranslationOutput, Error>
            do {
                result = .success(try await translator(request.text))
            } catch {
                result = .failure(error)
            }

            guard currentGeneration == hosted.generation else { return }
            inFlightRequestID = nil
            finishRequest(id, with: result)
        }

        guard currentGeneration == hosted.generation else { return }
        resetCurrentSession(cancelDrain: false)
        kickSessionIfNeeded()
    }

    private func scheduleTimeout(for id: UUID) {
        timeouts[id] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: requestTimeout)
            guard !Task.isCancelled else { return }
            timeoutRequest(id)
        }
    }

    private func timeoutRequest(_ id: UUID) {
        guard requests[id] != nil else { return }
        let wasInFlight = inFlightRequestID == id
        let pair = requests[id]?.pair
        finishRequest(
            id,
            with: .failure(TranslationError.apiError("Apple Translation timed out"))
        )
        recoverSessionAfterRequestRemoval(pair: pair, wasInFlight: wasInFlight)
    }

    private func cancelRequest(_ id: UUID) {
        guard requests[id] != nil else { return }
        let wasInFlight = inFlightRequestID == id
        let pair = requests[id]?.pair
        finishRequest(id, with: .failure(CancellationError()))
        recoverSessionAfterRequestRemoval(pair: pair, wasInFlight: wasInFlight)
    }

    private func recoverSessionAfterRequestRemoval(pair: Pair?, wasInFlight: Bool) {
        guard pair == currentPair else { return }
        let hasQueuedRequestForPair = queue.contains { requests[$0]?.pair == pair }
        if wasInFlight || (!hasQueuedRequestForPair && inFlightRequestID == nil) {
            resetCurrentSession(cancelDrain: true)
            kickSessionIfNeeded()
        }
    }

    private func finishRequest(
        _ id: UUID,
        with result: Result<AppleTranslationOutput, Error>
    ) {
        guard let request = requests.removeValue(forKey: id) else { return }
        queue.removeAll { $0 == id }
        timeouts.removeValue(forKey: id)?.cancel()
        switch result {
        case .success(let output):
            request.continuation.resume(returning: output)
        case .failure(let error):
            request.continuation.resume(throwing: error)
        }
    }

    private func kickSessionIfNeeded() {
        guard currentGeneration == nil else { return }
        while let id = queue.first, requests[id] == nil {
            queue.removeFirst()
        }
        guard let id = queue.first, let request = requests[id] else {
            hostedSession = nil
            return
        }

        let generation = UUID()
        currentPair = request.pair
        currentGeneration = generation
        hostedSession = HostedAppleTranslationSession(
            generation: generation,
            source: request.pair.source,
            target: request.pair.target,
            configuration: TranslationSession.Configuration(
                source: request.pair.source?.localeLanguage,
                target: request.pair.target.localeLanguage
            )
        )
    }

    private func resetCurrentSession(cancelDrain: Bool) {
        if cancelDrain { currentDrain?.task.cancel() }
        currentDrain = nil
        currentPair = nil
        currentGeneration = nil
        inFlightRequestID = nil
        if var hosted = hostedSession {
            hosted.configuration.invalidate()
            hostedSession = hosted
        }
        hostedSession = nil
    }

    private func ensureHostWindow() {
        guard hostWindow == nil else { return }
        let application = NSApplication.shared
        if Bundle.main.bundleURL.pathExtension.lowercased() != "app" {
            application.setActivationPolicy(.prohibited)
        }
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
        Group {
            if let hosted = provider.hostedSession {
                Color.clear
                    .id(hosted.generation)
                    .translationTask(hosted.configuration) { session in
                        await provider.runHostedSession(hosted) { text in
                            let response = try await session.translate(text)
                            return AppleTranslationOutput(
                                text: response.targetText,
                                sourceLanguage: Language(localeLanguage: response.sourceLanguage)
                                    ?? hosted.source
                                    ?? .auto
                            )
                        }
                    }
            } else {
                Color.clear
            }
        }
    }
}
