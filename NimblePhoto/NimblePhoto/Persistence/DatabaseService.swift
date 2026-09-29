import Foundation
import SQLite3

/// SQLite-backed cache of photo metadata. Disposable by design: deleting the
/// database file and relaunching must fully restore behavior via re-scanning
/// (spec §11, §15.12). All access is serialized through this actor.
actor DatabaseService {
    // SQLite serializes its own access (opened with SQLITE_OPEN_FULLMUTEX),
    // and every access outside `init` goes through this actor's isolated
    // methods anyway, so the raw handle itself is safe to touch from the
    // nonisolated helpers below (needed so `init` can call them before
    // `self` is actor-isolated).
    private nonisolated(unsafe) var db: OpaquePointer?
    private static let currentSchemaVersion: Int32 = 3

    static func containerURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("NimblePhoto", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("index.sqlite")
    }

    init(fileURL: URL) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(fileURL.path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            throw DatabaseError.openFailed(message)
        }
        db = handle
        do {
            try exec("PRAGMA journal_mode=WAL;")
            try exec("PRAGMA foreign_keys=ON;")
            try verifyIntegrity()
            try migrate()
        } catch {
            // A throwing init never runs deinit, so close here or the
            // handle leaks.
            sqlite3_close(handle)
            db = nil
            throw error
        }
    }

    /// Opens the database; if that fails for any reason — including a
    /// corrupt file caught by `PRAGMA quick_check` — deletes the database
    /// files and builds a fresh one. The DB is a disposable cache by design
    /// (spec §11): recreating and re-scanning fully restores behavior,
    /// whereas failing here would mean crashing at launch.
    static func openRecreatingIfNeeded(fileURL: URL) throws -> DatabaseService {
        do {
            return try DatabaseService(fileURL: fileURL)
        } catch {
            removeDatabaseFiles(at: fileURL)
            return try DatabaseService(fileURL: fileURL)
        }
    }

    private static func removeDatabaseFiles(at fileURL: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: fileURL.path + suffix))
        }
    }

    deinit {
        sqlite3_close(db)
    }

    enum DatabaseError: Error {
        case openFailed(String)
        case execFailed(String)
        case prepareFailed(String)
        case stepFailed(String)
        case corrupt(String)
    }

    /// `PRAGMA quick_check` catches malformed databases that nonetheless
    /// open successfully; anything but a single "ok" row is corruption.
    private nonisolated func verifyIntegrity() throws {
        let stmt = try prepare("PRAGMA quick_check(1);")
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let message = sqlite3_column_text(stmt, 0).map({ String(cString: $0) })
        else { throw DatabaseError.corrupt("quick_check returned no result") }
        guard message.caseInsensitiveCompare("ok") == .orderedSame else {
            throw DatabaseError.corrupt(message)
        }
    }

    private nonisolated func migrate() throws {
        var userVersion: Int32 = 0
        let stmt = try prepare("PRAGMA user_version;")
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            userVersion = sqlite3_column_int(stmt, 0)
        }
        guard userVersion < Self.currentSchemaVersion else { return }

        try exec("""
            CREATE TABLE IF NOT EXISTS photos (
                path TEXT PRIMARY KEY,
                folderPath TEXT NOT NULL,
                fileName TEXT NOT NULL,
                pixelWidth INTEGER,
                pixelHeight INTEGER,
                dateTaken REAL,
                dateSource TEXT NOT NULL,
                effectiveDate REAL NOT NULL,
                cameraMake TEXT,
                cameraModel TEXT,
                fileSize INTEGER NOT NULL,
                fileModified REAL NOT NULL,
                isVideo INTEGER NOT NULL DEFAULT 0,
                category INTEGER NOT NULL
            );
            """)
        try exec("CREATE INDEX IF NOT EXISTS idx_photos_folder ON photos(folderPath);")
        try exec("CREATE INDEX IF NOT EXISTS idx_photos_effectiveDate ON photos(effectiveDate);")

        if userVersion > 0 {
            if userVersion < 2 {
                // Upgrading from schema v1: the table already existed without
                // isVideo, so CREATE TABLE IF NOT EXISTS above was a no-op.
                try? exec("ALTER TABLE photos ADD COLUMN isVideo INTEGER NOT NULL DEFAULT 0;")
            }
            if userVersion < 3 {
                // v3 adds no columns; cached video rows are dropped once so
                // their capture date (now read via AVFoundation) and pixel
                // dimensions get re-extracted on the next folder scan.
                try? exec("DELETE FROM photos WHERE isVideo = 1;")
            }
        }

        try exec("PRAGMA user_version = \(Self.currentSchemaVersion);")
    }

    // MARK: - Low-level helpers

    private nonisolated func exec(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &errorPointer) != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errorPointer)
            throw DatabaseError.execFailed(message)
        }
    }

    private nonisolated func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        return stmt
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, Self.sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindDouble(_ stmt: OpaquePointer?, _ index: Int32, _ value: Date?) {
        if let value {
            sqlite3_bind_double(stmt, index, value.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    // MARK: - Queries

    func upsert(_ record: PhotoRecord) throws {
        let sql = """
            INSERT INTO photos
                (path, folderPath, fileName, pixelWidth, pixelHeight, dateTaken,
                 dateSource, effectiveDate, cameraMake, cameraModel, fileSize,
                 fileModified, isVideo, category)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)
            ON CONFLICT(path) DO UPDATE SET
                folderPath=excluded.folderPath,
                fileName=excluded.fileName,
                pixelWidth=excluded.pixelWidth,
                pixelHeight=excluded.pixelHeight,
                dateTaken=excluded.dateTaken,
                dateSource=excluded.dateSource,
                effectiveDate=excluded.effectiveDate,
                cameraMake=excluded.cameraMake,
                cameraModel=excluded.cameraModel,
                fileSize=excluded.fileSize,
                fileModified=excluded.fileModified,
                isVideo=excluded.isVideo,
                category=excluded.category;
            """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, record.path)
        bindText(stmt, 2, record.folderPath)
        bindText(stmt, 3, record.fileName)
        if let w = record.pixelWidth { sqlite3_bind_int(stmt, 4, Int32(w)) } else { sqlite3_bind_null(stmt, 4) }
        if let h = record.pixelHeight { sqlite3_bind_int(stmt, 5, Int32(h)) } else { sqlite3_bind_null(stmt, 5) }
        bindDouble(stmt, 6, record.dateTaken)
        bindText(stmt, 7, record.dateSource)
        bindDouble(stmt, 8, record.effectiveDate)
        bindText(stmt, 9, record.cameraMake)
        bindText(stmt, 10, record.cameraModel)
        sqlite3_bind_int64(stmt, 11, record.fileSize)
        bindDouble(stmt, 12, record.fileModified)
        sqlite3_bind_int(stmt, 13, record.isVideo ? 1 : 0)
        sqlite3_bind_int(stmt, 14, Int32(record.category))
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func updateCategory(path: String, category: Int) throws {
        let stmt = try prepare("UPDATE photos SET category = ?1 WHERE path = ?2;")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(category))
        bindText(stmt, 2, path)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func deletePhotos(paths: [String]) throws {
        guard !paths.isEmpty else { return }
        for path in paths {
            let stmt = try prepare("DELETE FROM photos WHERE path = ?1;")
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, path)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    /// Removes rows for `folderPath` whose path isn't in `keepPaths`, i.e.
    /// files that disappeared from disk since the last scan.
    func pruneFolder(folderPath: String, keepPaths: Set<String>) throws {
        let existing = try photos(inFolder: folderPath)
        let toDelete = existing.map(\.path).filter { !keepPaths.contains($0) }
        try deletePhotos(paths: toDelete)
    }

    func photos(inFolder folderPath: String) throws -> [PhotoRecord] {
        let stmt = try prepare("SELECT path, folderPath, fileName, pixelWidth, pixelHeight, dateTaken, dateSource, effectiveDate, cameraMake, cameraModel, fileSize, fileModified, isVideo, category FROM photos WHERE folderPath = ?1;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, folderPath)

        var results: [PhotoRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(readRecord(from: stmt))
        }
        return results
    }

    func photo(path: String) throws -> PhotoRecord? {
        let stmt = try prepare("SELECT path, folderPath, fileName, pixelWidth, pixelHeight, dateTaken, dateSource, effectiveDate, cameraMake, cameraModel, fileSize, fileModified, isVideo, category FROM photos WHERE path = ?1;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, path)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return readRecord(from: stmt)
    }

    private func readRecord(from stmt: OpaquePointer?) -> PhotoRecord {
        let path = String(cString: sqlite3_column_text(stmt, 0))
        let folderPath = String(cString: sqlite3_column_text(stmt, 1))
        let fileName = String(cString: sqlite3_column_text(stmt, 2))
        let pixelWidth = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 3))
        let pixelHeight = sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 4))
        let dateTaken = sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
        let dateSource = String(cString: sqlite3_column_text(stmt, 6))
        let effectiveDate = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
        let cameraMake = sqlite3_column_type(stmt, 8) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 8))
        let cameraModel = sqlite3_column_type(stmt, 9) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 9))
        let fileSize = sqlite3_column_int64(stmt, 10)
        let fileModified = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 11))
        let isVideo = sqlite3_column_int(stmt, 12) != 0
        let category = Int(sqlite3_column_int(stmt, 13))
        return PhotoRecord(
            path: path, folderPath: folderPath, fileName: fileName,
            pixelWidth: pixelWidth, pixelHeight: pixelHeight,
            dateTaken: dateTaken, dateSource: dateSource, effectiveDate: effectiveDate,
            cameraMake: cameraMake, cameraModel: cameraModel,
            fileSize: fileSize, fileModified: fileModified, isVideo: isVideo, category: category
        )
    }
}
