import Foundation

/// Persisted user preferences, backed by UserDefaults. Nonisolated so the
/// keys are usable from nonisolated stores (e.g. `CategoryNamingStore`).
nonisolated enum SettingsKeys {
    static let rootBookmark = "NP_rootBookmarkData"
    static let gridCellSize = "NP_gridCellSize"
    static let sidebarVisible = "NP_sidebarVisible"
    static let infoPanelVisible = "NP_infoPanelVisible"
    static let infoPanelToggledSections = "NP_infoPanelToggledSections"
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

    /// The right-hand EXIF panel; shared by the grid and the full-size
    /// viewer, and remembered across launches.
    var isInfoPanelVisible: Bool {
        didSet { UserDefaults.standard.set(isInfoPanelVisible, forKey: SettingsKeys.infoPanelVisible) }
    }

    init() {
        let stored = UserDefaults.standard.double(forKey: SettingsKeys.gridCellSize)
        gridCellSize = Settings.gridCellSizeRange.contains(stored) ? stored : Settings.defaultGridCellSize
        isSidebarVisible = UserDefaults.standard.object(forKey: SettingsKeys.sidebarVisible) as? Bool ?? true
        isInfoPanelVisible = UserDefaults.standard.bool(forKey: SettingsKeys.infoPanelVisible)
    }

    func toggleInfoPanel() {
        isInfoPanelVisible.toggle()
    }
}
