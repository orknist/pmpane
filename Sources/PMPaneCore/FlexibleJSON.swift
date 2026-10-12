import Foundation

enum FlexibleStringOrArray: Decodable, Sendable {
    case string(String)
    case array([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            self = .array(try container.decode([String].self))
        }
    }

    var values: [String] {
        switch self {
        case .string(let s): [s]
        case .array(let a): a
        }
    }

    var first: String? { values.first }
}
