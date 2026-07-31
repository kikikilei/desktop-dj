import AppKit
import Foundation

enum SkinRenderMode: String, Codable {
    case flattened
    case layered
}

enum SkinAnimationState: String, Codable {
    case playing
    case sleeping
    case switching
}

struct SkinAnimationClip: Codable, Identifiable {
    let id: String
    let state: SkinAnimationState
    let file: String
    let fps: Int
    let duration: TimeInterval
    let weight: Double
    let cooldownSeconds: TimeInterval
    let isPrimary: Bool
}

struct SkinCompactAssets: Codable {
    let playing: String
    let paused: String
}

struct SkinInteractionRegion: Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let tolerance: CGFloat

    func contains(_ point: NSPoint) -> Bool {
        NSRect(
            x: x - tolerance,
            y: y - tolerance,
            width: width + tolerance * 2,
            height: height + tolerance * 2
        ).contains(point)
    }
}

struct SkinInteractionDefinition: Codable {
    let expandedPet: SkinInteractionRegion
    let compactPet: SkinInteractionRegion
}

struct SkinDefinition: Codable, Identifiable {
    let schemaVersion: Int
    let id: String
    let name: String
    let author: String
    let renderMode: SkinRenderMode
    let animations: [SkinAnimationClip]
    let compact: SkinCompactAssets
    let interaction: SkinInteractionDefinition

    func clips(for state: SkinAnimationState) -> [SkinAnimationClip] {
        animations.filter { $0.state == state }
    }
}

struct LoadedSkin: Identifiable {
    let definition: SkinDefinition
    let rootURL: URL
    let isBundled: Bool

    var id: String { definition.id }

    func url(for relativePath: String) -> URL {
        rootURL.appendingPathComponent(relativePath)
    }

    func image(for relativePath: String) -> NSImage? {
        NSImage(contentsOf: url(for: relativePath))
    }
}

@MainActor
final class SkinCatalog {
    private(set) var skins: [LoadedSkin] = []
    private(set) var current: LoadedSkin

    let externalSkinsURL: URL

    init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        externalSkinsURL = applicationSupport
            .appendingPathComponent("Desktop DJ", isDirectory: true)
            .appendingPathComponent("Skins", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: externalSkinsURL,
            withIntermediateDirectories: true
        )

        let loaded = Self.loadBundledSkins() + Self.loadExternalSkins(
            from: externalSkinsURL
        )
        let fallback = Self.fallbackCowCat()
        skins = loaded.isEmpty ? [fallback] : loaded

        let preferredID = UserDefaults.standard.string(
            forKey: "desktopDJSkinID"
        )
        current = skins.first(where: { $0.id == preferredID })
            ?? skins.first(where: { $0.id == "cow-cat" })
            ?? skins[0]
    }

    @discardableResult
    func select(id: String) -> Bool {
        guard let skin = skins.first(where: { $0.id == id }) else {
            return false
        }
        current = skin
        UserDefaults.standard.set(id, forKey: "desktopDJSkinID")
        return true
    }

    func reloadExternalSkins() {
        let bundled = skins.filter(\.isBundled)
        let external = Self.loadExternalSkins(from: externalSkinsURL)
        skins = bundled + external.filter { candidate in
            !bundled.contains(where: { $0.id == candidate.id })
        }

        if !skins.contains(where: { $0.id == current.id }),
           let cowCat = skins.first(where: { $0.id == "cow-cat" })
                ?? skins.first {
            current = cowCat
        }
    }

    private static func loadBundledSkins() -> [LoadedSkin] {
        guard let resources = Bundle.main.resourceURL else { return [] }
        let skinsRoot = resources.appendingPathComponent(
            "Skins",
            isDirectory: true
        )
        return loadSkins(from: skinsRoot, isBundled: true)
    }

    private static func loadExternalSkins(from root: URL) -> [LoadedSkin] {
        loadSkins(from: root, isBundled: false)
    }

    private static func loadSkins(
        from root: URL,
        isBundled: Bool
    ) -> [LoadedSkin] {
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return directories.compactMap { directory in
            let manifestURL = directory.appendingPathComponent("skin.json")
            guard
                let data = try? Data(contentsOf: manifestURL),
                let definition = try? JSONDecoder().decode(
                    SkinDefinition.self,
                    from: data
                ),
                validate(definition: definition, rootURL: directory)
            else {
                return nil
            }
            return LoadedSkin(
                definition: definition,
                rootURL: directory,
                isBundled: isBundled
            )
        }
        .sorted {
            $0.definition.name.localizedCaseInsensitiveCompare(
                $1.definition.name
            ) == .orderedAscending
        }
    }

    private static func validate(
        definition: SkinDefinition,
        rootURL: URL
    ) -> Bool {
        guard
            definition.schemaVersion == 1,
            !definition.id.isEmpty,
            !definition.animations.isEmpty,
            definition.animations.allSatisfy({
                $0.duration > 0
                    && $0.duration <= 60
                    && (1...30).contains($0.fps)
                    && safeAssetPath($0.file, rootURL: rootURL)
            }),
            safeAssetPath(definition.compact.playing, rootURL: rootURL),
            safeAssetPath(definition.compact.paused, rootURL: rootURL)
        else {
            return false
        }
        return true
    }

    private static func safeAssetPath(
        _ path: String,
        rootURL: URL
    ) -> Bool {
        let allowedExtensions = ["gif", "png", "jpg", "jpeg", "webp"]
        guard
            !path.hasPrefix("/"),
            !path.split(separator: "/").contains(".."),
            allowedExtensions.contains(
                URL(fileURLWithPath: path).pathExtension.lowercased()
            )
        else {
            return false
        }

        let candidate = rootURL
            .appendingPathComponent(path)
            .standardizedFileURL
        return candidate.path.hasPrefix(rootURL.standardizedFileURL.path)
            && FileManager.default.fileExists(atPath: candidate.path)
    }

    private static func fallbackCowCat() -> LoadedSkin {
        let resources = Bundle.main.resourceURL
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Assets")
        let definition = SkinDefinition(
            schemaVersion: 1,
            id: "cow-cat",
            name: "Cow Cat",
            author: "Desktop DJ",
            renderMode: .flattened,
            animations: [
                SkinAnimationClip(
                    id: "playing-main",
                    state: .playing,
                    file: "cat-playing-loop.gif",
                    fps: 12,
                    duration: 5.04,
                    weight: 1,
                    cooldownSeconds: 0,
                    isPrimary: true
                ),
                SkinAnimationClip(
                    id: "sleeping-main",
                    state: .sleeping,
                    file: "cat-resting-loop.gif",
                    fps: 12,
                    duration: 4.04,
                    weight: 1,
                    cooldownSeconds: 0,
                    isPrimary: true
                ),
                SkinAnimationClip(
                    id: "switching-main",
                    state: .switching,
                    file: "cat-switching-once.gif",
                    fps: 12,
                    duration: 4.04,
                    weight: 1,
                    cooldownSeconds: 0,
                    isPrimary: true
                ),
            ],
            compact: SkinCompactAssets(
                playing: "headphones-upright.png",
                paused: "headphones-flat.png"
            ),
            interaction: SkinInteractionDefinition(
                expandedPet: SkinInteractionRegion(
                    x: 0,
                    y: 54,
                    width: 230,
                    height: 159,
                    tolerance: 6
                ),
                compactPet: SkinInteractionRegion(
                    x: 0,
                    y: 23,
                    width: 80,
                    height: 65,
                    tolerance: 4
                )
            )
        )
        return LoadedSkin(
            definition: definition,
            rootURL: resources,
            isBundled: true
        )
    }
}
