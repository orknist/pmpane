import Foundation

/// Extra metadata fetched lazily when a package is inspected.
public struct PackageDetailEnrichment: Sendable, Equatable, Hashable {
    public var summary: String?
    public var homepage: String?
    public var repository: String?

    public init(summary: String? = nil, homepage: String? = nil, repository: String? = nil) {
        self.summary = summary
        self.homepage = homepage
        self.repository = repository
    }

    public var isEmpty: Bool {
        (summary?.isEmpty ?? true)
            && (homepage?.isEmpty ?? true)
            && (repository?.isEmpty ?? true)
    }
}

public enum PackageDetailParsers {
    public static func npm(_ data: Data) throws -> PackageDetailEnrichment {
        let root = try JSONDecoder().decode(NpmRegistryRoot.self, from: data)
        let latestTag = root.distTags?["latest"]
        let latest = latestTag.flatMap { root.versions?[$0] }
        let summary = compactSummary(latest?.description ?? root.description)
        let repository = repositoryURL(latest?.repository ?? root.repository)
        let homepage = sanitizeURL(latest?.homepage ?? root.homepage)
        return PackageDetailEnrichment(summary: summary, homepage: homepage, repository: repository)
    }

    public static func pypi(_ data: Data) throws -> PackageDetailEnrichment {
        let root = try JSONDecoder().decode(PyPIRoot.self, from: data)
        let info = root.info
        let summary = compactSummary(info?.summary)
        let projectURLs = info?.project_urls ?? [:]
        let repository = pickPyPIRepository(from: projectURLs)
        let homepage = sanitizeURL(info?.home_page)
            ?? pickPyPIHomepage(from: projectURLs)
        return PackageDetailEnrichment(summary: summary, homepage: homepage, repository: repository)
    }

    public static func rubygems(_ data: Data) throws -> PackageDetailEnrichment {
        let root = try JSONDecoder().decode(RubyGemsRoot.self, from: data)
        let summary = compactSummary(root.info)
        let homepage = sanitizeURL(root.homepage_uri)
            ?? sanitizeURL(root.project_uri)
        let repository = sanitizeURL(root.source_code_uri)
        return PackageDetailEnrichment(summary: summary, homepage: homepage, repository: repository)
    }

    public static func parse(source: SourceKind, data: Data) throws -> PackageDetailEnrichment {
        switch source {
        case .npm, .bun:
            return try npm(data)
        case .pip, .uv:
            return try pypi(data)
        case .gem:
            return try rubygems(data)
        case .brewFormula, .brewCask:
            return PackageDetailEnrichment()
        }
    }

    public static func github(_ data: Data) throws -> PackageDetailEnrichment {
        let root = try JSONDecoder().decode(GitHubRepoRoot.self, from: data)
        return PackageDetailEnrichment(
            summary: compactSummary(root.description),
            homepage: sanitizeURL(root.homepage),
            repository: sanitizeURL(root.html_url)
        )
    }

    /// Overlay GitHub API fields onto registry metadata.
    public static func merging(
        _ base: PackageDetailEnrichment,
        withGitHub github: PackageDetailEnrichment
    ) -> PackageDetailEnrichment {
        var result = base
        if let repository = github.repository, !repository.isEmpty {
            result.repository = repository
        }
        if let homepage = github.homepage, !homepage.isEmpty {
            result.homepage = homepage
        } else if let homepage = result.homepage,
                  let repository = result.repository,
                  urlsEquivalent(homepage, repository) {
            // Registry often repeats the repo URL as Homepage; leave repository as the link.
            result.homepage = nil
        }
        if let summary = github.summary, !summary.isEmpty {
            result.summary = summary
        }
        return result
    }

    /// `https://api.github.com/repos/{owner}/{repo}` when `url` points at a GitHub repository.
    public static func githubAPIURL(fromRepositoryURL urlString: String) -> URL? {
        guard let (owner, repo) = githubOwnerRepo(from: urlString) else { return nil }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        let encodedOwner = owner.addingPercentEncoding(withAllowedCharacters: allowed) ?? owner
        let encodedRepo = repo.addingPercentEncoding(withAllowedCharacters: allowed) ?? repo
        return URL(string: "https://api.github.com/repos/\(encodedOwner)/\(encodedRepo)")
    }

    public static func githubOwnerRepo(from urlString: String) -> (owner: String, repo: String)? {
        guard let sanitized = sanitizeURL(urlString) ?? optionalHTTPURL(urlString),
              let url = URL(string: sanitized),
              let host = url.host?.lowercased()
        else { return nil }

        guard host == "github.com" || host == "www.github.com" else { return nil }
        let parts = url.path.split(separator: "/").filter { !$0.isEmpty }
        // Only bare `/{owner}/{repo}` roots — not /issues, /tree/…, etc.
        guard parts.count == 2 else { return nil }

        let owner = String(parts[0])
        var repo = String(parts[1])
        if repo.hasSuffix(".git") {
            repo = String(repo.dropLast(4))
        }
        guard !owner.isEmpty, !repo.isEmpty else { return nil }
        return (owner, repo)
    }

