import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var backendManager: BackendManager
    @EnvironmentObject private var preferences: PreferencesManager
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "translate")
                    .foregroundStyle(.blue)
                Text("TranslateKit")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("v1.0")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Active backend
            Menu {
                ForEach(backendManager.backends, id: \.id) { backend in
                    Button {
                        backendManager.setActive(backend)
                    } label: {
                        HStack {
                            Text(backend.name)
                            if backend.id == backendManager.activeBackend.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "cpu")
                        .frame(width: 16)
                    Text("Engine: \(backendManager.activeBackend.name)")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // Target language
            Menu {
                ForEach(Language.targetLanguages) { lang in
                    Button {
                        preferences.targetLanguage = lang
                    } label: {
                        HStack {
                            Text("\(lang.flag) \(lang.displayName)")
                            if lang == preferences.targetLanguage {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "globe")
                        .frame(width: 16)
                    Text("Language: \(preferences.targetLanguage.flag) \(preferences.targetLanguage.displayName)")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // Settings
            Button {
                showingSettings = true
            } label: {
                HStack {
                    Image(systemName: "gear")
                        .frame(width: 16)
                    Text("Settings...")
                    Spacer()
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider()

            // Quit
            Button {
                NSApp.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "power")
                        .frame(width: 16)
                    Text("Quit TranslateKit")
                    Spacer()
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 250)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}
