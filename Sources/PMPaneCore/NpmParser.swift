import Foundation

public enum NpmParser {
    public static func packages(listJSON: Data, outdatedJSON: Data) throws -> [Package] {
        let decoder = JSONDecoder()
        let listRoot = try decoder.decode(NpmListRoot.self, from: listJSON)
        let outdatedRoot = try decoder.decode([String: NpmOutdatedEntry].self, from: outdatedJSON)

        guard var dependencies = listRoot.dependencies else { return [] }

        // Drop npm root wrapper entries without a normal dependency shape.
        dependencies = dependencies.filter { _, value in
            value.version != nil
        }

        return dependencies.keys.sorted().compactMap { name -> Package? in
            guard let dep = dependencies[name], let version = dep.version else { return nil }
            let outdated = outdatedRoot[name]
            let isOutdated = outdated != nil
            let latest = outdated?.latest ?? outdated?.wanted

            return Package(
                id: "npm:\(name)",
                name: name,
                fullName: name,
                displayName: name,
                source: .npm,
                installedVersion: version,
                latestVersion: latest,
                isOutdated: isOutdated,
                updatesItself: false,
                greedyOnly: false,
                pinned: false,
                installedOnRequest: true,
                installedAsDependency: false,
                summary: "",
                homepage: nil,
                tap: nil,
                trust: .notApplicable,
                versionIsLatest: false
            )
        }
    }
}

private struct NpmListRoot: Decodable {
    var name: String?
    var dependencies: [String: NpmListEntry]?
}

private struct NpmListEntry: Decodable {
    var version: String?
}

private struct NpmOutdatedEntry: Decodable {
    var current: String?
    var wanted: String?
    var latest: String?
}