    private static func optionalHTTPURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        return nil
    }

    /// First paragraph, single-line, capped for the inspector.
    public static func compactSummary(_ text: String?, limit: Int = 280) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let paragraph = trimmed
            .components(separatedBy: "\n\n")
            .first?
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? trimmed

        guard !paragraph.isEmpty else { return nil }
        if paragraph.count <= limit { return paragraph }
        return String(paragraph.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    public static func sanitizeURL(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.uppercased() == "UNKNOWN" || value == "null" { return nil }
        if value.hasPrefix("git+") {
            value = String(value.dropFirst(4))
        }
        if value.hasPrefix("git://") {
            value = "https://" + value.dropFirst("git://".count)
        }
        if value.hasSuffix(".git") {
            value = String(value.dropLast(4))
        }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return value
    }

    private static func repositoryURL(_ repository: NpmRepository?) -> String? {
        guard let repository else { return nil }
        if let url = sanitizeURL(repository.url) { return url }
        if let url = sanitizeURL(repository.stringValue) { return url }
        return nil
    }

    /// Loose equality so `…/repo#readme` and `…/repo` collapse to one link in the UI.
    public static func urlsEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        normalizeURLForCompare(lhs) == normalizeURLForCompare(rhs)
    }

    private static func normalizeURLForCompare(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let hash = value.firstIndex(of: "#") {
            value = String(value[..<hash])
        }
        while value.hasSuffix("/") {
            value = String(value.dropLast())
        }
        return value
    }

    /// PyPI labels vary (`Source`, `GitHub: repo`, …). Score entries; never grab a random URL.
    private static func pickPyPIRepository(from urls: [String: String]) -> String? {
        var best: (score: Int, url: String)?
        for (key, value) in urls {
            guard let url = sanitizeURL(value) else { continue }
            let score = pyPIRepositoryScore(key: key, url: url)
            guard score > 0 else { continue }
            if score > (best?.score ?? 0) {
                best = (score, url)
            }
        }
        return best?.url
    }

    private static func pickPyPIHomepage(from urls: [String: String]) -> String? {
        let exactKeys = ["Homepage", "Home", "Documentation", "Docs", "Docs: RTD"]
        let lowered = Dictionary(urls.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        for key in exactKeys {
            if let value = urls[key] ?? lowered[key.lowercased()],
               let url = sanitizeURL(value),
               !isWeakDocumentationURL(url) {
                return url
            }
        }

        var best: (score: Int, url: String)?
        for (key, value) in urls {
            guard let url = sanitizeURL(value) else { continue }
            let score = pyPIHomepageScore(key: key, url: url)
            guard score > 0 else { continue }
            if score > (best?.score ?? 0) {
                best = (score, url)
            }
        }
        return best?.url
    }

    private static func pyPIRepositoryScore(key: String, url: String) -> Int {
        let keyLower = key.lowercased()
        if keyLooksNonRepository(keyLower) { return 0 }

        var score = 0
        switch keyLower {
        case "source", "source code", "repository", "code":
            score += 100
        default:
            break
        }
        if keyLower.contains("repo") { score += 90 }
        if keyLower.contains("source") { score += 80 }
        if keyLower == "homepage" || keyLower == "home" {
            score += isSourceForgeURL(url) ? 55 : 0
        }
        if isSourceForgeURL(url) {
            score += 40
            if looksLikeRepositoryRoot(url) { score += 25 }
        }
        return score
    }

    private static func pyPIHomepageScore(key: String, url: String) -> Int {
        let keyLower = key.lowercased()
        if keyLower.contains("changelog") || keyLower.contains("change log") { return 0 }
        if keyLooksNonRepository(keyLower)
            && !keyLower.contains("home")
            && !keyLower.contains("doc") {
            return 0
        }

        var score = 0
        if keyLower == "homepage" || keyLower == "home" { score += 100 }
        if keyLower.contains("home") { score += 70 }
        if keyLower == "documentation" || keyLower == "docs" || keyLower == "docs: rtd" {
            score += isWeakDocumentationURL(url) ? 0 : 40
        } else if keyLower.contains("doc"), !isWeakDocumentationURL(url) {
            score += 30
        }
        if isSourceForgeURL(url), looksLikeRepositoryRoot(url) { score += 20 }
        return score
    }

    private static func keyLooksNonRepository(_ keyLower: String) -> Bool {
        let blocked = [
            "issue", "pull", "ci", "action", "coverage", "codecov", "chat", "matrix",
            "discord", "twitter", "mastodon", "funding", "sponsor", "donate", "changelog",
            "change log", "wiki", "security",
        ]
        return blocked.contains { keyLower.contains($0) }
    }

    private static func isSourceForgeURL(_ url: String) -> Bool {
        let lower = url.lowercased()
        let hosts = [
            "github.com/", "gitlab.com/", "bitbucket.org/", "codeberg.org/",
            "git.sr.ht/", "sourceforge.net/",
        ]
        return hosts.contains { lower.contains($0) }
    }

    /// `https://github.com/org/repo` (not issues/actions/tree/…).
    private static func looksLikeRepositoryRoot(_ url: String) -> Bool {
        guard let parsed = URL(string: url), let host = parsed.host?.lowercased() else { return false }
        let forgeHosts: Set<String> = [
            "github.com", "www.github.com", "gitlab.com", "www.gitlab.com",
            "bitbucket.org", "www.bitbucket.org", "codeberg.org", "www.codeberg.org",
        ]
        guard forgeHosts.contains(host) else { return false }
        let parts = parsed.path.split(separator: "/").filter { !$0.isEmpty }
        guard parts.count == 2 else { return false }
        return parsed.fragment == nil
    }

    /// Changelog / deep doc pages make poor “Homepage” stand-ins.
    private static func isWeakDocumentationURL(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.contains("changelog")
            || lower.contains("changes.html")
            || lower.contains("/history")
            || lower.contains("/release")
    }
}

