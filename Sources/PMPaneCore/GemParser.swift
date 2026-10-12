import Foundation

public enum GemParser {
    /// Default gems shipped with Ruby are excluded from inventory (see `defaultGemFilter`).
    public static let defaultGemFilter: Set<String> = [
        "did_you_mean", "minitest", "net-pop", "net-smtp", "power_assert", "rake", "rbs", "rexml",
        "rss", "test-unit", "typeprof", "debug", "rdoc", "irb", "bundler", "psych", "stringio",
        "tsort", "timeout", "uri", "yaml", "zlib", "error_highlight", "syntax_suggest", "abbrev",
        "base64", "benchmark", "bigdecimal", "csv", "drb", "getoptlong", "matrix", "mutex_m", "nkf",
        "observer", "prime", "resolv-replace", "syslog",
    ]

    public static func packages(listText: String, outdatedText: String) throws -> [Package] {
        let installed = parseGemList(listText)
        let outdated = parseGemOutdated(outdatedText)

        return installed
            .filter { !defaultGemFilter.contains($0.name) }
            .map { gem in
                let out = outdated[gem.name]
                let isOutdated = out != nil
                return Package(
                    id: "gem:\(gem.name)",
                    name: gem.name,
                    fullName: gem.name,
                    displayName: gem.name,
                    source: .gem,
                    installedVersion: gem.version,
                    latestVersion: out?.latest,
                    isOutdated: isOutdated,
                    updatesItself: false,
                    greedyOnly: false,
                    pinned: false,
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

    private static func parseGemList(_ text: String) -> [(name: String, version: String)] {
        var result: [(String, String)] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line).trimmingCharacters(in: .whitespaces)
            guard let open = s.firstIndex(of: "("), let close = s.lastIndex(of: ")") else { continue }
            let name = String(s[..<open]).trimmingCharacters(in: .whitespaces)
            let versionsPart = String(s[s.index(after: open)..<close])
            let firstVersion = versionsPart.split(separator: ",").first.map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
            guard !name.isEmpty, let version = firstVersion, !version.isEmpty else { continue }
            result.append((name, version))
        }
        return result
    }

    private static func parseGemOutdated(_ text: String) -> [String: (installed: String, latest: String)] {
        var result: [String: (String, String)] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line).trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { continue }
            // name (installed < latest)
            guard let open = s.firstIndex(of: "("), let close = s.lastIndex(of: ")") else { continue }
            let name = String(s[..<open]).trimmingCharacters(in: .whitespaces)
            let inner = String(s[s.index(after: open)..<close])
            let parts = inner.split(separator: "<", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }
            result[name] = (parts[0], parts[1])
        }
        return result
    }
}
