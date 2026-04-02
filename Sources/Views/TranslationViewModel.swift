import SwiftUI

enum TranslationMode {
    case show
    case replace
}

@MainActor
final class TranslationViewModel: ObservableObject {
    @Published var sourceText: String = ""
    @Published var translatedText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var detectedSourceLanguage: Language?
    @Published var mode: TranslationMode = .show
    @Published var showPanel: Bool = false

    private weak var sourcePasteboard: NSPasteboard?
    private let backendManager = BackendManager.shared
    private let preferences = PreferencesManager.shared

    func translate(_ text: String, mode: TranslationMode = .show, pasteboard: NSPasteboard? = nil) {
        sourceText = text
        self.mode = mode
        self.sourcePasteboard = pasteboard
        translatedText = ""
        errorMessage = nil
        detectedSourceLanguage = nil
        showPanel = true
        isLoading = true

        Task {
            await performTranslation()
        }
    }

    func retryTranslation() {
        guard !sourceText.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        Task {
            await performTranslation()
        }
    }

    func replaceSelection() {
        guard let pasteboard = sourcePasteboard, !translatedText.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(translatedText, forType: .string)
        showPanel = false
    }

    private func performTranslation() async {
        guard !sourceText.isEmpty else {
            isLoading = false
            return
        }

        let source: Language = preferences.autoDetectSource ? .auto : .english
        let target = preferences.targetLanguage

        do {
            let result = try await backendManager.activeBackend.translate(
                sourceText,
                from: source,
                to: target
            )

            withAnimation(.easeOut(duration: 0.2)) {
                translatedText = result.translatedText
                detectedSourceLanguage = result.sourceLanguage
                isLoading = false
            }
        } catch {
            withAnimation {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}
