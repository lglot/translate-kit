import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import TranslateKitCore
import Translation

struct SettingsView: View {
    var onDone: (() -> Void)? = nil

    @EnvironmentObject private var preferences: PreferencesManager
    @EnvironmentObject private var backendManager: BackendManager

    @State private var selectedBackendID = ProviderID.apple.rawValue
    @State private var apiKeys: [ProviderID: String] = [:]
    @State private var savedAPIKeys: [ProviderID: String] = [:]
    @State private var credentialStatus: [ProviderID: CredentialSaveStatus] = [:]
    @State private var azureEndpoint = ""
    @State private var libreTranslateEndpoint = ""
    @State private var awsAccessKeyID = ""
    @State private var awsSecretAccessKey = ""
    @State private var awsSessionToken = ""
    @State private var savedAWSValues = AWSSecretValues.empty
    @State private var accessibilityGranted = AccessibilityPermission.isGranted

    private let permissionTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if let error = preferences.configurationError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(preferences.configurationURL.path)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    } header: {
                        Text("Configuration requires attention")
                    }
                }

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
                        ForEach(Language.targetLanguages.filter { $0 != preferences.secondLanguage }) { language in
                            Text("\(language.flag) \(language.displayName)").tag(language)
                        }
                    }
                    Picker("Other language:", selection: $preferences.secondLanguage) {
                        ForEach(Language.targetLanguages.filter { $0 != preferences.firstLanguage }) { language in
                            Text("\(language.flag) \(language.displayName)").tag(language)
                        }
                    }
                    Text("Text detected as one language is translated to the other, in both directions.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    AppleModelStatusView()
                }

                Section("Translation Engine") {
                    Picker("Engine:", selection: $selectedBackendID) {
                        ForEach(backendManager.providers, id: \.descriptor.id) { state in
                            Text(state.descriptor.name).tag(state.descriptor.id.rawValue)
                        }
                    }
                    .onChange(of: selectedBackendID) { _, newID in
                        guard let provider = ProviderID(rawValue: newID) else { return }
                        backendManager.setActive(provider)
                    }

                    if let state = selectedProviderState, !state.isConfigured {
                        Label("No usable credential was discovered for this provider.", systemImage: "key.slash")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }

                    Text(privacyDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Section("Provider Configuration") {
                    Picker("Google authentication", selection: $preferences.googleCloudAuth) {
                        Text("Automatic").tag("auto")
                        Text("API key").tag("api-key")
                        Text("gcloud").tag("gcloud")
                    }

                    Picker("Azure authentication", selection: $preferences.azureAuth) {
                        Text("Automatic").tag("auto")
                        Text("API key").tag("api-key")
                        Text("Entra CLI").tag("entra")
                    }
                    endpointRow(
                        title: "Azure endpoint",
                        value: $azureEndpoint,
                        savedValue: preferences.azureEndpoint,
                        save: saveAzureEndpoint
                    )
                    TextField("Azure region", text: $preferences.azureRegion)

                    Picker("AWS authentication", selection: $preferences.awsAuth) {
                        Text("Profile or native chain").tag("profile")
                        Text("Static credentials").tag("static")
                    }
                    if preferences.awsAuth == "profile" {
                        if awsProfiles.isEmpty {
                            TextField("AWS profile (default when empty)", text: $preferences.awsProfile)
                        } else {
                            Picker("AWS profile", selection: $preferences.awsProfile) {
                                Text("Default chain").tag("")
                                ForEach(awsProfiles, id: \.self) { Text($0).tag($0) }
                            }
                        }
                    }
                    TextField("AWS region (SDK default when empty)", text: $preferences.awsRegion)

                    endpointRow(
                        title: "LibreTranslate endpoint",
                        value: $libreTranslateEndpoint,
                        savedValue: preferences.libreTranslateEndpoint,
                        save: saveLibreTranslateEndpoint
                    )
                }

                Section("API Keys") {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                        apiKeyRow(provider: .deepl, title: "DeepL")
                        GridRow {
                            Color.clear.frame(width: 110, height: 1)
                            HStack(spacing: 12) {
                                Toggle("Pro account", isOn: $preferences.deeplIsPro)
                                Link(
                                    "Create a DeepL API key",
                                    destination: URL(string: "https://www.deepl.com/pro-api")!
                                )
                            }
                            .font(.system(size: 11))
                            .gridCellColumns(2)
                        }

                        apiKeyRow(provider: .googleCloud, title: "Google Cloud")
                        GridRow {
                            Color.clear.frame(width: 110, height: 1)
                            Link(
                                "Create a Google Cloud API key",
                                destination: URL(string: "https://console.cloud.google.com/apis/credentials")!
                            )
                            .font(.system(size: 11))
                            .gridCellColumns(2)
                        }

                        apiKeyRow(provider: .azure, title: "Azure")
                        apiKeyRow(provider: .libretranslate, title: "LibreTranslate")
                    }

                    DisclosureGroup("AWS static credentials (advanced)") {
                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                            GridRow {
                                Text("Access key ID")
                                SecureField("Paste access key ID", text: $awsAccessKeyID)
                                    .frame(width: 260)
                            }
                            GridRow {
                                Text("Secret access key")
                                SecureField("Paste secret access key", text: $awsSecretAccessKey)
                                    .frame(width: 260)
                            }
                            GridRow {
                                Text("Session token")
                                SecureField("Optional session token", text: $awsSessionToken)
                                    .frame(width: 260)
                            }
                            GridRow {
                                Color.clear
                                credentialAction(provider: .aws, isDirty: currentAWSValues != savedAWSValues) {
                                    saveAWSStaticCredentials()
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                    .onChange(of: awsAccessKeyID) { _, _ in credentialStatus[.aws] = .idle }
                    .onChange(of: awsSecretAccessKey) { _, _ in credentialStatus[.aws] = .idle }
                    .onChange(of: awsSessionToken) { _, _ in credentialStatus[.aws] = .idle }
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
        .onAppear(perform: loadState)
        .task {
            await backendManager.reload()
        }
    }

    private var selectedProviderState: ProviderState? {
        backendManager.providers.first { $0.descriptor.id.rawValue == selectedBackendID }
    }

    private var privacyDescription: String {
        switch selectedProviderState?.descriptor.privacy {
        case .onDevice:
            "Apple translates on-device. Selected text stays on this Mac."
        case .configuredServer:
            "Text is sent only to the configured LibreTranslate-compatible server."
        case .cloudService:
            "Text is sent to the selected provider's cloud translation service."
        case nil:
            "Select a translation provider."
        }
    }

    private var awsProfiles: [String] {
        let discovered = backendManager.providers
            .first { $0.descriptor.id == .aws }?
            .profiles ?? []
        return Array(Set(discovered + [preferences.awsProfile]).subtracting([""])).sorted()
    }

    private var currentAWSValues: AWSSecretValues {
        AWSSecretValues(
            accessKeyID: awsAccessKeyID,
            secretAccessKey: awsSecretAccessKey,
            sessionToken: awsSessionToken
        )
    }

    @ViewBuilder
    private func apiKeyRow(provider: ProviderID, title: String) -> some View {
        GridRow {
            Text(title).frame(width: 110, alignment: .trailing)
            SecureField("Paste API key", text: apiKeyBinding(provider))
                .accessibilityLabel("\(title) API key")
                .frame(width: 260)
            credentialAction(provider: provider, isDirty: apiKeyIsDirty(provider)) {
                saveAPIKey(provider)
            }
        }
    }

    @ViewBuilder
    private func credentialAction(
        provider: ProviderID,
        isDirty: Bool,
        save: @escaping () -> Void
    ) -> some View {
        Group {
            switch credentialStatus[provider, default: .idle] {
            case .saved:
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Label("Could not save", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            case .idle:
                Button("Save", action: save)
                    .disabled(!isDirty)
            }
        }
        .font(.system(size: 11))
        .frame(width: 100, alignment: .leading)
    }

    @ViewBuilder
    private func endpointRow(
        title: String,
        value: Binding<String>,
        savedValue: String,
        save: @escaping () -> Void
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                TextField("HTTPS endpoint", text: value)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                Button("Save", action: save)
                    .disabled(value.wrappedValue == savedValue)
            }
        }
    }

    private func apiKeyBinding(_ provider: ProviderID) -> Binding<String> {
        Binding(
            get: { apiKeys[provider, default: ""] },
            set: { value in
                apiKeys[provider] = value
                credentialStatus[provider] = .idle
            }
        )
    }

    private func apiKeyIsDirty(_ provider: ProviderID) -> Bool {
        apiKeys[provider, default: ""] != savedAPIKeys[provider, default: ""]
    }

    private func loadState() {
        preferences.reloadConfiguration()
        selectedBackendID = preferences.activeBackendID
        azureEndpoint = preferences.azureEndpoint
        libreTranslateEndpoint = preferences.libreTranslateEndpoint

        for provider in [ProviderID.deepl, .googleCloud, .azure, .libretranslate] {
            let value = KeychainHelper.get(SecretReference.translateKit(provider).account) ?? ""
            apiKeys[provider] = value
            savedAPIKeys[provider] = value
        }

        awsAccessKeyID = KeychainHelper.get("aws_access_key_id") ?? ""
        awsSecretAccessKey = KeychainHelper.get("aws_secret_access_key") ?? ""
        awsSessionToken = KeychainHelper.get("aws_session_token") ?? ""
        savedAWSValues = currentAWSValues
    }

    private func saveAPIKey(_ provider: ProviderID) {
        let value = apiKeys[provider, default: ""]
        let account = SecretReference.translateKit(provider).account
        let succeeded = value.isEmpty
            ? KeychainHelper.delete(account)
            : KeychainHelper.set(value, for: account)
        guard succeeded else {
            credentialStatus[provider] = .failed
            return
        }

        savedAPIKeys[provider] = value
        markSaved(provider)
        Task { await backendManager.reload() }
    }

    private func saveAWSStaticCredentials() {
        do {
            _ = try preferences.validatedConfiguration()
            let resolver = CredentialResolver()
            if awsAccessKeyID.isEmpty, awsSecretAccessKey.isEmpty, awsSessionToken.isEmpty {
                try resolver.deleteAWSStatic()
            } else {
                try resolver.storeAWSStatic(
                    accessKeyID: awsAccessKeyID,
                    secretAccessKey: awsSecretAccessKey,
                    sessionToken: awsSessionToken.isEmpty ? nil : awsSessionToken
                )
                preferences.awsAuth = "static"
            }
            savedAWSValues = currentAWSValues
            markSaved(.aws)
            Task { await backendManager.reload() }
        } catch {
            credentialStatus[.aws] = .failed
        }
    }

    private func markSaved(_ provider: ProviderID) {
        credentialStatus[provider] = .saved
        Task {
            try? await Task.sleep(for: .seconds(2))
            if credentialStatus[provider] == .saved {
                credentialStatus[provider] = .idle
            }
        }
    }

    private func saveAzureEndpoint() {
        do {
            try preferences.setAzureEndpoint(azureEndpoint)
        } catch {
            return
        }
    }

    private func saveLibreTranslateEndpoint() {
        do {
            try preferences.setLibreTranslateEndpoint(libreTranslateEndpoint)
            Task { await backendManager.reload() }
        } catch {
            return
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

private enum CredentialSaveStatus: Equatable {
    case idle
    case saved
    case failed
}

private struct AWSSecretValues: Equatable {
    let accessKeyID: String
    let secretAccessKey: String
    let sessionToken: String

    static let empty = AWSSecretValues(accessKeyID: "", secretAccessKey: "", sessionToken: "")
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
                // User cancellation is reflected by the status refresh below.
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
