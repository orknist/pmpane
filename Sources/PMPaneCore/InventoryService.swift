import Foundation
import os

public struct InventoryService: Sendable {
    private let runner: any CommandRunning
    private let cacheDirectory: URL

    public init(runner: any CommandRunning, cacheDirectory: URL) {
        self.runner = runner
        self.cacheDirectory = cacheDirectory
    }

    private static var jsonEncoder: JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }

    private static var jsonDecoder: JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }

    public func loadCached() throws -> Inventory? {
        let url = cacheDirectory.appendingPathComponent("inventory.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try Self.jsonDecoder.decode(Inventory.self, from: data)
    }

    public func saveCache(_ inventory: Inventory) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let cacheURL = cacheDirectory.appendingPathComponent("inventory.json")
        try Self.jsonEncoder.encode(inventory).write(to: cacheURL, options: .atomic)
    }

    /// Full inventory refresh (all sources in parallel).
    public func refresh() async throws -> Inventory {
        try await refresh(sources: Set(InventorySource.allCases), base: nil, onEvent: nil)
    }

    /// Scans the given sources in parallel, merging each result into `base` (or an empty inventory).
    public func refresh(
        sources: Set<InventorySource>,
        base: Inventory?,
        onEvent: (@Sendable (RefreshEvent) async -> Void)?
    ) async throws -> Inventory {
        var inventory = base ?? Inventory(
            packages: [],
            taps: [],
            tools: [],
            refreshedAt: Date(),
            warnings: []
        )

        await withTaskGroup(of: SourceScanResult.self) { group in
            for source in sources {
                group.addTask {
                    if let onEvent {
                        await onEvent(.started(source))
                    }
                    return await self.scan(source)
                }
            }
            for await result in group {
                inventory.merge(result)
                if let onEvent {
                    await onEvent(.finished(result))
                }
            }
        }

        inventory.refreshedAt = Date()
        // When the caller drives progressive merge via onEvent, it owns the
        // authoritative inventory + cache (avoids races with concurrent scoped refreshes).
        if onEvent == nil {
            try saveCache(inventory)
        }
        return inventory
    }

    public func scan(_ source: InventorySource) async -> SourceScanResult {
        switch source {
        case .brew: await scanBrew()
        case .npm: await scanNpm()
        case .pip: await scanPip()
        case .gem: await scanGem()
        case .uv: await scanUv()
        case .bun: await scanBun()
        }
    }

    // MARK: - Per-source scans

    private func scanBrew() async -> SourceScanResult {
        guard let brew = await ToolEnvironment.resolveBrew(runner: runner) else {
            return SourceScanResult(
                source: .brew,
                packages: [],
                taps: [],
                tool: RuntimeTool(id: "brew", displayName: "Homebrew", available: false),
                warnings: ["Homebrew (brew) was not found on PATH."]
            )
        }

        async let brewVersion = toolVersion(executable: brew, arguments: ["--version"])
        async let repositoryOut = runner.capture(executable: brew, arguments: ["--repository"])

        let repositoryPath: String
        if let repo = try? await repositoryOut, repo.status == 0,
           let text = String(data: repo.stdout, encoding: .utf8)
        {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            repositoryPath = trimmed.isEmpty
                ? BrewCatalogFreshness.repositoryPath(fromBrewExecutable: brew)
                : trimmed
        } else {
            repositoryPath = BrewCatalogFreshness.repositoryPath(fromBrewExecutable: brew)
        }
        let tool = RuntimeTool(
            id: "brew",
            displayName: "Homebrew",
            available: true,
            executable: brew,
            version: await brewVersion,
            catalogUpdatedAt: BrewCatalogFreshness.lastUpdateDate(repositoryPath: repositoryPath)
        )

        do {
            async let infoOut = captureJSON(executable: brew, arguments: ["info", "--json=v2", "--installed"])
            async let outdated = captureJSON(executable: brew, arguments: ["outdated", "--json=v2"])
            async let greedy = captureJSON(executable: brew, arguments: ["outdated", "--json=v2", "--greedy"])
            async let tapInfo = captureJSON(executable: brew, arguments: ["tap-info", "--json", "--installed"])
            async let trust = captureJSON(executable: brew, arguments: ["trust", "--json=v1"])
            async let formulaListOut = runner.capture(
                executable: brew,
                arguments: ["list", "--formula", "--full-name"]
            )
            async let caskListOut = runner.capture(
                executable: brew,
                arguments: ["list", "--cask", "--full-name"]
            )

            var info = try await infoOut
            let formulaList = try await formulaListOut
            let caskList = try await caskListOut
            var warnings: [String] = []

            if formulaList.status == 0, caskList.status == 0 {
                let listedFormulae = BrewInfoEnrichment.names(fromListOutput: formulaList.stdout)
                let listedCasks = BrewInfoEnrichment.names(fromListOutput: caskList.stdout)
                let missing = try BrewInfoEnrichment.missingIDs(
                    listedFormulae: listedFormulae,
                    listedCasks: listedCasks,
                    info: info
                )
                let missingIDs = missing.formulae + missing.casks
                if !missingIDs.isEmpty {
                    let supplemental = try await captureJSON(
                        executable: brew,
                        arguments: ["info", "--json=v2"] + missingIDs
                    )
                    info = try BrewInfoEnrichment.merge(base: info, extra: supplemental)
                    warnings.append(
                        "Included \(missingIDs.count) installed package(s) omitted by brew info because their tap is untrusted."
                    )
                }
            } else {
                if formulaList.status != 0 {
                    warnings.append("brew list --formula failed: \(formulaList.stderr.prefix(200))")
                }
                if caskList.status != 0 {
                    warnings.append("brew list --cask failed: \(caskList.stderr.prefix(200))")
                }
            }

            let merged = try await BrewMerger.merge(
                info: info,
                outdated: outdated,
                greedyOutdated: greedy,
                tapInfo: tapInfo,
                trust: trust
            )
            return SourceScanResult(
                source: .brew,
                packages: merged.packages,
                taps: merged.taps,
                tool: tool,
                warnings: warnings
            )
        } catch {
            return SourceScanResult(
                source: .brew,
                packages: [],
                taps: [],
                tool: tool,
                warnings: ["Homebrew inventory failed: \(error.localizedDescription)"]
            )
        }
    }

    private func scanNpm() async -> SourceScanResult {
        guard let npm = await ToolEnvironment.resolveNpm(runner: runner) else {
            return SourceScanResult(
                source: .npm,
                packages: [],
                tool: RuntimeTool(id: "npm", displayName: "npm", available: false),
                warnings: ["npm was not found on this Mac."]
            )
        }

        async let npmVersion = toolVersion(executable: npm, arguments: ["--version"])
        let tool = RuntimeTool(
            id: "npm",
            displayName: "npm",
            available: true,
            executable: npm,
            version: await npmVersion
        )

        do {
            async let listOut = runner.capture(executable: npm, arguments: ["list", "-g", "--depth=0", "--json"])
            async let outdatedOut = runner.capture(executable: npm, arguments: ["outdated", "-g", "--json"])
            let list = try await listOut
            let outdated = try await outdatedOut
            guard list.status == 0 else {
                throw ManagerError.commandFailed("npm list", list.stderr)
            }
            if outdated.status == 0 || outdated.status == 1 {
                let pkgs = try NpmParser.packages(
                    listJSON: list.stdout,
                    outdatedJSON: Self.nonEmptyJSON(outdated.stdout, fallback: "{}")
                )
                return SourceScanResult(source: .npm, packages: pkgs, tool: tool)
            }
            let pkgs = try NpmParser.packages(listJSON: list.stdout, outdatedJSON: Data("{}".utf8))
            return SourceScanResult(
                source: .npm,
                packages: pkgs,
                tool: tool,
                warnings: ["npm outdated failed: \(outdated.stderr.prefix(200))"]
            )
        } catch {
            return SourceScanResult(
                source: .npm,
                packages: [],
                tool: tool,
                warnings: ["npm inventory failed: \(error.localizedDescription)"]
            )
        }
    }

    private func scanPip() async -> SourceScanResult {
        guard let python3 = await ToolEnvironment.resolveOnPATH("python3", runner: runner) else {
            return SourceScanResult(
                source: .pip,
                packages: [],
                tool: RuntimeTool(id: "pip", displayName: "pip", available: false),
                warnings: ["python3 was not found on PATH."]
            )
        }

        async let pipVersion = toolVersion(executable: python3, arguments: ["-m", "pip", "--version"])
        let tool = RuntimeTool(
            id: "pip",
            displayName: "pip",
            available: true,
            executable: python3,
            version: await pipVersion
        )

        do {
            async let listOut = runner.capture(
                executable: python3,
                arguments: ["-m", "pip", "list", "--format=json"]
            )
            async let outdatedOut = runner.capture(
                executable: python3,
                arguments: ["-m", "pip", "list", "--outdated", "--format=json"]
            )
            let list = try await listOut
            let outdated = try await outdatedOut
            guard list.status == 0 else {
                throw ManagerError.commandFailed("pip list", list.stderr)
            }
            if outdated.status == 0 {
                let pkgs = try PipParser.packages(
                    listJSON: list.stdout,
                    outdatedJSON: Self.nonEmptyJSON(outdated.stdout, fallback: "[]")
                )
                return SourceScanResult(source: .pip, packages: pkgs, tool: tool)
            }
            let pkgs = try PipParser.packages(listJSON: list.stdout, outdatedJSON: Data("[]".utf8))
            return SourceScanResult(
                source: .pip,
                packages: pkgs,
                tool: tool,
                warnings: ["pip outdated failed: \(outdated.stderr.prefix(200))"]
            )
        } catch {
            return SourceScanResult(
                source: .pip,
                packages: [],
                tool: tool,
                warnings: ["pip inventory failed: \(error.localizedDescription)"]
            )
        }
    }

    private func scanGem() async -> SourceScanResult {
        guard let gem = await ToolEnvironment.resolveOnPATH("gem", runner: runner) else {
            return SourceScanResult(
                source: .gem,
                packages: [],
                tool: RuntimeTool(id: "gem", displayName: "RubyGems", available: false),
                warnings: ["gem was not found on PATH."]
            )
        }

        async let gemVersion = toolVersion(executable: gem, arguments: ["--version"])
        let tool = RuntimeTool(
            id: "gem",
            displayName: "RubyGems",
            available: true,
            executable: gem,
            version: await gemVersion
        )

        do {
            async let listOut = runner.capture(executable: gem, arguments: ["list", "--local"])
            async let outdatedOut = runner.capture(executable: gem, arguments: ["outdated"])
            let list = try await listOut
            let outdated = try await outdatedOut
            guard list.status == 0 else {
                throw ManagerError.commandFailed("gem list", list.stderr)
            }
            let listText = String(data: list.stdout, encoding: .utf8) ?? ""
            let outdatedText = String(data: outdated.stdout, encoding: .utf8) ?? ""
            let pkgs = try GemParser.packages(listText: listText, outdatedText: outdatedText)
            return SourceScanResult(source: .gem, packages: pkgs, tool: tool)
        } catch {
            return SourceScanResult(
                source: .gem,
                packages: [],
                tool: tool,
                warnings: ["gem inventory failed: \(error.localizedDescription)"]
            )
        }
    }

    private func scanUv() async -> SourceScanResult {
        guard let uv = await ToolEnvironment.resolveUv(runner: runner) else {
            return SourceScanResult(
                source: .uv,
                packages: [],
                tool: RuntimeTool(id: "uv", displayName: "uv", available: false),
                warnings: ["uv was not found on this Mac."]
            )
        }

        async let uvVersion = toolVersion(executable: uv, arguments: ["--version"])
        let tool = RuntimeTool(
            id: "uv",
            displayName: "uv",
            available: true,
            executable: uv,
            version: await uvVersion
        )

        do {
            async let listOut = runner.capture(
                executable: uv,
                arguments: ["tool", "list", "--show-version-specifiers"]
            )
            async let outdatedOut = runner.capture(
                executable: uv,
                arguments: ["tool", "list", "--outdated", "--show-version-specifiers"]
            )
            let list = try await listOut
            let outdated = try await outdatedOut
            guard list.status == 0 else {
                throw ManagerError.commandFailed("uv tool list", list.stderr)
            }
            let listText = String(data: list.stdout, encoding: .utf8) ?? ""
            // "No tools installed" is written to stderr with empty stdout.
            let listCombined = listText.isEmpty ? list.stderr : listText

            if outdated.status == 0 {
                let outdatedText = String(data: outdated.stdout, encoding: .utf8) ?? ""
                let pkgs = try UvToolParser.packages(listText: listCombined, outdatedText: outdatedText)
                return SourceScanResult(source: .uv, packages: pkgs, tool: tool)
            }
            let pkgs = try UvToolParser.packages(listText: listCombined, outdatedText: "")
            return SourceScanResult(
                source: .uv,
                packages: pkgs,
                tool: tool,
                warnings: ["uv tool list --outdated failed: \(outdated.stderr.prefix(200))"]
            )
        } catch {
            return SourceScanResult(
                source: .uv,
                packages: [],
                tool: tool,
                warnings: ["uv inventory failed: \(error.localizedDescription)"]
            )
        }
    }

    private func scanBun() async -> SourceScanResult {
        guard let bun = await ToolEnvironment.resolveBun(runner: runner) else {
            return SourceScanResult(
                source: .bun,
                packages: [],
                tool: RuntimeTool(id: "bun", displayName: "bun", available: false),
                warnings: ["bun was not found on this Mac."]
            )
        }

        async let bunVersion = toolVersion(executable: bun, arguments: ["--version"])
        let tool = RuntimeTool(
            id: "bun",
            displayName: "bun",
            available: true,
            executable: bun,
            version: await bunVersion
        )

        do {
            async let listOut = runner.capture(
                executable: bun,
                arguments: ["pm", "ls", "--global"]
            )
            async let outdatedOut = runner.capture(
                executable: bun,
                arguments: ["outdated", "--global"]
            )
            let list = try await listOut
            let outdated = try await outdatedOut
            guard list.status == 0 else {
                // No global lockfile yet means "no bun globals", not a user-facing failure.
                if BunParser.isMissingLockfileError(list.stderr) {
                    return SourceScanResult(source: .bun, packages: [], tool: tool)
                }
                throw ManagerError.commandFailed("bun pm ls --global", list.stderr)
            }
            let listText = String(data: list.stdout, encoding: .utf8) ?? ""

            if outdated.status == 0 {
                let outdatedText = String(data: outdated.stdout, encoding: .utf8) ?? ""
                let pkgs = try BunParser.packages(listText: listText, outdatedText: outdatedText)
                return SourceScanResult(source: .bun, packages: pkgs, tool: tool)
            }
            let pkgs = try BunParser.packages(listText: listText, outdatedText: "")
            // No global lockfile yet means "nothing outdated", not a user-facing failure.
            // `bun pm ls --global` can succeed with 0 packages while `outdated --global` still exits non-zero.
            if BunParser.isMissingLockfileError(outdated.stderr) {
                return SourceScanResult(source: .bun, packages: pkgs, tool: tool)
            }
            return SourceScanResult(
                source: .bun,
                packages: pkgs,
                tool: tool,
                warnings: ["bun outdated --global failed: \(outdated.stderr.prefix(200))"]
            )
        } catch {
            return SourceScanResult(
                source: .bun,
                packages: [],
                tool: tool,
                warnings: ["bun inventory failed: \(error.localizedDescription)"]
            )
        }
    }

    public func plan(_ action: PackageAction, inventory: Inventory) throws -> [PlannedCommand] {
        switch action {
        case .refreshCatalog:
            guard let brew = inventory.tools.first(where: { $0.id == "brew" })?.executable else {
                throw ValidationError.unsupported("Homebrew is not available.")
            }
            return [makePlannedCommand(executable: brew, arguments: ["update"], id: "brew-update")]

        case .upgrade(let packages, let includeSelfUpdating):
            return try planUpgrade(packages: packages, includeSelfUpdating: includeSelfUpdating, inventory: inventory)

        case .pin(let package):
            return try planPin(package: package, pin: true, inventory: inventory)

        case .unpin(let package):
            return try planPin(package: package, pin: false, inventory: inventory)

        case .remove(let package):
            return try planRemove(package: package, inventory: inventory)

        case .trustItem(let package):
            return try planTrustItem(package: package, trust: true, inventory: inventory)

        case .untrustItem(let package):
            return try planTrustItem(package: package, trust: false, inventory: inventory)

        case .trustTap(let tap):
            return try planTrustTap(tap: tap, trust: true, inventory: inventory)

        case .untrustTap(let tap):
            return try planTrustTap(tap: tap, trust: false, inventory: inventory)

        case .addTap(let tap):
            return try planAddTap(tap: tap, inventory: inventory)

        case .removeTap(let tap):
            return try planRemoveTap(tap: tap, inventory: inventory)
        }
    }

    public func perform(
        _ action: PackageAction,
        inventory: Inventory,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws {
        let commands = try plan(action, inventory: inventory)
        for command in commands {
            let streamed = OSAllocatedUnfairLock(initialState: "")
            let status = try await runner.run(
                executable: command.executable,
                arguments: command.arguments,
                onOutput: { chunk in
                    streamed.withLock { $0 += chunk }
                    onOutput(chunk)
                }
            )
            if status != 0 {
                let output = streamed.withLock { $0 }
                throw ManagerError.commandFailed(
                    command.display,
                    Self.failureDetail(status: status, output: output)
                )
            }
        }
    }

    /// Maps common sudo / askpass failures to a clearer message for GUI users.
    static func failureDetail(status: Int, output: String) -> String {
        let lower = output.lowercased()
        let needsAdmin =
            lower.contains("a password is required")
            || lower.contains("a terminal is required to read the password")
            || lower.contains("sudo: no askpass program specified")
            || lower.contains("password dialog cancelled")
        if needsAdmin {
            return """
            This package needs administrator access. Enter your macOS password when prompted, \
            or try again if you cancelled the password dialog. (exit status \(status))
            """
        }
        return "exit status \(status)"
    }

    // MARK: - Planning helpers

    private func planUpgrade(
        packages: [Package],
        includeSelfUpdating: Bool,
        inventory: Inventory
    ) throws -> [PlannedCommand] {
        var formulae: [String] = []
        var casks: [String] = []
        var npmNames: [String] = []
        var pipNames: [String] = []
        var gemNames: [String] = []
        var uvUpgradeNames: [String] = []
        var uvForceLatestNames: [String] = []
        var bunNames: [String] = []

        for pkg in packages {
            let shouldUpgrade: Bool
            switch pkg.source {
            case .brewFormula, .brewCask:
                if pkg.pinned { continue }
                if pkg.isOutdated {
                    shouldUpgrade = true
                } else if includeSelfUpdating && pkg.greedyOnly {
                    shouldUpgrade = true
                } else {
                    shouldUpgrade = false
                }
            case .npm, .pip, .gem:
                shouldUpgrade = pkg.isOutdated && !pkg.pinned
            case .uv, .bun:
                if !pkg.isOutdated {
                    shouldUpgrade = false
                } else if pkg.pinned {
                    // Version-constrained tools need an explicit “Upgrade anyway”.
                    shouldUpgrade = includeSelfUpdating
                } else {
                    shouldUpgrade = true
                }
            }

            guard shouldUpgrade else { continue }

            switch pkg.source {
            case .brewFormula:
                try NameValidation.validatePackageToken(pkg.name)
                formulae.append(pkg.name)
            case .brewCask:
                try NameValidation.validatePackageToken(pkg.name)
                casks.append(pkg.name)
            case .npm:
                try NameValidation.validatePackageToken(pkg.name)
                npmNames.append(pkg.name)
            case .pip:
                try NameValidation.validatePackageToken(pkg.name)
                pipNames.append(pkg.name)
            case .gem:
                try NameValidation.validatePackageToken(pkg.name)
                gemNames.append(pkg.name)
            case .uv:
                try NameValidation.validatePackageToken(pkg.name)
                if pkg.pinned {
                    uvForceLatestNames.append(pkg.name)
                } else {
                    uvUpgradeNames.append(pkg.name)
                }
            case .bun:
                try NameValidation.validatePackageToken(pkg.name)
                bunNames.append(pkg.name)
            }
        }

        var commands: [PlannedCommand] = []
        if !formulae.isEmpty {
            guard let brew = inventory.tools.first(where: { $0.id == "brew" })?.executable else {
                throw ValidationError.unsupported("Homebrew is not available.")
            }
            commands.append(makePlannedCommand(
                executable: brew,
                arguments: ["upgrade"] + formulae,
                id: "brew-upgrade-formulae"
            ))
        }
        if !casks.isEmpty {
            guard let brew = inventory.tools.first(where: { $0.id == "brew" })?.executable else {
                throw ValidationError.unsupported("Homebrew is not available.")
            }
            // When includeSelfUpdating is true, pass --greedy so auto_updates and :latest casks actually upgrade
            // (plain `brew upgrade --cask` skips them unless --greedy is set; verified via `brew upgrade --help`).
            var caskArgs = ["upgrade", "--cask"]
            if includeSelfUpdating {
                caskArgs.append("--greedy")
            }
            caskArgs.append(contentsOf: casks)
            commands.append(makePlannedCommand(
                executable: brew,
                arguments: caskArgs,
                id: "brew-upgrade-casks"
            ))
        }

        if !npmNames.isEmpty {
            let npmExec = inventory.tools.first(where: { $0.id == "npm" })?.executable
            guard let npmExec else { throw ValidationError.unsupported("npm is not available.") }
            let specs = npmNames.map { "\($0)@latest" }
            commands.append(makePlannedCommand(
                executable: npmExec,
                arguments: ["install", "-g"] + specs,
                id: "npm-upgrade"
            ))
        }

        if !pipNames.isEmpty {
            let python = inventory.tools.first(where: { $0.id == "pip" })?.executable
            guard let python else { throw ValidationError.unsupported("pip is not available.") }
            for name in pipNames {
                commands.append(makePlannedCommand(
                    executable: python,
                    arguments: ["-m", "pip", "install", "--upgrade", name],
                    id: "pip-upgrade-\(name)"
                ))
            }
        }

        if !gemNames.isEmpty {
            let gemExec = inventory.tools.first(where: { $0.id == "gem" })?.executable
            guard let gemExec else { throw ValidationError.unsupported("gem is not available.") }
            commands.append(makePlannedCommand(
                executable: gemExec,
                arguments: ["update"] + gemNames,
                id: "gem-upgrade"
            ))
        }

        if !uvUpgradeNames.isEmpty {
            let uvExec = inventory.tools.first(where: { $0.id == "uv" })?.executable
            guard let uvExec else { throw ValidationError.unsupported("uv is not available.") }
            commands.append(makePlannedCommand(
                executable: uvExec,
                arguments: ["tool", "upgrade"] + uvUpgradeNames,
                id: "uv-upgrade"
            ))
        }

        if !uvForceLatestNames.isEmpty {
            let uvExec = inventory.tools.first(where: { $0.id == "uv" })?.executable
            guard let uvExec else { throw ValidationError.unsupported("uv is not available.") }
            for name in uvForceLatestNames {
                commands.append(makePlannedCommand(
                    executable: uvExec,
                    arguments: ["tool", "install", "\(name)@latest"],
                    id: "uv-install-latest-\(name)"
                ))
            }
        }

        if !bunNames.isEmpty {
            let bunExec = inventory.tools.first(where: { $0.id == "bun" })?.executable
            guard let bunExec else { throw ValidationError.unsupported("bun is not available.") }
            commands.append(makePlannedCommand(
                executable: bunExec,
                arguments: ["update", "--global", "--latest"] + bunNames,
                id: "bun-upgrade"
            ))
        }

        if commands.isEmpty {
            throw ValidationError.unsupported(
                "Nothing to upgrade. Pinned packages are skipped, and apps that update themselves need “Upgrade anyway” or the include toggle."
            )
        }

        return commands
    }

    private func planPin(package: Package, pin: Bool, inventory: Inventory) throws -> [PlannedCommand] {
        guard let brew = inventory.tools.first(where: { $0.id == "brew" })?.executable else {
            throw ValidationError.unsupported("Homebrew is not available.")
        }
        try NameValidation.validatePackageToken(package.name)
        switch package.source {
        case .brewFormula:
            let verb = pin ? "pin" : "unpin"
            return [makePlannedCommand(executable: brew, arguments: [verb, package.name], id: "brew-\(verb)-formula")]
        case .brewCask:
            let verb = pin ? "pin" : "unpin"
            return [makePlannedCommand(
                executable: brew,
                arguments: [verb, "--cask", package.name],
                id: "brew-\(verb)-cask"
            )]
        case .npm, .pip, .gem, .uv, .bun:
            throw ValidationError.unsupported("Pin is not supported for \(package.source.rawValue).")
        }
    }

    private func planRemove(package: Package, inventory: Inventory) throws -> [PlannedCommand] {
        try NameValidation.validatePackageToken(package.name)
        switch package.source {
        case .brewFormula:
            guard let brew = inventory.tools.first(where: { $0.id == "brew" })?.executable else {
                throw ValidationError.unsupported("Homebrew is not available.")
            }
            let uninstallTarget = brewQualifiedName(package)
            var commands: [PlannedCommand] = []
            if package.trust == .untrusted {
                let trustID = try brewTrustID(package)
                commands.append(makePlannedCommand(
                    executable: brew,
                    arguments: ["trust", "--formula", trustID],
                    id: "brew-trust-formula-before-uninstall"
                ))
            }
            commands.append(makePlannedCommand(
                executable: brew,
                arguments: ["uninstall", uninstallTarget],
                id: "brew-uninstall-formula"
            ))
            if package.trust == .untrusted {
                let trustID = try brewTrustID(package)
                commands.append(makePlannedCommand(
                    executable: brew,
                    arguments: ["untrust", "--formula", trustID],
                    id: "brew-untrust-formula-after-uninstall"
                ))
            }
            return commands
        case .brewCask:
            guard let brew = inventory.tools.first(where: { $0.id == "brew" })?.executable else {
                throw ValidationError.unsupported("Homebrew is not available.")
            }
            let uninstallTarget = brewQualifiedName(package)
            var commands: [PlannedCommand] = []
            if package.trust == .untrusted {
                let trustID = try brewTrustID(package)
                commands.append(makePlannedCommand(
                    executable: brew,
                    arguments: ["trust", "--cask", trustID],
                    id: "brew-trust-cask-before-uninstall"
                ))
            }
            commands.append(makePlannedCommand(
                executable: brew,
                arguments: ["uninstall", "--cask", uninstallTarget],
                id: "brew-uninstall-cask"
            ))
            if package.trust == .untrusted {
                let trustID = try brewTrustID(package)
                commands.append(makePlannedCommand(
                    executable: brew,
                    arguments: ["untrust", "--cask", trustID],
                    id: "brew-untrust-cask-after-uninstall"
                ))
            }
            return commands
        case .npm:
            guard let npm = inventory.tools.first(where: { $0.id == "npm" })?.executable else {
                throw ValidationError.unsupported("npm is not available.")
            }
            return [makePlannedCommand(
                executable: npm,
                arguments: ["uninstall", "-g", package.name],
                id: "npm-uninstall"
            )]
        case .pip:
            guard let python = inventory.tools.first(where: { $0.id == "pip" })?.executable else {
                throw ValidationError.unsupported("pip is not available.")
            }
            return [makePlannedCommand(
                executable: python,
                arguments: ["-m", "pip", "uninstall", "-y", package.name],
                id: "pip-uninstall"
            )]
        case .gem:
            guard let gem = inventory.tools.first(where: { $0.id == "gem" })?.executable else {
                throw ValidationError.unsupported("gem is not available.")
            }
            return [makePlannedCommand(
                executable: gem,
                arguments: ["uninstall", package.name, "--all", "--ignore-dependencies", "--executables"],
                id: "gem-uninstall"
            )]
        case .uv:
            guard let uv = inventory.tools.first(where: { $0.id == "uv" })?.executable else {
                throw ValidationError.unsupported("uv is not available.")
            }
            return [makePlannedCommand(
                executable: uv,
                arguments: ["tool", "uninstall", package.name],
                id: "uv-uninstall"
            )]
        case .bun:
            guard let bun = inventory.tools.first(where: { $0.id == "bun" })?.executable else {
                throw ValidationError.unsupported("bun is not available.")
            }
            return [makePlannedCommand(
                executable: bun,
                arguments: ["remove", "--global", package.name],
                id: "bun-uninstall"
            )]
        }
    }

    private func planTrustItem(package: Package, trust: Bool, inventory: Inventory) throws -> [PlannedCommand] {
        guard package.source == .brewFormula || package.source == .brewCask else {
            throw ValidationError.unsupported("Trust is only supported for Homebrew packages.")
        }
        if package.trust == .official {
            throw ValidationError.unsupported("Official Homebrew packages do not require trust.")
        }
        guard let brew = inventory.tools.first(where: { $0.id == "brew" })?.executable else {
            throw ValidationError.unsupported("Homebrew is not available.")
        }
        let verb = trust ? "trust" : "untrust"
        switch package.source {
        case .brewFormula:
            let id = package.fullName.contains("/") ? package.fullName : (package.tap.map { "\($0)/\(package.name)" } ?? package.name)
            try NameValidation.validatePackageToken(id.replacingOccurrences(of: "/", with: "-"))
            guard id.contains("/") else {
                throw ValidationError.invalidName("Formula trust id must be tap-qualified.")
            }
            return [makePlannedCommand(
                executable: brew,
                arguments: [verb, "--formula", id],
                id: "brew-\(verb)-formula"
            )]
        case .brewCask:
            let id = package.fullName.contains("/") ? package.fullName : (package.tap.map { "\($0)/\(package.name)" } ?? package.name)
            try NameValidation.validateTrustFormulaID(id)
            return [makePlannedCommand(
                executable: brew,
                arguments: [verb, "--cask", id],
                id: "brew-\(verb)-cask"
            )]
        default:
            throw ValidationError.unsupported("Trust is only supported for Homebrew packages.")
        }
    }

    private func planTrustTap(tap: String, trust: Bool, inventory: Inventory) throws -> [PlannedCommand] {
        try NameValidation.validateTap(tap)
        if BrewTrust.officialTaps.contains(tap) {
            throw ValidationError.unsupported("Official taps do not require trust.")
        }
        guard let brew = inventory.tools.first(where: { $0.id == "brew" })?.executable else {
            throw ValidationError.unsupported("Homebrew is not available.")
        }
        let verb = trust ? "trust" : "untrust"
        return [makePlannedCommand(executable: brew, arguments: [verb, tap], id: "brew-\(verb)-tap")]
    }

    private func planAddTap(tap: String, inventory: Inventory) throws -> [PlannedCommand] {
        try NameValidation.validateTap(tap)
        if inventory.taps.contains(where: { $0.name == tap && $0.isTapped }) {
            throw ValidationError.unsupported("Tap “\(tap)” is already installed.")
        }
        guard let brew = inventory.tools.first(where: { $0.id == "brew" })?.executable else {
            throw ValidationError.unsupported("Homebrew is not available.")
        }
        return [makePlannedCommand(executable: brew, arguments: ["tap", tap], id: "brew-tap")]
    }

    private func planRemoveTap(tap: String, inventory: Inventory) throws -> [PlannedCommand] {
        try NameValidation.validateTap(tap)
        if BrewTrust.officialTaps.contains(tap) {
            throw ValidationError.unsupported("Official taps cannot be removed.")
        }
        guard let record = inventory.taps.first(where: { $0.name == tap }), record.isTapped else {
            throw ValidationError.unsupported("Tap “\(tap)” is not installed.")
        }
        guard let brew = inventory.tools.first(where: { $0.id == "brew" })?.executable else {
            throw ValidationError.unsupported("Homebrew is not available.")
        }
        let installed = inventory.packages.filter { $0.tap == tap }
        // Untap --force must load each installed formula/cask; untrusted ones refuse to load.
        let needsTemporaryTrust = installed.contains { $0.trust == .untrusted }

        var commands: [PlannedCommand] = []
        if needsTemporaryTrust {
            commands.append(makePlannedCommand(
                executable: brew,
                arguments: ["trust", tap],
                id: "brew-trust-tap-before-untap"
            ))
        }
        var arguments = ["untap"]
        if !installed.isEmpty {
            arguments.append("--force")
        }
        arguments.append(tap)
        commands.append(makePlannedCommand(executable: brew, arguments: arguments, id: "brew-untap"))
        if needsTemporaryTrust {
            commands.append(makePlannedCommand(
                executable: brew,
                arguments: ["untrust", tap],
                id: "brew-untrust-tap-after-untap"
            ))
        }
        return commands
    }

    private func brewQualifiedName(_ package: Package) -> String {
        if package.fullName.contains("/") {
            return package.fullName
        }
        if let tap = package.tap, !tap.isEmpty {
            return "\(tap)/\(package.name)"
        }
        return package.name
    }

    private func brewTrustID(_ package: Package) throws -> String {
        let id = brewQualifiedName(package)
        try NameValidation.validateTrustFormulaID(id)
        guard id.contains("/") else {
            throw ValidationError.invalidName("Trust id must be tap-qualified.")
        }
        return id
    }

    private func captureJSON(executable: String, arguments: [String]) async throws -> Data {
        let output = try await runner.capture(executable: executable, arguments: arguments)
        guard output.status == 0 else {
            throw ManagerError.commandFailed(([executable] + arguments).joined(separator: " "), output.stderr)
        }
        let stdout = Self.droppingLeadingWhitespace(output.stdout)
        guard !stdout.isEmpty, stdout.first == UInt8(ascii: "{") || stdout.first == UInt8(ascii: "[") else {
            let snippet = output.stderr.prefix(200)
            throw ManagerError.invalidJSON(String(snippet))
        }
        return stdout
    }

    private static func droppingLeadingWhitespace(_ data: Data) -> Data {
        var index = data.startIndex
        while index < data.endIndex {
            let byte = data[index]
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                index = data.index(after: index)
            } else {
                break
            }
        }
        return index == data.startIndex ? data : Data(data[index...])
    }

    private static func nonEmptyJSON(_ data: Data, fallback: String) -> Data {
        let trimmed = droppingLeadingWhitespace(data)
        return trimmed.isEmpty ? Data(fallback.utf8) : trimmed
    }

    private func toolVersion(executable: String, arguments: [String]) async -> String? {
        guard let output = try? await runner.capture(executable: executable, arguments: arguments),
              output.status == 0 else { return nil }
        let line = String(data: output.stdout, encoding: .utf8)?
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)
        return line?.trimmingCharacters(in: .whitespaces)
    }
}

enum ManagerError: Error, LocalizedError {
    case commandFailed(String, String)
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let cmd, let detail): "\(cmd) failed: \(detail)"
        case .invalidJSON(let detail): "Expected JSON output: \(detail)"
        }
    }
}
