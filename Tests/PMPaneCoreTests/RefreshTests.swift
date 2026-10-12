import Foundation
import Testing
import os
@testable import PMPaneCore

private final class RecordingRunner: CommandRunning, @unchecked Sendable {
    private let calls = OSAllocatedUnfairLock(initialState: [(executable: String, arguments: [String])]())

    func capture(executable: String, arguments: [String]) async throws -> CommandOutput {
        calls.withLock { $0.append((executable, arguments)) }

        if executable.hasSuffix("which"), arguments == ["uv"] {
            return CommandOutput(status: 0, stdout: Data("/fake/uv\n".utf8), stderr: "")
        }
        if arguments == ["--version"] {
            return CommandOutput(status: 0, stdout: Data("uv 0.0.0\n".utf8), stderr: "")
        }
        if arguments.starts(with: ["tool", "list"]) {
            if arguments.contains("--outdated") {
                let text = try FixtureSupport.loadText("uv_tool_outdated.txt")
                return CommandOutput(status: 0, stdout: Data(text.utf8), stderr: "")
            }
            let text = try FixtureSupport.loadText("uv_tool_list.txt")
            return CommandOutput(status: 0, stdout: Data(text.utf8), stderr: "")
        }
        return CommandOutput(status: 1, stdout: Data(), stderr: "not found")
    }

    func run(
        executable: String,
        arguments: [String],
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> Int {
        calls.withLock { $0.append((executable, arguments)) }
        return 1
    }

    var capturedExecutables: [String] {
        calls.withLock { $0.map(\.executable) }
    }
}

@Suite struct RefreshTests {
    private func makePackage(
        id: String,
        name: String,
        source: SourceKind,
        installed: String = "1.0",
        latest: String? = "2.0",
        outdated: Bool = true,
        pinned: Bool = false
    ) -> Package {
        Package(
            id: id,
            name: name,
            fullName: name,
            displayName: name,
            source: source,
            installedVersion: installed,
            latestVersion: latest,
            isOutdated: outdated,
            updatesItself: false,
            greedyOnly: false,
            pinned: pinned,
            installedOnRequest: true,
            installedAsDependency: false,
            summary: pinned ? "[required: ==\(installed)]" : "",
            trust: .notApplicable,
            versionIsLatest: !outdated
        )
    }

    @Test func inventoryMergeReplacesOnlyRequestedSource() throws {
        let brew = makePackage(id: "brewFormula:wget", name: "wget", source: .brewFormula, outdated: false)
        let oldUv = makePackage(id: "uv:ruff", name: "ruff", source: .uv, installed: "0.1.0")
        var inventory = Inventory(
            packages: [brew, oldUv],
            taps: [
                TapRecord(
                    name: "homebrew/core",
                    official: true,
                    tapTrusted: true,
                    isTapped: true,
                    formulaCount: 1,
                    caskCount: 0,
                    trustedFormulae: [],
                    trustedCasks: [],
                    isStaleTrust: false
                ),
            ],
            tools: [
                RuntimeTool(id: "brew", displayName: "Homebrew", available: true, executable: "/brew"),
                RuntimeTool(id: "uv", displayName: "uv", available: true, executable: "/old/uv", version: "0.1"),
            ],
            refreshedAt: Date.distantPast,
            warnings: ["uv inventory failed: old", "Homebrew inventory failed: keep"]
        )

        let newUv = makePackage(id: "uv:ruff", name: "ruff", source: .uv, installed: "0.8.0", outdated: false)
        inventory.merge(
            SourceScanResult(
                source: .uv,
                packages: [newUv],
                tool: RuntimeTool(id: "uv", displayName: "uv", available: true, executable: "/new/uv", version: "0.2"),
                warnings: ["uv tool list --outdated failed: nope"]
            )
        )

        #expect(inventory.packages.count == 2)
        #expect(inventory.packages.contains { $0.id == "brewFormula:wget" })
        let ruff = try #require(inventory.packages.first { $0.id == "uv:ruff" })
        #expect(ruff.installedVersion == "0.8.0")
        #expect(inventory.taps.count == 1)
        #expect(inventory.tools.first { $0.id == "uv" }?.executable == "/new/uv")
        #expect(inventory.warnings.contains { $0.hasPrefix("Homebrew") })
        #expect(inventory.warnings.contains { $0.hasPrefix("uv tool list") })
        #expect(!inventory.warnings.contains { $0 == "uv inventory failed: old" })
    }

