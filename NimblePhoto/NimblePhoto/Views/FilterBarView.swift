import SwiftUI

/// Category chips with full-folder counts and multi-select toggle filtering,
/// plus an "All" state (spec §7.2).
struct FilterBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(FolderContentsModel.self) private var contentsModel

    private func count(for category: Category) -> Int {
        contentsModel.photos.lazy.filter { $0.category == category }.count
    }

    var body: some View {
        @Bindable var appState = appState
        // Establishes an Observation dependency so chip labels refresh
        // immediately after a category rename in Settings.
        let _ = CategoryNamingTicker.shared.version
        ControlGroup {
            Button {
                appState.showAll()
            } label: {
                Text("All")
                    .fontWeight(appState.activeFilters.isEmpty ? .semibold : .regular)
            }

            ForEach(Category.allCases) { category in
                let isOn = appState.isFilterActive(category)
                Button {
                    appState.toggleFilter(category)
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(category.color)
                            .frame(width: 8, height: 8)
                        Text(category.displayName)
                        Text("\(count(for: category))")
                            .foregroundStyle(.secondary)
                    }
                    .opacity(isOn ? 1.0 : 0.5)
                }
            }
        }
    }
}
