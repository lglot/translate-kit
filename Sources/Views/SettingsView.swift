import SwiftUI
import ServiceManagement
import KeyboardShortcuts
import Translation

struct SettingsView: View {
    var onDone: (() -> Void)? = nil

    @EnvironmentObject private var preferences: PreferencesManager
    @EnvironmentObject private var backendManager: BackendManager

    @State private var deeplAPIKey = ""
    @State private var googleCloudAPIKey = ""
    @State private var selectedBackendID = "apple"
    @State private var showingSaved = false
    @State private var accessibilityGranted = AccessibilityPermission.isGranted

    private let permissionTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("General") {
                    Toggle("Launch at login", isOn: $preferences.launchAtLogin)
                        .onChange(of: preferences.launchAtLogin) { _, newValue in
                            toggleLaunchAtLogin(enabled: newValue)
                        }

                    Toggle("Show menu bar icon", isOn: $preferences.showMenuBarIcon)
                }

                Section("Hotkeys") {
                    KeyboardShortcuts.Recorder("Translate selection (popup):", name: .translateRead)
                    KeyboardShortcuts.Recorder("Translate & replace in place:", name: .translateReplace)

                    LabeledContent("Accessibility permission") {
                        if accessibilityGranted {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.green)
                        } else {
                            HStack(spacing: 6) {
                                Label("Required for hotkeys", systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.orange)
                                Button("Open System Settings") {
                                    AccessibilityPermission.request()
                                    AccessibilityPermission.openSystemSettings()
                                }
                            }
                        }
                    }
                    .onReceive(permissionTimer) { _ in
                        accessibilityGranted = AccessibilityPermission.isGranted
                    }
                }

                Section("Languages") {
                    Picker("Your language:", selection: $preferences.firstLanguage) {
                        ForEach(Language.targetLanguages) { lang in
                            Text("\(lang.flag) \(lang.displayName)").tag(lang)
                        }
                    }
                    Picker("Other language:", selection: $preferences.secondLanguage) {
                        ForEach(Language.targetLanguages) { lang in
                            Text("\(lang.flag) \(lang.displayName)").tag(lang)
                        }
                    }
                    Text("Text detected as one language is translated to the other, in both directions.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    AppleModelStatusView()
                }

                Section("Translation Engine") {
                    Picker("Engine:", selection: $selectedBackendID) {
                        ForEach(backendManager.backends, id: \.id) { backend in
                            Text(backend.name).tag(backend.id)
                        }
                    }
                    .onChange(of: selectedBackendID) { _, newID in
                        if let backend = backendManager.backends.first(where: { $0.id == newID }) {
                            backendManager.setActive(backend)
                        }
                    }

                    Text("Apple translates on-device: your text never leaves the Mac. DeepL and Google Cloud send text to their servers.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
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
        selectedBackendID = backendManager.activeBackendID
        showSavedConfirmation()
    }

    private func showSavedConfirmation() {
        withAnimation { showingSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showingSaved = false }
        }
    }

    private func toggleLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[TranslateKit] Launch at login error: \(error.localizedDescription)")
        }
    }
}

/// Shows whether the on-device Apple model for the configured pair is
/// installed, and triggers the system download sheet when it is not.
struct AppleModelStatusView: View {
    @EnvironmentObject private var preferences: PreferencesManager

    @State private var statusText = "Checking..."
    @State private var needsDownload = false
    @State private var downloadConfig: TranslationSession.Configuration?

    var body: some View {
        LabeledContent("Apple language pack") {
            HStack(spacing: 6) {
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if needsDownload {
                    Button("Download...") {
                        downloadConfig = TranslationSession.Configuration(
                            source: preferences.firstLanguage.localeLanguage,
                            target: preferences.secondLanguage.localeLanguage
                        )
                    }
                }
            }
        }
        .translationTask(downloadConfig) { session in
            do {
                try await session.prepareTranslation()
            } catch {
                // user cancelled the download sheet: status refresh below reflects it
            }
            await refresh()
        }
        .task(id: "\(preferences.firstLanguage.rawValue)-\(preferences.secondLanguage.rawValue)") {
            await refresh()
        }
    }

    private func refresh() async {
        let availability = LanguageAvailability()
        let status = await availability.status(
            from: preferences.firstLanguage.localeLanguage,
            to: preferences.secondLanguage.localeLanguage
        )
        await MainActor.run {
            switch status {
            case .installed:
                statusText = "Installed"
                needsDownload = false
            case .supported:
                statusText = "Not downloaded"
                needsDownload = true
            case .unsupported:
                statusText = "Pair not supported on-device"
                needsDownload = false
            @unknown default:
                statusText = "Unknown"
                needsDownload = false
            }
        }
    }
}
