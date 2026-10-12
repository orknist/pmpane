import Foundation

enum ToolEnvironment {
    static let guiPATH = "/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    static let defaultSystemPrefixes = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/opt/local/bin",
    ]

    /// Builds a process environment. Always uses a stable developer PATH (not the
    /// inherited login-shell PATH). When `executable` is set, its directory is
    /// prepended so scripts like `#!/usr/bin/env node` resolve the sibling binary.
    static func environment(
        forExecutable executable: String? = nil,
        base: [String: String]? = nil
    ) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let base {
            env.merge(base) { _, new in new }
        }
        var path = guiPATH
        if let executable {
            let dir = (executable as NSString).deletingLastPathComponent
            if !dir.isEmpty, dir != ".", !path.split(separator: ":").contains(where: { $0 == dir }) {
                path = "\(dir):\(path)"
            }
        }
        env["PATH"] = path
        if env["HOME"] == nil || env["HOME"]?.isEmpty == true {
            env["HOME"] = NSHomeDirectory()
        }
        return env
    }

    static func resolveBrew(runner: any CommandRunning) async -> String? {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return await which("brew", runner: runner)
    }

    static func resolveOnPATH(_ name: String, runner: any CommandRunning) async -> String? {
        for prefix in defaultSystemPrefixes {
            let path = "\(prefix)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return await which(name, runner: runner)
    }

    /// Resolves `uv` from system prefixes, then common install locations.
    static func resolveUv(
        runner: any CommandRunning,
        home: String = NSHomeDirectory(),
        systemPrefixes: [String] = defaultSystemPrefixes
    ) async -> String? {
        let fm = FileManager.default
        var candidates: [String] = []
        for prefix in systemPrefixes {
            candidates.append("\(prefix)/uv")
        }
        candidates.append("\(home)/.local/bin/uv")
        candidates.append("\(home)/.cargo/bin/uv")
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        return await which("uv", runner: runner)
    }

    /// Resolves `bun` from system prefixes, then the official installer location.
    static func resolveBun(
        runner: any CommandRunning,
        home: String = NSHomeDirectory(),
        systemPrefixes: [String] = defaultSystemPrefixes
    ) async -> String? {
        let fm = FileManager.default
        var candidates: [String] = []
        for prefix in systemPrefixes {
            candidates.append("\(prefix)/bun")
        }
        candidates.append("\(home)/.bun/bin/bun")
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        return await which("bun", runner: runner)
    }

    /// Resolves a stable absolute path to `npm` for global inventory.
    /// Prefers system prefixes, then known version-manager defaults — never session shims.
    static func resolveNpm(
        runner: any CommandRunning,
        home: String = NSHomeDirectory(),
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        systemPrefixes: [String] = defaultSystemPrefixes
    ) async -> String? {
        let fm = FileManager.default
        for path in npmCandidatePaths(
            home: home,
            processEnvironment: processEnvironment,
            systemPrefixes: systemPrefixes
        ) {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        return await which("npm", runner: runner)
    }

    /// Ordered candidate paths (existence not checked). Exposed for tests.
    static func npmCandidatePaths(
        home: String,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        systemPrefixes: [String] = defaultSystemPrefixes
    ) -> [String] {
        var paths: [String] = []
        var seen = Set<String>()

        func add(_ path: String?) {
            guard let path, !path.isEmpty, !seen.contains(path) else { return }
            seen.insert(path)
            paths.append(path)
        }

        for prefix in systemPrefixes {
            add("\(prefix)/npm")
        }

        add("\(home)/.volta/bin/npm")

        let fnmDirs = [
            processEnvironment["FNM_DIR"],
            "\(home)/.local/share/fnm",
            "\(home)/.fnm",
        ].compactMap { $0 }
        for dir in fnmDirs {
            add("\(dir)/aliases/default/bin/npm")
        }

        let nvmDir = processEnvironment["NVM_DIR"] ?? "\(home)/.nvm"
        add(resolveNvmNpm(nvmDir: nvmDir))

        let asdfData = processEnvironment["ASDF_DATA_DIR"] ?? "\(home)/.asdf"
        if let version = toolVersionFromToolVersions(
            at: "\(home)/.tool-versions",
            names: ["nodejs", "node"]
        ) ?? readTrimmedFile(at: "\(asdfData)/alias/nodejs/default") {
            add(resolveVersionedNpm(installsDir: "\(asdfData)/installs/nodejs", version: version))
        }

        let miseData = processEnvironment["MISE_DATA_DIR"] ?? "\(home)/.local/share/mise"
        if let version = miseNodeVersion(home: home) ?? toolVersionFromToolVersions(
            at: "\(home)/.tool-versions",
            names: ["node", "nodejs"]
        ) {
            add(resolveVersionedNpm(installsDir: "\(miseData)/installs/node", version: version))
        }

        let nodenvRoot = processEnvironment["NODENV_ROOT"] ?? "\(home)/.nodenv"
        if let version = readTrimmedFile(at: "\(nodenvRoot)/version")
            ?? readTrimmedFile(at: "\(home)/.node-version")
        {
            add("\(nodenvRoot)/versions/\(version)/bin/npm")
        }

        let protoHome = processEnvironment["PROTO_HOME"] ?? "\(home)/.proto"
        if let version = protoNodeVersion(protoHome: protoHome, home: home) {
            add(resolveVersionedNpm(installsDir: "\(protoHome)/tools/node", version: version))
        }
        add("\(protoHome)/shims/npm")

        add("\(home)/.nodebrew/current/bin/npm")
        add("\(home)/.nix-profile/bin/npm")

        return paths
    }

    // MARK: - Version managers

    private static func resolveNvmNpm(nvmDir: String) -> String? {
        guard var alias = readTrimmedFile(at: "\(nvmDir)/alias/default") else { return nil }
        for _ in 0..<10 {
            for candidate in nvmVersionNames(alias) {
                let path = "\(nvmDir)/versions/node/\(candidate)/bin/npm"
                if FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
            if let next = readTrimmedFile(at: "\(nvmDir)/alias/\(alias)") {
                alias = next
                continue
            }
            break
        }
        return nil
    }

    private static func nvmVersionNames(_ alias: String) -> [String] {
        if alias.hasPrefix("v") {
            return [alias]
        }
        return ["v\(alias)", alias]
    }

    private static func miseNodeVersion(home: String) -> String? {
        let configs = [
            "\(home)/.config/mise/config.toml",
            "\(home)/.mise/config.toml",
            "\(home)/.mise.toml",
        ]
        for config in configs {
            if let version = parseTomlToolVersion(at: config, tool: "node") {
                return version
            }
        }
        return nil
    }

    private static func protoNodeVersion(protoHome: String, home: String) -> String? {
        if let version = parseProtoToolsVersion(at: "\(protoHome)/.prototools", tool: "node") {
            return version
        }
        if let version = parseProtoToolsVersion(at: "\(home)/.prototools", tool: "node") {
            return version
        }
        // Single installed version → use it as the implicit default.
        let installs = "\(protoHome)/tools/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: installs) {
            let usable = versions.filter { $0 != "manifest.json" && !$0.hasPrefix(".") }
                .sorted()
            if usable.count == 1 {
                return usable[0]
            }
        }
        return nil
    }

    private static func resolveVersionedNpm(installsDir: String, version: String) -> String? {
        let fm = FileManager.default
        let direct = "\(installsDir)/\(version)/bin/npm"
        if fm.isExecutableFile(atPath: direct) {
            return direct
        }
        guard let entries = try? fm.contentsOfDirectory(atPath: installsDir) else { return nil }
        let matches = entries.filter { entry in
            entry == version
                || entry.hasPrefix(version + ".")
                || (version.hasPrefix("v") && entry == String(version.dropFirst()))
                || (!version.hasPrefix("v") && entry == "v\(version)")
        }.sorted()
        // Prefer the last (highest) lexical match for partial versions like "24".
        for entry in matches.reversed() {
            let path = "\(installsDir)/\(entry)/bin/npm"
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private static func toolVersionFromToolVersions(at path: String, names: [String]) -> String? {
        guard let text = readFile(at: path) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 2 else { continue }
            if names.contains(parts[0]) {
                return parts[1]
            }
        }
        return nil
    }

    private static func parseTomlToolVersion(at path: String, tool: String) -> String? {
        guard let text = readFile(at: path) else { return nil }
        // Matches: node = "24.1.0" / node = '24' / node = 24.1.0
        let pattern = #"^\s*"# + NSRegularExpression.escapedPattern(for: tool)
            + #"\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s#]+))\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        for i in 1..<match.numberOfRanges {
            let r = match.range(at: i)
            if r.location != NSNotFound, let swiftRange = Range(r, in: text) {
                return String(text[swiftRange])
            }
        }
        return nil
    }

    private static func parseProtoToolsVersion(at path: String, tool: String) -> String? {
        // .prototools is TOML-like: node = "20.11.0"
        parseTomlToolVersion(at: path, tool: tool)
    }

    private static func readTrimmedFile(at path: String) -> String? {
        guard let text = readFile(at: path) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                return String(trimmed)
            }
        }
        return nil
    }

    private static func readFile(at path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func which(_ name: String, runner: any CommandRunning) async -> String? {
        do {
            let output = try await runner.capture(executable: "/usr/bin/which", arguments: [name])
            guard output.status == 0 else { return nil }
            let path = String(data: output.stdout, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else {
                return nil
            }
            return path
        } catch {
            return nil
        }
    }
}
