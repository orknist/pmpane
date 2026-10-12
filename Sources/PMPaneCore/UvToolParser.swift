import Foundation

public enum UvToolParser {
    public static func packages(listText: String, outdatedText: String) throws -> [Package] {
        let installed = parseToolList(listText)
        let outdatedByName = parseToolList(outdatedText).reduce(into: [String: String]()) { result, tool in
            if let latest = tool.latestVersion {
                result[tool.name] = latest
            }
        }

        return installed.map { tool in
            let latest = outdatedByName[tool.name] ?? tool.latestVersion
            let isOutdated = latest != nil
            let pinned = !(tool.requiredSpecifier?.isEmpty ?? true)
            var summaryParts: [String] = []
            if let required = tool.requiredSpecifier, !required.isEmpty {
                summaryParts.append("required: \(required)")
            }
            if !tool.commands.isEmpty {
                summaryParts.append(tool.commands.joined(separator: ", "))
            }
            return Package(
                id: "uv:\(tool.name)",
                name: tool.name,
                fullName: tool.name,
                displayName: tool.name,
                source: .uv,
                installedVersion: tool.version,
                latestVersion: latest,
                isOutdated: isOutdated,
                updatesItself: false,
                greedyOnly: false,
                pinned: pinned,
                installedOnRequest: true,
                installedAsDependency: false,
                summary: summaryParts.joined(separator: " · "),
                homepage: nil,
                tap: nil,
                trust: .notApplicable,
                versionIsLatest: false
            )
        }
        .sorted { $0.name < $1.name }
    }

    private struct ParsedTool {
        var name: String
        var version: String
        var latestVersion: String?
        var requiredSpecifier: String?
        var commands: [String]
    }

    /// Parses `uv tool list` / `uv tool list --outdated` human-readable output.
    ///
    /// Example:
    /// ```
    /// ruff v0.8.0 [required: ==0.8.0]
    /// - ruff
    /// httpie v3.2.3 [required: ==3.2.3] [latest: 3.2.4]
    /// - http
    /// - httpie
    /// ```
    private static func parseToolList(_ text: String) -> [ParsedTool] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        if trimmed.localizedCaseInsensitiveContains("No tools installed") { return [] }

        var tools: [ParsedTool] = []
        var current: ParsedTool?

        func flush() {
            if let current {
                tools.append(current)
            }
            current = nil
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("- ") {
                let command = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !command.isEmpty {
                    current?.commands.append(command)
                }
                continue
            }

            guard let parsed = parseHeaderLine(line) else { continue }
            flush()
            current = parsed
        }
        flush()
        return tools
    }

    private static func parseHeaderLine(_ line: String) -> ParsedTool? {
        guard let vRange = line.range(of: " v") else { return nil }
        let name = String(line[..<vRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains(where: \.isWhitespace) else { return nil }

        let afterV = String(line[vRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !afterV.isEmpty else { return nil }

        var latest: String?
        var required: String?

        var search = afterV[...]
        while let open = search.firstIndex(of: "["),
              let close = search[open...].firstIndex(of: "]") {
            let inner = String(search[search.index(after: open)..<close])
                .trimmingCharacters(in: .whitespaces)
            if let latestRange = inner.range(of: "latest:", options: .caseInsensitive) {
                latest = normalizeVersion(String(inner[latestRange.upperBound...]))
            } else if let requiredRange = inner.range(of: "required:", options: .caseInsensitive) {
                required = String(inner[requiredRange.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
            }
            search = search[search.index(after: close)...]
        }

        let beforeAnnotation: String
        if let bracket = afterV.firstIndex(of: "[") {
            beforeAnnotation = String(afterV[..<bracket]).trimmingCharacters(in: .whitespaces)
        } else if let parenOpen = afterV.firstIndex(of: "("),
                  let parenClose = afterV[parenOpen...].firstIndex(of: ")") {
            let inner = String(afterV[afterV.index(after: parenOpen)..<parenClose])
            if let latestRange = inner.range(of: "latest:", options: .caseInsensitive) {
                latest = normalizeVersion(String(inner[latestRange.upperBound...]))
            }
            beforeAnnotation = String(afterV[..<parenOpen]).trimmingCharacters(in: .whitespaces)
        } else {
            beforeAnnotation = afterV
        }

        let versionToken = beforeAnnotation.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        let version = normalizeVersion(versionToken)
        guard !version.isEmpty else { return nil }

        return ParsedTool(
            name: name,
            version: version,
            latestVersion: latest,
            requiredSpecifier: required,
            commands: []
        )
    }

    private static func normalizeVersion(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
    }
}
