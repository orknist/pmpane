import Foundation
import PMPaneCore

enum FixtureSupport {
    static var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
    }

    static func load(_ name: String) throws -> Data {
        try Data(contentsOf: fixturesDirectory.appendingPathComponent(name))
    }

    static func loadText(_ name: String) throws -> String {
        try String(contentsOf: fixturesDirectory.appendingPathComponent(name), encoding: .utf8)
    }

    static func sampleInventory(tools: [RuntimeTool] = [
        RuntimeTool(id: "brew", displayName: "Homebrew", available: true, executable: "/opt/homebrew/bin/brew"),
        RuntimeTool(id: "npm", displayName: "npm", available: true, executable: "/fake/npm"),
        RuntimeTool(id: "pip", displayName: "pip", available: true, executable: "/fake/python3"),
        RuntimeTool(id: "gem", displayName: "gem", available: true, executable: "/fake/gem"),
        RuntimeTool(id: "uv", displayName: "uv", available: true, executable: "/fake/uv"),
        RuntimeTool(id: "bun", displayName: "bun", available: true, executable: "/fake/bun"),
    ]) -> Inventory {
        Inventory(packages: [], taps: [], tools: tools, refreshedAt: Date(), warnings: [])
    }
}
