import Foundation

enum PackageListFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case outdated
    case pinned
    case ignored
    case dependencies
    case untrusted
    case selfUpdating

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .outdated: "Outdated"
        case .pinned: "Pinned"
        case .ignored: "Ignored"
        case .dependencies: "Deps"
        case .untrusted: "Untrusted"
        case .selfUpdating: "Self-update"
        }
    }
}
