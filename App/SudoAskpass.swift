import Foundation

/// Installs a `SUDO_ASKPASS` wrapper so Homebrew can prompt via the app’s native
/// password dialog when upgrading casks that touch protected paths.
enum SudoAskpass {
    private static let wrapperName = "sudo-askpass"
    static let argument = "--sudo-askpass"

    /// Writes an executable wrapper that re-launches this app in askpass mode and
    /// exports `SUDO_ASKPASS` for child processes started via `ProcessCommandRunner`.
    static func install() {
        guard let executable = Bundle.main.executablePath else { return }

        let fm = FileManager.default
        guard let support = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return
        }

        let dir = support.appendingPathComponent("PMPane", isDirectory: true)
        let destination = dir.appendingPathComponent(wrapperName)
        let script = """
        #!/bin/bash
        exec \(shellSingleQuoted(executable)) \(argument)

        """

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try script.write(to: destination, atomically: true, encoding: .utf8)
            try fm.setAttributes(
                [.posixPermissions: NSNumber(value: 0o755)],
                ofItemAtPath: destination.path
            )
            setenv("SUDO_ASKPASS", destination.path, 1)
        } catch {
            // Leave SUDO_ASKPASS unset; brew mutations that need sudo will fail clearly.
        }
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
