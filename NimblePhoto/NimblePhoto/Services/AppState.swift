import Foundation

enum FocusedPane {
    case tree
    case grid
    case fullSize
}

/// Overall selection/focus/filter state shared across the main window.
@Observable
final class AppState {
    var selectedFolderURL: URL?

    /// The keyboard cursor: the single photo shown in the status bar and the
    /// full-size viewer. Usually also selected, but cmd-click can deselect
    /// it while it stays highlighted.
    var highlightedPhotoID: String?

    /// Photos targeted by classification. When it holds more than one id, a
    /// category keystroke applies to all of them.
    var selectedPhotoIDs: Set<String> = []

    /// Fixed end of a shift-click / shift-arrow range selection.
    var selectionAnchorID: String?

    var focusedPane: FocusedPane = .grid

    /// Categories currently visible in the grid. Empty means "All" (spec §7.2).
    var activeFilters: Set<Category> = []

    var isShowingFullSize = false

    var statusMessage: String?
    /// SF Symbol shown with `statusMessage`; nil means the warning glyph.
    var statusSymbol: String?
    private var statusClearTask: Task<Void, Never>?

    /// Collapses highlight, selection, and anchor onto a single photo
    /// (or clears all three when `id` is nil).
    func select(_ id: String?) {
        highlightedPhotoID = id
        selectedPhotoIDs = id.map { [$0] } ?? []
        selectionAnchorID = id
    }

    func isFilterActive(_ category: Category) -> Bool {
        activeFilters.isEmpty || activeFilters.contains(category)
    }

    func toggleFilter(_ category: Category) {
        if activeFilters.contains(category) {
            activeFilters.remove(category)
        } else {
            if activeFilters.isEmpty {
                // Coming from "All": start a fresh explicit selection with
                // just this category.
                activeFilters = [category]
            } else {
                activeFilters.insert(category)
            }
        }
    }

    func showAll() {
        activeFilters = []
    }

    /// Errors are transient (spec §7.4): they replace the highlighted-photo
    /// info in the status bar for a few seconds, then it comes back.
    func showError(_ message: String) {
        showStatus(message, symbol: nil)
    }

    /// Non-error status (e.g. progress or a confirmation), shown like an
    /// error but with its own glyph.
    func showStatus(_ message: String, symbol: String?) {
        statusMessage = message
        statusSymbol = symbol
        statusClearTask?.cancel()
        statusClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
        }
    }
}
