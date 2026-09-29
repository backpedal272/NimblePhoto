import Foundation

/// Orchestrates renaming a category's display name and/or Finder tag name:
/// validation, finding already-tagged files that need migrating, and
/// performing the bulk Finder-tag rewrite. Used by the Settings window
/// (spec: user-definable categories).
enum CategoryRenameService {
    struct SkippedFile: Sendable, Identifiable {
        let path: String
        let reason: String
        var id: String { path }
    }

    struct RenameOutcome: Sendable, Identifiable {
        let id = UUID()
        var migratedCount: Int
        var skipped: [SkippedFile]
    }

    static let tagSuffixMaxLength = 20
    static let displayNameMaxLength = 30

    private static let tagSuffixCharacterSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")

    /// Returns a user-facing error message, or `nil` if valid.
    static func validate(displayName: String, tagSuffix: String, excluding category: Category) -> String? {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSuffix = tagSuffix.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else { return "Display name can't be empty." }
        guard !trimmedSuffix.isEmpty else { return "Tag name can't be empty." }
        guard trimmedName.count <= displayNameMaxLength else {
            return "Display name must be \(displayNameMaxLength) characters or fewer."
        }
        guard trimmedSuffix.count <= tagSuffixMaxLength else {
            return "Tag name must be \(tagSuffixMaxLength) characters or fewer."
        }
        guard trimmedSuffix.unicodeScalars.allSatisfy({ tagSuffixCharacterSet.contains($0) }) else {
            return "Tag name can only contain letters, numbers, and underscores."
        }
        guard trimmedSuffix.lowercased() != "unclassified" else {
            return "\"\(trimmedSuffix)\" is reserved for Unclassified."
        }

        for other in Category.allCases where other != category && other != .unclassified {
            let naming = CategoryNamingStore.naming(for: other)
            if naming.tagSuffix.caseInsensitiveCompare(trimmedSuffix) == .orderedSame {
                return "\"\(trimmedSuffix)\" is already used by \(other.displayName)."
            }
            if naming.displayName.caseInsensitiveCompare(trimmedName) == .orderedSame {
                return "\"\(trimmedName)\" is already used by another category."
            }
        }
        return nil
    }

    /// Recursively scans the folder tree under `rootURL` on disk for media
    /// files carrying `tagName`, returning their paths. Scanning disk —
    /// rather than asking the database, which only knows folders the user
    /// has visited in-app — guarantees files in never-visited subfolders
    /// are migrated too instead of silently keeping a retired tag.
    static func filesCarryingTag(_ tagName: String, under rootURL: URL) async -> [String] {
        await Task.detached(priority: .userInitiated) { () -> [String] in
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }

            var matches: [String] = []
            while let url = enumerator.nextObject() as? URL {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true else { continue }
                guard SupportedImageTypes.hasImageExtension(url) || SupportedVideoTypes.hasVideoExtension(url) else { continue }
                guard let tags = try? TagService.readRawTags(at: url) else { continue }
                if tags.contains(where: { tagBaseName($0) == tagName }) {
                    matches.append(url.path)
                }
            }
            return matches
        }.value
    }

    /// Renames `category` to `naming`, rewriting the Finder tag on
    /// `migratingPaths` (found beforehand via `filesCarryingTag`, with user
    /// confirmation when non-empty). The migration always runs to completion
    /// (not cancellable) and the naming change is committed afterwards
    /// regardless of per-file failures, which are collected and returned
    /// instead of aborting.
    static func commit(
        _ naming: CategoryNamingStore.Naming,
        for category: Category,
        migratingPaths paths: [String] = [],
        progress: (@Sendable (_ completed: Int, _ total: Int) -> Void)? = nil
    ) async -> RenameOutcome {
        let previousTagName = category.tagName
        let newTagName = "NP_" + naming.tagSuffix

        guard !paths.isEmpty, newTagName != previousTagName else {
            CategoryNamingStore.setNaming(naming, for: category)
            return RenameOutcome(migratedCount: 0, skipped: [])
        }

        let outcome = await migrateTags(paths: paths, from: previousTagName, to: newTagName, colorIndex: category.colorIndex, progress: progress)

        CategoryNamingStore.setNaming(naming, for: category)
        return outcome
    }

    private nonisolated static func tagBaseName(_ tag: String) -> String {
        tag.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? tag
    }

    private static func migrateTags(
        paths: [String],
        from previousTagName: String,
        to newTagName: String,
        colorIndex: Int,
        progress: (@Sendable (_ completed: Int, _ total: Int) -> Void)?
    ) async -> RenameOutcome {
        await Task.detached(priority: .userInitiated) { () -> RenameOutcome in
            let total = paths.count
            var migrated = 0
            var skipped: [SkippedFile] = []

            for (index, path) in paths.enumerated() {
                defer { progress?(index + 1, total) }
                let url = URL(fileURLWithPath: path)
                do {
                    var tags = try TagService.readRawTags(at: url)
                    guard let entryIndex = tags.firstIndex(where: { tag in
                        let name = tag.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? tag
                        return name == previousTagName
                    }) else {
                        skipped.append(SkippedFile(path: path, reason: "No longer carries the \(previousTagName) tag"))
                        continue
                    }
                    tags[entryIndex] = "\(newTagName)\n\(colorIndex)"
                    try TagService.writeRawTags(tags, to: url)
                    migrated += 1
                } catch {
                    skipped.append(SkippedFile(path: path, reason: describe(error)))
                }
            }
            return RenameOutcome(migratedCount: migrated, skipped: skipped)
        }.value
    }

    private nonisolated static func describe(_ error: Error) -> String {
        switch error {
        case ExtendedAttributes.XAttrError.readFailed(let errno), ExtendedAttributes.XAttrError.writeFailed(let errno):
            return String(cString: strerror(errno))
        case TagService.TagError.decodeFailed:
            return "Couldn't read existing Finder tags"
        case TagService.TagError.encodeFailed:
            return "Couldn't write Finder tags"
        default:
            return error.localizedDescription
        }
    }
}
