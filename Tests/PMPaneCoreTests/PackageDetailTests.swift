import Foundation
import Testing
import PMPaneCore

@Suite struct PackageDetailTests {
    @Test func registryURLsForEverySource() {
        #expect(
            PackageLinks.registryURL(source: .brewFormula, name: "wget")
                == "https://formulae.brew.sh/formula/wget"
        )
        #expect(
            PackageLinks.registryURL(source: .brewCask, name: "firefox")
                == "https://formulae.brew.sh/cask/firefox"
        )
        #expect(
            PackageLinks.registryURL(source: .npm, name: "leftpad")
                == "https://www.npmjs.com/package/leftpad"
        )
        #expect(
            PackageLinks.registryURL(source: .npm, name: "@sindresorhus/is")
                == "https://www.npmjs.com/package/@sindresorhus/is"
        )
        #expect(
            PackageLinks.registryURL(source: .bun, name: "cowsay")
                == "https://www.npmjs.com/package/cowsay"
        )
        #expect(
            PackageLinks.registryURL(source: .pip, name: "requests")
                == "https://pypi.org/project/requests/"
        )
        #expect(
            PackageLinks.registryURL(source: .uv, name: "ruff")
                == "https://pypi.org/project/ruff/"
        )
        #expect(
            PackageLinks.registryURL(source: .gem, name: "customgem")
                == "https://rubygems.org/gems/customgem"
        )
    }

    @Test func registryAPIURLEncodesScopedNpm() {
        let url = PackageLinks.registryAPIURL(source: .npm, name: "@sindresorhus/is")
        #expect(url?.absoluteString == "https://registry.npmjs.org/@sindresorhus%2Fis")
        #expect(PackageLinks.registryAPIURL(source: .brewFormula, name: "wget") == nil)
    }

    @Test func npmParserReadsDescriptionHomepageAndRepository() throws {
        let json = """
        {
          "name": "left-pad",
          "description": "String left pad",
          "homepage": "https://github.com/stevemao/left-pad#readme",
          "dist-tags": { "latest": "1.3.0" },
          "versions": {
            "1.3.0": {
              "description": "String left pad",
              "homepage": "https://github.com/stevemao/left-pad#readme",
              "repository": {
                "type": "git",
                "url": "git+https://github.com/stevemao/left-pad.git"
              }
            }
          }
        }
        """
        let enrichment = try PackageDetailParsers.npm(Data(json.utf8))
        #expect(enrichment.summary == "String left pad")
        #expect(enrichment.homepage == "https://github.com/stevemao/left-pad#readme")
        #expect(enrichment.repository == "https://github.com/stevemao/left-pad")
    }

    @Test func pypiParserSplitsHomepageAndRepository() throws {
        let json = """
        {
          "info": {
            "summary": "Python HTTP for Humans.",
            "home_page": "",
            "project_urls": {
              "Documentation": "https://requests.readthedocs.io",
              "Source": "https://github.com/psf/requests"
            }
          }
        }
        """
        let enrichment = try PackageDetailParsers.pypi(Data(json.utf8))
        #expect(enrichment.summary == "Python HTTP for Humans.")
        #expect(enrichment.homepage == "https://requests.readthedocs.io")
        #expect(enrichment.repository == "https://github.com/psf/requests")
    }

    @Test func pypiParserPrefersGitHubRepoOverChangelog() throws {
        let json = """
        {
          "info": {
            "summary": "Async http client/server framework (asyncio)",
            "home_page": null,
            "project_urls": {
              "CI: GitHub Actions": "https://github.com/aio-libs/aiohttp/actions?query=workflow%3ACI",
              "Docs: Changelog": "https://docs.aiohttp.org/en/stable/changes.html",
              "Docs: RTD": "https://docs.aiohttp.org",
              "GitHub: issues": "https://github.com/aio-libs/aiohttp/issues",
              "GitHub: repo": "https://github.com/aio-libs/aiohttp",
              "Homepage": "https://github.com/aio-libs/aiohttp"
            }
          }
        }
        """
        let enrichment = try PackageDetailParsers.pypi(Data(json.utf8))
        #expect(enrichment.homepage == "https://github.com/aio-libs/aiohttp")
        #expect(enrichment.repository == "https://github.com/aio-libs/aiohttp")
    }

    @Test func rubygemsParserCompactsLongInfo() throws {
        let longInfo = String(repeating: "Rake is useful. ", count: 40)
        let json = """
        {
          "info": "\(longInfo)",
          "homepage_uri": "https://github.com/ruby/rake",
          "source_code_uri": "https://github.com/ruby/rake",
          "project_uri": "https://rubygems.org/gems/rake"
        }
        """
        let enrichment = try PackageDetailParsers.rubygems(Data(json.utf8))
        let summary = try #require(enrichment.summary)
        #expect(summary.hasSuffix("…"))
        #expect(summary.count <= 280)
        #expect(enrichment.homepage == "https://github.com/ruby/rake")
        #expect(enrichment.repository == "https://github.com/ruby/rake")
        #expect(
            PackageDetailParsers.urlsEquivalent(
                enrichment.homepage!,
                enrichment.repository!
            )
        )
    }

    @Test func sanitizeURLRejectsUnknownAndAcceptsGitPlus() {
        #expect(PackageDetailParsers.sanitizeURL("UNKNOWN") == nil)
        #expect(
            PackageDetailParsers.sanitizeURL("git+https://github.com/foo/bar.git")
                == "https://github.com/foo/bar"
        )
    }

    @Test func detailServiceUsesLoader() async throws {
        let payload = Data("""
        {
          "info": {
            "summary": "Fast Python linter",
            "home_page": "https://docs.astral.sh/ruff/",
            "project_urls": {}
          }
        }
        """.utf8)

        let service = PackageDetailService { url in
            #expect(url.absoluteString == "https://pypi.org/pypi/ruff/json")
            return payload
        }
        let enrichment = try await service.fetch(source: .uv, name: "ruff")
        #expect(enrichment.summary == "Fast Python linter")
        #expect(enrichment.homepage == "https://docs.astral.sh/ruff/")
    }

    @Test func githubOwnerRepoParsing() {
        #expect(
            PackageDetailParsers.githubOwnerRepo(from: "https://github.com/aio-libs/aiohttp")
                .map { "\($0.owner)/\($0.repo)" }
                == "aio-libs/aiohttp"
        )
        #expect(
            PackageDetailParsers.githubAPIURL(fromRepositoryURL: "git+https://github.com/aio-libs/aiohttp.git")?
                .absoluteString
                == "https://api.github.com/repos/aio-libs/aiohttp"
        )
        #expect(
            PackageDetailParsers.githubAPIURL(
                fromRepositoryURL: "https://github.com/aio-libs/aiohttp/issues"
            ) == nil
        )
    }

    @Test func githubMergePrefersDocsHomepageAndRepoHTMLURL() throws {
        let base = PackageDetailEnrichment(
            summary: "Async http client/server framework (asyncio)",
            homepage: "https://github.com/aio-libs/aiohttp",
            repository: "https://github.com/aio-libs/aiohttp"
        )
        let githubJSON = """
        {
          "description": "Asynchronous HTTP client/server framework for asyncio and Python",
          "homepage": "https://docs.aiohttp.org",
          "html_url": "https://github.com/aio-libs/aiohttp"
        }
        """
        let github = try PackageDetailParsers.github(Data(githubJSON.utf8))
        let merged = PackageDetailParsers.merging(base, withGitHub: github)
        #expect(merged.summary == "Asynchronous HTTP client/server framework for asyncio and Python")
        #expect(merged.homepage == "https://docs.aiohttp.org")
        #expect(merged.repository == "https://github.com/aio-libs/aiohttp")
    }

    @Test func detailServiceFetchesGitHubAfterPyPI() async throws {
        let pypi = Data("""
        {
          "info": {
            "summary": "Async http client/server framework (asyncio)",
            "home_page": null,
            "project_urls": {
              "GitHub: repo": "https://github.com/aio-libs/aiohttp",
              "Homepage": "https://github.com/aio-libs/aiohttp"
            }
          }
        }
        """.utf8)
        let github = Data("""
        {
          "description": "Asynchronous HTTP client/server framework for asyncio and Python",
          "homepage": "https://docs.aiohttp.org",
          "html_url": "https://github.com/aio-libs/aiohttp"
        }
        """.utf8)

        let seen = LockedURLLog()
        let service = PackageDetailService { url in
            seen.append(url.absoluteString)
            switch url.absoluteString {
            case "https://pypi.org/pypi/aiohttp/json":
                return pypi
            case "https://api.github.com/repos/aio-libs/aiohttp":
                return github
            default:
                Issue.record("Unexpected URL \(url.absoluteString)")
                return Data()
            }
        }

        let enrichment = try await service.fetch(source: .pip, name: "aiohttp")
        #expect(seen.snapshot() == [
            "https://pypi.org/pypi/aiohttp/json",
            "https://api.github.com/repos/aio-libs/aiohttp",
        ])
        #expect(enrichment.homepage == "https://docs.aiohttp.org")
        #expect(enrichment.repository == "https://github.com/aio-libs/aiohttp")
        #expect(enrichment.summary == "Asynchronous HTTP client/server framework for asyncio and Python")
    }
}

private final class LockedURLLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        values.append(value)
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
