import Foundation

enum NameValidation {
    /// Allows scoped names such as `@scope/pkg` (npm / bun).
    private static let packagePattern = try! NSRegularExpression(pattern: #"^(?:@[A-Za-z0-9._-]+/)?[A-Za-z0-9][A-Za-z0-9@+._/-]*$"#)
    private static let tapPattern = try! NSRegularExpression(pattern: #"^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$"#)

    static func validatePackageToken(_ name: String) throws {
        if name.isEmpty {
            throw ValidationError.invalidName("Package name must not be empty.")
        }
        if name.hasPrefix("-") {
            throw ValidationError.invalidName("Package name must not start with '-'.")
        }
        if name.contains("..") {
            throw ValidationError.invalidName("Package name must not contain '..'.")
        }
        if name.contains(where: \.isWhitespace) {
            throw ValidationError.invalidName("Package name must not contain whitespace.")
        }
        let shellMeta = CharacterSet(charactersIn: ";|&$`<>(){}[]*?~!")
        if name.unicodeScalars.contains(where: { shellMeta.contains($0) }) {
            throw ValidationError.invalidName("Package name contains invalid characters.")
        }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        guard packagePattern.firstMatch(in: name, range: range) != nil else {
            throw ValidationError.invalidName("Package name '\(name)' is not a valid token.")
        }
    }

    static func validateTap(_ tap: String) throws {
        if tap.contains("..") {
            throw ValidationError.invalidName("Tap name must not contain '..'.")
        }
        if tap.hasPrefix("-") {
            throw ValidationError.invalidName("Tap name must not start with '-'.")
        }
        let parts = tap.split(separator: "/")
        guard parts.count == 2 else {
            throw ValidationError.invalidName("Tap must be exactly user/repo.")
        }
        let range = NSRange(tap.startIndex..<tap.endIndex, in: tap)
        guard tapPattern.firstMatch(in: tap, range: range) != nil else {
            throw ValidationError.invalidName("Tap '\(tap)' is not valid.")
        }
    }

    static func validateTrustFormulaID(_ id: String) throws {
        let slashCount = id.filter { $0 == "/" }.count
        guard slashCount >= 1 else {
            throw ValidationError.invalidName("Trust formula id must be tap-qualified (contain '/').")
        }
        try validatePackageToken(id.replacingOccurrences(of: "/", with: "-"))
    }
}

enum ValidationError: Error, LocalizedError {
    case invalidName(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .invalidName(let message): message
        case .unsupported(let message): message
        }
    }
}

func makePlannedCommand(executable: String, arguments: [String], id: String) -> PlannedCommand {
    let display = ([executable] + arguments).joined(separator: " ")
    return PlannedCommand(id: id, executable: executable, arguments: arguments, display: display)
}
