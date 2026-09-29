import SwiftUI

/// The five mutually-exclusive classification buckets, keyed by keystroke.
/// Plain value data used from background tasks (tag I/O) as well as the UI,
/// so it opts out of the project's default MainActor isolation.
nonisolated enum Category: Int, CaseIterable, Identifiable, Codable, Sendable {
    case delete = 0
    case unclassified = 1
    case keep = 2
    case star = 3
    case select = 4

    var id: Int { rawValue }

    /// Order used to pick a single category when a file unexpectedly carries
    /// multiple NP_ tags (spec §6.1): Star > Select > Keep > Delete > Unclassified.
    static let selfHealPriority: [Category] = [.star, .select, .keep, .delete, .unclassified]

    /// User-customizable for every category except `.unclassified`, which is
    /// always `"NP_Unclassified"` (spec: no tag == Unclassified).
    var tagName: String {
        switch self {
        case .unclassified: return "NP_Unclassified"
        default: return CategoryNamingStore.tagName(for: self)
        }
    }

    /// Finder color index encoded in the tag string ("Name\nN").
    /// 0=none, 1=Gray, 2=Green, 3=Purple, 4=Blue, 5=Yellow, 6=Red, 7=Orange.
    var colorIndex: Int {
        switch self {
        case .delete: return 6
        case .unclassified: return 1
        case .keep: return 2
        case .star: return 5
        case .select: return 4
        }
    }

    /// User-customizable for every category except `.unclassified`.
    var displayName: String {
        switch self {
        case .unclassified: return "Unclassified"
        default: return CategoryNamingStore.displayName(for: self)
        }
    }

    var color: Color {
        switch self {
        case .delete: return .red
        case .unclassified: return .gray
        case .keep: return .green
        case .star: return .yellow
        case .select: return .blue
        }
    }

    var symbolName: String {
        switch self {
        case .delete: return "trash"
        case .unclassified: return "circle.dashed"
        case .keep: return "checkmark.circle"
        case .star: return "star.fill"
        case .select: return "hand.point.up.left.fill"
        }
    }

    /// The keystroke that selects this category ("0"..."4").
    var keyEquivalent: String { String(rawValue) }

    init?(tagName: String) {
        if tagName == "NP_Unclassified" {
            self = .unclassified
        } else if let match = CategoryNamingStore.category(forTagName: tagName) {
            self = match
        } else {
            return nil
        }
    }
}
