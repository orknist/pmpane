import Foundation

/// When Homebrew last ran a real catalog fetch (`brew update` / auto-update).
///
/// Homebrew itself uses `$HOMEBREW_REPOSITORY/.git/FETCH_HEAD` mtime for this
/// (see `Library/Homebrew/utils/auto-update.sh`). There is no dedicated
/// `brew` subcommand that prints the value.
public enum BrewCatalogFreshness {
    /// Modification time of `repository/.git/FETCH_HEAD`, if present.
    public static func lastUpdateDate(repositoryPath: String) -> Date? {
        let trimmed = repositoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let fetchHead = (trimmed as NSString).appendingPathComponent(".git/FETCH_HEAD")
        guard FileManager.default.fileExists(atPath: fetchHead) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: fetchHead)
        return attrs?[.modificationDate] as? Date
    }

    /// Best-effort repository root from a `brew` executable path (`…/bin/brew` → `…`).
    public static func repositoryPath(fromBrewExecutable brew: String) -> String {
        let resolved = URL(fileURLWithPath: brew).resolvingSymlinksInPath()
        return resolved
            .deletingLastPathComponent() // bin
            .deletingLastPathComponent() // repository
            .path
    }

    public static func lastUpdateDate(brewExecutable: String) -> Date? {
        lastUpdateDate(repositoryPath: repositoryPath(fromBrewExecutable: brewExecutable))
    }

    /// Coarse toolbar label — no seconds; recent fetches read as “just now”.
    public static func updatedLabel(for date: Date, relativeTo now: Date = .now) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        if elapsed < 60 {
            return "Updated just now"
        }
        if elapsed < 3600 {
            let minutes = Int(elapsed / 60)
            return "Updated \(minutes)m ago"
        }
        if elapsed < 86_400 {
            let hours = Int(elapsed / 3600)
            return "Updated \(hours)h ago"
        }
        let days = Int(elapsed / 86_400)
        return "Updated \(days)d ago"
    }
}
