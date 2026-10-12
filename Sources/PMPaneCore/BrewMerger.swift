import Foundation

public enum BrewMerger {
    public static func merge(
        info: Data,
        outdated: Data,
        greedyOutdated: Data,
        tapInfo: Data,
        trust: Data
    ) throws -> (packages: [Package], taps: [TapRecord]) {
        let decoder = JSONDecoder()
        let infoRoot = try decoder.decode(BrewInfoRoot.self, from: info)
        let outdatedRoot = try decoder.decode(BrewOutdatedRoot.self, from: outdated)
        let greedyRoot = try decoder.decode(BrewOutdatedRoot.self, from: greedyOutdated)
        let tapRecordsRaw = try decoder.decode([BrewTapInfoEntry].self, from: tapInfo)
        let trustJSON = try decoder.decode(BrewTrustJSON.self, from: trust)
        let officialTaps = Set(tapRecordsRaw.compactMap { $0.official == true ? $0.name : nil })
            .union(BrewTrust.officialTaps)

        let plainFormulaOutdated = Dictionary(
            uniqueKeysWithValues: outdatedRoot.formulae.map { ($0.name, $0) }
        )
        let plainCaskOutdated = Dictionary(
            uniqueKeysWithValues: outdatedRoot.casks.map { ($0.name, $0) }
        )
        let greedyFormulaOutdated = Set(greedyRoot.formulae.map(\.name))
        let greedyCaskOutdated = Dictionary(
            uniqueKeysWithValues: greedyRoot.casks.map { ($0.name, $0) }
        )

        var requiredByMap: [String: [String]] = [:]
        for formula in infoRoot.formulae {
            guard !formula.installed.isEmpty else { continue }
            for dep in formula.dependencies ?? [] {
                requiredByMap[dep, default: []].append(formula.name)
            }
        }
        for key in requiredByMap.keys {
            requiredByMap[key] = Array(Set(requiredByMap[key] ?? [])).sorted()
        }

        var packages: [Package] = []

        for formula in infoRoot.formulae {
            guard !formula.installed.isEmpty else { continue }
            let installedEntry = pickInstalled(formula: formula)
            let name = formula.name
            let fullName = formula.full_name ?? name
            let tap = formula.tap
            let candidates = BrewTrust.candidateIDs(name: name, fullName: fullName, tap: tap)
            let trustState = BrewTrust.trustState(
                isFormula: true,
                tap: tap,
                candidateIDs: candidates,
                trust: trustJSON,
                officialTaps: officialTaps
            )

            let outdatedKeys = Self.outdatedLookupKeys(name: name, fullName: fullName)
            let plain = Self.firstOutdated(in: plainFormulaOutdated, keys: outdatedKeys)
            let inGreedy = outdatedKeys.contains(where: { greedyFormulaOutdated.contains($0) })
            var (isOutdated, greedyOnly, latestVersion) = outdatedFlags(
                plain: plain,
                inPlain: plain != nil,
                inGreedyOnly: inGreedy && plain == nil,
                currentVersion: plain?.current_version
            )
            // Fallback when outdated JSON keying mismatches, but info already knows.
            if !isOutdated, formula.outdated == true {
                isOutdated = true
                latestVersion = latestVersion ?? formula.versions?.stable
            } else if isOutdated, latestVersion == nil {
                latestVersion = formula.versions?.stable
            }

            let installedOnRequest = installedEntry.installed_on_request ?? false
            let installedAsDependency = !installedOnRequest
            let dependsOn = (formula.dependencies ?? []).sorted()

            let pkg = Package(
                id: "brewFormula:\(fullName)",
                name: name,
                fullName: fullName,
                displayName: name,
                source: .brewFormula,
                installedVersion: installedEntry.version,
                latestVersion: latestVersion,
                isOutdated: isOutdated,
                updatesItself: false,
                greedyOnly: greedyOnly,
                pinned: formula.pinned ?? plain?.pinned ?? false,
                installedOnRequest: installedOnRequest,
                installedAsDependency: installedAsDependency,
                summary: formula.desc ?? "",
                homepage: formula.homepage,
                tap: tap,
                trust: trustState,
                versionIsLatest: false,
                dependsOn: dependsOn,
                requiredBy: requiredByMap[name] ?? [],
                appBundleNames: []
            )
            packages.append(pkg)
        }

        for cask in infoRoot.casks {
            guard cask.installed != nil else { continue }
            let token = cask.token
            let fullToken = cask.full_token ?? token
            let tap = cask.tap
            let displayName = cask.name?.first ?? token
            let candidates = BrewTrust.candidateIDs(name: token, fullName: fullToken, tap: tap)
            let trustState = BrewTrust.trustState(
                isFormula: false,
                tap: tap,
                candidateIDs: candidates,
                trust: trustJSON,
                officialTaps: officialTaps
            )

            let versionStr = cask.version ?? cask.installed ?? ""
            let versionIsLatest = versionStr.lowercased() == "latest"
            let autoUpdates = cask.auto_updates == true
            let updatesItself = autoUpdates || versionIsLatest

            let outdatedKeys = Self.outdatedLookupKeys(name: token, fullName: fullToken)
            let plain = Self.firstOutdated(in: plainCaskOutdated, keys: outdatedKeys)
            let greedy = Self.firstOutdated(in: greedyCaskOutdated, keys: outdatedKeys)
            let inPlain = plain != nil
            let inGreedy = greedy != nil
            var (isOutdated, greedyOnly, latestVersion) = outdatedFlags(
                plain: greedy ?? plain,
                inPlain: inPlain,
                inGreedyOnly: inGreedy && !inPlain,
                currentVersion: (greedy ?? plain)?.current_version
            )
            if !isOutdated, cask.outdated == true {
                isOutdated = true
                latestVersion = latestVersion ?? cask.version
            } else if isOutdated, latestVersion == nil {
                latestVersion = cask.version
            }

            let pkg = Package(
                id: "brewCask:\(fullToken)",
                name: token,
                fullName: fullToken,
                displayName: displayName,
                source: .brewCask,
                installedVersion: cask.installed ?? versionStr,
                latestVersion: latestVersion,
                isOutdated: isOutdated,
                updatesItself: updatesItself,
                greedyOnly: greedyOnly,
                pinned: cask.pinned ?? false,
                installedOnRequest: true,
                installedAsDependency: false,
                summary: cask.desc ?? "",
                homepage: cask.homepage,
                tap: tap,
                trust: trustState,
                versionIsLatest: versionIsLatest,
                dependsOn: [],
                requiredBy: [],
                appBundleNames: BrewCaskArtifacts.appBundleNames(from: cask.artifacts)
            )
            packages.append(pkg)
        }

        let taps = buildTapRecords(tapInfo: tapRecordsRaw, trust: trustJSON)
        return (packages.sorted { $0.id < $1.id }, taps.sorted { $0.name < $1.name })
    }

