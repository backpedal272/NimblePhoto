import AppKit
import ImageIO
import Vision

/// "Copy All Text": runs Vision OCR over whole photos and puts every
/// recognized line on the pasteboard. There is no manual selection — all
/// detected text is taken, in reading order. Read-only on the image files.
nonisolated enum TextRecognitionService {
    /// Longest edge the image is decoded at for OCR: large enough for small
    /// print, far cheaper than a full decode of a 45 MP photo.
    private static let maxPixel = 4096

    /// Recognizes text in each image path (videos are skipped) and copies
    /// the result to the general pasteboard. OCR takes a moment (longer on
    /// first use, while Vision loads its models), so progress and the
    /// outcome are reported in the status bar; beeps when nothing was found.
    @MainActor
    static func copyAllText(from paths: [String], appState: AppState) {
        let urls = paths.map { URL(fileURLWithPath: $0) }
            .filter { !SupportedVideoTypes.hasVideoExtension($0) }
        guard !urls.isEmpty else { NSSound.beep(); return }
        appState.showStatus("Recognizing text…", symbol: "text.viewfinder")
        Task {
            let texts = await Task.detached(priority: .userInitiated) {
                urls.compactMap { recognizeText(at: $0) }.filter { !$0.isEmpty }
            }.value
            guard !texts.isEmpty else {
                NSSound.beep()
                appState.showStatus("No text found", symbol: "text.viewfinder")
                return
            }
            let text = texts.joined(separator: "\n\n")
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            let lines = text.split(whereSeparator: \.isNewline).count
            appState.showStatus("Copied \(lines) line\(lines == 1 ? "" : "s") of text", symbol: "doc.on.clipboard")
        }
    }

    static func hasCopyableTarget(_ paths: [String]) -> Bool {
        paths.contains { !SupportedVideoTypes.hasVideoExtension(URL(fileURLWithPath: $0)) }
    }

    /// All text lines found in the image, top to bottom, or nil if the image
    /// couldn't be decoded.
    static func recognizeText(at url: URL) -> String? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            return nil
        }
        let observations = request.results ?? []
        // Vision's bounding boxes use a bottom-left origin: sort by top edge
        // descending, then left to right, to get reading order.
        let lines = observations
            .sorted {
                let a = $0.boundingBox, b = $1.boundingBox
                if abs(a.midY - b.midY) > min(a.height, b.height) / 2 { return a.midY > b.midY }
                return a.minX < b.minX
            }
            .compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}
