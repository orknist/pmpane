import SwiftUI

/// Window-toolbar actions for the list column.
/// Three leading panels: Reload, optional list toggles, optional Update Homebrew.
struct ContentToolbarModifier: ViewModifier {
    @Bindable var model: AppModel
    var showsListOptions: Bool

    func body(content: Content) -> some View {
        content
            .toolbar {
                reloadToolbarContent

                if showsListOptions {
                    listOptionsToolbarContent
                }

                if model.sidebarSection.showsUpdateHomebrew {
                    updateHomebrewToolbarContent
                }
            }
    }

    @ToolbarContentBuilder
    private var reloadToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                Task { await model.refreshInventory() }
            } label: {
                Label("Reload Packages", systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .fixedSize()
            .help(model.sidebarSection.reloadHelp)
            .disabled(!model.canReloadCurrentScope)
        }
    }

    /// Adjacent `.navigation` groups merge into one glass capsule on macOS;
    /// `ToolbarSpacer` does not split that leading cluster. Hide the system
    /// shared background and draw a second capsule with `glassEffect`.
    @ToolbarContentBuilder
    private var listOptionsToolbarContent: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .navigation) {
                ZStack {
                    toolbarHeightReference
                    HStack(spacing: 14) {
                        Toggle("Group by Tap", isOn: $model.groupByTap)
                            .toggleStyle(.checkbox)
                            .help("Group packages under their Homebrew tap")

                        Toggle("Include self-updating", isOn: $model.includeSelfUpdatingUpgrades)
                            .toggleStyle(.checkbox)
                            .help("Show greedy / self-updating cask upgrades in the list and Updates count; pass --greedy when upgrading")
                    }
                    .padding(.horizontal, 12)
                }
                .glassEffect(.regular.interactive(), in: Capsule())
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItemGroup(placement: .navigation) {
                Toggle("Group by Tap", isOn: $model.groupByTap)
                    .toggleStyle(.checkbox)
                    .help("Group packages under their Homebrew tap")

                Toggle("Include self-updating", isOn: $model.includeSelfUpdatingUpgrades)
                    .toggleStyle(.checkbox)
                    .help("Show greedy / self-updating cask upgrades in the list and Updates count; pass --greedy when upgrading")
            }
        }
    }

    /// Own capsule so showing/hiding does not reflow Reload or list-option panels.
    @ToolbarContentBuilder
    private var updateHomebrewToolbarContent: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .navigation) {
                ZStack {
                    toolbarHeightReference
                    HStack(spacing: 10) {
                        Button {
                            Task { await model.refreshCatalogThenInventory() }
                        } label: {
                            Label("Update Homebrew", systemImage: "arrow.triangle.2.circlepath")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.bordered)
                        .fixedSize()
                        .help(updateHomebrewHelp)
                        .disabled(model.isBusy(.brew))

                        if model.brewCatalogUpdatedAt != nil {
                            catalogUpdatedLabel
                        }
                    }
                    .padding(.leading, 4)
                    .padding(.trailing, model.brewCatalogUpdatedAt == nil ? 4 : 12)
                }
                .glassEffect(.regular.interactive(), in: Capsule())
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    Task { await model.refreshCatalogThenInventory() }
                } label: {
                    Label("Update Homebrew", systemImage: "arrow.triangle.2.circlepath")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .fixedSize()
                .help(updateHomebrewHelp)
                .disabled(model.isBusy(.brew))

                if model.brewCatalogUpdatedAt != nil {
                    catalogUpdatedLabel
                        .padding(.trailing, 8)
                }
            }
        }
    }

    /// Re-evaluates every 30s so “just now” → “1m ago” while the app stays open.
    private var catalogUpdatedLabel: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let updated = model.brewCatalogUpdatedLabel(relativeTo: context.date) {
                Text(updated)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .help(catalogUpdatedHelp)
            }
        }
    }

    private var updateHomebrewHelp: String {
        "Runs brew update to refresh Homebrew’s package catalog, then reloads the list."
    }

    private var catalogUpdatedHelp: String {
        "Last time brew update (or Homebrew auto-update) fetched the catalog. Based on Homebrew’s own FETCH_HEAD timestamp."
    }

    /// Custom glass must match native toolbar capsule height. Checkbox
    /// toggles are shorter than bordered buttons, so size against a
    /// hidden sibling that uses the same button style as Reload.
    @ViewBuilder
    private var toolbarHeightReference: some View {
        Button("Reload Packages", systemImage: "arrow.clockwise") {}
            .labelStyle(.titleAndIcon)
            .buttonStyle(.bordered)
            .fixedSize()
            .hidden()
            .accessibilityHidden(true)
    }
}

extension View {
    func contentToolbar(model: AppModel, showsListOptions: Bool) -> some View {
        modifier(ContentToolbarModifier(model: model, showsListOptions: showsListOptions))
    }
}