    private static func pickInstalled(formula: BrewInfoFormula) -> BrewInstalledEntry {
        if let linked = formula.linked_keg,
           let match = formula.installed.first(where: { $0.version == linked }) {
            return match
        }
        return formula.installed[0]
    }

    /// `brew outdated --json` uses short names for core/cask and fully-qualified
    /// names for third-party taps (e.g. `supabase/tap/supabase`).
    private static func outdatedLookupKeys(name: String, fullName: String) -> [String] {
        var keys: [String] = []
        for key in [name, fullName] where !key.isEmpty && !keys.contains(key) {
            keys.append(key)
        }
        return keys
    }

    private static func firstOutdated(
        in dictionary: [String: BrewOutdatedEntry],
        keys: [String]
    ) -> BrewOutdatedEntry? {
        for key in keys {
            if let entry = dictionary[key] {
                return entry
            }
        }
        return nil
    }

    private static func outdatedFlags(
        plain: BrewOutdatedEntry?,
        inPlain: Bool,
        inGreedyOnly: Bool,
        currentVersion: String?
    ) -> (isOutdated: Bool, greedyOnly: Bool, latestVersion: String?) {
        if inPlain {
            return (true, false, currentVersion ?? plain?.current_version)
        }
        if inGreedyOnly {
            return (false, true, currentVersion ?? plain?.current_version)
        }
        return (false, false, nil)
    }

