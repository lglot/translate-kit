import AppKit
import SwiftUI
import Carbon

@main
struct TranslateKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(BackendManager.shared)
                .environmentObject(PreferencesManager.shared)
        }
    }
}

// MARK: - AppDelegate (NOT @MainActor — @objc methods need it off)

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var floatingPanel: FloatingTranslationPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register service provider
        NSApplication.shared.servicesProvider = ServiceProvider()

        // Setup menu bar
        setupMenuBar()

        // Listen for service trigger
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleServiceTrigger(_:)),
            name: .translateServiceTriggered,
            object: nil
        )

        // Setup global hotkey (⌘⇧T)
        setupGlobalHotkey()

        print("[TranslateKit] Started successfully")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Menu Bar

    private var globalHotkeyMonitor: Any?

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "translate", accessibilityDescription: "TranslateKit")
            button.action = #selector(statusItemClicked(_:))
            button.target = self
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let menu = buildMenu()
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.statusItem?.menu = nil
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "TranslateKit v1.0", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        // Engine
        let engineItem = NSMenuItem(title: "Engine", action: nil, keyEquivalent: "")
        let engineSubmenu = NSMenu()
        for backend in BackendManager.shared.backends {
            let item = NSMenuItem(
                title: backend.name,
                action: #selector(setEngine(_:)),
                keyEquivalent: ""
            )
            item.representedObject = backend.id
            item.state = backend.id == BackendManager.shared.activeBackendID ? .on : .off
            engineSubmenu.addItem(item)
        }
        engineItem.submenu = engineSubmenu
        menu.addItem(engineItem)

        // Language
        let langItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let langSubmenu = NSMenu()
        let prefs = PreferencesManager.shared
        for lang in Language.targetLanguages {
            let item = NSMenuItem(
                title: "\(lang.flag) \(lang.displayName)",
                action: #selector(setLanguage(_:)),
                keyEquivalent: ""
            )
            item.representedObject = lang.rawValue
            item.state = lang == prefs.targetLanguage ? .on : .off
            langSubmenu.addItem(item)
        }
        langItem.submenu = langSubmenu
        menu.addItem(langItem)

        menu.addItem(.separator())

        // Settings
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit TranslateKit", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func setEngine(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let backend = BackendManager.shared.backends.first(where: { $0.id == id }) else { return }
        BackendManager.shared.setActive(backend)
    }

    @objc private func openSettings() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "TranslateKit Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView:
            SettingsView()
                .environmentObject(BackendManager.shared)
                .environmentObject(PreferencesManager.shared)
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let lang = Language(rawValue: raw) else { return }
        PreferencesManager.shared.targetLanguage = lang
    }

    // MARK: - Service Handler

    @objc private func handleServiceTrigger(_ notification: Notification) {
        print("[TranslateKit] Service triggered!")
        guard let text = notification.userInfo?["text"] as? String, !text.isEmpty else {
            print("[TranslateKit] No text received")
            return
        }
        print("[TranslateKit] Text: \(text)")
        showTranslationPanel(text: text)
    }

    // MARK: - Floating Panel

    private func showTranslationPanel(text: String) {
        DispatchQueue.main.async { [weak self] in
            // Close previous panel
            self?.floatingPanel?.close()

            let backendManager = BackendManager.shared
            let prefs = PreferencesManager.shared

            let source: Language = prefs.autoDetectSource ? .auto : .english
            let target = prefs.targetLanguage

            // Create the SwiftUI view
            let view = TranslatingView(
                sourceText: text,
                sourceLanguage: source,
                targetLanguage: target,
                backend: backendManager.activeBackend
            )
            let hostingView = NSHostingView(rootView: view)

            let panel = FloatingTranslationPanel()
            panel.contentView = hostingView
            self?.floatingPanel = panel
            panel.presentNearCursor()

            print("[TranslateKit] Panel shown")
        }
    }

    // MARK: - Global Hotkey ⌘⇧T

    private func setupGlobalHotkey() {
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 0x11 {
                DispatchQueue.main.async {
                    let pb = NSPasteboard.general
                    if let text = pb.string(forType: .string), !text.isEmpty {
                        self?.showTranslationPanel(text: text)
                    }
                }
            }
        }
    }
}
