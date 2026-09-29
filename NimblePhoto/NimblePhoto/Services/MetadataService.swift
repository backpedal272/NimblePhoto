import AVFoundation
import Foundation
import ImageIO

/// Extracts pixel dimensions, capture date, and camera make/model — via
/// ImageIO for photos (`extract`) and AVFoundation for videos
/// (`extractVideo`). File-system/decode bound; callers run it off the main
/// actor.
nonisolated enum MetadataService {
    struct Extracted {
        var pixelWidth: Int?
        var pixelHeight: Int?
        var dateTaken: Date?
        var cameraMake: String?
        var cameraModel: String?
    }

    private static let exifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    static func extract(from url: URL) -> Extracted {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return Extracted()
        }

        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int

        var dateTaken: Date?
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            dateTaken = exifDateFormatter.date(from: raw)
        }

        var make: String?
        var model: String?
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            make = tiff[kCGImagePropertyTIFFMake] as? String
            model = tiff[kCGImagePropertyTIFFModel] as? String
        }

        return Extracted(
            pixelWidth: width,
            pixelHeight: height,
            dateTaken: dateTaken,
            cameraMake: make,
            cameraModel: model
        )
    }

    /// Video counterpart of `extract`: recording date from the asset's
    /// creation-date metadata (so videos sort by capture date like photos,
    /// not by file mtime) and display dimensions from the video track.
    static func extractVideo(from url: URL) async -> Extracted {
        let asset = AVURLAsset(url: url)

        var dateTaken: Date?
        if let item = try? await asset.load(.creationDate) {
            dateTaken = try? await item.load(.dateValue)
        }

        var width: Int?
        var height: Int?
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let (naturalSize, transform) = try? await track.load(.naturalSize, .preferredTransform) {
            let size = naturalSize.applying(transform)
            width = Int(abs(size.width))
            height = Int(abs(size.height))
        }

        return Extracted(pixelWidth: width, pixelHeight: height, dateTaken: dateTaken)
    }
}