    private static func buildTapRecords(tapInfo: [BrewTapInfoEntry], trust: BrewTrustJSON) -> [TapRecord] {
        var byName: [String: TapRecord] = [:]
        let tappedNames = Set(tapInfo.map(\.name))

        for entry in tapInfo {
            let tapTrusted = entry.trusted == true || trust.taps.contains(entry.name)
            let trustedFormulae = trust.formulae.filter { $0.hasPrefix(entry.name + "/") }
            let trustedCasks = trust.casks.filter { $0.hasPrefix(entry.name + "/") }
            byName[entry.name] = TapRecord(
                name: entry.name,
                official: entry.official == true,
                tapTrusted: tapTrusted,
                isTapped: true,
                remote: entry.remote,
                formulaCount: entry.formula_names?.count ?? 0,
                caskCount: entry.cask_tokens?.count ?? 0,
                trustedFormulae: trustedFormulae.sorted(),
                trustedCasks: trustedCasks.sorted(),
                isStaleTrust: false
            )
        }

        var impliedTapsFromItems = Set<String>()
        for id in trust.formulae + trust.casks {
            let parts = id.split(separator: "/")
            if parts.count >= 2 {
                impliedTapsFromItems.insert("\(parts[0])/\(parts[1])")
            }
        }

        let allExtraTapNames = Set(trust.taps).union(impliedTapsFromItems).subtracting(tappedNames)
        for tapName in allExtraTapNames.sorted() {
            let wholeTapTrusted = trust.taps.contains(tapName)
            let trustedFormulae = trust.formulae.filter { $0.hasPrefix(tapName + "/") }
            let trustedCasks = trust.casks.filter { $0.hasPrefix(tapName + "/") }
            byName[tapName] = TapRecord(
                name: tapName,
                official: BrewTrust.officialTaps.contains(tapName),
                tapTrusted: wholeTapTrusted,
                isTapped: false,
                remote: nil,
                formulaCount: 0,
                caskCount: 0,
                trustedFormulae: trustedFormulae.sorted(),
                trustedCasks: trustedCasks.sorted(),
                isStaleTrust: true
            )
        }

        return Array(byName.values)
    }
}

// MARK: - Brew JSON models

private struct BrewInfoRoot: Decodable {
    var formulae: [BrewInfoFormula]
    var casks: [BrewInfoCask]
}

private struct BrewInfoFormula: Decodable {
    var name: String
    var full_name: String?
    var tap: String?
    var desc: String?
    var homepage: String?
    var pinned: Bool?
    var outdated: Bool?
    var linked_keg: String?
    var dependencies: [String]?
    var installed: [BrewInstalledEntry]
    var versions: BrewInfoVersions?
}

private struct BrewInfoVersions: Decodable {
    var stable: String?
}

private struct BrewInstalledEntry: Decodable {
    var version: String
    var installed_on_request: Bool?
    var installed_as_dependency: Bool?
}

private struct BrewInfoCask: Decodable {
    var token: String
    var full_token: String?
    var tap: String?
    var desc: String?
    var homepage: String?
    var name: [String]?
    var version: String?
    var installed: String?
    var auto_updates: Bool?
    var pinned: Bool?
    var outdated: Bool?
    var artifacts: LossyArtifactList?
}

private struct BrewArtifact: Decodable {
    var app: FlexibleStringOrArray?

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            app = try container.decodeIfPresent(FlexibleStringOrArray.self, forKey: .app)
        } else {
            app = nil
        }
    }

    private enum CodingKeys: String, CodingKey { case app }
}

private struct LossyArtifactList: Decodable {
    var items: [BrewArtifact]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [BrewArtifact] = []
        while !container.isAtEnd {
            if let artifact = try? container.decode(BrewArtifact.self) {
                result.append(artifact)
            } else if container.isAtEnd {
                break
            } else {
                _ = try? container.decode(JSONSkip.self)
            }
        }
        items = result
    }
}

private struct JSONSkip: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { return }
        if (try? container.decode(Bool.self)) != nil { return }
        if (try? container.decode(Int.self)) != nil { return }
        if (try? container.decode(Double.self)) != nil { return }
        if (try? container.decode(String.self)) != nil { return }
        if (try? container.decode([JSONSkip].self)) != nil { return }
        if (try? container.decode([String: JSONSkip].self)) != nil { return }
    }
}

private enum BrewCaskArtifacts {
    static func appBundleNames(from artifacts: LossyArtifactList?) -> [String] {
        guard let artifacts else { return [] }
        var names: [String] = []
        for artifact in artifacts.items {
            for value in artifact.app?.values ?? [] {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                names.append(trimmed.hasSuffix(".app") ? trimmed : "\(trimmed).app")
            }
        }
        return Array(Set(names)).sorted()
    }
}

private struct BrewOutdatedRoot: Decodable {
    var formulae: [BrewOutdatedEntry]
    var casks: [BrewOutdatedEntry]
}

private struct BrewOutdatedEntry: Decodable {
    var name: String
    var installed_versions: FlexibleStringOrArray?
    var current_version: String?
    var pinned: Bool?
}

private struct BrewTapInfoEntry: Decodable {
    var name: String
    var official: Bool?
    var trusted: Bool?
    var remote: String?
    var formula_names: [String]?
    var cask_tokens: [String]?
}
