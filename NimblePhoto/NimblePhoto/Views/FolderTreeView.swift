import SwiftUI

/// Recursive, lazily-expanding folder tree (spec §7.1). Selecting a row
/// loads that folder's direct images into the grid; arrow keys move/expand
/// via native List/DisclosureGroup keyboard handling plus Tab-focus
/// integration in `MainWindowView`.
struct FolderTreeView: View {
    @Environment(AppState.self) private var appState
    @Environment(FolderTreeModel.self) private var treeModel
    let onSelect: (URL) -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        List {
            if let root = treeModel.root {
                FolderRowView(node: root, onSelect: onSelect, isRoot: true)
            } else if treeModel.isBuildingRoot {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading folders…").foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .focusEffectDisabled()
        .focused($isFocused)
        .onChange(of: appState.focusedPane) { _, pane in
            isFocused = (pane == .tree)
        }
        .onTapGesture {
            appState.focusedPane = .tree
        }
        .onKeyPress(phases: .down) { press in
            // Only bare Tab switches panes; modified Tab (⇧⇥, ⌃⇥, …) is left
            // to the system so standard focus cycling keeps working.
            guard press.key == .tab,
                  press.modifiers.isDisjoint(with: [.command, .option, .control, .shift]) else { return .ignored }
            appState.focusedPane = .grid
            return .handled
        }
    }
}

private struct FolderRowView: View {
    @Environment(AppState.self) private var appState
    @Environment(FolderTreeModel.self) private var treeModel
    let node: FolderNode
    let onSelect: (URL) -> Void
    @State private var isExpanded: Bool

    init(node: FolderNode, onSelect: @escaping (URL) -> Void, isRoot: Bool = false) {
        self.node = node
        self.onSelect = onSelect
        _isExpanded = State(initialValue: isRoot)
    }

    private var isSelected: Bool { appState.selectedFolderURL == node.url }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(node.children) { child in
                FolderRowView(node: child, onSelect: onSelect)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(isSelected ? Color.nimbleCream : Color.nimbleBlue)
                Text(node.name)
                    .foregroundStyle(isSelected ? Color.nimbleCream : Color.primary)
                Spacer(minLength: 4)
                Text("\(node.imageCount)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.nimbleCream.opacity(0.85) : Color.secondary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.nimbleBlue : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect(node.url)
            }
        }
        .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 12))
        .listRowBackground(Color.clear)
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                Task { await treeModel.loadChildren(of: node) }
            }
        }
    }
}
