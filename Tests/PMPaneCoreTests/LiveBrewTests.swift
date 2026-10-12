import Foundation
import Testing
import PMPaneCore
@testable import PMPaneCore

@Suite struct LiveBrewTests {
    @Test func liveBrewMerge() async throws {
        guard ProcessInfo.processInfo.environment["PMPANE_LIVE_BREW"] == "1" else {
            return
        }
        let runner = ProcessCommandRunner()
        guard let brew = await ToolEnvironment.resolveBrew(runner: runner) else {
            return
        }

        func captureJSON(_ args: [String]) async throws -> Data {
            let output = try await runner.capture(executable: brew, arguments: args)
            guard output.status == 0 else {
                throw ManagerError.commandFailed(args.joined(separator: " "), output.stderr)
            }
            return output.stdout
        }

        let merged = try BrewMerger.merge(
            info: try await captureJSON(["info", "--json=v2", "--installed"]),
            outdated: try await captureJSON(["outdated", "--json=v2"]),
            greedyOutdated: try await captureJSON(["outdated", "--json=v2", "--greedy"]),
            tapInfo: try await captureJSON(["tap-info", "--json", "--installed"]),
            trust: try await captureJSON(["trust", "--json=v1"])
        )

        let officialTaps = Set(merged.taps.filter(\.official).map(\.name))
        #expect(officialTaps.contains("homebrew/core"))
        #expect(officialTaps.contains("homebrew/cask"))

        for pkg in merged.packages where pkg.source == .brewFormula || pkg.source == .brewCask {
            #expect(pkg.tap != nil)
            #expect(pkg.trust != .notApplicable)
        }
    }
}
