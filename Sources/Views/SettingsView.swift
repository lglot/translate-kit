import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var onDone: (() -> Void)? = nil

    @EnvironmentObject private var preferences: PreferencesManager
    @EnvironmentObject private var backendManager: BackendManager

    @State private var deeplAPIKey = ""
    @State private var googleCloudAPIKey = ""
    @State private var selectedBackendID = "google-web"
    @State private var showingSaved = false

    var body: some View {
        VStack(spacing: 0) {
            // Content
            Form {
                Section("General") {
                    Toggle("Launch at login", isOn: $preferences.launchAtLogin)
                        .onChange(of: preferences.launchAtLogin) { newValue in
                            toggleLaunchAtLogin(enabled: newValue)
                        }

                    Toggle("Show menu bar icon", isOn: $preferences.showMenuBarIcon)

                    Toggle("Auto-detect source language", isOn: $preferences.autoDetectSource)
                }

                Section("Translation") {
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
                }

                Section("API Keys") {
                    LabeledContent("DeepL") {
                        HStack(spacing: 6) {
                            SecureField("API key", text: $deeplAPIKey)
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

                    Link("Get free DeepL API key", destination: URL(string: "https://www.deepl.com/pro-api")!)
                        .font(.system(size: 11))

                    LabeledContent("Google Cloud") {
                        HStack(spacing: 6) {
                            SecureField("API key", text: $googleCloudAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                            Button("Save") {
                                saveKey(googleCloudAPIKey, keychainKey: "google_cloud_api_key")
                            }
                        }
                    }

                    Link("Get Google Cloud API key", destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
                        .font(.system(size: 11))

                    if showingSaved {
                        Label("Saved in Keychain", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                    }
                }
            }
            .formStyle(.grouped)

            // Done button at bottom
            HStack {
                Spacer()
                Button("Done") { onDone?() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding(.bottom, 16)
        }
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

    private func toggleLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[TranslateKit] Launch at login error: \(error)")
            }
        }
    }
}
