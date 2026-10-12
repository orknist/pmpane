import AppKit
import SwiftUI

private enum AppLinks {
    static let repository = URL(string: "https://github.com/orknist/pmpane")!
}

@main
struct PMPaneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    init() {
        if CommandLine.arguments.contains(SudoAskpass.argument) {
            SudoAskpassPrompt.runAndExit()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .onAppear { model.onAppear() }
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("About PM Pane") {
                    showAboutPanel()
                }
            }
            CommandGroup(replacing: .help) {
                Button("PM Pane on GitHub") {
                    NSWorkspace.shared.open(AppLinks.repository)
                }
            }
        }
    }

    private func showAboutPanel() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 4

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]

        let credits = NSMutableAttributedString(
            string: "List and upgrade packages across Homebrew, npm, pip, gem, uv, and bun.\n",
            attributes: baseAttributes
        )
        credits.append(
            NSAttributedString(
                string: AppLinks.repository.absoluteString,
                attributes: baseAttributes.merging([
                    .foregroundColor: NSColor.linkColor,
                    .link: AppLinks.repository,
                ]) { _, new in new }
            )
        )

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .credits: credits,
        ])
    }
}
