import AppKit
import SwiftUI

/// Native password prompt used when this process is launched as `SUDO_ASKPASS`.
///
/// Homebrew’s `sudo -A` path requires a password on stdout. Apple’s Touch ID PAM
/// module intentionally skips its UI in askpass mode, so the system biometric
/// sheet cannot be used here — a secure native dialog is the correct approach.
@MainActor
enum SudoAskpassPrompt {
    static func runAndExit() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let password = AskpassPanelController().runModal()
        if let password {
            FileHandle.standardOutput.write(Data((password + "\n").utf8))
            exit(0)
        }
        exit(1)
    }
}

@MainActor
private final class AskpassPanelController: NSObject, NSWindowDelegate {
    private var result: String?
    private var window: NSWindow?

    func runModal() -> String? {
        let root = AskpassRootView(
            onCancel: { [weak self] in self?.finish(with: nil) },
            onAuthorize: { [weak self] password in self?.finish(with: password) }
        )
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "PM Pane"
        window.styleMask = [.titled, .closable]
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.level = .modalPanel
        window.delegate = self
        window.setContentSize(NSSize(width: 400, height: 210))
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
        window.close()
        self.window = nil
        return result
    }

    private func finish(with password: String?) {
        result = password
        NSApp.stopModal()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish(with: nil)
        return false
    }
}

private struct AskpassRootView: View {
    let onCancel: () -> Void
    let onAuthorize: (String) -> Void

    @State private var password = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Administrator Access Required")
                        .font(.headline)
                    Text("Homebrew needs your macOS password to modify protected files.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(authorize)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Authorize", action: authorize)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { focused = true }
    }

    private var appIcon: NSImage {
        let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        icon.size = NSSize(width: 64, height: 64)
        return icon
    }

    private func authorize() {
        guard !password.isEmpty else { return }
        onAuthorize(password)
    }
}
