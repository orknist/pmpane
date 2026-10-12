import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("inspectorWidth") private var inspectorWidthStorage = Double(AppLayout.inspectorIdealWidth)
    @State private var inspectorDragStartWidth: CGFloat?

    var body: some View {
        @Bindable var model = model

        // VStack (not safeAreaInset) so the drawer participates in layout and shrinks the split view above it.
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
            } detail: {
                // Inspector is a plain trailing panel — not a NavigationSplitView column —
                // so it never gets its own navbar. Width is user-resizable via the handle.
                HStack(spacing: 0) {
                    contentColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    inspectorResizeHandle

                    InspectorView()
                        .frame(width: clampedInspectorWidth)
                        .frame(maxHeight: .infinity)
                }
            }
            .navigationSplitViewStyle(.balanced)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            OutputDrawerView()
        }
        .frame(minWidth: 980, minHeight: 700)
        .sheet(item: $model.pendingConfirmation) { pending in
            ConfirmationSheet(pending: pending)
        }
        .sheet(isPresented: $model.isAddingTap) {
            AddTapSheet()
        }
        .alert("Error", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK") { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var clampedInspectorWidth: CGFloat {
        min(
            max(CGFloat(inspectorWidthStorage), AppLayout.inspectorMinWidth),
            AppLayout.inspectorMaxWidth
        )
    }

    private var inspectorResizeHandle: some View {
        Color.clear
            .frame(width: 8)
            .frame(maxHeight: .infinity)
            .overlay { Divider() }
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if inspectorDragStartWidth == nil {
                            inspectorDragStartWidth = clampedInspectorWidth
                        }
                        let proposed = (inspectorDragStartWidth ?? clampedInspectorWidth)
                            - value.translation.width
                        inspectorWidthStorage = Double(
                            min(max(proposed, AppLayout.inspectorMinWidth), AppLayout.inspectorMaxWidth)
                        )
                    }
                    .onEnded { _ in
                        inspectorDragStartWidth = nil
                    }
            )
            .zIndex(1)
    }

    @ViewBuilder
    private var contentColumn: some View {
        if model.sidebarSection == .taps, model.tapFilter == nil {
            TapListView()
        } else {
            PackageListView()
        }
    }
}
