import Foundation

/// Reads and writes the `com.apple.metadata:_kMDItemUserTags` extended
/// attribute directly (binary plist array of "Name" / "Name\nColorIndex"
/// strings) so non-NP tags and color info are preserved exactly (spec §6).
/// All methods are synchronous and file-system bound; callers run them off
/// the main actor.
nonisolated enum TagService {
    static let xattrName = "com.apple.metadata:_kMDItemUserTags"

    enum TagError: Error {
        case decodeFailed
        case encodeFailed
    }

    /// Raw tag strings currently on the file, in on-disk order.
    static func readRawTags(at url: URL) throws -> [String] {
        guard let data = try ExtendedAttributes.read(xattrName, from: url.path), !data.isEmpty else {
            return []
        }
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String] else {
            throw TagError.decodeFailed
        }
        return plist
    }

    static func writeRawTags(_ tags: [String], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: tags, format: .binary, options: 0)
        try ExtendedAttributes.write(xattrName, data: data, to: url.path)
    }

    /// Determines the photo's category from its raw tags. A file with no
    /// NP_ tag is `.unclassified`. If multiple NP_ tags are present
    /// (unexpected), picks by `Category.selfHealPriority`.
    static func category(fromRawTags tags: [String]) -> Category {
        let npCategories = tags.compactMap { tag -> Category? in
            let name = tag.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? tag
            return Category(tagName: name)
        }
        guard !npCategories.isEmpty else { return .unclassified }
        for candidate in Category.selfHealPriority where npCategories.contains(candidate) {
            return candidate
        }
        return .unclassified
    }

    static func readCategory(at url: URL) throws -> Category {
        category(fromRawTags: try readRawTags(at: url))
    }

    /// Removes all NP_ tags and appends the tag for `category`, preserving
    /// every other tag and its color exactly (spec §6.2).
    static func writeCategory(_ category: Category, to url: URL) throws {
        var tags = try readRawTags(at: url)
        tags.removeAll { tag in
            let name = tag.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? tag
            return name.hasPrefix("NP_")
        }
        tags.append("\(category.tagName)\n\(category.colorIndex)")
        try writeRawTags(tags, to: url)
    }
}
