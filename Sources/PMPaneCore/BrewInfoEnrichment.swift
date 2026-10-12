import Foundation

/// Homebrew omits untrusted third-party installs from `brew info --json=v2 --installed`.
/// Fully-qualified `brew info` still returns them, so we reconcile against `brew list`.
enum BrewInfoEnrichment {
    struct InstalledIDs: Equatable {
        var formulae: Set<String>
        var casks: Set<String>
    }

    static func names(fromListOutput data: Data) -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Warning:") && !$0.hasPrefix("Error:") }
    }

    static func installedIDs(fromInfo info: Data) throws -> InstalledIDs {
        let root = try decodeRoot(info)
        let formulae = Set(root.formulae.compactMap { formulaID($0) })
        let casks = Set(root.casks.compactMap { caskID($0) })
        return InstalledIDs(formulae: formulae, casks: casks)
    }

    static func missingIDs(
        listedFormulae: [String],
        listedCasks: [String],
        info: Data
    ) throws -> (formulae: [String], casks: [String]) {
        let known = try installedIDs(fromInfo: info)
        let missingFormulae = listedFormulae.filter { !known.formulae.contains($0) }
        let missingCasks = listedCasks.filter { !known.casks.contains($0) }
        return (missingFormulae.sorted(), missingCasks.sorted())
    }

    static func merge(base: Data, extra: Data) throws -> Data {
        var baseRoot = try decodeRoot(base)
        let extraRoot = try decodeRoot(extra)

        var formulaByID: [String: JSONObject] = [:]
        for formula in baseRoot.formulae {
            if let id = formulaID(formula) {
                formulaByID[id] = formula
            }
        }
        for formula in extraRoot.formulae {
            if let id = formulaID(formula) {
                formulaByID[id] = formula
            }
        }

        var caskByID: [String: JSONObject] = [:]
        for cask in baseRoot.casks {
            if let id = caskID(cask) {
                caskByID[id] = cask
            }
        }
        for cask in extraRoot.casks {
            if let id = caskID(cask) {
                caskByID[id] = cask
            }
        }

        baseRoot.formulae = formulaByID.keys.sorted().compactMap { formulaByID[$0] }
        baseRoot.casks = caskByID.keys.sorted().compactMap { caskByID[$0] }

        let encoded = try JSONSerialization.data(withJSONObject: [
            "formulae": baseRoot.formulae,
            "casks": baseRoot.casks,
        ])
        return encoded
    }

    // MARK: - Private

    private typealias JSONObject = [String: Any]

    private struct Root {
        var formulae: [JSONObject]
        var casks: [JSONObject]
    }

    private static func decodeRoot(_ data: Data) throws -> Root {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else {
            throw ManagerError.invalidJSON("brew info root must be an object")
        }
        let formulae = dict["formulae"] as? [JSONObject] ?? []
        let casks = dict["casks"] as? [JSONObject] ?? []
        return Root(formulae: formulae, casks: casks)
    }

    private static func formulaID(_ formula: JSONObject) -> String? {
        if let full = formula["full_name"] as? String, !full.isEmpty { return full }
        if let name = formula["name"] as? String, !name.isEmpty { return name }
        return nil
    }

    private static func caskID(_ cask: JSONObject) -> String? {
        if let full = cask["full_token"] as? String, !full.isEmpty { return full }
        if let token = cask["token"] as? String, !token.isEmpty { return token }
        return nil
    }
}
