import Foundation

public enum SourceKind: String, Codable, CaseIterable, Sendable, Hashable {
    case brewFormula
    case brewCask
    case npm
    case pip
    case gem
    case uv
    case bun

    /// Inventory scan unit (Homebrew formulae/casks share one brew scan).
    public var inventorySource: InventorySource {
        switch self {
        case .brewFormula, .brewCask: .brew
        case .npm: .npm
        case .pip: .pip
        case .gem: .gem
        case .uv: .uv
        case .bun: .bun
        }
    }
}

/// Unit of inventory scanning / refresh progress (not the same as `SourceKind`).
public enum InventorySource: String, CaseIterable, Sendable, Hashable {
    case brew
    case npm
    case pip
    case gem
    case uv
    case bun

    public var toolID: String { rawValue }

    public var displayName: String {
        switch self {
        case .brew: "Homebrew"
        case .npm: "npm"
        case .pip: "pip"
        case .gem: "gem"
        case .uv: "uv"
        case .bun: "bun"
        }
    }

    public var packageSources: Set<SourceKind> {
        switch self {
        case .brew: [.brewFormula, .brewCask]
        case .npm: [.npm]
        case .pip: [.pip]
        case .gem: [.gem]
        case .uv: [.uv]
        case .bun: [.bun]
        }
    }
}

public struct SourceScanResult: Sendable {
    public var source: InventorySource
    public var packages: [Package]
    public var taps: [TapRecord]?
    public var tool: RuntimeTool
    public var warnings: [String]

    public init(
        source: InventorySource,
        packages: [Package],
        taps: [TapRecord]? = nil,
        tool: RuntimeTool,
        warnings: [String] = []
    ) {
        self.source = source
        self.packages = packages
        self.taps = taps
        self.tool = tool
        self.warnings = warnings
    }
}

public enum RefreshEvent: Sendable {
    case started(InventorySource)
    case finished(SourceScanResult)
}

public enum TrustState: String, Codable, Sendable, Hashable {
    case notApplicable
    case official
    case tapTrusted
    case itemTrusted
    case untrusted
}

public struct Package: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var fullName: String
    public var displayName: String
    public var source: SourceKind
    public var installedVersion: String
    public var latestVersion: String?
    public var isOutdated: Bool
    public var updatesItself: Bool
    public var greedyOnly: Bool
    public var pinned: Bool
    public var installedOnRequest: Bool
    public var installedAsDependency: Bool
    public var summary: String
    public var homepage: String?
    public var tap: String?
    public var trust: TrustState
    public var versionIsLatest: Bool
    public var dependsOn: [String]
    public var requiredBy: [String]
    /// Cask `.app` bundle names from brew artifacts (e.g. `Audacity 4.app`).
    public var appBundleNames: [String]

    public init(
        id: String,
        name: String,
        fullName: String,
        displayName: String,
        source: SourceKind,
        installedVersion: String,
        latestVersion: String? = nil,
        isOutdated: Bool,
        updatesItself: Bool,
        greedyOnly: Bool,
        pinned: Bool,
        installedOnRequest: Bool,
        installedAsDependency: Bool,
        summary: String,
        homepage: String? = nil,
        tap: String? = nil,
        trust: TrustState,
        versionIsLatest: Bool,
        dependsOn: [String] = [],
        requiredBy: [String] = [],
        appBundleNames: [String] = []
    ) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.displayName = displayName
        self.source = source
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
        self.isOutdated = isOutdated
        self.updatesItself = updatesItself
        self.greedyOnly = greedyOnly
        self.pinned = pinned
        self.installedOnRequest = installedOnRequest
        self.installedAsDependency = installedAsDependency
        self.summary = summary
        self.homepage = homepage
        self.tap = tap
        self.trust = trust
        self.versionIsLatest = versionIsLatest
        self.dependsOn = dependsOn
        self.requiredBy = requiredBy
        self.appBundleNames = appBundleNames
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, fullName, displayName, source
        case installedVersion, latestVersion, isOutdated, updatesItself, greedyOnly
        case pinned, installedOnRequest, installedAsDependency, summary, homepage
        case tap, trust, versionIsLatest, dependsOn, requiredBy, appBundleNames
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        fullName = try c.decode(String.self, forKey: .fullName)
        displayName = try c.decode(String.self, forKey: .displayName)
        source = try c.decode(SourceKind.self, forKey: .source)
        installedVersion = try c.decode(String.self, forKey: .installedVersion)
        latestVersion = try c.decodeIfPresent(String.self, forKey: .latestVersion)
        isOutdated = try c.decode(Bool.self, forKey: .isOutdated)
        updatesItself = try c.decode(Bool.self, forKey: .updatesItself)
        greedyOnly = try c.decode(Bool.self, forKey: .greedyOnly)
        pinned = try c.decode(Bool.self, forKey: .pinned)
        installedOnRequest = try c.decode(Bool.self, forKey: .installedOnRequest)
        installedAsDependency = try c.decode(Bool.self, forKey: .installedAsDependency)
        summary = try c.decode(String.self, forKey: .summary)
        homepage = try c.decodeIfPresent(String.self, forKey: .homepage)
        tap = try c.decodeIfPresent(String.self, forKey: .tap)
        trust = try c.decode(TrustState.self, forKey: .trust)
        versionIsLatest = try c.decode(Bool.self, forKey: .versionIsLatest)
        dependsOn = try c.decodeIfPresent([String].self, forKey: .dependsOn) ?? []
        requiredBy = try c.decodeIfPresent([String].self, forKey: .requiredBy) ?? []
        appBundleNames = try c.decodeIfPresent([String].self, forKey: .appBundleNames) ?? []
    }

    /// Warning shown in the UI when removing a package that was installed as a dependency.
    public var removalWarning: String? {
        guard !installedOnRequest else { return nil }
        return "This package was installed as a dependency, not on request. Removing it may break other software."
    }
}

