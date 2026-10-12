import SwiftUI
import PMPaneCore

struct TapListView: View {
    @Environment(AppModel.self) private var model

    private var taps: [TapRecord] {
        model.inventory?.taps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        } ?? []
    }

    var body: some View {
        @Bindable var model = model

        Table(taps, selection: $model.selectedTapIDs) {
            // Fixed widths (min == max) so these columns cannot grow with the window.
            TableColumn("Name") { tap in
                Text(tap.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 140, ideal: 180, max: 180)

            TableColumn("Trust") { tap in
                Text(PackageFormatting.tapTrustText(tap))
                    .lineLimit(1)
            }
            .width(min: 72, ideal: 80, max: 80)

            TableColumn("Status") { tap in
                Text(PackageFormatting.tapStatusText(tap))
                    .lineLimit(1)
            }
            .width(min: 90, ideal: 110, max: 110)

            TableColumn("Formulae") { tap in
                Text("\(tap.formulaCount)")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .monospacedDigit()
            }
            .width(min: 64, ideal: 68, max: 68)

            TableColumn("Casks") { tap in
                Text("\(tap.caskCount)")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .monospacedDigit()
            }
            .width(min: 52, ideal: 56, max: 56)

            TableColumn("Installed") { tap in
                Text("\(model.installedPackageCount(for: tap.name))")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .monospacedDigit()
            }
            .width(min: 64, ideal: 72, max: 72)

            // No max — AppKit last-column-only sizing fills leftover space here.
            TableColumn("Remote") { tap in
                Text(tap.remote ?? "—")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 160, ideal: 280)
        }
        .tableLastColumnAutosize()
        .contextMenu(forSelectionType: String.self) { ids in
            tapContextMenu(for: ids)
        } primaryAction: { ids in
            if let tap = resolvedTap(from: ids) {
                model.showPackagesForTap(tap)
            }
        }
        .navigationTitle("")
        .toolbar(removing: .title)
        .contentToolbar(model: model, showsListOptions: false)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    model.presentAddTap()
                } label: {
                    Label("Add Tap", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .fixedSize()
                .help("Add a Homebrew tap (user/repo)")
                .disabled(model.isBusy(.brew))
                .padding(.trailing, 12)
            }
        }
    }

    @ViewBuilder
    private func tapContextMenu(for ids: Set<String>) -> some View {
        if let tap = resolvedTap(from: ids) {
            let installedCount = model.installedPackageCount(for: tap.name)

            Button("Show Installed Packages (\(installedCount))") {
                model.showPackagesForTap(tap)
            }

            if !tap.official {
                Divider()

                if !tap.tapTrusted {
                    Button("Trust Tap") {
                        Task { await model.planTrustTap(tap.name) }
                    }
                }
                if tap.tapTrusted || tap.isStaleTrust {
                    Button("Untrust Tap") {
                        Task { await model.planUntrustTap(tap.name) }
                    }
                }

                if tap.isTapped {
                    Divider()
                    Button("Remove Tap…", role: .destructive) {
                        Task { await model.planRemoveTap(tap) }
                    }
                }
            }
        }
    }

    private func resolvedTap(from ids: Set<String>) -> TapRecord? {
        guard ids.count == 1, let name = ids.first else { return nil }
        return model.inventory?.taps.first { $0.name == name }
    }
}
