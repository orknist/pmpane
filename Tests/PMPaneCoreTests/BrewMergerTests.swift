import Foundation
import Testing
import PMPaneCore

@Suite struct BrewMergerTests {
    private func merged() throws -> (packages: [Package], taps: [TapRecord]) {
        try BrewMerger.merge(
            info: FixtureSupport.load("brew_info.json"),
            outdated: FixtureSupport.load("brew_outdated.json"),
            greedyOutdated: FixtureSupport.load("brew_outdated_greedy.json"),
            tapInfo: FixtureSupport.load("brew_tap_info.json"),
            trust: FixtureSupport.load("brew_trust.json")
        )
    }

    private func package(named name: String, in packages: [Package]) -> Package? {
        packages.first { $0.name == name && ($0.source == .brewFormula || $0.source == .brewCask) }
    }

    @Test func officialFormulaInstalledOnRequest() throws {
        let result = try merged()
        let wget = try #require(package(named: "wget", in: result.packages))
        #expect(wget.trust == .official)
        #expect(wget.installedOnRequest == true)
        #expect(wget.isOutdated == false)
    }

    @Test func dependencyWithoutInstalledAsDependencyKey() throws {
        let result = try merged()
        let libpng = try #require(package(named: "libpng", in: result.packages))
        #expect(libpng.installedOnRequest == false)
        #expect(libpng.installedAsDependency == true)
        #expect(libpng.requiredBy.contains("wget"))
        let wget = try #require(package(named: "wget", in: result.packages))
        #expect(wget.dependsOn.contains("libpng"))
    }

    @Test func greedyOnlyAutoUpdatesCask() throws {
        let result = try merged()
        let firefox = try #require(package(named: "firefox", in: result.packages))
        #expect(firefox.greedyOnly == true)
        #expect(firefox.isOutdated == false)
        #expect(firefox.updatesItself == true)
        #expect(firefox.latestVersion == "132.0")
    }

    @Test func plainOutdatedCask() throws {
        let result = try merged()
        let cask = try #require(package(named: "plaincask", in: result.packages))
        #expect(cask.isOutdated == true)
        #expect(cask.greedyOnly == false)
    }

    @Test func thirdPartyUntrusted() throws {
        let result = try merged()
        let shadow = try #require(package(named: "shadowpkg", in: result.packages))
        #expect(shadow.trust == .untrusted)
    }

    @Test func thirdPartyOutdatedUsesFullyQualifiedName() throws {
        let info = """
        {
          "formulae": [
            {
              "name": "supabase",
              "full_name": "supabase/tap/supabase",
              "tap": "supabase/tap",
              "outdated": true,
              "versions": { "stable": "2.120.0" },
              "installed": [{ "version": "2.84.2", "installed_on_request": true }]
            }
          ],
          "casks": []
        }
        """.data(using: .utf8)!
        let outdated = """
        {
          "formulae": [
            {
              "name": "supabase/tap/supabase",
              "installed_versions": ["2.84.2"],
              "current_version": "2.120.0",
              "pinned": false
            }
          ],
          "casks": []
        }
        """.data(using: .utf8)!
        let empty = Data(#"{"formulae":[],"casks":[]}"#.utf8)
        let tapInfo = Data(#"[{"name":"supabase/tap","official":false,"trusted":false,"formula_names":["supabase"],"cask_tokens":[]}]"#.utf8)
        let trust = Data(#"{"taps":[],"formulae":[],"casks":[],"commands":[]}"#.utf8)

        let result = try BrewMerger.merge(
            info: info,
            outdated: outdated,
            greedyOutdated: empty,
            tapInfo: tapInfo,
            trust: trust
        )
        let supabase = try #require(package(named: "supabase", in: result.packages))
        #expect(supabase.isOutdated == true)
        #expect(supabase.latestVersion == "2.120.0")
        #expect(supabase.trust == .untrusted)
    }

    @Test func itemTrustedFormulaAndTapRecord() throws {
        let result = try merged()
        let opencode = try #require(package(named: "opencode", in: result.packages))
        #expect(opencode.trust == .itemTrusted)
        let tap = try #require(result.taps.first { $0.name == "anomalyco/tap" })
        #expect(tap.tapTrusted == false)
        #expect(tap.trustedFormulae.contains("anomalyco/tap/opencode"))
    }

    @Test func wholeTapTrustedViaTrustList() throws {
        let result = try merged()
        let pkg = try #require(package(named: "trustedtapformula", in: result.packages))
        #expect(pkg.trust == .tapTrusted)
        let tap = try #require(result.taps.first { $0.name == "user/trustedtap" })
        #expect(tap.tapTrusted == true)
    }

    @Test func staleTapRecordFromTrustTaps() throws {
        let result = try merged()
        let tap = try #require(result.taps.first { $0.name == "joowonoil/lumimax" })
        #expect(tap.isTapped == false)
        #expect(tap.isStaleTrust == true)
        #expect(tap.tapTrusted == true)
    }
}