public struct TapRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var official: Bool
    public var tapTrusted: Bool
    public var isTapped: Bool
    public var remote: String?
    public var formulaCount: Int
    public var caskCount: Int
    public var trustedFormulae: [String]
    public var trustedCasks: [String]
    public var isStaleTrust: Bool

    public init(
        name: String,
        official: Bool,
        tapTrusted: Bool,
        isTapped: Bool,
        remote: String? = nil,
        formulaCount: Int,
        caskCount: Int,
        trustedFormulae: [String],
        trustedCasks: [String],
        isStaleTrust: Bool
    ) {
        self.name = name
        self.official = official
        self.tapTrusted = tapTrusted
        self.isTapped = isTapped
        self.remote = remote
        self.formulaCount = formulaCount
        self.caskCount = caskCount
        self.trustedFormulae = trustedFormulae
        self.trustedCasks = trustedCasks
        self.isStaleTrust = isStaleTrust
    }
}

public struct RuntimeTool: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var displayName: String
    public var available: Bool
    public var executable: String?
    public var version: String?
    /// Homebrew only: last `brew update` / auto-update fetch time (`FETCH_HEAD` mtime).
    public var catalogUpdatedAt: Date?

    public init(
        id: String,
        displayName: String,
        available: Bool,
        executable: String? = nil,
        version: String? = nil,
        catalogUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.available = available
        self.executable = executable
        self.version = version
        self.catalogUpdatedAt = catalogUpdatedAt
    }
}

public struct Inventory: Codable, Sendable {
    public var packages: [Package]
    public var taps: [TapRecord]
    public var tools: [RuntimeTool]
    public var refreshedAt: Date
    public var warnings: [String]

    public init(
        packages: [Package],
        taps: [TapRecord],
        tools: [RuntimeTool],
        refreshedAt: Date,
        warnings: [String]
    ) {
        self.packages = packages
        self.taps = taps
        self.tools = tools
        self.refreshedAt = refreshedAt
        self.warnings = warnings
    }

    /// Replaces packages (and brew taps) for each result’s source, upserts tools, merges warnings.
    public mutating func merge(_ result: SourceScanResult) {
        let kinds = result.source.packageSources
        packages.removeAll { kinds.contains($0.source) }
        packages.append(contentsOf: result.packages)
        if let taps = result.taps {
            self.taps = taps
        }
        if let index = tools.firstIndex(where: { $0.id == result.tool.id }) {
            tools[index] = result.tool
        } else {
            tools.append(result.tool)
        }
        let prefix = warningPrefix(for: result.source)
        warnings.removeAll { $0.hasPrefix(prefix) }
        warnings.append(contentsOf: result.warnings)
        refreshedAt = Date()
    }

