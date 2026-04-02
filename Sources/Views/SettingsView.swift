import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var preferences: PreferencesManager
    @EnvironmentObject private var backendManager: BackendManager
    @Environment(\.dismiss) private var dismiss

    @State private var deeplAPIKey = ""
    @State private var googleCloudAPIKey = ""
    @State private var selectedBackendID = "google-web"
    @State private var showingSaved = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    generalSection
                    Divider()
                    translationSection
                    Divider()
                    apiKeysSection
                }
                .padding(20)
            }
        }
        .frame(width: 460, height: 440)
        .onAppear {
            deeplAPIKey = KeychainHelper.get("deepl_api_key") ?? ""
            googleCloudAPIKey = KeychainHelper.get("google_cloud_api_key") ?? ""
            selectedBackendID = backendManager.activeBackendID
        }
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("General")
                .font(.system(size: 13, weight: .semibold))

            Toggle("Launch at login", isOn: $preferences.launchAtLogin)
                .toggleStyle(.switch)

            Toggle("Show menu bar icon", isOn: $preferences.showMenuBarIcon)
                .toggleStyle(.switch)

            Toggle("Auto-detect source language", isOn: $preferences.autoDetectSource)
                .toggleStyle(.switch)
        }
    }

    // MARK: - Translation

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Translation")
                .font(.system(size: 13, weight: .semibold))

            HStack {
                Text("Default target language:")
                    .frame(width: 160, alignment: .trailing)

                Picker("", selection: $preferences.targetLanguage) {
                    ForEach(Language.targetLanguages) { lang in
                        Text("\(lang.flag) \(lang.displayName)").tag(lang)
                    }
                }
                .labelsHidden()
            }

            HStack {
                Text("Translation engine:")
                    .frame(width: 160, alignment: .trailing)

                Picker("", selection: $selectedBackendID) {
                    ForEach(backendManager.backends, id: \.id) { backend in
                        Text(backend.name).tag(backend.id)
                    }
                }
                .labelsHidden()
                .onChange(of: selectedBackendID) { newID in
                    if let backend = backendManager.backends.first(where: { $0.id == newID }) {
                        backendManager.setActive(backend)
                    }
                }
            }
        }
    }

    // MARK: - API Keys

    private var apiKeysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("API Keys")
                .font(.system(size: 13, weight: .semibold))

            Text("API keys are stored securely in your macOS Keychain.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            // DeepL
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("DeepL API Key:")
                        .frame(width: 120, alignment: .trailing)
                    SecureField("Enter DeepL API key", text: $deeplAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                    Toggle("Pro", isOn: $preferences.deeplIsPro)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                HStack(spacing: 8) {
                    Spacer().frame(width: 120)
                    Button("Save") {
                        if deeplAPIKey.isEmpty {
                            KeychainHelper.delete("deepl_api_key")
                        } else {
                            KeychainHelper.set(deeplAPIKey, for: "deepl_api_key")
                        }
                        backendManager.reload()
                        showSavedConfirmation()
                    }
                    .buttonStyle(.borderless)

                    Link("Get free API key \u{2192}",
                         destination: URL(string: "https://www.deepl.com/pro-api")!)
                        .font(.system(size: 10))
                }
            }

            // Google Cloud
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Google Cloud Key:")
                        .frame(width: 120, alignment: .trailing)
                    SecureField("Enter Google Cloud API key", text: $googleCloudAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }

                HStack(spacing: 8) {
                    Spacer().frame(width: 120)
                    Button("Save") {
                        if googleCloudAPIKey.isEmpty {
                            KeychainHelper.delete("google_cloud_api_key")
                        } else {
                            KeychainHelper.set(googleCloudAPIKey, for: "google_cloud_api_key")
                        }
                        backendManager.reload()
                        showSavedConfirmation()
                    }
                    .buttonStyle(.borderless)

                    Link("Get API key \u{2192}",
                         destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
                        .font(.system(size: 10))
                }
            }

            if showingSaved {
                HStack {
                    Spacer().frame(width: 120)
                    Label("Saved!", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }
        }
    }

    private func showSavedConfirmation() {
        withAnimation { showingSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showingSaved = false }
        }
    }
}
