import Foundation

/// Persisted user preferences, backed by UserDefaults. Nonisolated so the
/// keys are usable from nonisolated stores (e.g. `CategoryNamingStore`).
nonisolated enum SettingsKeys {
    static let rootBookmark = "NP_rootBookmarkData"
    static let gridCellSize = "NP_gridCellSize"
    static let sidebarVisible = "NP_sidebarVisible"
    static let categoryNaming = "NP_categoryNaming"
}

@Observable
final class Settings {
    static let defaultGridCellSize: Double = 300
    static let gridCellSizeRange: ClosedRange<Double> = 120...400

    var gridCellSize: Double {
        didSet { UserDefaults.standard.set(gridCellSize, forKey: SettingsKeys.gridCellSize) }
    }

    var isSidebarVisible: Bool {
        didSet { UserDefaults.standard.set(isSidebarVisible, forKey: SettingsKeys.sidebarVisible) }
    }

    init() {
        let stored = UserDefaults.standard.double(forKey: SettingsKeys.gridCellSize)
        gridCellSize = Settings.gridCellSizeRange.contains(stored) ? stored : Settings.defaultGridCellSize
        isSidebarVisible = UserDefaults.standard.object(forKey: SettingsKeys.sidebarVisible) as? Bool ?? true
    }
}
