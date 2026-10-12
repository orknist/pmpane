import SwiftUI

struct OutputDrawerView: View {
    @Environment(AppModel.self) private var model
    private let bottomID = "operation-output-bottom"

    var body: some View {
        @Bindable var model = model

        DisclosureGroup(isExpanded: $model.drawerExpanded) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.outputText.isEmpty ? "Output from the last operation appears here." : model.outputText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)

                    Color.clear
                        .frame(height: 1)
                        .id(bottomID)
                }
                .defaultScrollAnchor(.bottom)
                .frame(maxHeight: 160)
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: model.outputText) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: model.drawerExpanded) { _, expanded in
                    guard expanded else { return }
                    scrollToBottom(proxy)
                }
            }
        } label: {
            HStack {
                Text("Operation output")
                    .font(.subheadline.weight(.medium))
                if model.isPerformingAction {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        // Defer one turn so the Text layout has the new lines before we scroll.
        DispatchQueue.main.async {
            withAnimation(nil) {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        }
    }
}