    @Test func packageActionAffectedSources() {
        let uv = makePackage(id: "uv:ruff", name: "ruff", source: .uv)
        let bun = makePackage(id: "bun:cowsay", name: "cowsay", source: .bun)
        let brew = makePackage(id: "brewFormula:wget", name: "wget", source: .brewFormula)

        #expect(PackageAction.upgrade(packages: [uv, bun], includeSelfUpdating: false).affectedSources == [.uv, .bun])
        #expect(PackageAction.remove(uv).affectedSources == [.uv])
        #expect(PackageAction.pin(brew).affectedSources == [.brew])
        #expect(PackageAction.refreshCatalog.affectedSources == [.brew])
        #expect(PackageAction.addTap("example/tap").affectedSources == [.brew])
    }

    @Test func optimisticUpgradeAndRemove() throws {
        let uv = makePackage(
            id: "uv:ruff",
            name: "ruff",
            source: .uv,
            installed: "0.8.0",
            latest: "0.17.0",
            outdated: true,
            pinned: true
        )
        let other = makePackage(id: "bun:cowsay", name: "cowsay", source: .bun)
        var inventory = Inventory(
            packages: [uv, other],
            taps: [],
            tools: [],
            refreshedAt: Date(),
            warnings: []
        )

        inventory.applyOptimistic(.upgrade(packages: [uv], includeSelfUpdating: true))
        let upgraded = try #require(inventory.packages.first { $0.id == "uv:ruff" })
        #expect(upgraded.installedVersion == "0.17.0")
        #expect(!upgraded.isOutdated)
        #expect(!upgraded.pinned)

        inventory.applyOptimistic(.remove(other))
        #expect(inventory.packages.count == 1)
        #expect(inventory.packages.first?.id == "uv:ruff")
    }

    @Test func optimisticRefreshCatalogUpdatesBrewTimestamp() {
        var inventory = Inventory(
            packages: [],
            taps: [],
            tools: [
                RuntimeTool(
                    id: "brew",
                    displayName: "Homebrew",
                    available: true,
                    catalogUpdatedAt: Date(timeIntervalSince1970: 0)
                ),
            ],
            refreshedAt: Date(),
            warnings: []
        )
        let before = Date()
        inventory.applyOptimistic(.refreshCatalog)
        let updated = inventory.tools.first { $0.id == "brew" }?.catalogUpdatedAt
        #expect(updated != nil)
        #expect(updated! >= before)
    }

    @Test func scopedRefreshOnlyScansRequestedSource() async throws {
        let brew = makePackage(id: "brewFormula:wget", name: "wget", source: .brewFormula, outdated: false)
        let staleUv = makePackage(id: "uv:old", name: "old", source: .uv, installed: "0.0.1")
        let base = Inventory(
            packages: [brew, staleUv],
            taps: [],
            tools: FixtureSupport.sampleInventory().tools,
            refreshedAt: Date(),
            warnings: []
        )

        let runner = RecordingRunner()
        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent("PMPaneRefreshTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cache) }

        let service = InventoryService(runner: runner, cacheDirectory: cache)
        let refreshed = try await service.refresh(sources: [.uv], base: base, onEvent: nil)

        #expect(refreshed.packages.contains { $0.id == "brewFormula:wget" })
        #expect(!refreshed.packages.contains { $0.id == "uv:old" })
        #expect(refreshed.packages.contains { $0.source == .uv && $0.name == "ruff" })

        let executables = runner.capturedExecutables
        // `/opt/homebrew/bin/uv` is fine; the brew *binary* must not be invoked.
        #expect(!executables.contains { $0 == "brew" || $0.hasSuffix("/brew") })
        #expect(!executables.contains { $0 == "npm" || $0.hasSuffix("/npm") })
        #expect(!executables.contains { $0 == "bun" || $0.hasSuffix("/bun") })
    }

    @Test func sourceKindMapsToInventorySource() {
        #expect(SourceKind.brewFormula.inventorySource == .brew)
        #expect(SourceKind.brewCask.inventorySource == .brew)
        #expect(SourceKind.npm.inventorySource == .npm)
        #expect(SourceKind.uv.inventorySource == .uv)
        #expect(InventorySource.brew.packageSources == [.brewFormula, .brewCask])
    }
}
