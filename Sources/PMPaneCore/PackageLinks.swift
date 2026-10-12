import Foundation

/// Stable public registry / catalogue pages for installed packages.
public enum PackageLinks {
    /// Returns a browsable catalogue URL for the package’s ecosystem, if one exists.
    public static func registryURL(source: SourceKind, name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch source {
        case .brewFormula:
            return "https://formulae.brew.sh/formula/\(pathSegment(trimmed))"
        case .brewCask:
            return "https://formulae.brew.sh/cask/\(pathSegment(trimmed))"
        case .npm, .bun:
            return "https://www.npmjs.com/package/\(npmPackagePath(trimmed))"
        case .pip, .uv:
            return "https://pypi.org/project/\(pathSegment(trimmed))/"
        case .gem:
            return "https://rubygems.org/gems/\(pathSegment(trimmed))"
        }
    }

    /// Registry API endpoint used for lazy detail enrichment (not shown in UI).
    public static func registryAPIURL(source: SourceKind, name: String) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch source {
        case .brewFormula, .brewCask:
            return nil
        case .npm, .bun:
            var allowed = CharacterSet.urlPathAllowed
            allowed.remove(charactersIn: "/")
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
            return URL(string: "https://registry.npmjs.org/\(encoded)")
        case .pip, .uv:
            return URL(string: "https://pypi.org/pypi/\(pathSegment(trimmed))/json")
        case .gem:
            return URL(string: "https://rubygems.org/api/v1/gems/\(pathSegment(trimmed)).json")
        }
    }

    private static func pathSegment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    /// npmjs.com keeps the `@scope/name` slash in the path.
    private static func npmPackagePath(_ name: String) -> String {
        if name.hasPrefix("@"), let slash = name.firstIndex(of: "/") {
            let scope = String(name[..<slash])
            let pkg = String(name[name.index(after: slash)...])
            return "\(pathSegment(scope))/\(pathSegment(pkg))"
        }
        return pathSegment(name)
    }
}
