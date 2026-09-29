import AppKit
import ImageIO

/// Decodes viewer images fast: downsampled to the screen's pixel size via
/// ImageIO (decoding a 45 MP photo at display resolution is several times
/// faster than a full decode, and RAW files use their embedded JPEG preview
/// instead of a full RAW development), kept in a small LRU cache, with
/// neighbors prefetched so arrow-key navigation feels instant. The decoded
/// bitmap is wrapped in an `NSImage` whose logical `size` is the photo's
/// full pixel dimensions, so the viewer's fit/zoom math is independent of
/// how many pixels were actually decoded.
actor FullSizeImageLoader {
    struct Loaded: @unchecked Sendable {
        let image: NSImage
        /// False when the bitmap is downsampled; the viewer requests a
        /// full-resolution decode on top when the user zooms in.
        let isFullResolution: Bool
    }

    private let maxCached = 5
    private var cache: [String: Loaded] = [:]
    private var cacheOrder: [String] = []
    private var inFlight: [String: Task<Loaded?, Never>] = [:]

    private static func cacheKey(_ photo: Photo) -> String {
        "\(photo.id)|\(photo.fileModified.timeIntervalSinceReferenceDate)"
    }

    /// Screen-resolution image for fit-to-window display, from cache when
    /// possible.
    func fitImage(for photo: Photo, maxPixel: Int) async -> Loaded? {
        let key = Self.cacheKey(photo)
        if let hit = cache[key] {
            touch(key)
            return hit
        }
        let task: Task<Loaded?, Never>
        if let existing = inFlight[key] {
            task = existing
        } else {
            let url = photo.fileURL
            task = Task.detached(priority: .userInitiated) {
                Self.decode(url: url, maxPixel: maxPixel)
            }
            inFlight[key] = task
        }
        let loaded = await task.value
        inFlight[key] = nil
        if let loaded { store(key, loaded) }
        return loaded
    }

    /// Warms the cache for photos the user is likely to navigate to next.
    func prefetch(_ photos: [Photo], maxPixel: Int) {
        for photo in photos where !photo.isVideo {
            let key = Self.cacheKey(photo)
            guard cache[key] == nil, inFlight[key] == nil else { continue }
            let url = photo.fileURL
            let task = Task.detached(priority: .utility) {
                Self.decode(url: url, maxPixel: maxPixel)
            }
            inFlight[key] = task
            Task {
                let loaded = await task.value
                inFlight[key] = nil
                if let loaded { store(key, loaded) }
            }
        }
    }

    /// Full-resolution decode for 100%/zoom mode. Deliberately not cached —
    /// a 60 MP image is hundreds of MB decoded; the fit-size cache is what
    /// keeps navigation fast.
    nonisolated func fullImage(for photo: Photo) async -> Loaded? {
        let url = photo.fileURL
        return await Task.detached(priority: .userInitiated) {
            Self.decode(url: url, maxPixel: nil)
        }.value
    }

    // MARK: - Cache bookkeeping

    private func store(_ key: String, _ loaded: Loaded) {
        cache[key] = loaded
        touch(key)
        while cacheOrder.count > maxCached, let oldest = cacheOrder.first {
            cacheOrder.removeFirst()
            cache[oldest] = nil
        }
    }

    private func touch(_ key: String) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
    }

    // MARK: - Decoding

    /// `maxPixel == nil` means full resolution. The thumbnail API is used
    /// for both tiers because it honors the EXIF orientation transform and
    /// supports downsampled decoding.
    private nonisolated static func decode(url: URL, maxPixel: Int?) -> Loaded? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        var pixelWidth = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        var pixelHeight = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        // EXIF orientations 5–8 are 90°-rotated: displayed dimensions swap.
        if let orientation = properties?[kCGImagePropertyOrientation] as? UInt32, orientation >= 5 {
            swap(&pixelWidth, &pixelHeight)
        }
        let longSide = max(pixelWidth, pixelHeight)
        let target = maxPixel ?? (longSide > 0 ? longSide : 16_384)

        // RAW: prefer the embedded preview (usually a full-size JPEG) over a
        // slow RAW development. Fall back to a real decode if the file's
        // embedded preview turns out to be tiny.
        let preferEmbeddedPreview = SupportedImageTypes.hasRawExtension(url)
        var cgImage = createThumbnail(source: source, maxPixel: target, fromImageAlways: !preferEmbeddedPreview)
        if preferEmbeddedPreview,
           let candidate = cgImage,
           max(candidate.width, candidate.height) < min(target, longSide > 0 ? longSide : target) / 2 {
            cgImage = createThumbnail(source: source, maxPixel: target, fromImageAlways: true) ?? candidate
        }
        guard let cgImage else { return nil }

        let displaySize = (pixelWidth > 0 && pixelHeight > 0)
            ? NSSize(width: pixelWidth, height: pixelHeight)
            : NSSize(width: cgImage.width, height: cgImage.height)
        // Small tolerance: ImageIO can round the requested size down a pixel.
        let isFull = max(cgImage.width, cgImage.height) + 4 >= max(Int(displaySize.width), Int(displaySize.height))
        return Loaded(image: NSImage(cgImage: cgImage, size: displaySize), isFullResolution: isFull)
    }

    private nonisolated static func createThumbnail(source: CGImageSource, maxPixel: Int, fromImageAlways: Bool) -> CGImage? {
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        options[fromImageAlways ? kCGImageSourceCreateThumbnailFromImageAlways : kCGImageSourceCreateThumbnailFromImageIfAbsent] = true
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
