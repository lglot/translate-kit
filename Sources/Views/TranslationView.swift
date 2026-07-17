import SwiftUI

struct TranslatingView: View {
    let sourceText: String
    var onSizeChange: ((CGSize) -> Void)? = nil

    @State private var translatedText: String = ""
    @State private var errorMessage: String?
    @State private var isLoading: Bool = true
    @State private var target: Language?
    @State private var targetOverride: Language?

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
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ViewSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(ViewSizeKey.self) { size in
            onSizeChange?(size)
        }
        .task {
            await translate()
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

            Menu {
                ForEach(Language.targetLanguages) { lang in
                    Button {
                        guard lang != target else { return }
                        targetOverride = lang
                        Task { await translate() }
                    } label: {
                        if lang == target {
                            Label("\(lang.flag) \(lang.displayName)", systemImage: "checkmark")
                        } else {
                            Text("\(lang.flag) \(lang.displayName)")
                        }
                    }
                }
            } label: {
                if let target {
                    Text("\(target.flag) \(target.displayName)")
                        .font(.system(size: 11))
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

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
            VStack(alignment: .leading, spacing: 4) {
                Text("ORIGINAL")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                ScrollView {
                    Text(sourceText)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
                .fixedSize(horizontal: false, vertical: true)
            }

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
                        ScrollView {
                            Text(translatedText)
                                .font(.system(size: 15, weight: .medium))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .frame(maxHeight: 320)
                        .fixedSize(horizontal: false, vertical: true)
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
            let backend = BackendManager.shared.activeBackend
            Label(backend.name, systemImage: backend.id == "apple" ? "apple.logo" : "cloud")
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

    // MARK: - Translation

    private func translate() async {
        await MainActor.run {
            withAnimation {
                isLoading = true
                errorMessage = nil
            }
        }
        do {
            let result = try await TranslationCoordinator.translate(sourceText, targetOverride: targetOverride)
            await MainActor.run {
                withAnimation {
                    translatedText = result.translatedText
                    target = result.targetLanguage
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

struct ViewSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
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
