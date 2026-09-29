import AppKit
import SwiftUI

/// Lazy square-cell grid of the current folder's (filtered, sorted) photos
/// (spec §7.3). Owns highlight + multi-selection: arrow keys move the
/// highlight (⇧ extends a range from the anchor), ⌘/⇧-click toggle and
/// range-select, ⌘A selects everything visible, and category keystrokes
/// apply to the whole selection.
struct ThumbnailGridView: View {
    @Environment(AppState.self) private var appState
    @Environment(Settings.self) private var settings
    @Environment(\.openWindow) private var openWindow
    let photos: [Photo]
    let thumbnailService: ThumbnailService
    let onClassify: (Category, [String]) -> Void
    let onOpenFullSize: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let cellSize = settings.gridCellSize
            let columns = max(1, Int(geometry.size.width / (cellSize + 12)))
            let pageSize = columns * max(1, Int(geometry.size.height / (cellSize + 48)))

            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellSize), spacing: 12), count: columns), spacing: 16) {
                        ForEach(photos) { photo in
                            ThumbnailCellView(
                                photo: photo,
                                cellSize: cellSize,
                                isHighlighted: appState.highlightedPhotoID == photo.id,
                                isSelected: appState.selectedPhotoIDs.contains(photo.id),
                                thumbnailService: thumbnailService
                            )
                                .id(photo.id)
                                .onTapGesture {
                                    handleTap(on: photo)
                                }
                                .simultaneousGesture(TapGesture(count: 2).onEnded {
                                    appState.select(photo.id)
                                    onOpenFullSize()
                                })
                                .contextMenu {
                                    ForEach(Category.allCases) { category in
                                        Button {
                                            onClassify(category, contextTargets(for: photo))
                                        } label: {
                                            Label(category.displayName, systemImage: category.symbolName)
                                        }
                                    }
                                    Divider()
                                    Button {
                                        let urls = contextTargets(for: photo).map { URL(fileURLWithPath: $0) }
                                        NSWorkspace.shared.activateFileViewerSelecting(urls)
                                    } label: {
                                        Label("Show in Finder", systemImage: "finder")
                                    }
                                }
                        }
                    }
                    .padding(16)
                }
                .onChange(of: appState.highlightedPhotoID) { _, newValue in
                    if let newValue {
                        withAnimation { scrollProxy.scrollTo(newValue, anchor: .center) }
                    }
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onAppear {
                if appState.focusedPane == .grid { isFocused = true }
            }
            .onChange(of: appState.focusedPane) { _, pane in
                isFocused = (pane == .grid)
            }
            .onKeyPress(phases: .down) { press in
                handleKey(press, columns: columns, pageSize: pageSize)
            }
        }
    }

    // MARK: - Keyboard

    private func handleKey(_ press: KeyPress, columns: Int, pageSize: Int) -> KeyPress.Result {
        // Check only the modifiers that matter and ignore the rest: macOS
        // decorates navigation keys with phantom flags (.function,
        // .numericPad, Caps Lock adds .capsLock), and treating those as
        // "modified" makes every arrow key fall through unhandled and beep.
        let shift = press.modifiers.contains(.shift)
        // Arrows etc. respond with or without ⇧, but never with ⌘/⌥/⌃.
        let plain = press.modifiers.isDisjoint(with: [.command, .option, .control])
        let bare = plain && !shift

        switch press.key {
        case .leftArrow where plain: move(by: -1, extending: shift); return .handled
        case .rightArrow where plain: move(by: 1, extending: shift); return .handled
        case .upArrow where plain: move(by: -columns, extending: shift); return .handled
        case .downArrow where plain: move(by: columns, extending: shift); return .handled
        case .home where plain: move(toIndex: 0, extending: shift); return .handled
        case .end where plain: move(toIndex: photos.count - 1, extending: shift); return .handled
        case .pageUp where plain: move(by: -pageSize, extending: shift); return .handled
        case .pageDown where plain: move(by: pageSize, extending: shift); return .handled
        case .escape where bare:
            guard appState.selectedPhotoIDs.count > 1 else { return .ignored }
            appState.select(appState.highlightedPhotoID)
            return .handled
        case .return where bare, .space where bare:
            onOpenFullSize()
            return .handled
        case .tab:
            // Only bare Tab switches panes; modified Tab (⇧⇥, ⌃⇥, …) is left
            // to the system so standard focus cycling keeps working.
            guard bare else { return .ignored }
            appState.focusedPane = .tree
            return .handled
        default: break
        }

        if press.modifiers.contains(.command), press.characters == "a" {
            selectAll()
            return .handled
        }
        if bare, let value = Int(press.characters), let category = Category(rawValue: value) {
            let targets = classifyTargets()
            guard !targets.isEmpty else { return .ignored }
            onClassify(category, targets)
            return .handled
        }
        if press.characters == "?" {
            openWindow(id: "shortcuts")
            return .handled
        }
        return .ignored
    }

    // MARK: - Selection

    private func handleTap(on photo: Photo) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            toggleSelection(of: photo.id)
        } else if modifiers.contains(.shift) {
            extendSelection(toID: photo.id)
        } else {
            appState.select(photo.id)
        }
        appState.focusedPane = .grid
        isFocused = true
    }

    private func move(by delta: Int, extending: Bool) {
        guard !photos.isEmpty else { return }
        guard let currentID = appState.highlightedPhotoID,
              let currentIndex = photos.firstIndex(where: { $0.id == currentID }) else {
            appState.select(photos.first?.id)
            return
        }
        move(toIndex: min(max(currentIndex + delta, 0), photos.count - 1), extending: extending)
    }

    private func move(toIndex index: Int, extending: Bool) {
        guard photos.indices.contains(index) else { return }
        if extending {
            extendSelection(toIndex: index)
        } else {
            appState.select(photos[index].id)
        }
    }

    private func extendSelection(toID id: String) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        extendSelection(toIndex: index)
    }

    private func extendSelection(toIndex index: Int) {
        let anchorIndex = appState.selectionAnchorID
            .flatMap { id in photos.firstIndex(where: { $0.id == id }) }
            ?? index
        let range = min(anchorIndex, index)...max(anchorIndex, index)
        appState.selectedPhotoIDs = Set(photos[range].map(\.id))
        appState.selectionAnchorID = photos[anchorIndex].id
        appState.highlightedPhotoID = photos[index].id
    }

    private func toggleSelection(of id: String) {
        if appState.selectedPhotoIDs.contains(id) {
            appState.selectedPhotoIDs.remove(id)
        } else {
            appState.selectedPhotoIDs.insert(id)
            appState.selectionAnchorID = id
        }
        appState.highlightedPhotoID = id
    }

    private func selectAll() {
        guard !photos.isEmpty else { return }
        appState.selectedPhotoIDs = Set(photos.map(\.id))
        if appState.highlightedPhotoID == nil {
            appState.highlightedPhotoID = photos.first?.id
        }
        appState.selectionAnchorID = appState.highlightedPhotoID
    }

    /// A category keystroke targets the multi-selection when there is one,
    /// otherwise the highlighted photo.
    private func classifyTargets() -> [String] {
        if appState.selectedPhotoIDs.count > 1 {
            return photos.filter { appState.selectedPhotoIDs.contains($0.id) }.map(\.id)
        }
        return appState.highlightedPhotoID.map { [$0] } ?? []
    }

    /// The context menu targets the selection only when the right-clicked
    /// photo is part of it; otherwise just that photo.
    private func contextTargets(for photo: Photo) -> [String] {
        if appState.selectedPhotoIDs.count > 1, appState.selectedPhotoIDs.contains(photo.id) {
            return photos.filter { appState.selectedPhotoIDs.contains($0.id) }.map(\.id)
        }
        return [photo.id]
    }
}

