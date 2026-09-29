import Foundation

/// A node in the folder tree. Children are loaded lazily so a deep tree
/// doesn't block the UI (spec §7.1).
@Observable
final class FolderNode: Identifiable {
    let url: URL
    let name: String
    var children: [FolderNode] = []
    var isLoaded = false
    /// Count of direct (non-recursive) image and video files in this folder,
    /// matching what selecting it loads into the grid (spec §7.1).
    var imageCount: Int = 0

    var id: String { url.path }

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
    }
}
