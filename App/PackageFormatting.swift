import Foundation
import PMPaneCore

enum PackageFormatting {
    static func statusText(
        for package: Package,
        preferences: PackageUpdatePreferences = PackageUpdatePreferences()
    ) -> String {
        if preferences.isIgnored(package) { return "Ignored" }
        if preferences.isVersionSkipped(package) {
            if let version = package.latestVersion, !version.isEmpty {
                return "Skipped \(version)"
            }
            return "Skipped"
        }
        if package.pinned { return "Pinned" }
        if package.isOutdated { return "Outdated" }
        if package.updatesItself || package.greedyOnly { return "Updates itself" }
        if package.source == .brewFormula, !package.installedOnRequest {
            return "Dependency"
        }
        return "Up to date"
    }

    static func trustLabel(_ trust: TrustState) -> String {
        switch trust {
        case .notApplicable: "N/A"
        case .official: "Official"
        case .tapTrusted: "Tap trusted"
        case .itemTrusted: "Item trusted"
        case .untrusted: "Untrusted"
        }
    }

    static func sourceLabel(_ source: SourceKind) -> String {
        switch source {
        case .brewFormula: "Formula"
        case .brewCask: "Cask"
        case .npm: "npm"
        case .pip: "pip"
        case .gem: "gem"
        case .uv: "uv"
        case .bun: "bun"
        }
    }

    static func tapStatusText(_ tap: TapRecord) -> String {
        if tap.isStaleTrust {
            // Trust entry exists in brew, but the tap itself is no longer installed.
            return "Stale trust"
        }
        if tap.isTapped {
            return "Tapped"
        }
        return "Not tapped"
    }

    static func tapTrustText(_ tap: TapRecord) -> String {
        if tap.official { return "Official" }
        if tap.tapTrusted { return "Trusted" }
        return "Untrusted"
    }

    static func runtimeSubtitle(for tool: RuntimeTool?) -> String {
        guard let tool else { return "Not installed" }
        guard tool.available else { return "Not installed" }
        let path = tool.executable ?? "unknown"
        let version = tool.version.map { " \($0)" } ?? ""
        return "\(path)\(version)"
    }

    /// Short relative time for the toolbar, e.g. "just now", "3m ago", "2h ago".
    static func relativeTime(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 45 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3600)h ago" }
        if seconds < 86_400 * 7 { return "\(seconds / 86_400)d ago" }
        return date.formatted(date: .numeric, time: .omitted)
    }
}
