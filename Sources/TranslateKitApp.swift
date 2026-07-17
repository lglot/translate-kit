import AppKit
import SwiftUI
import ServiceManagement
import KeyboardShortcuts

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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var floatingPanel: FloatingTranslationPanel?
    private var toastPanel: FloatingTranslationPanel?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.servicesProvider = ServiceProvider()
        setupMenuBar()
        setupHotkeys()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleServiceTrigger(_:)),
            name: .translateServiceTriggered,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        if !PreferencesManager.shared.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    // Open Settings when launched from Spotlight / double-click
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    // MARK: - Hotkeys

    private func setupHotkeys() {
        KeyboardShortcuts.onKeyUp(for: .translateRead) { [weak self] in
            Task { @MainActor in await self?.runReadFlow() }
        }
        KeyboardShortcuts.onKeyUp(for: .translateReplace) { [weak self] in
            Task { @MainActor in await self?.runReplaceFlow() }
        }
    }

    @MainActor
    private func runReadFlow() async {
        guard ensureAccessibility() else { return }
        // let the user release the hotkey modifiers before we synthesize keys
        try? await Task.sleep(for: .milliseconds(150))
        do {
            let text = try await ReplaceEngine.shared.captureSelection()
            showTranslationPanel(text: text)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    @MainActor
    private func runReplaceFlow() async {
        guard ensureAccessibility() else { return }
        try? await Task.sleep(for: .milliseconds(150))
        do {
            try await ReplaceEngine.shared.translateAndReplaceFocused()
        } catch {
            NSSound.beep()
            showToast(error.localizedDescription)
        }
    }

    @MainActor
    private func ensureAccessibility() -> Bool {
        if AccessibilityPermission.isGranted { return true }
        AccessibilityPermission.request()
        showToast("TranslateKit needs the Accessibility permission. Grant it in System Settings, then try again.")
        return false
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "translate", accessibilityDescription: "TranslateKit")
            button.action = #selector(statusItemClicked(_:))
            button.target = self
        }
        statusItem?.isVisible = PreferencesManager.shared.showMenuBarIcon
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
        menu.addItem(NSMenuItem(title: "TranslateKit v\(Self.appVersion)", action: nil, keyEquivalent: ""))
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

        let prefs = PreferencesManager.shared
        let pairItem = NSMenuItem(
            title: "Languages: \(prefs.firstLanguage.flag) \(prefs.firstLanguage.displayName) ⇄ \(prefs.secondLanguage.flag) \(prefs.secondLanguage.displayName)",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        menu.addItem(pairItem)

        menu.addItem(.separator())

        if !AccessibilityPermission.isGranted {
            let permissionItem = NSMenuItem(
                title: "⚠️ Grant Accessibility Permission...",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            menu.addItem(permissionItem)
            menu.addItem(.separator())
        }

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

    @objc private func openAccessibilitySettings() {
        AccessibilityPermission.openSystemSettings()
    }

    // MARK: - Settings Window

    @objc @discardableResult private func openSettings() -> Bool {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return true
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "TranslateKit Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView:
            SettingsView {
                window.close()
            }
            .environmentObject(BackendManager.shared)
            .environmentObject(PreferencesManager.shared)
        )
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Welcome to TranslateKit"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView:
            OnboardingView {
                PreferencesManager.shared.hasCompletedOnboarding = true
                window.close()
            }
        )
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Service Handler

    @objc private func handleServiceTrigger(_ notification: Notification) {
        guard let text = notification.userInfo?["text"] as? String, !text.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.showTranslationPanel(text: text)
        }
    }

    // MARK: - Floating Panel

    @MainActor
    private func showTranslationPanel(text: String) {
        floatingPanel?.close()

        let panel = FloatingTranslationPanel()
        let view = TranslatingView(sourceText: text) { [weak panel] size in
            panel?.updateContentSize(size)
        }
        let hostingView = NSHostingView(rootView: view)
        panel.contentView = hostingView
        panel.setContentSize(hostingView.fittingSize)
        floatingPanel = panel
        panel.presentNearCursor()
    }

    // MARK: - Toast

    @MainActor
    private func showToast(_ message: String) {
        toastPanel?.close()

        let panel = FloatingTranslationPanel()
        let view = HStack(spacing: 8) {
            Image(systemName: "translate")
                .foregroundStyle(.blue)
            Text(message)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 380)
        .background(VisualEffectBackground())
        let hostingView = NSHostingView(rootView: view)
        panel.contentView = hostingView
        panel.setContentSize(hostingView.fittingSize)
        toastPanel = panel
        panel.presentNearCursor()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self, weak panel] in
            panel?.close()
            if self?.toastPanel === panel { self?.toastPanel = nil }
        }
    }

    // MARK: - Preferences observer

    @objc private func preferencesChanged() {
        statusItem?.isVisible = PreferencesManager.shared.showMenuBarIcon
    }
}
