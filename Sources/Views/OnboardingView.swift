import SwiftUI
import KeyboardShortcuts

struct OnboardingView: View {
    var onDone: () -> Void

    @State private var accessibilityGranted = AccessibilityPermission.isGranted

    private let permissionTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: "translate")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("Welcome to TranslateKit")
                        .font(.title2.bold())
                    Text("Instant translation in any app, in both directions.")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                step(number: "1", title: "Grant the Accessibility permission",
                     detail: "Needed to read the selection and replace text in other apps.") {
                    if accessibilityGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open System Settings") {
                            AccessibilityPermission.request()
                            AccessibilityPermission.openSystemSettings()
                        }
                    }
                }

                step(number: "2", title: "Translate what you read",
                     detail: "Select text anywhere and press the hotkey: the translation shows in a popup.") {
                    KeyboardShortcuts.Recorder("", name: .translateRead)
                }

                step(number: "3", title: "Translate what you write",
                     detail: "Type in your language in any text field, press the hotkey: the text is replaced with the translation. Press again to undo.") {
                    KeyboardShortcuts.Recorder("", name: .translateReplace)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Get Started") { onDone() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Spacer()
            }
        }
        .padding(24)
        .frame(width: 520, height: 480)
        .onReceive(permissionTimer) { _ in
            accessibilityGranted = AccessibilityPermission.isGranted
        }
    }

    @ViewBuilder
    private func step<Trailing: View>(
        number: String,
        title: String,
        detail: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.blue.opacity(0.15)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            trailing()
        }
    }
}
