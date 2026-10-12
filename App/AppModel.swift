import AppKit
import Foundation
import Observation
import PMPaneCore

struct PendingConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let commands: [PlannedCommand]
    let action: PackageAction
}

struct TapPackageGroup: Identifiable, Hashable {
    var id: String { tapName }
    let tapName: String
    let packages: [Package]
}

@MainActor
@Observable
final class AppModel {
    var inventory: Inventory?
    var sidebarSection: SidebarSection = .all
    var tapFilter: TapRecord?
    var selectedPackageIDs: Set<String> = []
    var selectedTapIDs: Set<String> = []

    var searchText = ""
    var listFilter: PackageListFilter = .all
    var groupByTap = true
    var expandedTapIDs: Set<String> = []
    var includeSelfUpdatingUpgrades = false

    var refreshingSources: Set<InventorySource> = []
    /// Sources currently running a write action (upgrade/remove/…); independent per manager.
    var actionSources: Set<InventorySource> = []
    var outputText = ""
    var drawerExpanded = true

    var pendingConfirmation: PendingConfirmation?
    var alertMessage: String?
    var isAddingTap = false

    /// Local ignore / skip-version preferences (not Homebrew pin).
    var updatePreferences = PackageUpdatePreferences()

    /// Lazy registry metadata keyed by package id (description / real homepage).
    var packageDetailCache: [String: PackageDetailEnrichment] = [:]
    /// Package ids currently fetching registry details.
    var packageDetailLoadingIDs: Set<String> = []

    private let service: InventoryService
    private let detailService: PackageDetailService
    private let preferencesDirectory: URL

    var isRefreshing: Bool { !refreshingSources.isEmpty }
    var isPerformingAction: Bool { !actionSources.isEmpty }
    var busySources: Set<InventorySource> { refreshingSources.union(actionSources) }

    var reloadScope: Set<InventorySource> { sidebarSection.reloadSources }

    /// True when at least one source in the current Reload scope is idle.
    var canReloadCurrentScope: Bool {
        !reloadScope.subtracting(busySources).isEmpty
    }

    func isRefreshing(_ source: InventorySource) -> Bool {
        refreshingSources.contains(source)
    }

    func isRefreshing(_ sources: Set<InventorySource>) -> Bool {
        !sources.isDisjoint(with: refreshingSources)
    }

    func isBusy(_ source: InventorySource) -> Bool {
        busySources.contains(source)
    }

    func isBusy(_ sources: Set<InventorySource>) -> Bool {
        !sources.isDisjoint(with: busySources)
    }

    func isBusy(_ package: Package) -> Bool {
        isBusy(package.source.inventorySource)
    }

    /// True when any selected package’s manager is busy.
    var isSelectionBusy: Bool {
        isBusy(Set(selectedPackages.map(\.source.inventorySource)))
    }

    init() {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("PMPane", isDirectory: true)
        preferencesDirectory = supportDirectory
        service = InventoryService(runner: ProcessCommandRunner(), cacheDirectory: supportDirectory)
        detailService = PackageDetailService()
        updatePreferences = (try? PackageUpdatePreferences.load(from: supportDirectory))
            ?? PackageUpdatePreferences()
    }

    var updatesBadgeCount: Int {
        // Touch prefs + toggle so Observation always invalidates badge + lists together.
        _ = includeSelfUpdatingUpgrades
        _ = updatePreferences
        return inventory?.packages.filter(isUpdateCandidate).count ?? 0
    }

    /// Outdated packages, plus greedy-only casks when “Include self-updating” is on.
    func isUpdateCandidate(_ package: Package) -> Bool {
        guard !package.pinned else { return false }
        guard !updatePreferences.suppressesUpdates(for: package) else { return false }
        if package.isOutdated { return true }
        if includeSelfUpdatingUpgrades, package.greedyOnly { return true }
        return false
    }

    /// Selected packages that would actually receive an update from “Upgrade selected”.
    var selectedUpgradeablePackages: [Package] {
        selectedPackages.filter(isUpdateCandidate)
    }

    func isUpdateSuppressed(_ package: Package) -> Bool {
        updatePreferences.suppressesUpdates(for: package)
    }

    func ignorePackage(_ package: Package) {
        var prefs = updatePreferences
        prefs.ignore(packageID: package.id)
        updatePreferences = prefs
        persistUpdatePreferences()
        pruneStalePackageSelection()
    }

