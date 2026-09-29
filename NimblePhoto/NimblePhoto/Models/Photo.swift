import Foundation

enum DateSource: String, Codable {
    case exif
    case fileModified
}

/// A single image file. `id` is the absolute file path, which is stable as
/// long as the file isn't moved (the app never moves files, so this holds).
/// Plain value data used from background actors as well as the UI, so it
/// opts out of the project's default MainActor isolation.
nonisolated struct Photo: Identifiable, Hashable {
    var id: String { fileURL.path }

    let fileURL: URL
    var folderPath: String
    var fileName: String

    var pixelWidth: Int?
    var pixelHeight: Int?

    var dateTaken: Date?
    var dateSource: DateSource
    var effectiveDate: Date

    var cameraMake: String?
    var cameraModel: String?

    var fileSize: Int64
    var fileModified: Date

    var isVideo: Bool

    var category: Category

    static func ==(lhs: Photo, rhs: Photo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
