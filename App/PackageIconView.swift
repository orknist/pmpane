import AppKit
import SwiftUI
import PMPaneCore

@MainActor
enum PackageIconResolver {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for package: Package) -> NSImage {
        let key = package.id as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let image: NSImage
        switch package.source {
        case .brewCask:
            image = caskIcon(for: package) ?? placeholder(systemName: "app.fill")
        case .brewFormula:
            image = placeholder(systemName: "terminal")
        case .npm:
            image = placeholder(systemName: "shippingbox")
        case .pip:
            image = placeholder(systemName: "chevron.left.forwardslash.chevron.right")
        case .gem:
            image = placeholder(systemName: "diamond")
        case .uv:
            image = placeholder(systemName: "hammer")
        case .bun:
            image = placeholder(systemName: "hare")
        }

        cache.setObject(image, forKey: key)
        return image
    }

    private static func caskIcon(for package: Package) -> NSImage? {
        let candidates = appPathCandidates(for: package)
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return NSWorkspace.shared.icon(forFile: path)
            }
        }
        return nil
    }

    private static func appPathCandidates(for package: Package) -> [String] {
        var names = package.appBundleNames
        if names.isEmpty {
            names = ["\(package.displayName).app", "\(package.name).app"]
        }

        let roots = [
            "/Applications",
            "/Applications/Utilities",
            NSHomeDirectory() + "/Applications",
            "/opt/homebrew/Caskroom/\(package.name)",
            "/usr/local/Caskroom/\(package.name)",
        ]

        var paths: [String] = []
        for root in roots {
            for name in names {
                paths.append((root as NSString).appendingPathComponent(name))
            }
        }

        // Caskroom versioned install: /opt/homebrew/Caskroom/<token>/<version>/<App>.app
        for caskroom in ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"] {
            let tokenDir = (caskroom as NSString).appendingPathComponent(package.name)
            if let versions = try? FileManager.default.contentsOfDirectory(atPath: tokenDir) {
                for version in versions {
                    let versionDir = (tokenDir as NSString).appendingPathComponent(version)
                    for name in names {
                        paths.append((versionDir as NSString).appendingPathComponent(name))
                    }
                    if let apps = try? FileManager.default.contentsOfDirectory(atPath: versionDir) {
                        for entry in apps where entry.hasSuffix(".app") {
                            paths.append((versionDir as NSString).appendingPathComponent(entry))
                        }
                    }
                }
            }
        }

        return paths
    }

    private static func placeholder(systemName: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        return NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
            ?? NSImage(size: NSSize(width: 28, height: 28))
    }
}

struct PackageIconView: View {
    let package: Package
    var size: CGFloat = 22

    var body: some View {
        Image(nsImage: PackageIconResolver.icon(for: package))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}
