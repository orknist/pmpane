import Foundation
import Testing
@testable import PMPaneCore

@Suite struct BrewInfoEnrichmentTests {
    @Test func namesIgnoreWarningsAndBlankLines() {
        let text = """
        wget
        supabase/tap/supabase

        Warning: something noisy
        anomalyco/tap/opencode
        """
        let names = BrewInfoEnrichment.names(fromListOutput: Data(text.utf8))
        #expect(names == [
            "wget",
            "supabase/tap/supabase",
            "anomalyco/tap/opencode",
        ])
    }

    @Test func missingIDsDetectUntrustedOmittedInstalls() throws {
        let info = """
        {
          "formulae": [
            { "name": "wget", "full_name": "wget", "installed": [{ "version": "1.0" }] }
          ],
          "casks": [
            { "token": "firefox", "full_token": "firefox", "installed": "1.0" }
          ]
        }
        """.data(using: .utf8)!

        let missing = try BrewInfoEnrichment.missingIDs(
            listedFormulae: ["wget", "supabase/tap/supabase"],
            listedCasks: ["firefox", "vendor/tap/hidden"],
            info: info
        )
        #expect(missing.formulae == ["supabase/tap/supabase"])
        #expect(missing.casks == ["vendor/tap/hidden"])
    }

    @Test func mergeAddsSupplementalFormulaeAndCasks() throws {
        let base = """
        {
          "formulae": [
            { "name": "wget", "full_name": "wget", "installed": [{ "version": "1.0" }] }
          ],
          "casks": []
        }
        """.data(using: .utf8)!
        let extra = """
        {
          "formulae": [
            {
              "name": "supabase",
              "full_name": "supabase/tap/supabase",
              "tap": "supabase/tap",
              "installed": [{ "version": "2.84.2", "installed_on_request": true }]
            }
          ],
          "casks": [
            {
              "token": "hidden",
              "full_token": "vendor/tap/hidden",
              "tap": "vendor/tap",
              "installed": "1.2.3"
            }
          ]
        }
        """.data(using: .utf8)!

        let merged = try BrewInfoEnrichment.merge(base: base, extra: extra)
        let ids = try BrewInfoEnrichment.installedIDs(fromInfo: merged)
        #expect(ids.formulae == ["supabase/tap/supabase", "wget"])
        #expect(ids.casks == ["vendor/tap/hidden"])

        let packages = try BrewMerger.merge(
            info: merged,
            outdated: Data("""
            {"formulae":[],"casks":[]}
            """.utf8),
            greedyOutdated: Data("""
            {"formulae":[],"casks":[]}
            """.utf8),
            tapInfo: Data("""
            [
              {
                "name": "homebrew/core",
                "official": true,
                "trusted": true,
                "formula_names": ["wget"],
                "cask_tokens": []
              },
              {
                "name": "supabase/tap",
                "official": false,
                "trusted": false,
                "formula_names": ["supabase"],
                "cask_tokens": []
              },
              {
                "name": "vendor/tap",
                "official": false,
                "trusted": false,
                "formula_names": [],
                "cask_tokens": ["hidden"]
              }
            ]
            """.utf8),
            trust: Data("""
            {"taps":[],"formulae":[],"casks":[],"commands":[]}
            """.utf8)
        )
        let supabase = try #require(packages.packages.first { $0.fullName == "supabase/tap/supabase" })
        #expect(supabase.trust == .untrusted)
        #expect(supabase.installedVersion == "2.84.2")
        #expect(packages.packages.contains { $0.fullName == "vendor/tap/hidden" })
    }
}
