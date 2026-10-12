import SwiftUI
import PMPaneCore

struct PackageListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            listChrome

            if model.groupByTap {
                groupedTable
            } else {
                flatTable
            }
        }
        .navigationTitle("")
        .toolbar(removing: .title)
        .contentToolbar(model: model, showsListOptions: true)
        .onChange(of: model.listFilter) { _, _ in
            model.pruneStalePackageSelection()
        }
        .onChange(of: model.searchText) { _, _ in
            model.pruneStalePackageSelection()
        }
        .onChange(of: model.includeSelfUpdatingUpgrades) { _, _ in
            model.pruneStalePackageSelection()
        }
    }

    private var listChrome: some View {
        @Bindable var model = model

        return VStack(alignment: .leading, spacing: 8) {
            if model.tapFilter != nil {
                HStack(spacing: 8) {
                    Button {
                        model.clearTapFilter()
                    } label: {
                        Label("Taps", systemImage: "chevron.left")
                    }
                    .buttonStyle(.link)
                    .help("Back to the taps list")

                    if let tap = model.tapFilter {
                        Text(tap.name)
                            .font(.subheadline.weight(.semibold))
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
            }

            HStack(alignment: .center, spacing: 12) {
                Picker("Filter", selection: $model.listFilter) {
                    ForEach(PackageListFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.regular)
                .fixedSize(horizontal: true, vertical: false)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search packages", text: $model.searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var flatTable: some View {
        @Bindable var model = model

        return Table(model.filteredPackages, selection: $model.selectedPackageIDs) {
            packageColumns
        }
        // Force refresh when the self-updating toggle changes (Table can otherwise stale).
        .id(listIdentity)
    }

    /// Same columns as the flat table, with tap sections when “Group by Tap” is on.
    private var groupedTable: some View {
        @Bindable var model = model

        return Table(of: Package.self, selection: $model.selectedPackageIDs) {
            packageColumns
        } rows: {
            ForEach(model.packagesGroupedByTap) { group in
                Section(group.tapName) {
                    ForEach(group.packages) { pkg in
                        TableRow(pkg)
                    }
                }
            }
        }
        .id(listIdentity)
    }

    private var listIdentity: String {
        let prefs = model.updatePreferences
        let muteKey = "\(prefs.ignoredPackageIDs.count)-\(prefs.skippedVersions.count)"
        return "\(model.sidebarSection.rawValue)-\(model.includeSelfUpdatingUpgrades)-\(model.listFilter.rawValue)-\(model.filteredPackages.count)-\(muteKey)"
    }

    @TableColumnBuilder<Package, Never>
    private var packageColumns: some TableColumnContent<Package, Never> {
        TableColumn("Name") { (pkg: Package) in
            HStack(spacing: 8) {
                PackageIconView(package: pkg, size: 20)
                Text(pkg.displayName)
            }
        }
        .width(min: 160, ideal: 220)

        TableColumn("Installed") { (pkg: Package) in
            Text(pkg.installedVersion)
                .foregroundStyle(pkg.isOutdated ? .primary : .secondary)
        }
        .width(min: 70, ideal: 90)

        TableColumn("Latest") { (pkg: Package) in
            Text(pkg.latestVersion ?? "—")
        }
        .width(min: 70, ideal: 90)

        if model.sidebarSection.showsSourceColumn {
            TableColumn("Source") { (pkg: Package) in
                Text(PackageFormatting.sourceLabel(pkg.source))
            }
            .width(min: 70, ideal: 80)
        }

        if model.sidebarSection.showsTapAndTrustColumns {
            TableColumn("Tap") { (pkg: Package) in
                Text(pkg.tap ?? "—")
            }
            .width(min: 120, ideal: 160)

            TableColumn("Trust") { (pkg: Package) in
                Text(PackageFormatting.trustLabel(pkg.trust))
            }
            .width(min: 80, ideal: 100)
        }

        TableColumn("Status") { (pkg: Package) in
            Text(PackageFormatting.statusText(for: pkg, preferences: model.updatePreferences))
        }
        .width(min: 90, ideal: 120)
    }
}
