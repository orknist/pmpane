import SwiftUI
import PMPaneCore

struct InspectorView: View {
    @Environment(AppModel.self) private var model
    @State private var depsExpanded = true
    @State private var requiredByExpanded = true

    var body: some View {
        Group {
            if let package = model.inspectorPackage {
                packageInspector(package)
            } else if let tap = model.inspectorTap {
                tapInspector(tap)
            } else if model.selectedPackages.count > 1 {
                multiPackageInspector
            } else {
                ContentUnavailableView(
                    "No selection",
                    systemImage: "sidebar.right",
                    description: Text(
                        model.sidebarSection == .taps
                            ? "Select a tap to manage it, or double-click to show its installed packages."
                            : "Select a package to see details and actions."
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var multiPackageInspector: some View {
        let upgradeable = model.selectedUpgradeablePackages
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(model.selectedPackages.count) packages selected")
                    .font(.title3.weight(.semibold))

                if upgradeable.isEmpty {
                    Text("None of the selected packages have an available update.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    if upgradeable.count < model.selectedPackages.count {
                        Text("\(upgradeable.count) of \(model.selectedPackages.count) have an available update.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await model.planUpgradeSelected() }
                    } label: {
                        Label(
                            upgradeable.count == model.selectedPackages.count
                                ? "Upgrade selected"
                                : "Upgrade \(upgradeable.count) outdated",
                            systemImage: "arrow.up.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.isSelectionBusy)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func packageInspector(_ package: Package) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    PackageIconView(package: package, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(package.displayName)
                            .font(.title3.weight(.semibold))
                            .textSelection(.enabled)
                        Text(PackageFormatting.sourceLabel(package.source))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !package.summary.isEmpty {
                    Text(package.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if let enriched = model.enrichedSummary(for: package) {
                    Text(enriched)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } else if model.isLoadingPackageDetails(package), package.summary.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading package details…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Details") {
                    detailRows(packageDetailRows(package))
                }

                packageLinksSection(package)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Actions")
                        .font(.headline)

                    VStack(spacing: 8) {
                        Button {
                            let includeSelf = package.greedyOnly
                                || package.updatesItself
                                || (allowsPinnedUpgradeAnyway(package))
                            Task {
                                await model.planUpgrade(
                                    package: package,
                                    includeSelfUpdating: includeSelf
                                )
                            }
                        } label: {
                            Label(
                                upgradeButtonTitle(for: package),
                                systemImage: "arrow.up.circle.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(model.isBusy(package) || !canUpgrade(package))

                        if package.source == .brewFormula || package.source == .brewCask {
                            borderedAction(
                                title: package.pinned ? "Unpin" : "Pin",
                                systemImage: package.pinned ? "pin.slash" : "pin"
                            ) {
                                Task { await model.planPin(package) }
                            }
                            .disabled(model.isBusy(package))
                        }

                        if model.isUpdateSuppressed(package) {
                            borderedAction(
                                title: "Show updates again",
                                systemImage: "eye"
                            ) {
                                model.clearPackageMute(package)
                            }
                        } else {
                            borderedAction(
                                title: "Ignore this package",
                                systemImage: "eye.slash"
                            ) {
                                model.ignorePackage(package)
                            }

                            if canSkipVersion(package) {
                                borderedAction(
                                    title: "Skip this version",
                                    systemImage: "forward"
                                ) {
                                    model.skipPackageVersion(package)
                                }
                            }
                        }

                        Button(role: .destructive) {
                            Task { await model.planRemove(package) }
                        } label: {
                            Label("Remove", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(.red)
                        .disabled(model.isBusy(package))
                    }

                    if showsTrustSection(for: package) {
                        Divider()
                            .padding(.vertical, 4)

                        Text("Trust")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        VStack(spacing: 8) {
                            if package.trust == .untrusted {
                                borderedAction(
                                    title: "Trust this package",
                                    systemImage: "checkmark.shield"
                                ) {
                                    Task { await model.planTrustItem(package) }
                                }
                                .disabled(model.isBusy(package))
                            }

                            if package.trust == .itemTrusted {
                                borderedAction(
                                    title: "Untrust package",
                                    systemImage: "xmark.shield"
                                ) {
                                    Task { await model.planUntrustItem(package) }
                                }
                                .disabled(model.isBusy(package))
                            }

                            if let tap = package.tap, !isOfficialTap(tap) {
                                if package.trust != .tapTrusted {
                                    borderedAction(
                                        title: "Trust entire tap",
                                        systemImage: "shield.lefthalf.filled"
                                    ) {
                                        Task { await model.planTrustTap(tap) }
                                    }
                                    .disabled(model.isBusy(.brew))
                                }
                                if package.trust == .tapTrusted {
                                    borderedAction(
                                        title: "Untrust tap",
                                        systemImage: "shield.slash"
                                    ) {
                                        Task { await model.planUntrustTap(tap) }
                                    }
                                    .disabled(model.isBusy(.brew))
                                }
                            }
                        }
                    }
                }

                if !package.dependsOn.isEmpty {
                    RelationChipsSection(
                        title: "Dependencies",
                        names: package.dependsOn,
                        isExpanded: $depsExpanded
                    )
                }

                if !package.requiredBy.isEmpty {
                    RelationChipsSection(
                        title: "Required By",
                        names: package.requiredBy,
                        isExpanded: $requiredByExpanded
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: package.id) {
            await model.ensurePackageDetails(for: package)
        }
    }

    @ViewBuilder
    private func packageLinksSection(_ package: Package) -> some View {
        let registry = PackageLinks.registryURL(source: package.source, name: package.name)
        let homepage = nonEmptyURL(package.homepage)
        let repository = nonEmptyURL(model.enrichedRepository(for: package))
        let showHomepage = homepage.map { $0 != registry } ?? false
        let showRepository = repository.map { repo in
            if let registry, PackageDetailParsers.urlsEquivalent(repo, registry) { return false }
            if let homepage, PackageDetailParsers.urlsEquivalent(repo, homepage) { return false }
            return true
        } ?? false
        let canEnrich = package.source != .brewFormula && package.source != .brewCask
        let showLoadingLinks = model.isLoadingPackageDetails(package)
            && canEnrich
            && homepage == nil
            && repository == nil

        if registry != nil || showHomepage || showRepository || showLoadingLinks {
            GroupBox("Links") {
                VStack(alignment: .leading, spacing: 6) {
                    if let registry {
                        linkRow(title: "Registry", url: registry)
                    }
                    if let homepage, showHomepage {
                        linkRow(title: "Homepage", url: homepage)
                    }
                    if let repository, showRepository {
                        linkRow(title: "Repository", url: repository)
                    } else if showLoadingLinks {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Looking up links…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func nonEmptyURL(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func linkRow(title: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(url) {
                model.openHomepage(url)
            }
            .buttonStyle(.link)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    private func tapInspector(_ tap: TapRecord) -> some View {
        let installedCount = model.installedPackageCount(for: tap.name)
        let showingPackages = model.tapFilter?.name == tap.name

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tap.name)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                    Text(PackageFormatting.tapStatusText(tap))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GroupBox("Details") {
                    detailRows(tapDetailRows(tap, installedCount: installedCount))
                }

                if tap.isStaleTrust {
                    Text("A trust entry exists for this tap, but the tap is not installed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Actions")
                        .font(.headline)

                    VStack(spacing: 8) {
                        if showingPackages {
                            borderedAction(
                                title: "Back to taps",
                                systemImage: "list.bullet"
                            ) {
                                model.clearTapFilter()
                            }
                        } else {
                            Button {
                                model.showPackagesForTap(tap)
                            } label: {
                                Label(
                                    "Show installed packages (\(installedCount))",
                                    systemImage: "shippingbox"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(model.isBusy(.brew))
                        }

                        if !tap.official {
                            if !tap.tapTrusted {
                                borderedAction(
                                    title: "Trust entire tap",
                                    systemImage: "shield.lefthalf.filled"
                                ) {
                                    Task { await model.planTrustTap(tap.name) }
                                }
                                .disabled(model.isBusy(.brew))
                            }
                            if tap.tapTrusted || tap.isStaleTrust {
                                borderedAction(
                                    title: "Untrust tap",
                                    systemImage: "shield.slash"
                                ) {
                                    Task { await model.planUntrustTap(tap.name) }
                                }
                                .disabled(model.isBusy(.brew))
                            }
                            if tap.isTapped {
                                borderedAction(
                                    title: "Remove tap…",
                                    systemImage: "trash"
                                ) {
                                    Task { await model.planRemoveTap(tap) }
                                }
                                .disabled(model.isBusy(.brew))
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func packageDetailRows(_ package: Package) -> [(String, String)] {
        var rows: [(String, String)] = [
            ("Full name", package.fullName),
            ("Tap", package.tap ?? "—"),
            ("Trust", PackageFormatting.trustLabel(package.trust)),
            ("Installed", package.installedVersion),
            ("Latest", package.latestVersion ?? "—"),
            ("Status", PackageFormatting.statusText(for: package, preferences: model.updatePreferences)),
            ("Pinned", package.pinned ? "Yes" : "No"),
        ]
        if model.updatePreferences.isIgnored(package) {
            rows.append(("Updates", "Ignored"))
        } else if model.updatePreferences.isVersionSkipped(package),
                  let version = package.latestVersion {
            rows.append(("Updates", "Skipped \(version)"))
        }
        if package.source == .brewFormula {
            rows.append(("On request", package.installedOnRequest ? "Yes" : "No"))
        }
        if package.updatesItself || package.greedyOnly {
            rows.append(("Updates itself", "Yes"))
        }
        return rows
    }

    private func tapDetailRows(_ tap: TapRecord, installedCount: Int) -> [(String, String)] {
        var rows: [(String, String)] = [
            ("Trust", PackageFormatting.tapTrustText(tap)),
            ("Installed", "\(installedCount)"),
            ("Formulae", "\(tap.formulaCount)"),
            ("Casks", "\(tap.caskCount)"),
        ]
        if let remote = tap.remote {
            rows.append(("Remote", remote))
        }
        return rows
    }

    private func detailRows(_ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Divider()
                }
                detailRow(row.0, row.1)
                    .padding(.vertical, 6)
            }
        }
    }

    /// Title hugs its content; value uses the remaining width and wraps instead of truncating.
    private func detailRow(_ title: String, _ value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Text(value)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.secondary)
                Text(value)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
    }

    private func borderedAction(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func showsTrustSection(for package: Package) -> Bool {
        guard package.source == .brewFormula || package.source == .brewCask else { return false }
        guard package.trust != .official else { return false }
        return true
    }

    private func isOfficialTap(_ tap: String) -> Bool {
        tap == "homebrew/core" || tap == "homebrew/cask"
    }

    /// uv / bun version pins allow an explicit “Upgrade anyway”; Homebrew pins stay blocked.
    private func allowsPinnedUpgradeAnyway(_ package: Package) -> Bool {
        (package.source == .uv || package.source == .bun) && package.pinned && package.isOutdated
    }

    private func canUpgrade(_ package: Package) -> Bool {
        if allowsPinnedUpgradeAnyway(package) {
            return true
        }
        if package.pinned { return false }
        return package.isOutdated || package.greedyOnly
    }

    private func canSkipVersion(_ package: Package) -> Bool {
        guard let latest = package.latestVersion, !latest.isEmpty else { return false }
        return package.isOutdated || package.greedyOnly
    }

    private func upgradeButtonTitle(for package: Package) -> String {
        if allowsPinnedUpgradeAnyway(package) {
            return "Upgrade anyway"
        }
        if package.greedyOnly, !package.isOutdated {
            return "Upgrade anyway"
        }
        return "Upgrade"
    }
}
