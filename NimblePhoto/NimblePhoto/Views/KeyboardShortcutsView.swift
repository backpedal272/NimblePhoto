import SwiftUI

/// Read-only reference of every keyboard shortcut. Opened from
/// Help ▸ Keyboard Shortcuts (⌘/), or by pressing "?" in the grid or the
/// full-size viewer.
struct KeyboardShortcutsView: View {
    private struct Row: Identifiable {
        let keys: String
        let action: String
        var id: String { keys + action }
    }

    var body: some View {
        // Category rows show live display names; re-evaluate after renames.
        let _ = CategoryNamingTicker.shared.version
        VStack(alignment: .leading, spacing: 20) {
            section("Classify (grid & viewer)", rows: classifyRows,
                    footnote: "A digit applies to every selected photo.")
            section("Thumbnail Grid", rows: [
                Row(keys: "← → ↑ ↓", action: "Move the highlight"),
                Row(keys: "⇧ + arrows", action: "Extend the selection"),
                Row(keys: "Home / End", action: "First / last photo"),
                Row(keys: "Page ↑ / Page ↓", action: "Jump a screenful"),
                Row(keys: "⌘A", action: "Select all visible photos"),
                Row(keys: "⌘ click / ⇧ click", action: "Toggle / range-select"),
                Row(keys: "Esc", action: "Collapse the selection"),
                Row(keys: "Return / Space", action: "Open the full-size viewer")
            ])
            section("Full-Size Viewer", rows: [
                Row(keys: "← → ↑ ↓", action: "Previous / next photo"),
                Row(keys: "Home / End", action: "First / last photo"),
                Row(keys: "+ / −", action: "Zoom in / out"),
                Row(keys: "Drag", action: "Pan when zoomed in"),
                Row(keys: "Esc / Return / Space", action: "Close the viewer")
            ])
            section("General", rows: [
                Row(keys: "⌘Z", action: "Undo a classification"),
                Row(keys: "Tab", action: "Switch between tree and grid"),
                Row(keys: "⌘R", action: "Refresh the current folder"),
                Row(keys: "⌘+ / ⌘−", action: "Bigger / smaller thumbnails"),
                Row(keys: "I / ⌘I", action: "Show / hide the info panel"),
                Row(keys: "?", action: "Show this window")
            ])
        }
        .padding(24)
        .frame(width: 430)
    }

    private var classifyRows: [Row] {
        Category.allCases.map { category in
            Row(keys: category.keyEquivalent, action: "Mark as \(category.displayName)")
        }
    }

    private func section(_ title: String, rows: [Row], footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.keys)
                        .font(.system(.callout, design: .monospaced))
                        .frame(width: 160, alignment: .leading)
                    Text(row.action)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
    }
}
