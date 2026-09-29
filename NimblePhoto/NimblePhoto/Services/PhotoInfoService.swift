import AVFoundation
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads everything the info panel shows: curated, human-formatted sections
/// (file, image, camera, exposure, dates, location, description) followed by
/// raw dumps of every ImageIO metadata dictionary. Read-only — never writes
/// to the file. File-system/decode bound; callers run it off the main actor.
nonisolated enum PhotoInfoService {
    typealias Row = PhotoInfo.Row
    typealias Section = PhotoInfo.Section

    static func info(for photo: Photo) async -> PhotoInfo {
        photo.isVideo ? await videoInfo(for: photo) : imageInfo(for: photo)
    }

    // MARK: - Images

    private static func imageInfo(for photo: Photo) -> PhotoInfo {
        var info = PhotoInfo()
        guard let source = CGImageSourceCreateWithURL(photo.fileURL as CFURL, nil) else {
            info.sections = [fileSection(for: photo, typeDescription: nil)]
            return info
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let exifAux = props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]

        let typeDescription = (CGImageSourceGetType(source) as String?)
            .flatMap { UTType($0)?.localizedDescription }

        info.exposureSummary = exposureSummary(exif: exif)
        info.coordinate = coordinate(gps: gps)

        var sections = [fileSection(for: photo, typeDescription: typeDescription)]
        sections.append(section("Image", "photo", imageRows(props: props, exif: exif, frameCount: CGImageSourceGetCount(source))))
        sections.append(section("Camera", "camera", cameraRows(exif: exif, exifAux: exifAux, tiff: tiff)))
        sections.append(section("Exposure", "camera.aperture", exposureRows(exif: exif)))
        sections.append(section("Dates", "calendar", dateRows(exif: exif, tiff: tiff)))
        sections.append(section("Location", "location", locationRows(gps: gps, coordinate: info.coordinate)))
        sections.append(section("Description", "text.alignleft", descriptionRows(tiff: tiff, iptc: iptc)))
        sections.append(contentsOf: rawSections(props))
        info.sections = sections.filter { !$0.rows.isEmpty }
        return info
    }

    private static func fileSection(for photo: Photo, typeDescription: String?) -> Section {
        var rows: [Row] = []
        rows.add("Name", photo.fileName)
        rows.add("Folder", photo.folderPath)
        rows.add("Kind", typeDescription)
        rows.add("Size", ByteCountFormatter.string(fromByteCount: photo.fileSize, countStyle: .file)
            + " (\(photo.fileSize.formatted()) bytes)")
        let created = (try? photo.fileURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate
        rows.add("Created", created.map(displayDate))
        rows.add("Modified", displayDate(photo.fileModified))
        return section("File", "doc", rows)
    }

    private static func imageRows(props: [CFString: Any], exif: [CFString: Any], frameCount: Int) -> [Row] {
        var rows: [Row] = []
        let width = int(props[kCGImagePropertyPixelWidth])
        let height = int(props[kCGImagePropertyPixelHeight])
        if let width, let height {
            let megapixels = Double(width * height) / 1_000_000
            rows.add("Dimensions", "\(width) × \(height) (\(megapixels.formatted(.number.precision(.fractionLength(1)))) MP)")
            rows.add("Aspect Ratio", aspectRatio(width, height))
        }
        if let orientation = int(props[kCGImagePropertyOrientation]) {
            rows.add("Orientation", orientationName(orientation))
        }
        if let dpi = double(props[kCGImagePropertyDPIWidth]) {
            rows.add("Resolution", "\(number(dpi)) dpi")
        }
        rows.add("Color Model", props[kCGImagePropertyColorModel] as? String)
        rows.add("Color Profile", props[kCGImagePropertyProfileName] as? String)
        if let colorSpace = int(exif[kCGImagePropertyExifColorSpace]) {
            rows.add("Color Space", colorSpace == 1 ? "sRGB" : colorSpace == 65535 ? "Uncalibrated" : "\(colorSpace)")
        }
        if let depth = int(props[kCGImagePropertyDepth]) {
            rows.add("Bit Depth", "\(depth) bits per channel")
        }
        if let hasAlpha = props[kCGImagePropertyHasAlpha] as? Bool {
            rows.add("Alpha Channel", hasAlpha ? "Yes" : "No")
        }
        if frameCount > 1 {
            rows.add("Images in File", "\(frameCount)")
        }
        return rows
    }

    private static func cameraRows(exif: [CFString: Any], exifAux: [CFString: Any], tiff: [CFString: Any]) -> [Row] {
        var rows: [Row] = []
        rows.add("Make", string(tiff[kCGImagePropertyTIFFMake]))
        rows.add("Model", string(tiff[kCGImagePropertyTIFFModel]))
        rows.add("Serial Number", string(exif[kCGImagePropertyExifBodySerialNumber]) ?? string(exifAux[kCGImagePropertyExifAuxSerialNumber]))
        rows.add("Lens Make", string(exif[kCGImagePropertyExifLensMake]))
        rows.add("Lens", string(exif[kCGImagePropertyExifLensModel]) ?? string(exifAux[kCGImagePropertyExifAuxLensModel]))
        if let spec = exif[kCGImagePropertyExifLensSpecification] as? [Double], spec.count == 4 {
            rows.add("Lens Specification", lensSpecification(spec))
        }
        rows.add("Lens Serial Number", string(exif[kCGImagePropertyExifLensSerialNumber]))
        rows.add("Software", string(tiff[kCGImagePropertyTIFFSoftware]))
        rows.add("Host Computer", string(tiff[kCGImagePropertyTIFFHostComputer]))
        return rows
    }

    private static func exposureRows(exif: [CFString: Any]) -> [Row] {
        var rows: [Row] = []
        rows.add("Exposure Time", double(exif[kCGImagePropertyExifExposureTime]).map(exposureTime))
        rows.add("Aperture", double(exif[kCGImagePropertyExifFNumber]).map { "ƒ/\(number($0))" })
        rows.add("ISO", iso(exif: exif).map { "\($0)" })
        rows.add("Focal Length", double(exif[kCGImagePropertyExifFocalLength]).map { "\(number($0)) mm" })
        rows.add("Focal Length (35mm)", int(exif[kCGImagePropertyExifFocalLenIn35mmFilm]).map { "\($0) mm" })
        rows.add("Exposure Bias", double(exif[kCGImagePropertyExifExposureBiasValue]).map(exposureBias))
        rows.add("Exposure Program", int(exif[kCGImagePropertyExifExposureProgram]).flatMap { lookup($0, exposurePrograms) })
        rows.add("Exposure Mode", int(exif[kCGImagePropertyExifExposureMode]).flatMap { lookup($0, [0: "Auto", 1: "Manual", 2: "Auto Bracket"]) })
        rows.add("Metering Mode", int(exif[kCGImagePropertyExifMeteringMode]).flatMap { lookup($0, meteringModes) })
        rows.add("Flash", int(exif[kCGImagePropertyExifFlash]).map(flashDescription))
        rows.add("White Balance", int(exif[kCGImagePropertyExifWhiteBalance]).flatMap { lookup($0, [0: "Auto", 1: "Manual"]) })
        rows.add("Light Source", int(exif[kCGImagePropertyExifLightSource]).flatMap { lookup($0, lightSources) })
        rows.add("Scene Type", int(exif[kCGImagePropertyExifSceneCaptureType]).flatMap { lookup($0, [0: "Standard", 1: "Landscape", 2: "Portrait", 3: "Night"]) })
        rows.add("Brightness", double(exif[kCGImagePropertyExifBrightnessValue]).map { "\(number($0)) EV" })
        rows.add("Subject Distance", double(exif[kCGImagePropertyExifSubjectDistance]).map { "\(number($0)) m" })
        if let zoom = double(exif[kCGImagePropertyExifDigitalZoomRatio]), zoom > 0, zoom != 1 {
            rows.add("Digital Zoom", "\(number(zoom))×")
        }
        rows.add("Contrast", int(exif[kCGImagePropertyExifContrast]).flatMap { lookup($0, [0: "Normal", 1: "Low", 2: "High"]) })
        rows.add("Saturation", int(exif[kCGImagePropertyExifSaturation]).flatMap { lookup($0, [0: "Normal", 1: "Low", 2: "High"]) })
        rows.add("Sharpness", int(exif[kCGImagePropertyExifSharpness]).flatMap { lookup($0, [0: "Normal", 1: "Soft", 2: "Hard"]) })
        return rows
    }

    private static func dateRows(exif: [CFString: Any], tiff: [CFString: Any]) -> [Row] {
        var rows: [Row] = []
        rows.add("Taken", exifDate(exif[kCGImagePropertyExifDateTimeOriginal], subsec: exif[kCGImagePropertyExifSubsecTimeOriginal]))
        rows.add("Digitized", exifDate(exif[kCGImagePropertyExifDateTimeDigitized], subsec: exif[kCGImagePropertyExifSubsecTimeDigitized]))
        rows.add("Edited", exifDate(tiff[kCGImagePropertyTIFFDateTime], subsec: exif[kCGImagePropertyExifSubsecTime]))
        rows.add("Time Zone", string(exif[kCGImagePropertyExifOffsetTimeOriginal]).map { "UTC\($0)" })
        return rows
    }

    private static func locationRows(gps: [CFString: Any], coordinate: PhotoInfo.Coordinate?) -> [Row] {
        var rows: [Row] = []
        if let coordinate {
            rows.add("Latitude", dms(coordinate.latitude, positive: "N", negative: "S"))
            rows.add("Longitude", dms(coordinate.longitude, positive: "E", negative: "W"))
            rows.add("Coordinates", String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude))
        }
        if let altitude = double(gps[kCGImagePropertyGPSAltitude]) {
            let below = int(gps[kCGImagePropertyGPSAltitudeRef]) == 1
            rows.add("Altitude", "\(number(altitude, digits: 1)) m \(below ? "below" : "above") sea level")
        }
        if let direction = double(gps[kCGImagePropertyGPSImgDirection]) {
            let reference = string(gps[kCGImagePropertyGPSImgDirectionRef]) == "M" ? "magnetic" : "true"
            rows.add("Direction", "\(number(direction, digits: 1))° \(reference) (\(compassPoint(direction)))")
        }
        if let speed = double(gps[kCGImagePropertyGPSSpeed]) {
            let unit = ["K": "km/h", "M": "mph", "N": "knots"][string(gps[kCGImagePropertyGPSSpeedRef]) ?? "K"] ?? "km/h"
            rows.add("Speed", "\(number(speed, digits: 1)) \(unit)")
        }
        rows.add("Accuracy", double(gps[kCGImagePropertyGPSHPositioningError]).map { "± \(number($0, digits: 1)) m" })
        if let date = string(gps[kCGImagePropertyGPSDateStamp]) {
            let time = string(gps[kCGImagePropertyGPSTimeStamp]).map { " \($0)" } ?? ""
            rows.add("GPS Time", "\(date)\(time) UTC")
        }
        return rows
    }

    private static func descriptionRows(tiff: [CFString: Any], iptc: [CFString: Any]) -> [Row] {
        var rows: [Row] = []
        rows.add("Title", string(iptc[kCGImagePropertyIPTCObjectName]))
        rows.add("Caption", string(iptc[kCGImagePropertyIPTCCaptionAbstract]) ?? string(tiff[kCGImagePropertyTIFFImageDescription]))
        rows.add("Keywords", (iptc[kCGImagePropertyIPTCKeywords] as? [String])?.joined(separator: ", "))
        rows.add("Artist", string(tiff[kCGImagePropertyTIFFArtist]) ?? (iptc[kCGImagePropertyIPTCByline] as? [String])?.joined(separator: ", "))
        rows.add("Copyright", string(tiff[kCGImagePropertyTIFFCopyright]) ?? string(iptc[kCGImagePropertyIPTCCopyrightNotice]))
        let place = [iptc[kCGImagePropertyIPTCCity], iptc[kCGImagePropertyIPTCProvinceState], iptc[kCGImagePropertyIPTCCountryPrimaryLocationName]]
            .compactMap(string)
        rows.add("Place", place.isEmpty ? nil : place.joined(separator: ", "))
        return rows
    }

    /// Every ImageIO dictionary ("{Exif}", "{TIFF}", "{MakerApple}", …) as
    /// sorted key/value rows, plus the top-level scalars under "General".
    private static func rawSections(_ props: [CFString: Any]) -> [Section] {
        var general: [Row] = []
        var sections: [Section] = []
        for (key, value) in props {
            let name = key as String
            if let dictionary = value as? [String: Any] {
                let title = name.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
                var rows: [Row] = []
                flatten(dictionary, prefix: "", into: &rows)
                sections.append(Section(title: title, symbolName: "list.bullet.rectangle", rows: rows.sorted { $0.label < $1.label }, isRaw: true))
            } else {
                general.append(Row(label: name, value: describe(value)))
            }
        }
        sections.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        if !general.isEmpty {
            sections.insert(Section(title: "General", symbolName: "list.bullet.rectangle", rows: general.sorted { $0.label < $1.label }, isRaw: true), at: 0)
        }
        return sections
    }

    private static func flatten(_ dictionary: [String: Any], prefix: String, into rows: inout [Row]) {
        for (key, value) in dictionary {
            let label = prefix.isEmpty ? key : "\(prefix).\(key)"
            if let nested = value as? [String: Any] {
                flatten(nested, prefix: label, into: &rows)
            } else {
                rows.append(Row(label: label, value: describe(value)))
            }
        }
    }

    private static func describe(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "Yes" : "No" }
            return self.number(number.doubleValue, digits: 4)
        case let array as [Any]:
            let items = array.prefix(32).map(describe)
            return items.joined(separator: ", ") + (array.count > 32 ? ", … (\(array.count) values)" : "")
        case let data as Data:
            return "\(data.count) bytes"
        default:
            return String(describing: value)
        }
    }

    // MARK: - Videos

    private static func videoInfo(for photo: Photo) async -> PhotoInfo {
        var info = PhotoInfo()
        let asset = AVURLAsset(url: photo.fileURL)
        let typeDescription = UTType(filenameExtension: photo.fileURL.pathExtension)?.localizedDescription
        var sections = [fileSection(for: photo, typeDescription: typeDescription)]

        var videoRows: [Row] = []
        if let duration = try? await asset.load(.duration), duration.isNumeric {
            videoRows.add("Duration", durationString(duration.seconds))
        }
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let (naturalSize, transform, frameRate, dataRate, formats) = try? await track.load(
               .naturalSize, .preferredTransform, .nominalFrameRate, .estimatedDataRate, .formatDescriptions) {
            let size = naturalSize.applying(transform)
            videoRows.add("Dimensions", "\(Int(abs(size.width))) × \(Int(abs(size.height)))")
            if frameRate > 0 { videoRows.add("Frame Rate", "\(number(Double(frameRate), digits: 2)) fps") }
            if dataRate > 0 { videoRows.add("Video Bitrate", bitrate(Double(dataRate))) }
            if let format = formats.first {
                videoRows.add("Video Codec", fourCC(CMFormatDescriptionGetMediaSubType(format)))
            }
        }
        if let track = try? await asset.loadTracks(withMediaType: .audio).first,
           let (dataRate, formats) = try? await track.load(.estimatedDataRate, .formatDescriptions) {
            if let format = formats.first {
                var codec = fourCC(CMFormatDescriptionGetMediaSubType(format))
                if let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                    codec += " · \(number(description.mSampleRate / 1000, digits: 1)) kHz · \(description.mChannelsPerFrame) ch"
                }
                videoRows.add("Audio", codec)
            }
            if dataRate > 0 { videoRows.add("Audio Bitrate", bitrate(Double(dataRate))) }
        }
        sections.append(section("Video", "film", videoRows))

        var metadataRows: [Row] = []
        if let item = try? await asset.load(.creationDate), let date = try? await item.load(.dateValue) {
            metadataRows.add("Recorded", displayDate(date))
        }
        let items = (try? await asset.load(.metadata)) ?? []
        for (identifier, label) in [(AVMetadataIdentifier.quickTimeMetadataMake, "Make"),
                                    (.quickTimeMetadataModel, "Model"),
                                    (.quickTimeMetadataSoftware, "Software")] {
            if let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first,
               let value = try? await item.load(.stringValue) {
                metadataRows.add(label, value)
            }
        }
        if let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .quickTimeMetadataLocationISO6709).first,
           let value = try? await item.load(.stringValue),
           let coordinate = iso6709Coordinate(value) {
            info.coordinate = coordinate
            metadataRows.add("Latitude", dms(coordinate.latitude, positive: "N", negative: "S"))
            metadataRows.add("Longitude", dms(coordinate.longitude, positive: "E", negative: "W"))
        }
        sections.append(section("Recording", "video", metadataRows))

        var rawRows: [Row] = []
        for item in items {
            guard let identifier = item.identifier?.rawValue,
                  let value = try? await item.load(.value) else { continue }
            rawRows.append(Row(label: identifier, value: describe(value)))
        }
        sections.append(Section(title: "Metadata", symbolName: "list.bullet.rectangle", rows: rawRows.sorted { $0.label < $1.label }, isRaw: true))

        info.sections = sections.filter { !$0.rows.isEmpty }
        return info
    }

    // MARK: - Formatting

    private static func section(_ title: String, _ symbolName: String, _ rows: [Row]) -> Section {
        Section(title: title, symbolName: symbolName, rows: rows)
    }

    private static func exposureSummary(exif: [CFString: Any]) -> String? {
        let parts = [
            double(exif[kCGImagePropertyExifFNumber]).map { "ƒ/\(number($0))" },
            double(exif[kCGImagePropertyExifExposureTime]).map(exposureTime),
            iso(exif: exif).map { "ISO \($0)" },
            (int(exif[kCGImagePropertyExifFocalLenIn35mmFilm]) ?? double(exif[kCGImagePropertyExifFocalLength]).map { Int($0.rounded()) })
                .map { "\($0) mm" }
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func iso(exif: [CFString: Any]) -> Int? {
        (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first
    }

    private static func coordinate(gps: [CFString: Any]) -> PhotoInfo.Coordinate? {
        guard var latitude = double(gps[kCGImagePropertyGPSLatitude]),
              var longitude = double(gps[kCGImagePropertyGPSLongitude]) else { return nil }
        if string(gps[kCGImagePropertyGPSLatitudeRef]) == "S" { latitude = -latitude }
        if string(gps[kCGImagePropertyGPSLongitudeRef]) == "W" { longitude = -longitude }
        return PhotoInfo.Coordinate(latitude: latitude, longitude: longitude)
    }

    /// Parses the leading "±DD.DDDD±DDD.DDDD" of an ISO 6709 location string.
    private static func iso6709Coordinate(_ value: String) -> PhotoInfo.Coordinate? {
        guard let match = value.firstMatch(of: /^([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)/),
              let latitude = Double(match.1), let longitude = Double(match.2) else { return nil }
        return PhotoInfo.Coordinate(latitude: latitude, longitude: longitude)
    }

    private static func exposureTime(_ seconds: Double) -> String {
        guard seconds > 0 else { return "0 s" }
        if seconds < 1 { return "1/\(Int((1 / seconds).rounded())) s" }
        return "\(number(seconds, digits: 1)) s"
    }

    private static func exposureBias(_ value: Double) -> String {
        value == 0 ? "0 EV" : "\(value > 0 ? "+" : "−")\(number(abs(value), digits: 2)) EV"
    }

    private static func lensSpecification(_ spec: [Double]) -> String {
        let focal = spec[0] == spec[1] ? "\(number(spec[0])) mm" : "\(number(spec[0]))–\(number(spec[1])) mm"
        let aperture = spec[2] == spec[3] ? "ƒ/\(number(spec[2]))" : "ƒ/\(number(spec[2]))–\(number(spec[3]))"
        return "\(focal) \(aperture)"
    }

    private static func flashDescription(_ value: Int) -> String {
        var parts = [value & 0x1 != 0 ? "Fired" : "Did not fire"]
        switch (value >> 3) & 0x3 {
        case 1: parts.append("forced on")
        case 2: parts.append("forced off")
        case 3: parts.append("auto")
        default: break
        }
        if value & 0x40 != 0 { parts.append("red-eye reduction") }
        if value & 0x20 != 0 { parts = ["No flash"] }
        return parts.joined(separator: ", ")
    }

    private static let exposurePrograms = [
        0: "Not Defined", 1: "Manual", 2: "Program", 3: "Aperture Priority", 4: "Shutter Priority",
        5: "Creative", 6: "Action", 7: "Portrait", 8: "Landscape"
    ]
    private static let meteringModes = [
        0: "Unknown", 1: "Average", 2: "Center-Weighted", 3: "Spot", 4: "Multi-Spot",
        5: "Pattern", 6: "Partial", 255: "Other"
    ]
    private static let lightSources = [
        0: "Unknown", 1: "Daylight", 2: "Fluorescent", 3: "Tungsten", 4: "Flash", 9: "Fine Weather",
        10: "Cloudy", 11: "Shade", 17: "Standard Light A", 18: "Standard Light B", 19: "Standard Light C",
        20: "D55", 21: "D65", 22: "D75", 23: "D50", 24: "ISO Studio Tungsten", 255: "Other"
    ]

    private static func lookup(_ value: Int, _ table: [Int: String]) -> String? {
        table[value] ?? "\(value)"
    }

    private static func orientationName(_ value: Int) -> String {
        let names = [1: "Normal", 2: "Mirrored", 3: "Rotated 180°", 4: "Mirrored, rotated 180°",
                     5: "Mirrored, rotated 90° CCW", 6: "Rotated 90° CW", 7: "Mirrored, rotated 90° CW", 8: "Rotated 90° CCW"]
        return names[value].map { "\($0) (\(value))" } ?? "\(value)"
    }

    private static func aspectRatio(_ width: Int, _ height: Int) -> String {
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let divisor = max(gcd(width, height), 1)
        let (w, h) = (width / divisor, height / divisor)
        if w <= 32 && h <= 32 { return "\(w):\(h)" }
        return "\(number(Double(width) / Double(height), digits: 3)):1"
    }

    private static func dms(_ value: Double, positive: String, negative: String) -> String {
        let absolute = abs(value)
        let degrees = Int(absolute)
        let minutesFull = (absolute - Double(degrees)) * 60
        let minutes = Int(minutesFull)
        let seconds = (minutesFull - Double(minutes)) * 60
        return String(format: "%d° %d′ %.2f″ %@", degrees, minutes, seconds, value >= 0 ? positive : negative)
    }

    private static func compassPoint(_ degrees: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int(((degrees.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45).rounded(.down)) % 8
        return points[index]
    }

    private static func durationString(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: seconds) ?? "\(number(seconds, digits: 1)) s"
    }

    private static func bitrate(_ bitsPerSecond: Double) -> String {
        bitsPerSecond >= 1_000_000
            ? "\(number(bitsPerSecond / 1_000_000, digits: 1)) Mbps"
            : "\(number(bitsPerSecond / 1000, digits: 0)) kbps"
    }

    private static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        let text = String(bytes: bytes, encoding: .macOSRoman)?.trimmingCharacters(in: .whitespaces) ?? "\(code)"
        let names = ["avc1": "H.264", "hvc1": "HEVC", "hev1": "HEVC", "ap4h": "ProRes 4444", "apch": "ProRes 422 HQ",
                     "apcn": "ProRes 422", "apcs": "ProRes 422 LT", "apco": "ProRes 422 Proxy", "mp4v": "MPEG-4",
                     "aac": "AAC", "lpcm": "PCM", "alac": "Apple Lossless", "ac-3": "AC-3", "ec-3": "E-AC-3"]
        return names[text].map { "\($0) (\(text))" } ?? text
    }

    private static let exifDateParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static func exifDate(_ raw: Any?, subsec: Any?) -> String? {
        guard let raw = string(raw) else { return nil }
        guard let date = exifDateParser.date(from: raw) else { return raw }
        var text = displayDate(date)
        if let subsec = string(subsec) { text += " (+.\(subsec) s)" }
        return text
    }

    private static func displayDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }

    private static func number(_ value: Double, digits: Int = 2) -> String {
        value.formatted(.number.precision(.fractionLength(0...digits)).grouping(.never))
    }

    private static func string(_ value: Any?) -> String? {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else { return nil }
        return string
    }

    private static func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}

nonisolated private extension Array where Element == PhotoInfo.Row {
    /// Appends a row only when there is something to show.
    mutating func add(_ label: String, _ value: String?) {
        guard let value, !value.isEmpty else { return }
        append(PhotoInfo.Row(label: label, value: value))
    }
}
