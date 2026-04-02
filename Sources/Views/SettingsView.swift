import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var preferences: PreferencesManager
    @EnvironmentObject private var backendManager: BackendManager
    @Environment(\.dismiss) private var dismiss

    @State private var deeplAPIKey = ""
    @State private var googleCloudAPIKey = ""
    @State private var selectedBackendID = "google-web"
    @State private var showingSaved = false

    private let labelWidth: CGFloat = 150

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

            Form {
                Section {
                    Toggle("Launch at login", isOn: $preferences.launchAtLogin)
                    Toggle("Show menu bar icon", isOn: $preferences.showMenuBarIcon)
                    Toggle("Auto-detect source language", isOn: $preferences.autoDetectSource)
                } header: {
                    Text("General")
                }

                Section {
                    Picker("Target language:", selection: $preferences.targetLanguage) {
                        ForEach(Language.targetLanguages) { lang in
                            Text("\(lang.flag) \(lang.displayName)").tag(lang)
                        }
                    }

                    Picker("Translation engine:", selection: $selectedBackendID) {
                        ForEach(backendManager.backends, id: \.id) { backend in
                            Text(backend.name).tag(backend.id)
                        }
                    }
                    .onChange(of: selectedBackendID) { newID in
                        if let backend = backendManager.backends.first(where: { $0.id == newID }) {
                            backendManager.setActive(backend)
                        }
                    }
                } header: {
                    Text("Translation")
                }

                Section {
                    Text("Stored securely in macOS Keychain.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    LabeledContent("DeepL API Key:") {
                        HStack(spacing: 6) {
                            SecureField("Enter key", text: $deeplAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                            Toggle("Pro", isOn: $preferences.deeplIsPro)
                                .toggleStyle(.switch)
                                .labelsHidden()
                            Button("Save") {
                                saveKey(deeplAPIKey, keychainKey: "deepl_api_key")
                            }
                        }
                    }

                    LabeledContent("") {
                        Link("Get free DeepL API key \u{2192}",
                             destination: URL(string: "https://www.deepl.com/pro-api")!)
                            .font(.system(size: 10))
                    }

                    LabeledContent("Google Cloud Key:") {
                        HStack(spacing: 6) {
                            SecureField("Enter key", text: $googleCloudAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                            Button("Save") {
                                saveKey(googleCloudAPIKey, keychainKey: "google_cloud_api_key")
                            }
                        }
                    }

                    LabeledContent("") {
                        Link("Get Google Cloud API key \u{2192}",
                             destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
                            .font(.system(size: 10))
                    }

                    if showingSaved {
                        LabeledContent("") {
                            Label("Saved!", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.green)
                        }
                    }
                } header: {
                    Text("API Keys")
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 480, height: 520)
        .onAppear {
            deeplAPIKey = KeychainHelper.get("deepl_api_key") ?? ""
            googleCloudAPIKey = KeychainHelper.get("google_cloud_api_key") ?? ""
            selectedBackendID = backendManager.activeBackendID
        }
    }

    private func saveKey(_ value: String, keychainKey: String) {
        if value.isEmpty {
            KeychainHelper.delete(keychainKey)
        } else {
            KeychainHelper.set(value, for: keychainKey)
        }
        backendManager.reload()
        showSavedConfirmation()
    }

    private func showSavedConfirmation() {
        withAnimation { showingSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showingSaved = false }
        }
    }
}
