import Foundation

/// Video files are recognized by extension only (unlike
/// `SupportedImageTypes.isImage`, there's no cheap authoritative probe —
/// validating playability means opening the asset with AVFoundation, which
/// happens lazily when the full-size viewer plays a video, not during
/// folder scans).
nonisolated enum SupportedVideoTypes {
    static let extensions: Set<String> = ["mp4", "mov", "m4v"]

    static func hasVideoExtension(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }
}
