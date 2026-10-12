import Foundation
import Testing
@testable import PMPaneCore

private struct FailingWhichRunner: CommandRunning {
    func capture(executable: String, arguments: [String]) async throws -> CommandOutput {
        CommandOutput(status: 1, stdout: Data(), stderr: "not found")
    }

    func run(
        executable: String,
        arguments: [String],
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> Int {
        1
    }
}

@Suite struct ToolEnvironmentTests {
    private let runner = FailingWhichRunner()

    @Test func environmentPrependsExecutableDirectory() throws {
        let env = ToolEnvironment.environment(forExecutable: "/tmp/fnm-node/bin/npm")
        let path = try #require(env["PATH"])
        #expect(path.hasPrefix("/tmp/fnm-node/bin:"))
        #expect(path.contains(ToolEnvironment.guiPATH))
    }

    @Test func environmentWithoutExecutableUsesGuiPATHOnly() {
        let env = ToolEnvironment.environment()
        #expect(env["PATH"] == ToolEnvironment.guiPATH)
    }

    @Test func environmentPreservesSudoAskpassFromBase() {
        let askpass = "/tmp/pmpane-sudo-askpass"
        let env = ToolEnvironment.environment(base: ["SUDO_ASKPASS": askpass])
        #expect(env["SUDO_ASKPASS"] == askpass)
        #expect(env["PATH"] == ToolEnvironment.guiPATH)
    }

    @Test func resolveNpmFindsFnmDefaultAlias() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(atPath: home) }

        let install = "\(home)/.local/share/fnm/node-versions/v24.21.0/installation"
        try makeExecutableNpm(at: "\(install)/bin/npm")
        try FileManager.default.createDirectory(
            atPath: "\(home)/.local/share/fnm/aliases",
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            atPath: "\(home)/.local/share/fnm/aliases/default",
            withDestinationPath: install
        )

        let resolved = await ToolEnvironment.resolveNpm(
            runner: runner,
            home: home,
            processEnvironment: [:],
            systemPrefixes: ["\(home)/no-system"]
        )
        #expect(resolved == "\(home)/.local/share/fnm/aliases/default/bin/npm")
    }

    @Test func resolveNpmFindsNvmDefaultAlias() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(atPath: home) }

        try makeExecutableNpm(at: "\(home)/.nvm/versions/node/v20.11.0/bin/npm")
        try write("\(home)/.nvm/alias/default", contents: "20.11.0\n")

        let resolved = await ToolEnvironment.resolveNpm(
            runner: runner,
            home: home,
            processEnvironment: [:],
            systemPrefixes: ["\(home)/no-system"]
        )
        #expect(resolved == "\(home)/.nvm/versions/node/v20.11.0/bin/npm")
    }

    @Test func resolveNpmFindsVolta() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(atPath: home) }

        try makeExecutableNpm(at: "\(home)/.volta/bin/npm")

        let resolved = await ToolEnvironment.resolveNpm(
            runner: runner,
            home: home,
            processEnvironment: [:],
            systemPrefixes: ["\(home)/no-system"]
        )
        #expect(resolved == "\(home)/.volta/bin/npm")
    }

    @Test func systemPrefixWinsOverVersionManager() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(atPath: home) }

        let systemBin = "\(home)/fake-brew/bin"
        try makeExecutableNpm(at: "\(systemBin)/npm")
        try makeExecutableNpm(at: "\(home)/.volta/bin/npm")

        let resolved = await ToolEnvironment.resolveNpm(
            runner: runner,
            home: home,
            processEnvironment: [:],
            systemPrefixes: [systemBin]
        )
        #expect(resolved == "\(systemBin)/npm")
    }

    @Test func npmCandidatePathsPreferSystemThenVoltaThenFnm() {
        let home = "/tmp/pmpane-home-order"
        let paths = ToolEnvironment.npmCandidatePaths(
            home: home,
            processEnvironment: [:],
            systemPrefixes: ["/opt/homebrew/bin", "/usr/local/bin"]
        )
        let brew = paths.firstIndex(of: "/opt/homebrew/bin/npm")
        let volta = paths.firstIndex(of: "\(home)/.volta/bin/npm")
        let fnm = paths.firstIndex(of: "\(home)/.local/share/fnm/aliases/default/bin/npm")
        #expect(brew != nil && volta != nil && fnm != nil)
        #expect(brew! < volta!)
        #expect(volta! < fnm!)
    }

    // MARK: - Helpers

    private func makeTempHome() throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PMPane-ToolEnv-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    private func makeExecutableNpm(at path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let script = "#!/bin/sh\necho 1.0.0\n"
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }

    private func write(_ path: String, contents: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
