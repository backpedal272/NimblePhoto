import Foundation

/// Detailed, display-ready metadata for one file, shown in the info panel.
/// Built off the main actor by `PhotoInfoService`, so it opts out of the
/// project's default MainActor isolation.
nonisolated struct PhotoInfo: Sendable {
    struct Row: Identifiable, Sendable {
        let label: String
        let value: String
        var id: String { label }
    }

    struct Section: Identifiable, Sendable {
        let title: String
        let symbolName: String
        let rows: [Row]
        /// Raw dictionary dumps start collapsed; curated sections start open.
        var isRaw = false
        var id: String { (isRaw ? "raw:" : "") + title }
    }

    struct Coordinate: Sendable {
        let latitude: Double
        let longitude: Double
    }

    /// One-line capture settings ("ƒ/1.8 · 1/120 s · ISO 50 · 26 mm").
    var exposureSummary: String?
    var sections: [Section] = []
    var coordinate: Coordinate?
}
