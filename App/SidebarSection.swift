import Foundation
import PMPaneCore

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case all
    case updates
    case formulae
    case casks
    case taps
    case npm
    case pip
    case gem
    case uv
    case bun

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .updates: "Updates"
        case .formulae: "Formulae"
        case .casks: "Casks"
        case .taps: "Taps"
        case .npm: "npm"
        case .pip: "pip"
        case .gem: "gem"
        case .uv: "uv"
        case .bun: "bun"
        }
    }

    static var homebrewSections: [SidebarSection] {
        [.formulae, .casks, .taps]
    }

    static var runtimeSections: [SidebarSection] {
        [.npm, .pip, .gem, .uv, .bun]
    }

    /// `brew update` only belongs on All / Updates / Homebrew sections.
    var showsUpdateHomebrew: Bool {
        switch self {
        case .all, .updates, .formulae, .casks, .taps: true
        case .npm, .pip, .gem, .uv, .bun: false
        }
    }

    /// Source is implied by the sidebar selection for runtime package lists.
    var showsSourceColumn: Bool {
        switch self {
        case .npm, .pip, .gem, .uv, .bun: false
        default: true
        }
    }

    /// Tap / Trust are Homebrew concepts; hide those columns for runtime lists.
    var showsTapAndTrustColumns: Bool {
        switch self {
        case .npm, .pip, .gem, .uv, .bun: false
        default: true
        }
    }

    func matches(_ package: Package) -> Bool {
        switch self {
        case .all, .updates:
            return true
        case .formulae:
            return package.source == .brewFormula
        case .casks:
            return package.source == .brewCask
        case .taps:
            return package.source == .brewFormula || package.source == .brewCask
        case .npm:
            return package.source == .npm
        case .pip:
            return package.source == .pip
        case .gem:
            return package.source == .gem
        case .uv:
            return package.source == .uv
        case .bun:
            return package.source == .bun
        }
    }

    func runtimeToolID() -> String? {
        switch self {
        case .npm: "npm"
        case .pip: "pip"
        case .gem: "gem"
        case .uv: "uv"
        case .bun: "bun"
        default: nil
        }
    }

    /// Package managers re-scanned when Reload is pressed for this section.
    var reloadSources: Set<InventorySource> {
        switch self {
        case .all, .updates:
            Set(InventorySource.allCases)
        case .formulae, .casks, .taps:
            [.brew]
        case .npm:
            [.npm]
        case .pip:
            [.pip]
        case .gem:
            [.gem]
        case .uv:
            [.uv]
        case .bun:
            [.bun]
        }
    }

    /// Inventory source whose sidebar row shows a spinner (nil for All / Updates).
    var inventorySourceForProgress: InventorySource? {
        switch self {
        case .all, .updates: nil
        case .formulae, .casks, .taps: .brew
        case .npm: .npm
        case .pip: .pip
        case .gem: .gem
        case .uv: .uv
        case .bun: .bun
        }
    }

    var reloadHelp: String {
        switch self {
        case .all, .updates:
            "Re-scan all package managers in parallel. Does not run brew update."
        case .formulae, .casks, .taps:
            "Re-scan Homebrew formulae, casks, and taps. Does not run brew update."
        case .npm:
            "Re-scan global npm packages only."
        case .pip:
            "Re-scan pip packages only."
        case .gem:
            "Re-scan RubyGems only."
        case .uv:
            "Re-scan uv tools only."
        case .bun:
            "Re-scan bun global packages only."
        }
    }
}