    func skipPackageVersion(_ package: Package) {
        guard let version = package.latestVersion, !version.isEmpty else { return }
        var prefs = updatePreferences
        prefs.skipVersion(packageID: package.id, version: version)
        updatePreferences = prefs
        persistUpdatePreferences()
        pruneStalePackageSelection()
    }

    func clearPackageMute(_ package: Package) {
        var prefs = updatePreferences
        prefs.clearMute(packageID: package.id)
        updatePreferences = prefs
        persistUpdatePreferences()
        pruneStalePackageSelection()
    }

    /// Drop selection IDs that are no longer in the visible package table
    /// (e.g. upgraded packages leaving the Outdated filter).
    func pruneStalePackageSelection() {
        let visibleIDs = Set(filteredPackages.map(\.id))
        let pruned = selectedPackageIDs.intersection(visibleIDs)
        if pruned != selectedPackageIDs {
            selectedPackageIDs = pruned
        }
    }

    private func persistUpdatePreferences() {
        do {
            try updatePreferences.save(to: preferencesDirectory)
        } catch {
            appendOutput("Failed to save update preferences: \(error.localizedDescription)\n")
        }
    }

    /// Greedy-only upgrade candidates stay hidden unless the toggle (or Self-update filter) is on.
    private func isHiddenSelfUpdatingCandidate(_ package: Package) -> Bool {
        !includeSelfUpdatingUpgrades && package.greedyOnly && !package.isOutdated
    }

    func runtimeTool(for section: SidebarSection) -> RuntimeTool? {
        guard let toolID = section.runtimeToolID() else { return nil }
        return inventory?.tools.first { $0.id == toolID }
    }

    /// Last `brew update` / auto-update fetch time (toolbar next to Update Homebrew).
    var brewCatalogUpdatedAt: Date? {
        inventory?.tools.first(where: { $0.id == "brew" })?.catalogUpdatedAt
    }

    func brewCatalogUpdatedLabel(relativeTo now: Date = .now) -> String? {
        guard let date = brewCatalogUpdatedAt else { return nil }
        return BrewCatalogFreshness.updatedLabel(for: date, relativeTo: now)
    }

    func onAppear() {
        loadCachedInventory()
        Task { await refreshInventory(sources: Set(InventorySource.allCases)) }
    }

    func sidebarSectionChanged(_ section: SidebarSection) {
        sidebarSection = section
        tapFilter = nil
        selectedTapIDs = []
        selectedPackageIDs = []
        listFilter = .all
        searchText = ""
        expandAllTapGroups()
    }

    func loadCachedInventory() {
        do {
            if let cached = try service.loadCached() {
                inventory = cached
                expandAllTapGroups()
            }
        } catch {
            appendOutput("Failed to load cache: \(error.localizedDescription)\n")
        }
    }

    func refreshInventory(sources: Set<InventorySource>? = nil) async {
        let requested = sources ?? reloadScope
        // Skip managers that are already refreshing or running a write action.
        let scope = requested.subtracting(busySources)
        guard !scope.isEmpty else { return }

        refreshingSources.formUnion(scope)
        defer { refreshingSources.subtract(scope) }

        do {
            _ = try await service.refresh(
                sources: scope,
                base: inventory,
                onEvent: { [weak self] event in
                    await MainActor.run {
                        guard let self else { return }
                        switch event {
                        case .started(let source):
                            self.refreshingSources.insert(source)
                        case .finished(let result):
                            if self.inventory != nil {
                                self.inventory?.merge(result)
                            } else {
                                var empty = Inventory(
                                    packages: [],
                                    taps: [],
                                    tools: [],
                                    refreshedAt: Date(),
                                    warnings: []
                                )
                                empty.merge(result)
                                self.inventory = empty
                            }
                            self.refreshingSources.remove(result.source)
                            self.expandAllTapGroups()
                            self.pruneStalePackageSelection()
                            if let inventory = self.inventory {
                                try? self.service.saveCache(inventory)
                            }
                            if !result.warnings.isEmpty {
                                self.appendOutput(result.warnings.joined(separator: "\n") + "\n")
                                self.drawerExpanded = true
                            }
                        }
                    }
                }
            )
            if let inventory {
                try? service.saveCache(inventory)
                pruneStaleSkippedVersions(using: inventory.packages)
            }
            expandAllTapGroups()
            pruneStalePackageSelection()
        } catch {
            appendOutput("Refresh failed: \(error.localizedDescription)\n")
            alertMessage = error.localizedDescription
        }
    }

    private func pruneStaleSkippedVersions(using packages: [Package]) {
        var prefs = updatePreferences
        prefs.pruneStaleSkips(using: packages)
        guard prefs != updatePreferences else { return }
        updatePreferences = prefs
        persistUpdatePreferences()
    }

