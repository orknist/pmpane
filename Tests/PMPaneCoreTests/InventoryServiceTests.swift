import Foundation
import Testing
import PMPaneCore
@testable import PMPaneCore

@Suite struct InventoryServiceTests {
    private let service = InventoryService(
        runner: ProcessCommandRunner(),
        cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("PMPaneCoreTests")
    )

    @Test func pinnedOutdatedExcludedFromUpgradePlan() throws {
        let result = try BrewMerger.merge(
            info: FixtureSupport.load("brew_info.json"),
            outdated: FixtureSupport.load("brew_outdated.json"),
            greedyOutdated: FixtureSupport.load("brew_outdated_greedy.json"),
            tapInfo: FixtureSupport.load("brew_tap_info.json"),
            trust: FixtureSupport.load("brew_trust.json")
        )
        let pinned = try #require(result.packages.first { $0.name == "pinnedpkg" })
        let inventory = Inventory(
            packages: result.packages,
            taps: result.taps,
            tools: FixtureSupport.sampleInventory().tools,
            refreshedAt: Date(),
            warnings: []
        )
        #expect(throws: ValidationError.self) {
            try service.plan(
                .upgrade(packages: [pinned], includeSelfUpdating: false),
                inventory: inventory
            )
        }
    }

    @Test func upgradeFormulaAndCaskTwoCommands() throws {
        let result = try BrewMerger.merge(
            info: FixtureSupport.load("brew_info.json"),
            outdated: FixtureSupport.load("brew_outdated.json"),
            greedyOutdated: FixtureSupport.load("brew_outdated_greedy.json"),
            tapInfo: FixtureSupport.load("brew_tap_info.json"),
            trust: FixtureSupport.load("brew_trust.json")
        )
        let formula = Package(
            id: "brewFormula:testformula",
            name: "testformula",
            fullName: "testformula",
            displayName: "testformula",
            source: .brewFormula,
            installedVersion: "1.0",
            latestVersion: "2.0",
            isOutdated: true,
            updatesItself: false,
            greedyOnly: false,
            pinned: false,
            installedOnRequest: true,
            installedAsDependency: false,
            summary: "",
            trust: .official,
            versionIsLatest: false
        )
        let cask = try #require(result.packages.first { $0.name == "plaincask" })
        let inventory = Inventory(
            packages: [formula, cask],
            taps: [],
            tools: FixtureSupport.sampleInventory().tools,
            refreshedAt: Date(),
            warnings: []
        )
        let commands = try service.plan(
            .upgrade(packages: [formula, cask], includeSelfUpdating: false),
            inventory: inventory
        )
        #expect(commands.count == 2)
        #expect(commands[0].executable == "/opt/homebrew/bin/brew")
        #expect(commands[0].arguments == ["upgrade", "testformula"])
        #expect(commands[1].arguments == ["upgrade", "--cask", "plaincask"])
    }

    @Test func invalidNameRejected() {
        #expect(throws: ValidationError.self) {
            try NameValidation.validatePackageToken("foo;rm")
        }
    }

    @Test func npmOutdatedAndUpgradePlan() throws {
        let packages = try NpmParser.packages(
            listJSON: FixtureSupport.load("npm_list.json"),
            outdatedJSON: FixtureSupport.load("npm_outdated.json")
        )
        let leftpad = try #require(packages.first { $0.name == "leftpad" })
        #expect(leftpad.isOutdated)
        #expect(leftpad.latestVersion == "1.2.0")
        let inventory = Inventory(
            packages: packages,
            taps: [],
            tools: FixtureSupport.sampleInventory().tools,
            refreshedAt: Date(),
            warnings: []
        )
        let commands = try service.plan(
            .upgrade(packages: [leftpad], includeSelfUpdating: false),
            inventory: inventory
        )
        #expect(commands.count == 1)
        #expect(commands[0].executable == "/fake/npm")
        #expect(commands[0].arguments == ["install", "-g", "leftpad@latest"])
    }

    @Test func pipJSONRoundTrip() throws {
        let packages = try PipParser.packages(
            listJSON: FixtureSupport.load("pip_list.json"),
            outdatedJSON: FixtureSupport.load("pip_outdated.json")
        )
        #expect(packages.count == 2)
        let requests = try #require(packages.first { $0.name == "requests" })
        #expect(requests.isOutdated)
        #expect(requests.latestVersion == "2.32.0")
    }

    @Test func gemFiltersDefaultsAndKeepsOutdated() throws {
        let packages = try GemParser.packages(
            listText: FixtureSupport.loadText("gem_list.txt"),
            outdatedText: FixtureSupport.loadText("gem_outdated.txt")
        )
        #expect(!packages.contains { $0.name == "rake" })
        let custom = try #require(packages.first { $0.name == "customgem" })
        #expect(custom.isOutdated)
    }

    @Test func uvToolListAndOutdatedPlan() throws {
        let packages = try UvToolParser.packages(
            listText: FixtureSupport.loadText("uv_tool_list.txt"),
            outdatedText: FixtureSupport.loadText("uv_tool_outdated.txt")
        )
        #expect(packages.count == 3)
        let ruff = try #require(packages.first { $0.name == "ruff" })
        #expect(ruff.source == .uv)
        #expect(ruff.installedVersion == "0.8.0")
        #expect(ruff.isOutdated)
        #expect(ruff.latestVersion == "0.17.0")
        #expect(ruff.pinned)
        #expect(ruff.summary.contains("==0.8.0"))

        let httpie = try #require(packages.first { $0.name == "httpie" })
        #expect(!httpie.isOutdated)
        #expect(!httpie.pinned)
        #expect(httpie.summary.contains("httpie"))

        let ty = try #require(packages.first { $0.name == "ty" })
        #expect(ty.isOutdated)
        #expect(!ty.pinned)

        let inventory = Inventory(
            packages: packages,
            taps: [],
            tools: FixtureSupport.sampleInventory().tools,
            refreshedAt: Date(),
            warnings: []
        )

        #expect(throws: ValidationError.self) {
            _ = try service.plan(
                .upgrade(packages: [ruff], includeSelfUpdating: false),
                inventory: inventory
            )
        }

        let force = try service.plan(
            .upgrade(packages: [ruff], includeSelfUpdating: true),
            inventory: inventory
        )
        #expect(force.count == 1)
        #expect(force[0].executable == "/fake/uv")
        #expect(force[0].arguments == ["tool", "install", "ruff@latest"])

        let unconstrained = try service.plan(
            .upgrade(packages: [ty], includeSelfUpdating: false),
            inventory: inventory
        )
        #expect(unconstrained.count == 1)
        #expect(unconstrained[0].arguments == ["tool", "upgrade", "ty"])

        let remove = try service.plan(.remove(ruff), inventory: inventory)
        #expect(remove.count == 1)
        #expect(remove[0].arguments == ["tool", "uninstall", "ruff"])
    }

    @Test func uvToolEmptyList() throws {
        let packages = try UvToolParser.packages(listText: "No tools installed\n", outdatedText: "")
        #expect(packages.isEmpty)
    }

    @Test func bunMissingLockfileIsNotAWarning() {
        let stderr = """
        error: missing lockfile, nothing to list
        note: run 'bun install' first
        """
        #expect(BunParser.isMissingLockfileError(stderr))
        #expect(!BunParser.isMissingLockfileError("bun pm ls --global failed: permission denied"))
    }

    @Test func bunGlobalListAndOutdatedPlan() throws {
        let packages = try BunParser.packages(
            listText: FixtureSupport.loadText("bun_pm_ls.txt"),
            outdatedText: FixtureSupport.loadText("bun_outdated.txt")
        )
        #expect(packages.count == 3)

        let cowsay = try #require(packages.first { $0.name == "cowsay" })
        #expect(cowsay.source == .bun)
        #expect(cowsay.isOutdated)
        #expect(cowsay.pinned)
        #expect(cowsay.latestVersion == "1.6.0")

        let leftpad = try #require(packages.first { $0.name == "leftpad" })
        #expect(leftpad.isOutdated)
        #expect(!leftpad.pinned)
        #expect(leftpad.latestVersion == "0.0.1")

        let scoped = try #require(packages.first { $0.name == "@sindresorhus/is" })
        #expect(!scoped.isOutdated)

        let inventory = Inventory(
            packages: packages,
            taps: [],
            tools: FixtureSupport.sampleInventory().tools,
            refreshedAt: Date(),
            warnings: []
        )

        #expect(throws: ValidationError.self) {
            _ = try service.plan(
                .upgrade(packages: [cowsay], includeSelfUpdating: false),
                inventory: inventory
            )
        }

        let force = try service.plan(
            .upgrade(packages: [cowsay], includeSelfUpdating: true),
            inventory: inventory
        )
        #expect(force.count == 1)
        #expect(force[0].executable == "/fake/bun")
        #expect(force[0].arguments == ["update", "--global", "--latest", "cowsay"])

        let unconstrained = try service.plan(
            .upgrade(packages: [leftpad], includeSelfUpdating: false),
            inventory: inventory
        )
        #expect(unconstrained.count == 1)
        #expect(unconstrained[0].arguments == ["update", "--global", "--latest", "leftpad"])

        let remove = try service.plan(.remove(scoped), inventory: inventory)
        #expect(remove.count == 1)
        #expect(remove[0].arguments == ["remove", "--global", "@sindresorhus/is"])
    }

    @Test func officialTrustItemPlanThrows() throws {
        let result = try BrewMerger.merge(
            info: FixtureSupport.load("brew_info.json"),
            outdated: FixtureSupport.load("brew_outdated.json"),
            greedyOutdated: FixtureSupport.load("brew_outdated_greedy.json"),
            tapInfo: FixtureSupport.load("brew_tap_info.json"),
            trust: FixtureSupport.load("brew_trust.json")
        )
        let wget = try #require(result.packages.first { $0.name == "wget" })
        let inventory = Inventory(
            packages: result.packages,
            taps: result.taps,
            tools: FixtureSupport.sampleInventory().tools,
            refreshedAt: Date(),
            warnings: []
        )
        #expect(throws: ValidationError.self) {
            _ = try service.plan(.trustItem(wget), inventory: inventory)
        }
    }

    @Test func addAndRemoveTapPlans() throws {
        let result = try BrewMerger.merge(
            info: FixtureSupport.load("brew_info.json"),
            outdated: FixtureSupport.load("brew_outdated.json"),
            greedyOutdated: FixtureSupport.load("brew_outdated_greedy.json"),
            tapInfo: FixtureSupport.load("brew_tap_info.json"),
            trust: FixtureSupport.load("brew_trust.json")
        )
        let inventory = Inventory(
            packages: result.packages,
            taps: result.taps,
            tools: FixtureSupport.sampleInventory().tools,
            refreshedAt: Date(),
            warnings: []
        )

        let add = try service.plan(.addTap("example/newtap"), inventory: inventory)
        #expect(add.count == 1)
        #expect(add[0].arguments == ["tap", "example/newtap"])

        let removable = try #require(result.taps.first { $0.name == "anomalyco/tap" && $0.isTapped })
        let remove = try service.plan(.removeTap(removable.name), inventory: inventory)
        #expect(remove.count == 1)
        #expect(remove[0].arguments == ["untap", "--force", removable.name])

        let untrustedTap = try #require(result.taps.first { $0.name == "shadow/tap" && $0.isTapped })
        let removeUntrusted = try service.plan(.removeTap(untrustedTap.name), inventory: inventory)
        #expect(removeUntrusted.map(\.arguments) == [
            ["trust", "shadow/tap"],
            ["untap", "--force", "shadow/tap"],
            ["untrust", "shadow/tap"],
        ])

        #expect(throws: ValidationError.self) {
            _ = try service.plan(.removeTap("homebrew/core"), inventory: inventory)
        }
    }

    @Test func removeUntrustedFormulaPlansTemporaryTrust() throws {
        let result = try BrewMerger.merge(
            info: FixtureSupport.load("brew_info.json"),
            outdated: FixtureSupport.load("brew_outdated.json"),
            greedyOutdated: FixtureSupport.load("brew_outdated_greedy.json"),
            tapInfo: FixtureSupport.load("brew_tap_info.json"),
            trust: FixtureSupport.load("brew_trust.json")
        )
        let shadow = try #require(result.packages.first { $0.name == "shadowpkg" })
        #expect(shadow.trust == .untrusted)
        let inventory = Inventory(
            packages: result.packages,
            taps: result.taps,
            tools: FixtureSupport.sampleInventory().tools,
            refreshedAt: Date(),
            warnings: []
        )
        let commands = try service.plan(.remove(shadow), inventory: inventory)
        #expect(commands.map(\.arguments) == [
            ["trust", "--formula", "shadow/tap/shadowpkg"],
            ["uninstall", "shadow/tap/shadowpkg"],
            ["untrust", "--formula", "shadow/tap/shadowpkg"],
        ])
    }

    @Test func failureDetailMapsSudoPasswordErrors() {
        let detail = InventoryService.failureDetail(
            status: 1,
            output: """
            sudo: a terminal is required to read the password; either use the -S option \
            to read from standard input or configure an askpass helper
            sudo: a password is required
            """
        )
        #expect(detail.contains("administrator access"))
        #expect(detail.contains("exit status 1"))
    }

    @Test func failureDetailKeepsGenericExitStatus() {
        let detail = InventoryService.failureDetail(status: 2, output: "Error: bottle checksum mismatch")
        #expect(detail == "exit status 2")
    }
}
