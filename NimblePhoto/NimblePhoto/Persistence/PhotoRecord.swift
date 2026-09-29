import Foundation

/// Flat row shape mirroring the `photos` table. `DatabaseService` deals only
/// in this type; `Photo` (the UI/domain model) is assembled from it by
/// higher-level code.
struct PhotoRecord: Sendable {
    var path: String
    var folderPath: String
    var fileName: String
    var pixelWidth: Int?
    var pixelHeight: Int?
    var dateTaken: Date?
    var dateSource: String
    var effectiveDate: Date
    var cameraMake: String?
    var cameraModel: String?
    var fileSize: Int64
    var fileModified: Date
    var isVideo: Bool
    var category: Int
}

extension PhotoRecord {
    init(photo: Photo) {
        self.path = photo.fileURL.path
        self.folderPath = photo.folderPath
        self.fileName = photo.fileName
        self.pixelWidth = photo.pixelWidth
        self.pixelHeight = photo.pixelHeight
        self.dateTaken = photo.dateTaken
        self.dateSource = photo.dateSource.rawValue
        self.effectiveDate = photo.effectiveDate
        self.cameraMake = photo.cameraMake
        self.cameraModel = photo.cameraModel
        self.fileSize = photo.fileSize
        self.fileModified = photo.fileModified
        self.isVideo = photo.isVideo
        self.category = photo.category.rawValue
    }

    func makePhoto() -> Photo {
        Photo(
            fileURL: URL(fileURLWithPath: path),
            folderPath: folderPath,
            fileName: fileName,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            dateTaken: dateTaken,
            dateSource: DateSource(rawValue: dateSource) ?? .fileModified,
            effectiveDate: effectiveDate,
            cameraMake: cameraMake,
            cameraModel: cameraModel,
            fileSize: fileSize,
            fileModified: fileModified,
            isVideo: isVideo,
            category: Category(rawValue: category) ?? .unclassified
        )
    }
}