    func refreshCatalogThenInventory() async {
        guard !isBusy(.brew) else { return }
        drawerExpanded = true
        await perform(action: .refreshCatalog)
    }

    var filteredPackages: [Package] {
        guard let inventory else { return [] }
        // Explicit read so list views refresh when the toolbar toggle changes.
        let includeSelfUpdating = includeSelfUpdatingUpgrades
        var packages = inventory.packages

        if let tapFilter {
            packages = packages.filter { ($0.tap ?? "") == tapFilter.name }
        } else {
            switch sidebarSection {
            case .updates:
                packages = packages.filter(isUpdateCandidate)
            case .taps:
                if selectedTapIDs.isEmpty, tapFilter == nil {
                    return []
                }
                fallthrough
            default:
                packages = packages.filter { sidebarSection.matches($0) }
            }
        }

        switch listFilter {
        case .all:
            break
        case .outdated:
            packages = packages.filter { pkg in
                guard !updatePreferences.suppressesUpdates(for: pkg) else { return false }
                return pkg.isOutdated || (includeSelfUpdating && pkg.greedyOnly)
            }
        case .pinned:
            packages = packages.filter(\.pinned)
        case .ignored:
            packages = packages.filter { updatePreferences.suppressesUpdates(for: $0) }
        case .dependencies:
            packages = packages.filter { $0.source == .brewFormula && !$0.installedOnRequest }
        case .untrusted:
            packages = packages.filter { $0.trust == .untrusted }
        case .selfUpdating:
            packages = packages.filter { $0.updatesItself || $0.greedyOnly }
        }

        // Outside Self-update / Ignored, hide greedy-only candidates when the toggle is off
        // so All / Formulae / Casks / Updates all visibly react to the checkbox.
        if listFilter != .selfUpdating, listFilter != .ignored {
            packages = packages.filter { !isHiddenSelfUpdatingCandidate($0) }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            packages = packages.filter { pkg in
                pkg.name.localizedCaseInsensitiveContains(query)
                    || pkg.displayName.localizedCaseInsensitiveContains(query)
                    || (pkg.tap?.localizedCaseInsensitiveContains(query) ?? false)
                    || pkg.summary.localizedCaseInsensitiveContains(query)
            }
        }

        return packages.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var packagesGroupedByTap: [TapPackageGroup] {
        let grouped = Dictionary(grouping: filteredPackages) { pkg in
            pkg.tap?.nilIfEmpty ?? "No tap"
        }
        return grouped.keys.sorted { lhs, rhs in
            if lhs == "homebrew/core" { return true }
            if rhs == "homebrew/core" { return false }
            if lhs == "homebrew/cask" { return true }
            if rhs == "homebrew/cask" { return false }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        .map { key in
            TapPackageGroup(
                tapName: key,
                packages: (grouped[key] ?? []).sorted {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
            )
        }
    }

    private func expandAllTapGroups() {
        guard let packages = inventory?.packages else { return }
        expandedTapIDs = Set(packages.map { $0.tap?.nilIfEmpty ?? "No tap" })
    }

    var selectedPackages: [Package] {
        filteredPackages.filter { selectedPackageIDs.contains($0.id) }
    }

    var inspectorPackage: Package? {
        guard selectedPackageIDs.count == 1, let id = selectedPackageIDs.first else { return nil }
        return filteredPackages.first { $0.id == id }
    }

    var inspectorTap: TapRecord? {
        if let tapFilter { return tapFilter }
        guard let name = selectedTapIDs.first else { return nil }
        return inventory?.taps.first { $0.name == name }
    }

    /// Single-click selection on the Taps table — does not leave the taps list.
    func selectTap(_ tap: TapRecord) {
        selectedTapIDs = [tap.name]
        selectedPackageIDs = []
    }

    /// Double-click / context menu — show installed packages from this tap.
    func showPackagesForTap(_ tap: TapRecord) {
        selectedTapIDs = [tap.name]
        tapFilter = tap
        selectedPackageIDs = []
        searchText = ""
        listFilter = .all
    }

    /// Return from a tap’s package list to the Taps table, keeping the tap selected.
    func clearTapFilter() {
        tapFilter = nil
        selectedPackageIDs = []
    }

    func installedPackageCount(for tapName: String) -> Int {
        inventory?.packages.filter { ($0.tap ?? "") == tapName }.count ?? 0
    }

    func openHomepage(_ urlString: String?) {
        guard let urlString,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Fetches registry description / homepage when the inspector opens a package.
    func ensurePackageDetails(for package: Package) async {
        switch package.source {
        case .brewFormula, .brewCask:
            return
        case .npm, .pip, .gem, .uv, .bun:
            break
        }

        if packageDetailCache[package.id] != nil { return }
        if packageDetailLoadingIDs.contains(package.id) { return }

        packageDetailLoadingIDs.insert(package.id)
        defer { packageDetailLoadingIDs.remove(package.id) }

        do {
            let enrichment = try await detailService.fetch(source: package.source, name: package.name)
            packageDetailCache[package.id] = enrichment
            applyPackageDetailEnrichment(packageID: package.id, enrichment: enrichment)
        } catch {
            // Cache empty result so a flaky network does not retry on every selection change.
            packageDetailCache[package.id] = PackageDetailEnrichment()
        }
    }

    func isLoadingPackageDetails(_ package: Package) -> Bool {
        packageDetailLoadingIDs.contains(package.id)
    }

    func enrichedSummary(for package: Package) -> String? {
        guard let summary = packageDetailCache[package.id]?.summary, !summary.isEmpty else { return nil }
        if summary == package.summary { return nil }
        return summary
    }

    func enrichedRepository(for package: Package) -> String? {
        guard let repository = packageDetailCache[package.id]?.repository, !repository.isEmpty else {
            return nil
        }
        return repository
    }

    private func applyPackageDetailEnrichment(packageID: String, enrichment: PackageDetailEnrichment) {
        guard var inventory, let index = inventory.packages.firstIndex(where: { $0.id == packageID }) else {
            return
        }
        var package = inventory.packages[index]
        var changed = false

        if package.summary.isEmpty, let summary = enrichment.summary, !summary.isEmpty {
            package.summary = summary
            changed = true
        }
        if let homepage = enrichment.homepage, !homepage.isEmpty, package.homepage != homepage {
            package.homepage = homepage
            changed = true
        }

        guard changed else { return }
        inventory.packages[index] = package
        self.inventory = inventory
    }

    // MARK: - Actions

    func planUpgrade(package: Package, includeSelfUpdating: Bool) async {
        guard !isBusy(package) else { return }
        drawerExpanded = true
        // Version-constrained uv / bun packages need an explicit confirmation before forcing latest.
        if package.source == .uv, package.pinned, package.isOutdated, includeSelfUpdating {
            await prepareConfirmation(
                title: "Upgrade anyway \(package.displayName)",
                message: """
                This uv tool was installed with a version pin (\(package.summary)).

                PM Pane will run `uv tool install \(package.name)@latest`, which clears the pin and installs the newest release.
                """,
                action: .upgrade(packages: [package], includeSelfUpdating: true)
            )
            return
        }
        if package.source == .bun, package.pinned, package.isOutdated, includeSelfUpdating {
            await prepareConfirmation(
                title: "Upgrade anyway \(package.displayName)",
                message: """
                This bun global package is held by its installed version range (Update == Current while Latest is newer).

                PM Pane will run `bun update --global --latest \(package.name)`, which installs the newest release.
                """,
                action: .upgrade(packages: [package], includeSelfUpdating: true)
            )
            return
        }
        await perform(
            action: .upgrade(packages: [package], includeSelfUpdating: includeSelfUpdating)
        )
    }

    func planUpgradeSelected() async {
        let packages = selectedUpgradeablePackages
        let sources = Set(packages.map(\.source.inventorySource))
        guard !packages.isEmpty, !isBusy(sources) else { return }
        drawerExpanded = true
        await perform(
            action: .upgrade(packages: packages, includeSelfUpdating: includeSelfUpdatingUpgrades)
        )
    }

    func planPin(_ package: Package) async {
        await prepareConfirmation(
            title: package.pinned ? "Unpin \(package.displayName)" : "Pin \(package.displayName)",
            message: package.pinned
                ? "Homebrew will allow upgrades for this package again."
                : "Homebrew will not upgrade this package until unpinned.",
            action: package.pinned ? .unpin(package) : .pin(package)
        )
    }

    func planRemove(_ package: Package) async {
        var message = "This will uninstall \(package.displayName)."
        if let warning = package.removalWarning {
            message += "\n\n\(warning)"
        }
        if package.trust == .untrusted,
           package.source == .brewFormula || package.source == .brewCask {
            message += """


            This package is untrusted, so brew cannot load it for uninstall. The plan temporarily trusts it, uninstalls, then untrusts it again.
            """
        }
        await prepareConfirmation(
            title: "Remove \(package.displayName)",
            message: message,
            action: .remove(package)
        )
    }

    func planTrustItem(_ package: Package) async {
        await prepareConfirmation(
            title: "Trust \(package.displayName)",
            message: "Marked packages will be treated as trusted for future brew operations.",
            action: .trustItem(package)
        )
    }

    func planUntrustItem(_ package: Package) async {
        await prepareConfirmation(
            title: "Untrust \(package.displayName)",
            message: "This package will be marked untrusted again.",
            action: .untrustItem(package)
        )
    }

    func planTrustTap(_ tapName: String) async {
        let message = """
        Trusting tap “\(tapName)” applies to all current and future formulae, casks, and commands published by that tap.

        Only proceed if you trust the tap maintainer and their code.
        """
        await prepareConfirmation(
            title: "Trust tap \(tapName)",
            message: message,
            action: .trustTap(tapName)
        )
    }

    func planUntrustTap(_ tapName: String) async {
        let isStale = inventory?.taps.first { $0.name == tapName }?.isStaleTrust == true
        let message: String
        if isStale {
            message = """
            This only removes the leftover brew trust entry for “\(tapName)”.

            The tap is not installed, so it will disappear from the Taps list afterward. No tap remove/untap is performed.
            """
        } else {
            message = "Formulae and casks from this tap will be marked untrusted unless individually trusted."
        }
        await prepareConfirmation(
            title: "Untrust tap \(tapName)",
            message: message,
            action: .untrustTap(tapName)
        )
    }

    func presentAddTap() {
        guard !isBusy(.brew) else { return }
        isAddingTap = true
    }

    func planAddTap(_ rawName: String) async {
        let tapName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tapName.isEmpty else { return }
        isAddingTap = false
        await prepareConfirmation(
            title: "Add tap \(tapName)",
            message: "Homebrew will clone this tap and make its formulae/casks available.",
            action: .addTap(tapName)
        )
    }

    func planRemoveTap(_ tap: TapRecord) async {
        let installed = (inventory?.packages ?? []).filter { $0.tap == tap.name }
        let count = installed.count
        let needsTemporaryTrust = installed.contains { $0.trust == .untrusted }
        var message = "This will run brew untap for “\(tap.name)”."
        if count > 0 {
            message += """


            \(count) installed package(s) still come from this tap. Untap will use --force, which uninstalls those packages before removing the tap.
            """
        }
        if needsTemporaryTrust {
            message += """


            One or more packages are untrusted, so brew cannot load them for untap. The plan temporarily trusts this tap, force-untaps, then untrusts it again.
            """
        }
        await prepareConfirmation(
            title: "Remove tap \(tap.name)",
            message: message,
            action: .removeTap(tap.name)
        )
    }

    private func prepareConfirmation(title: String, message: String, action: PackageAction) async {
        guard let inventory, !isBusy(action.affectedSources) else { return }
        do {
            let commands = try service.plan(action, inventory: inventory)
            pendingConfirmation = PendingConfirmation(
                title: title,
                message: message,
                commands: commands,
                action: action
            )
        } catch {
            appendOutput("Planning failed: \(error.localizedDescription)\n")
            alertMessage = error.localizedDescription
        }
    }

    func confirmPendingAction() async {
        guard let pending = pendingConfirmation else { return }
        pendingConfirmation = nil
        await perform(action: pending.action)
    }

    func cancelPendingAction() {
        pendingConfirmation = nil
    }

    private func perform(action: PackageAction) async {
        guard let current = inventory else { return }
        let sources = action.affectedSources
        guard !sources.isEmpty, !isBusy(sources) else { return }

        let shouldClearOutput = actionSources.isEmpty
        actionSources.formUnion(sources)
        if shouldClearOutput {
            outputText = ""
        } else {
            appendOutput("\n---\n")
        }

        var releasedAction = false
        let releaseAction = {
            guard !releasedAction else { return }
            self.actionSources.subtract(sources)
            releasedAction = true
        }
        defer { releaseAction() }

        do {
            try await service.perform(action, inventory: current) { [weak self] chunk in
                Task { @MainActor in
                    self?.appendOutput(chunk)
                }
            }
            inventory?.applyOptimistic(action)
            pruneStalePackageSelection()
            // Free the write lock before scoped refresh claims the same sources.
            releaseAction()
            await refreshInventory(sources: sources)
        } catch {
            appendOutput("\nError: \(error.localizedDescription)\n")
            alertMessage = error.localizedDescription
        }
    }

    private func appendOutput(_ text: String) {
        outputText += text
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
