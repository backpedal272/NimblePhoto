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
        HStack(spacing: 4) {
            FilterPill(isOn: appState.activeFilters.isEmpty) {
                appState.showAll()
            } label: {
                Text("All")
            }

            ForEach(Category.allCases) { category in
                FilterPill(isOn: appState.activeFilters.contains(category)) {
                    appState.toggleFilter(category)
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(category.color)
                            .frame(width: 8, height: 8)
                        Text(category.displayName)
                        Text("\(count(for: category))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        // Matches the toolbar item's own vertical inset (measured on screen), so
        // the "All" pill sits concentrically in the rounded toolbar background
        // with equal top, bottom, and left gaps.
        .padding(.horizontal, 7.5)
    }
}

/// A capsule toggle in the Nimble style: active pills are tinted with the
/// accent at reduced opacity rather than gray (style guide §2).
private struct FilterPill<Label: View>: View {
    let isOn: Bool
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            label
                .font(.callout.weight(isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Color.nimbleDeepBlue : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(isOn ? Color.nimbleBlue.opacity(0.18) : Color.clear)
                )
                .overlay(
                    Capsule().strokeBorder(isOn ? Color.nimbleBlue.opacity(0.6) : Color.clear, lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
