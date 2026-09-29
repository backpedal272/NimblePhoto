import Foundation

/// Builds the folder tree beneath a root, lazily: only the immediate
/// children of a node are enumerated, and only when that node is first
/// shown/expanded, so a deep tree never blocks the UI (spec §7.1). Empty
/// folders (no images, subfolders only) are still included.
@Observable
final class FolderTreeModel {
    private(set) var root: FolderNode?
    var isBuildingRoot = false

    func setRoot(_ url: URL) async {
        isBuildingRoot = true
        let node = FolderNode(url: url)
        node.imageCount = await Task.detached(priority: .userInitiated) {
            Self.countImages(in: url)
        }.value
        await loadChildren(of: node)
        root = node
        isBuildingRoot = false
    }

    func clear() {
        root = nil
    }

    /// Enumerates immediate subdirectories of `node`, populates its
    /// `children`, and counts each child's direct image files (for the
    /// sidebar badge), marking `node` loaded. Safe to call repeatedly
    /// (no-op if already loaded, unless `force` is set for a refresh).
    func loadChildren(of node: FolderNode, force: Bool = false) async {
        if node.isLoaded && !force { return }
        let url = node.url
        let subdirectories = await Task.detached(priority: .userInitiated) { () -> [(url: URL, imageCount: Int)] in
            let fm = FileManager.default
            guard let entries = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }
            let dirs = entries
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            return dirs.map { ($0, Self.countImages(in: $0)) }
        }.value

        let existingByPath = Dictionary(uniqueKeysWithValues: node.children.map { ($0.url.path, $0) })
        node.children = subdirectories.map { entry in
            let child = existingByPath[entry.url.path] ?? FolderNode(url: entry.url)
            child.imageCount = entry.imageCount
            return child
        }
        node.isLoaded = true
    }

    /// Fast, extension-based count of direct image and video files in `url`
    /// (spec §7.1: selecting a folder loads only its direct images). Uses
    /// the quick extension check rather than the authoritative ImageIO probe
    /// `FolderContentsModel` performs on selection, since this runs eagerly
    /// for every visible folder in the tree.
    private nonisolated static func countImages(in url: URL) -> Int {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        return entries.reduce(into: 0) { count, entry in
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            if !isDirectory && (SupportedImageTypes.hasImageExtension(entry) || SupportedVideoTypes.hasVideoExtension(entry)) {
                count += 1
            }
        }
    }
}
