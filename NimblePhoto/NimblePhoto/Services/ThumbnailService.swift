import AppKit
import AVFoundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Generates and caches square-fit thumbnails via ImageIO (photos) or
/// AVFoundation (a representative frame, for videos). Thumbnails are
/// generated once at `maxPixelSize` and cached on disk keyed by a hash of
/// path + mtime + size, so edits invalidate the cache automatically
/// (spec §10.2). Concurrency is bounded so huge folders don't exhaust memory.
actor ThumbnailService {
    /// Generate at the largest supported grid cell size; smaller cells
    /// downscale in-view rather than regenerating (spec §10.2).
    static let maxPixelSize = 400

    private let cacheDirectory: URL
    private let maxConcurrentGenerations = 6
    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(cacheDirectory: URL) {
        self.cacheDirectory = cacheDirectory
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    static func containerCacheDirectory() throws -> URL {
        let caches = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return caches.appendingPathComponent("NimblePhoto/thumbnails", isDirectory: true)
    }

    private func cacheKey(path: String, fileModified: Date, fileSize: Int64) -> String {
        let input = "\(path)|\(fileModified.timeIntervalSince1970)|\(fileSize)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func cachedThumbnailURL(path: String, fileModified: Date, fileSize: Int64) -> URL? {
        let url = cacheDirectory.appendingPathComponent(cacheKey(path: path, fileModified: fileModified, fileSize: fileSize) + ".jpg")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Generates (or returns the cached) thumbnail for a photo or video,
    /// respecting a bounded number of concurrent generations.
    func thumbnail(for sourceURL: URL, path: String, fileModified: Date, fileSize: Int64, isVideo: Bool = false) async -> URL? {
        if let cached = cachedThumbnailURL(path: path, fileModified: fileModified, fileSize: fileSize) {
            return cached
        }
        await acquireSlot()
        defer { releaseSlot() }

        // Re-check after waiting: another task may have generated it while we queued.
        if let cached = cachedThumbnailURL(path: path, fileModified: fileModified, fileSize: fileSize) {
            return cached
        }

        let destinationURL = cacheDirectory.appendingPathComponent(cacheKey(path: path, fileModified: fileModified, fileSize: fileSize) + ".jpg")

        // Decode + encode in a detached task so the actor is only suspended,
        // not blocked: otherwise every generation serializes through the
        // actor and the concurrency limit above never allows parallelism.
        return await Task.detached(priority: .userInitiated) { () -> URL? in
            let thumbnailImage: CGImage?
            if isVideo {
                thumbnailImage = await Self.videoFrame(from: sourceURL)
            } else {
                thumbnailImage = Self.imageFrame(from: sourceURL)
            }
            guard let thumbnailImage else { return nil }

            guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
                return nil
            }
            CGImageDestinationAddImage(destination, thumbnailImage, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return destinationURL
        }.value
    }

    private nonisolated static func imageFrame(from sourceURL: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Grabs a representative frame a little into the clip (rather than
    /// frame 0, which is often black/blank) via `AVAssetImageGenerator`:
    /// 1s in, or for shorter clips just before the end — zero-tolerance
    /// generation at the exact end boundary can fail.
    private nonisolated static func videoFrame(from sourceURL: URL) async -> CGImage? {
        let asset = AVURLAsset(url: sourceURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        var target = 1.0
        if let duration = try? await asset.load(.duration),
           duration.seconds.isFinite, duration.seconds > 0 {
            target = min(1.0, max(0, duration.seconds - 0.05))
        }
        let time = CMTime(seconds: target, preferredTimescale: 600)
        return try? await generator.image(at: time).image
    }

    private func acquireSlot() async {
        if activeCount < maxConcurrentGenerations {
            activeCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        activeCount += 1
    }

    private func releaseSlot() {
        activeCount -= 1
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        }
    }
}
