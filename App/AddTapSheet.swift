import SwiftUI

struct AddTapSheet: View {
    @Environment(AppModel.self) private var model
    @State private var tapName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Tap")
                .font(.title2.weight(.semibold))

            Text("Enter a Homebrew tap as user/repo (for example, homebrew/cask-fonts).")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("user/repo", text: $tapName)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit { submit() }

            HStack {
                Spacer()
                Button("Cancel") {
                    model.isAddingTap = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Continue") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tapName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy(.brew))
            }
        }
        .padding(24)
        .frame(minWidth: 420)
        .onAppear { nameFocused = true }
    }

    private func submit() {
        Task { await model.planAddTap(tapName) }
    }
}