    public mutating func merge(results: [SourceScanResult]) {
        for result in results {
            merge(result)
        }
    }

    /// Immediate UI update after a successful mutation, before scoped refresh confirms.
    public mutating func applyOptimistic(_ action: PackageAction) {
        switch action {
        case .upgrade(let pkgs, let includeSelfUpdating):
            let ids = Set(pkgs.compactMap { pkg -> String? in
                if pkg.pinned {
                    // Only “upgrade anyway” clears pins for uv/bun.
                    guard includeSelfUpdating, pkg.source == .uv || pkg.source == .bun else { return nil }
                }
                return pkg.id
            })
            for index in packages.indices where ids.contains(packages[index].id) {
                let latest = packages[index].latestVersion ?? packages[index].installedVersion
                packages[index].installedVersion = latest
                packages[index].isOutdated = false
                packages[index].greedyOnly = false
                packages[index].versionIsLatest = true
                if packages[index].pinned, includeSelfUpdating,
                   packages[index].source == .uv || packages[index].source == .bun {
                    packages[index].pinned = false
                }
            }

        case .remove(let package):
            packages.removeAll { $0.id == package.id }

        case .pin(let package):
            if let index = packages.firstIndex(where: { $0.id == package.id }) {
                packages[index].pinned = true
            }

        case .unpin(let package):
            if let index = packages.firstIndex(where: { $0.id == package.id }) {
                packages[index].pinned = false
            }

        case .trustItem(let package):
            if let index = packages.firstIndex(where: { $0.id == package.id }) {
                packages[index].trust = .itemTrusted
            }

        case .untrustItem(let package):
            if let index = packages.firstIndex(where: { $0.id == package.id }) {
                packages[index].trust = .untrusted
            }

        case .trustTap(let tapName):
            if let index = taps.firstIndex(where: { $0.name == tapName }) {
                taps[index].tapTrusted = true
            }
            for index in packages.indices where packages[index].tap == tapName {
                if packages[index].trust == .untrusted {
                    packages[index].trust = .tapTrusted
                }
            }

        case .untrustTap(let tapName):
            if let index = taps.firstIndex(where: { $0.name == tapName }) {
                taps[index].tapTrusted = false
            }
            for index in packages.indices where packages[index].tap == tapName {
                if packages[index].trust == .tapTrusted {
                    packages[index].trust = .untrusted
                }
            }

        case .addTap, .removeTap:
            break

        case .refreshCatalog:
            if let index = tools.firstIndex(where: { $0.id == "brew" }) {
                tools[index].catalogUpdatedAt = Date()
            }
        }
    }

    private func warningPrefix(for source: InventorySource) -> String {
        switch source {
        case .brew: "Homebrew"
        case .npm: "npm"
        case .pip: "pip"
        case .gem: "gem"
        case .uv: "uv"
        case .bun: "bun"
        }
    }
}

public struct PlannedCommand: Sendable, Hashable, Identifiable {
    public var id: String
    public var executable: String
    public var arguments: [String]
    public var display: String

    public init(id: String, executable: String, arguments: [String], display: String) {
        self.id = id
        self.executable = executable
        self.arguments = arguments
        self.display = display
    }
}

public enum PackageAction: Sendable {
    case upgrade(packages: [Package], includeSelfUpdating: Bool)
    case pin(Package)
    case unpin(Package)
    case remove(Package)
    case trustItem(Package)
    case trustTap(String)
    case untrustItem(Package)
    case untrustTap(String)
    case addTap(String)
    case removeTap(String)
    case refreshCatalog

    /// Inventory sources that should be re-scanned after this action succeeds.
    public var affectedSources: Set<InventorySource> {
        switch self {
        case .upgrade(let packages, _):
            Set(packages.map(\.source.inventorySource))
        case .pin(let package), .unpin(let package), .remove(let package),
             .trustItem(let package), .untrustItem(let package):
            [package.source.inventorySource]
        case .trustTap, .untrustTap, .addTap, .removeTap, .refreshCatalog:
            [.brew]
        }
    }
}

public struct CommandOutput: Sendable {
    public var status: Int
    public var stdout: Data
    public var stderr: String

    public init(status: Int, stdout: Data, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol CommandRunning: Sendable {
    func capture(executable: String, arguments: [String]) async throws -> CommandOutput
    func run(
        executable: String,
        arguments: [String],
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> Int
}
