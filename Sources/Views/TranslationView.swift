import SwiftUI
import Translation

struct TranslatingView: View {
    let sourceText: String
    let sourceLanguage: Language
    let targetLanguage: Language
    let backend: TranslationBackend

    @State private var translatedText: String = ""
    @State private var errorMessage: String?
    @State private var isLoading: Bool = true
    @State private var detectedLanguage: Language?

    private var isAppleBackend: Bool {
        backend.id == "apple"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.horizontal, 12)
            content
            Divider().padding(.horizontal, 12)
            footer
        }
        .background(VisualEffectBackground())
        .frame(width: 480)
        .task {
            if isAppleBackend {
                if #available(macOS 15.0, *) {
                    // Apple Translation handled by AppleTranslationHost below
                } else {
                    errorMessage = "Apple Translation requires macOS 15+"
                    isLoading = false
                }
            } else {
                await translateWithHTTP()
            }
        }
        .overlay {
            if isAppleBackend, #available(macOS 15.0, *) {
                AppleTranslationHost(
                    text: sourceText,
                    source: sourceLanguage,
                    target: targetLanguage,
                    translatedText: $translatedText,
                    isLoading: $isLoading,
                    errorMessage: $errorMessage
                )
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "translate")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.blue)
            Text("TranslateKit")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("\(targetLanguage.flag) \(targetLanguage.displayName)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button {
                NSApp.keyWindow?.close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Source
            VStack(alignment: .leading, spacing: 4) {
                Text("ORIGINAL")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(sourceText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Translation
            VStack(alignment: .leading, spacing: 4) {
                Text("TRANSLATION")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)

                Group {
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Translating...")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                    } else if let error = errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                    } else {
                        Text(translatedText)
                            .font(.system(size: 15, weight: .medium))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        HStack {
            Label(backend.name, systemImage: isAppleBackend ? "apple.logo" : "cloud")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(translatedText, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .disabled(translatedText.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - HTTP Translation

    private func translateWithHTTP() async {
        do {
            let result = try await backend.translate(sourceText, from: sourceLanguage, to: targetLanguage)
            await MainActor.run {
                withAnimation {
                    translatedText = result.translatedText
                    isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                withAnimation {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Apple Translation Host (macOS 15+)

@available(macOS 15.0, *)
struct AppleTranslationHost: View {
    let text: String
    let source: Language
    let target: Language

    @Binding var translatedText: String
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?

    @State private var config: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                config = TranslationSession.Configuration(
                    source: source == .auto ? nil : Locale.Language(identifier: source.rawValue),
                    target: Locale.Language(identifier: target.rawValue)
                )
            }
            .translationTask(config) { session in
                do {
                    let response = try await session.translate(text)
                    await MainActor.run {
                        withAnimation {
                            translatedText = response.targetText
                            isLoading = false
                        }
                    }
                } catch {
                    await MainActor.run {
                        withAnimation {
                            errorMessage = error.localizedDescription
                            isLoading = false
                        }
                    }
                }
            }
    }
}

// MARK: - Visual Effect Background

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
