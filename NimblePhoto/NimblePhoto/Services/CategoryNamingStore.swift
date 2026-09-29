import Foundation
import Observation
import os

/// Observation bridge for `CategoryNamingStore`, which is a nonisolated
/// static cache SwiftUI can't track. Views that render category names or
/// tag names read `version` in their body so a rename re-evaluates them.
@Observable
final class CategoryNamingTicker {
    static let shared = CategoryNamingTicker()
    private(set) var version = 0
    func bump() { version += 1 }
}

/// Persists user-customizable display names and Finder tag suffixes for the
/// 4 non-Unclassified categories (`Unclassified` is fixed and never stored
/// here). Backed by `UserDefaults`, cached in memory behind a lock so the
/// frequent reads from background tag I/O (folder scans of up to 50k files)
/// don't repeatedly decode JSON.
nonisolated enum CategoryNamingStore {
    struct Naming: Codable, Sendable, Equatable {
        var displayName: String
        var tagSuffix: String
    }

    /// Hardcoded fallback for the 4 editable slots, matching the tag names
    /// already written to disk by earlier versions of the app.
    static let defaults: [Int: Naming] = [
        Category.delete.rawValue: Naming(displayName: "Delete", tagSuffix: "Delete"),
        Category.keep.rawValue: Naming(displayName: "Keep", tagSuffix: "Keep"),
        Category.star.rawValue: Naming(displayName: "Star", tagSuffix: "Star"),
        Category.select.rawValue: Naming(displayName: "Select", tagSuffix: "Select")
    ]

    private static let lock = OSAllocatedUnfairLock<[Int: Naming]?>(initialState: nil)

    private static func load() -> [Int: Naming] {
        guard let data = UserDefaults.standard.data(forKey: SettingsKeys.categoryNaming),
              let stored = try? JSONDecoder().decode([Int: Naming].self, from: data)
        else {
            return defaults
        }
        return defaults.merging(stored) { _, new in new }
    }

    private static func current() -> [Int: Naming] {
        lock.withLock { cached in
            if let cached { return cached }
            let loaded = load()
            cached = loaded
            return loaded
        }
    }

    static func naming(for category: Category) -> Naming {
        current()[category.rawValue] ?? defaults[category.rawValue] ?? Naming(displayName: category.rawValue.description, tagSuffix: category.rawValue.description)
    }

    static func displayName(for category: Category) -> String {
        naming(for: category).displayName
    }

    static func tagName(for category: Category) -> String {
        "NP_" + naming(for: category).tagSuffix
    }

    /// Reverse lookup used by `Category.init?(tagName:)`. Only matches the 4
    /// editable slots' *current* tag names — retired tag names are not
    /// remembered.
    static func category(forTagName tagName: String) -> Category? {
        let all = current()
        for category in Category.allCases where category != .unclassified {
            if let naming = all[category.rawValue], "NP_" + naming.tagSuffix == tagName {
                return category
            }
        }
        return nil
    }

    /// Persists a new naming for `category` and updates the in-memory cache.
    static func setNaming(_ naming: Naming, for category: Category) {
        precondition(category != .unclassified, "Unclassified naming is fixed")
        let updated = lock.withLock { cached -> [Int: Naming] in
            var next = cached ?? load()
            next[category.rawValue] = naming
            cached = next
            return next
        }
        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: SettingsKeys.categoryNaming)
        }
        Task { @MainActor in
            CategoryNamingTicker.shared.bump()
        }
    }
}
