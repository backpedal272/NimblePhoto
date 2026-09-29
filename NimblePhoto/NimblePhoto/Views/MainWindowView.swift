import SwiftUI

/// Top-level layout: folder tree sidebar + filter bar / thumbnail grid /
/// status bar detail, with a full-size viewer overlay (spec §3, §7).
struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(RootFolderStore.self) private var rootFolderStore
    @Environment(FolderTreeModel.self) private var treeModel
    @Environment(FolderContentsModel.self) private var contentsModel
    @Environment(Settings.self) private var settings
    @Environment(\.undoManager) private var undoManager

    /// Viewer-resolution decode cache; owned here so it survives viewer
    /// open/close cycles and folder changes.
    @State private var imageLoader = FullSizeImageLoader()

    private var filteredPhotos: [Photo] {
        contentsModel.photos.filter { appState.isFilterActive($0.category) }
    }

    var body: some View {
        Group {
            if rootFolderStore.rootURL == nil {
                EmptyRootStateView(showButton: true)
            } else {
                NavigationSplitView(columnVisibility: sidebarVisibility) {
                    FolderTreeView(onSelect: selectFolder)
                        .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
                } detail: {
                    ZStack {
                        VStack(spacing: 0) {
                            if contentsModel.isLoading {
                                ProgressView("Loading…")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if appState.selectedFolderURL == nil {
                                Text("Select a folder")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                ThumbnailGridView(
                                    photos: filteredPhotos,
                                    thumbnailService: contentsModel.thumbnailService,
                                    onClassify: classify,
                                    onOpenFullSize: {
                                        appState.isShowingFullSize = true
                                        appState.focusedPane = .fullSize
                                    }
                                )
                            }
                            Divider()
                            StatusBarView()
                        }
                        if appState.isShowingFullSize {
                            FullSizeImageView(
                                photos: filteredPhotos,
                                thumbnailService: contentsModel.thumbnailService,
                                imageLoader: imageLoader,
                                onClassify: classify,
                                onClose: { appState.isShowingFullSize = false; appState.focusedPane = .grid }
                            )
                        }
                    }
                }
                .toolbar {
                    ToolbarItem {
                        FilterBarView()
                    }
                    ToolbarItem {
                        gridSizeSlider
                    }
                }
            }
        }
        .background(WindowCloseTerminator())
        .task {
            if let root = rootFolderStore.rootURL {
                await treeModel.setRoot(root)
                selectFolder(root)
            }
        }
        .onChange(of: rootFolderStore.rootURL) { _, newRoot in
            guard let newRoot else { return }
            Task {
                await treeModel.setRoot(newRoot)
                selectFolder(newRoot)
            }
        }
        .onChange(of: appState.activeFilters) { _, _ in
            // Filters changed: drop now-hidden photos from the selection so
            // a category keystroke can't touch anything invisible.
            let visible = Set(filteredPhotos.map(\.id))
            appState.selectedPhotoIDs.formIntersection(visible)
            if let highlighted = appState.highlightedPhotoID, !visible.contains(highlighted) {
                appState.select(filteredPhotos.first?.id)
            }
        }
    }

    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { settings.isSidebarVisible ? .all : .detailOnly },
            set: { settings.isSidebarVisible = $0 != .detailOnly }
        )
    }

    private func selectFolder(_ url: URL) {
        appState.isShowingFullSize = false
        appState.selectedFolderURL = url
        appState.select(nil)
        appState.focusedPane = .grid
        Task {
            await contentsModel.load(folder: url)
            if appState.highlightedPhotoID == nil {
                appState.select(filteredPhotos.first?.id)
            }
        }
    }

    private var gridSizeSlider: some View {
        @Bindable var settings = settings
        return HStack(spacing: 4) {
            Image(systemName: "photo")
                .font(.system(size: 11))
                .frame(width: 18, alignment: .center)
            Slider(value: $settings.gridCellSize, in: Settings.gridCellSizeRange)
                .frame(width: 180)
            Image(systemName: "photo")
                .font(.system(size: 18))
                .frame(width: 18, alignment: .center)
        }
        .padding(.horizontal, 12)
    }

    private func classify(_ category: Category, photoIDs: [String]) {
        let idSet = Set(photoIDs)
        let targets = contentsModel.photos.filter { idSet.contains($0.id) && $0.category != category }
        let leadID = appState.highlightedPhotoID
        let visibleBefore = filteredPhotos

        if !targets.isEmpty {
            registerUndo(
                restoring: targets.map { (path: $0.id, category: $0.category) },
                opposing: targets.map { (path: $0.id, category: category) },
                actionName: "Classify as \(category.displayName)"
            )
        }
        Task {
            await applyCategories(targets.map { (path: $0.id, category: category) })
            advanceAfterClassify(classifiedIDs: idSet, leadID: leadID, visibleBefore: visibleBefore)
        }
    }

    /// Writes the Finder tag for each change, then updates the in-memory
    /// model and the DB row. Failures are aggregated into one status-bar
    /// message rather than aborting the batch.
    private func applyCategories(_ changes: [(path: String, category: Category)]) async {
        var failures = 0
        for change in changes {
            let url = URL(fileURLWithPath: change.path)
            let category = change.category
            do {
                try await Task.detached(priority: .userInitiated) {
                    try TagService.writeCategory(category, to: url)
                }.value
                contentsModel.setCategory(category, forPhotoID: change.path)
                try? await contentsModel.database.updateCategory(path: change.path, category: category.rawValue)
            } catch {
                failures += 1
            }
        }
        if failures > 0 {
            appState.showError("Couldn't write tags for \(failures) file\(failures == 1 ? "" : "s")")
        }
    }

    /// Registers an undo that applies `entries` and re-registers with the
    /// roles swapped, so undo/redo ping-pong indefinitely. Restoring writes
    /// tags by path, so it keeps working after navigating to another folder
    /// (the grid/DB updates are no-ops for photos not currently loaded).
    private func registerUndo(
        restoring entries: [(path: String, category: Category)],
        opposing opposite: [(path: String, category: Category)],
        actionName: String
    ) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: contentsModel) { _ in
            MainActor.assumeIsolated {
                registerUndo(restoring: opposite, opposing: entries, actionName: actionName)
                Task {
                    await applyCategories(entries)
                    if let first = entries.first,
                       contentsModel.photos.contains(where: { $0.id == first.path }) {
                        appState.select(first.path)
                    }
                }
            }
        }
        undoManager.setActionName(actionName)
    }

    /// Standard culling flow: after classifying, move on to the next photo.
    /// Prefers the next still-visible photo after the highlight (skipping
    /// others in the same batch); stays put at the end of the list; falls
    /// back to the previous photo when the classified one dropped out of the
    /// current filter; closes the viewer when nothing visible remains.
    private func advanceAfterClassify(classifiedIDs: Set<String>, leadID: String?, visibleBefore: [Photo]) {
        guard let leadID, classifiedIDs.contains(leadID), appState.highlightedPhotoID == leadID,
              let leadIndex = visibleBefore.firstIndex(where: { $0.id == leadID })
        else { return }
        let visibleNow = Set(filteredPhotos.map(\.id))

        if let next = visibleBefore[visibleBefore.index(after: leadIndex)...]
            .first(where: { visibleNow.contains($0.id) && !classifiedIDs.contains($0.id) }) {
            appState.select(next.id)
        } else if visibleNow.contains(leadID) {
            appState.select(leadID)
        } else if let previous = visibleBefore[..<leadIndex]
            .last(where: { visibleNow.contains($0.id) && !classifiedIDs.contains($0.id) }) {
            appState.select(previous.id)
        } else {
            appState.select(nil)
            if appState.isShowingFullSize {
                appState.isShowingFullSize = false
                appState.focusedPane = .grid
            }
        }
    }
}

struct EmptyRootStateView: View {
    @Environment(RootFolderStore.self) private var rootFolderStore

    let showButton: Bool

    var body: some View {
        // Refreshes the category list after a rename in Settings.
        let _ = CategoryNamingTicker.shared.version
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                Text("Welcome to Nimble Photo")
                    .font(.largeTitle.weight(.semibold))
                Text("A fast, keyboard-driven way to sort through large photo collections. Browse your folders, review photos at full size, and sort each one into a category with a single keystroke.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Every photo gets one category, written as a Finder tag")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(Category.allCases) { category in
                    HStack(spacing: 10) {
                        Image(systemName: "\(category.rawValue).square.fill")
                            .foregroundStyle(category.color)
                            .frame(width: 20)
                        Text(category.displayName)
                            .fontWeight(.medium)
                        Spacer()
                        Text("Press \(category.keyEquivalent)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }

                Text("Your original files are never moved, renamed, or edited — only the Finder tag changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .frame(maxWidth: 360)
            .padding(20)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))

            if showButton {
                Button("Select Root Folder to Start") {
                    rootFolderStore.presentPicker()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