/// Fetches package description / homepage from public registries on demand.
public struct PackageDetailService: Sendable {
    public typealias DataLoader = @Sendable (URL) async throws -> Data

    private let load: DataLoader

    public init() {
        self.load = Self.makeDefaultLoader()
    }

    public init(load: @escaping DataLoader) {
        self.load = load
    }

    public func fetch(source: SourceKind, name: String) async throws -> PackageDetailEnrichment {
        guard let url = PackageLinks.registryAPIURL(source: source, name: name) else {
            return PackageDetailEnrichment()
        }
        let data = try await load(url)
        var enrichment = try PackageDetailParsers.parse(source: source, data: data)
        enrichment = await enrichFromGitHubIfPossible(enrichment)
        return enrichment
    }

    private func enrichFromGitHubIfPossible(
        _ enrichment: PackageDetailEnrichment
    ) async -> PackageDetailEnrichment {
        let candidates = [enrichment.repository, enrichment.homepage].compactMap { $0 }
        for candidate in candidates {
            guard let apiURL = PackageDetailParsers.githubAPIURL(fromRepositoryURL: candidate) else {
                continue
            }
            do {
                let data = try await load(apiURL)
                let github = try PackageDetailParsers.github(data)
                return PackageDetailParsers.merging(enrichment, withGitHub: github)
            } catch {
                // Rate limits / offline: keep registry metadata.
                return enrichment
            }
        }
        return enrichment
    }

    private static func makeDefaultLoader() -> DataLoader {
        { url in
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue("PMPane/1 CFNetwork", forHTTPHeaderField: "User-Agent")
            if url.host?.lowercased() == "api.github.com" {
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw PackageDetailError.httpStatus(http.statusCode)
            }
            return data
        }
    }
}

public enum PackageDetailError: Error, Sendable {
    case httpStatus(Int)
}

// MARK: - Registry DTOs

private struct NpmRegistryRoot: Decodable {
    var description: String?
    var homepage: String?
    var repository: NpmRepository?
    var distTags: [String: String]?
    var versions: [String: NpmVersion]?

    private enum CodingKeys: String, CodingKey {
        case description, homepage, repository, versions
        case distTags = "dist-tags"
    }
}

private struct NpmVersion: Decodable {
    var description: String?
    var homepage: String?
    var repository: NpmRepository?
}

private struct NpmRepository: Decodable {
    var url: String?
    var stringValue: String?

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(), let string = try? container.decode(String.self) {
            stringValue = string
            url = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        stringValue = nil
    }

    private enum CodingKeys: String, CodingKey {
        case url
    }
}

private struct PyPIRoot: Decodable {
    var info: PyPIInfo?
}

private struct PyPIInfo: Decodable {
    var summary: String?
    var home_page: String?
    var project_urls: [String: String]?
}

private struct RubyGemsRoot: Decodable {
    var info: String?
    var homepage_uri: String?
    var source_code_uri: String?
    var project_uri: String?
}

private struct GitHubRepoRoot: Decodable {
    var description: String?
    var homepage: String?
    var html_url: String?
}
