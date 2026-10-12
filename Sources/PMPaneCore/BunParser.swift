import Foundation

public enum BunParser {
    /// Bun exits with this when `~/.bun/install/global` has no lockfile yet.
    public static func isMissingLockfileError(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("missing lockfile")
    }

    public static func packages(listText: String, outdatedText: String) throws -> [Package] {
        let installed = parseList(listText)
        let outdatedByName = parseOutdated(outdatedText)

        return installed.map { entry in
            let outdated = outdatedByName[entry.name]
            let latest = outdated?.latest
            let update = outdated?.update
            let isOutdated = latest.map { $0 != entry.version } ?? false
            // Range holds the package when Update stays at Current while Latest is newer.
            let pinned = isOutdated
                && update.map { $0 == entry.version } == true
                && latest.map { $0 != entry.version } == true

            return Package(
                id: "bun:\(entry.name)",
                name: entry.name,
                fullName: entry.name,
                displayName: entry.name,
                source: .bun,
                installedVersion: entry.version,
                latestVersion: latest,
                isOutdated: isOutdated,
                updatesItself: false,
                greedyOnly: false,
                pinned: pinned,
                installedOnRequest: true,
                installedAsDependency: false,
                summary: "",
                homepage: nil,
                tap: nil,
                trust: .notApplicable,
                versionIsLatest: false
            )
        }
        .sorted { $0.name < $1.name }
    }

    private struct ListedPackage {
        var name: String
        var version: String
    }

    private struct OutdatedPackage {
        var current: String
        var update: String
        var latest: String
    }

    /// Parses `bun pm ls --global` tree lines such as `├── cowsay@1.5.0`.
    private static func parseList(_ text: String) -> [ListedPackage] {
        var result: [ListedPackage] = []
        var seen = Set<String>()
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // Tree prefixes: ├── └── │   etc.
            var body = line
            while body.hasPrefix("│") || body.hasPrefix("|") {
                body = String(body.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            if body.hasPrefix("├──") || body.hasPrefix("└──") {
                body = String(body.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if body.hasPrefix("├─") || body.hasPrefix("└─") {
                body = String(body.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if body.hasPrefix("--") {
                body = String(body.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else {
                continue
            }

            guard let at = body.lastIndex(of: "@") else { continue }
            let name = String(body[..<at])
            let version = String(body[body.index(after: at)...])
            guard !name.isEmpty, !version.isEmpty, !seen.contains(name) else { continue }
            // Skip obvious non-package header leftovers.
            if name.contains("node_modules") { continue }
            seen.insert(name)
            result.append(ListedPackage(name: name, version: version))
        }
        return result
    }

    /// Parses `bun outdated --global` table rows.
    private static func parseOutdated(_ text: String) -> [String: OutdatedPackage] {
        var result: [String: OutdatedPackage] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("|"), line.hasSuffix("|") else { continue }
            let inner = String(line.dropFirst().dropLast())
            let cells = inner.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 4 else { continue }

            let name = cells[0]
            let current = cells[1]
            let update = cells[2]
            let latest = cells[3]
            guard !name.isEmpty,
                  name.caseInsensitiveCompare("Package") != .orderedSame,
                  !name.allSatisfy({ $0 == "-" }),
                  !current.isEmpty,
                  !latest.isEmpty,
                  !current.allSatisfy({ $0 == "-" })
            else { continue }

            result[name] = OutdatedPackage(current: current, update: update, latest: latest)
        }
        return result
    }
}