private struct ThumbnailCellView: View {
    @Environment(FolderContentsModel.self) private var contentsModel
    let photo: Photo
    let cellSize: Double
    let isHighlighted: Bool
    let isSelected: Bool
    let thumbnailService: ThumbnailService

    @State private var image: NSImage?

    /// Read live from the model rather than the `photo` snapshot handed down
    /// by the enclosing `ForEach`/`LazyVGrid`, which doesn't reliably
    /// re-render already-mounted cells when only one array element changes.
    private var category: Category {
        contentsModel.photos.first(where: { $0.id == photo.id })?.category ?? photo.category
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.1))
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ProgressView().controlSize(.small)
                }
                if photo.isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: max(18, cellSize * 0.18)))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }
            .frame(width: cellSize, height: cellSize)

            HStack(spacing: 4) {
                Circle()
                    .fill(category.color)
                    .frame(width: 8, height: 8)
                Text(photo.fileName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: cellSize)
        }
        .padding(6)
        .background(
            isSelected ? Color.accentColor.opacity(0.22) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, lineWidth: isHighlighted ? 2 : 0)
        )
        // Keyed on the same identity as the thumbnail cache (path + mtime +
        // size) so an in-place file edit reloads the cell, not just a new id.
        .task(id: "\(photo.id)|\(photo.fileModified.timeIntervalSinceReferenceDate)|\(photo.fileSize)") {
            let url = await thumbnailService.thumbnail(
                for: photo.fileURL,
                path: photo.id,
                fileModified: photo.fileModified,
                fileSize: photo.fileSize,
                isVideo: photo.isVideo
            )
            guard let url else { return }
            image = await Task.detached(priority: .userInitiated) {
                NSImage(contentsOf: url)
            }.value
        }
    }
}
