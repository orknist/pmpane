import Foundation

enum BrewTrust {
    static let officialTaps: Set<String> = ["homebrew/core", "homebrew/cask"]

    static func candidateIDs(name: String, fullName: String, tap: String?) -> [String] {
        var ids = [fullName, name]
        if let tap, !tap.isEmpty {
            ids.append("\(tap)/\(name)")
        }
        return Array(Set(ids))
    }

    static func trustState(
        isFormula: Bool,
        tap: String?,
        candidateIDs: [String],
        trust: BrewTrustJSON,
        officialTaps: Set<String>
    ) -> TrustState {
        if let tap, officialTaps.contains(tap) {
            return .official
        }
        if let tap, trust.taps.contains(tap) {
            return .tapTrusted
        }
        let trustedList = isFormula ? trust.formulae : trust.casks
        if candidateIDs.contains(where: { trustedList.contains($0) }) {
            return .itemTrusted
        }
        return .untrusted
    }
}

struct BrewTrustJSON: Decodable, Sendable {
    var taps: [String]
    var formulae: [String]
    var casks: [String]
    var commands: [String]

    init(taps: [String] = [], formulae: [String] = [], casks: [String] = [], commands: [String] = []) {
        self.taps = taps
        self.formulae = formulae
        self.casks = casks
        self.commands = commands
    }
}
