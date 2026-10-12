import SwiftUI
import PMPaneCore

struct ConfirmationSheet: View {
    @Environment(AppModel.self) private var model
    let pending: PendingConfirmation

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(pending.title)
                .font(.title2.weight(.semibold))

            Text(pending.message)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox("Commands") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(pending.commands) { command in
                            Text(command.display)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(4)
                }
                .frame(minHeight: 80, maxHeight: 200)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    model.cancelPendingAction()
                }
                Button("Run") {
                    Task { await model.confirmPendingAction() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isBusy(pending.action.affectedSources) || pending.commands.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 480)
    }
}
