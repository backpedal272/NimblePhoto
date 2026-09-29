import ImageIO
import UniformTypeIdentifiers

nonisolated enum SupportedImageTypes {
    /// Extensions we recognize up front (fast path, avoids opening every
    /// non-image file with ImageIO). ImageIO's own supported-type list is the
    /// final authority — see `isImage(at:)`.
    static let extensions: Set<String> = [
        "jpg", "jpeg", "png", "webp", "heic", "heif", "tiff", "tif",
        "cr2", "dng", "raf"
    ]

    static func hasImageExtension(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    /// RAW formats where decoding the embedded JPEG preview is far cheaper
    /// than a full RAW development (used by the full-size viewer).
    static let rawExtensions: Set<String> = ["cr2", "dng", "raf"]

    static func hasRawExtension(_ url: URL) -> Bool {
        rawExtensions.contains(url.pathExtension.lowercased())
    }

    /// Authoritative check: can ImageIO open this as an image at all?
    static func isImage(at url: URL) -> Bool {
        guard hasImageExtension(url) else { return false }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetType(source) != nil
    }
}
