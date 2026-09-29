import Foundation

/// Loads and maintains the direct (non-recursive) images and videos of one folder:
/// reconciles against the DB cache, extracts metadata for new/changed files,
/// reads categories from Finder tags, and lazily fans out thumbnail
/// generation as cells become visible (spec §10.1).
@Observable
final class FolderContentsModel {
    private(set) var photos: [Photo] = []
    private(set) var isLoading = false
    private(set) var folderURL: URL?

    let database: DatabaseService
    let thumbnailService: ThumbnailService
    private let watcher = FolderWatcher()
    private var loadToken = UUID()

    init(database: DatabaseService, thumbnailService: ThumbnailService) {
        self.database = database
        self.thumbnailService = thumbnailService
    }

    func load(folder: URL) async {
        folderURL = folder
        isLoading = true
        let token = UUID()
        loadToken = token
        watcher.stop()

        let folderPath = folder.path

        var existingByPath: [String: PhotoRecord] = [:]
        if let rows = try? await database.photos(inFolder: folderPath) {
            existingByPath = Dictionary(uniqueKeysWithValues: rows.map { ($0.path, $0) })
        }
        guard loadToken == token else { return }

        // The whole per-file pass — directory scan, Finder-tag read (one
        // getxattr syscall each), and EXIF extraction for new/changed files —
        // stays off the main actor: at 50k files it would otherwise hang the
        // UI for seconds.
        let existing = existingByPath
        let records = await Task.detached(priority: .userInitiated) { () -> [PhotoRecord] in
            let fm = FileManager.default
            guard let entries = try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }

            var records: [PhotoRecord] = []
            records.reserveCapacity(entries.count)
            for url in entries {
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]),
                      values.isDirectory != true
                else { continue }
                let isVideo = SupportedVideoTypes.hasVideoExtension(url)
                guard isVideo || SupportedImageTypes.isImage(at: url) else { continue }
                let size = Int64(values.fileSize ?? 0)
                let modified = values.contentModificationDate ?? Date()
                records.append(await Self.makeRecord(
                    url: url,
                    folderPath: folderPath,
                    size: size,
                    modified: modified,
                    isVideo: isVideo,
                    existing: existing[url.path]
                ))
            }
            return records
        }.value

        guard loadToken == token else { return }

        for record in records {
            try? await database.upsert(record)
        }
        try? await database.pruneFolder(folderPath: folderPath, keepPaths: Set(records.map(\.path)))

        guard loadToken == token else { return }

        let sorted = records
            .map { $0.makePhoto() }
            .sorted { lhs, rhs in
                if lhs.effectiveDate != rhs.effectiveDate {
                    return lhs.effectiveDate < rhs.effectiveDate
                }
                return lhs.fileName.localizedStandardCompare(rhs.fileName) == .orderedAscending
            }

        photos = sorted
        isLoading = false

        watcher.start(path: folderPath) { [weak self] change in
            guard let self else { return }
            Task { @MainActor in
                switch change {
                case .added(let url), .modified(let url):
                    await self.addOrUpdate(fileAt: url)
                case .removed(let url):
                    await self.remove(fileAt: url)
                }
            }
        }
    }

    func stopWatching() {
        watcher.stop()
    }

    /// Updates the category of one photo in-place (called after a
    /// successful tag write) without a full folder reload.
    func setCategory(_ category: Category, forPhotoID photoID: String) {
        guard let index = photos.firstIndex(where: { $0.id == photoID }) else { return }
        photos[index].category = category
    }

    func addOrUpdate(fileAt url: URL) async {
        guard let folderURL, url.deletingLastPathComponent().path == folderURL.path else { return }
        // A file renamed/moved out of the folder arrives here as .modified
        // on its old path (FSEvents flags renames that way); treat a path
        // that no longer exists as a removal so no ghost entry lingers.
        guard FileManager.default.fileExists(atPath: url.path) else {
            await remove(fileAt: url)
            return
        }
        let isVideo = SupportedVideoTypes.hasVideoExtension(url)
        guard isVideo || SupportedImageTypes.isImage(at: url) else { return }
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        let size = Int64(values.fileSize ?? 0)
        let modified = values.contentModificationDate ?? Date()
        let folderPath = folderURL.path

        let record = await Task.detached(priority: .userInitiated) {
            await Self.makeRecord(url: url, folderPath: folderPath, size: size, modified: modified, isVideo: isVideo, existing: nil)
        }.value
        try? await database.upsert(record)

        let photo = record.makePhoto()
        var updated = photos.filter { $0.id != photo.id }
        updated.append(photo)
        photos = updated.sorted { lhs, rhs in
            if lhs.effectiveDate != rhs.effectiveDate { return lhs.effectiveDate < rhs.effectiveDate }
            return lhs.fileName.localizedStandardCompare(rhs.fileName) == .orderedAscending
        }
    }

    /// Builds the up-to-date record for one file: re-reads the Finder-tag
    /// category (cheap) and reuses the cached metadata when size + mtime
    /// still match, extracting EXIF only for new/changed files. Runs on
    /// background tasks — never call from the main actor with many files.
    private nonisolated static func makeRecord(
        url: URL,
        folderPath: String,
        size: Int64,
        modified: Date,
        isVideo: Bool,
        existing: PhotoRecord?
    ) async -> PhotoRecord {
        let category = (try? TagService.readCategory(at: url)) ?? .unclassified

        if let existing, existing.fileSize == size, datesMatch(existing.fileModified, modified) {
            var updated = existing
            updated.category = category.rawValue
            return updated
        }

        let extracted = isVideo
            ? await MetadataService.extractVideo(from: url)
            : MetadataService.extract(from: url)
        let dateTaken = extracted.dateTaken
        let dateSource: DateSource = dateTaken != nil ? .exif : .fileModified
        let effectiveDate = dateTaken ?? modified
        return PhotoRecord(
            path: url.path,
            folderPath: folderPath,
            fileName: url.lastPathComponent,
            pixelWidth: extracted.pixelWidth,
            pixelHeight: extracted.pixelHeight,
            dateTaken: dateTaken,
            dateSource: dateSource.rawValue,
            effectiveDate: effectiveDate,
            cameraMake: extracted.cameraMake,
            cameraModel: extracted.cameraModel,
            fileSize: size,
            fileModified: modified,
            isVideo: isVideo,
            category: category.rawValue
        )
    }

    /// APFS mtimes carry nanoseconds, but the DB stores epoch seconds as a
    /// Double, which can't represent them exactly — exact `==` would treat
    /// every unchanged file as modified and re-extract its EXIF each scan.
    private nonisolated static func datesMatch(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSinceReferenceDate - b.timeIntervalSinceReferenceDate) < 0.001
    }

    func remove(fileAt url: URL) async {
        guard photos.contains(where: { $0.id == url.path }) else { return }
        photos.removeAll { $0.id == url.path }
        try? await database.deletePhotos(paths: [url.path])
    }
}
