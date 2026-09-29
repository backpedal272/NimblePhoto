import AppKit
import SwiftUI

/// Right-hand inspector with detailed EXIF / file / video metadata for the
/// highlighted photo. Lives beside both the grid and the full-size viewer,
/// so it follows the highlight in either; toggled with ⌘I, "i", or the
/// toolbar button.
struct InfoPanelView: View {
    @Environment(AppState.self) private var appState
    @Environment(FolderContentsModel.self) private var contentsModel

    @State private var info: PhotoInfo?
    @State private var loadedPhotoID: String?
    /// Sections whose disclosure state differs from the default (curated
    /// sections open, raw dumps closed), persisted as a "|"-joined list.
    @AppStorage(SettingsKeys.infoPanelToggledSections) private var toggledSectionsStorage = ""

    private var photo: Photo? {
        guard let id = appState.highlightedPhotoID else { return nil }
        return contentsModel.photos.first { $0.id == id }
    }

    var body: some View {
        Group {
            if let photo {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header(for: photo)
                        Divider()
                        sections
                            // Keep the previous photo's data on screen (dimmed)
                            // while the next loads, instead of flashing empty.
                            .opacity(loadedPhotoID == photo.id ? 1 : 0.4)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .task(id: InfoKey(photo: photo)) {
                    let loaded = await Task.detached(priority: .userInitiated) {
                        await PhotoInfoService.info(for: photo)
                    }.value
                    guard !Task.isCancelled else { return }
                    info = loaded
                    loadedPhotoID = photo.id
                }
            } else {
                ContentUnavailableView("No Photo Selected", systemImage: "info.circle",
                                       description: Text("Select a photo to see its details."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private func header(for photo: Photo) -> some View {
        // Refreshes the category label after a rename in Settings.
        let _ = CategoryNamingTicker.shared.version
        return VStack(alignment: .leading, spacing: 6) {
            Text(photo.fileName)
                .font(.headline)
                .lineLimit(3)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                Label(photo.category.displayName, systemImage: photo.category.symbolName)
                    .foregroundStyle(photo.category.color)
                if appState.selectedPhotoIDs.count > 1 {
                    Text("· 1 of \(appState.selectedPhotoIDs.count) selected")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)

            if loadedPhotoID == photo.id, let summary = info?.exposureSummary {
                Text(summary)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.nimbleDeepBlue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.nimbleBlue.opacity(0.12), in: Capsule())
                    .textSelection(.enabled)
            }

            if loadedPhotoID == photo.id, let coordinate = info?.coordinate {
                Button {
                    openInMaps(coordinate)
                } label: {
                    Label("Show in Maps", systemImage: "map")
                }
                .buttonStyle(.link)
                .font(.callout)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var sections: some View {
        if let info {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(info.sections) { section in
                    DisclosureGroup(isExpanded: expansionBinding(for: section)) {
                        rows(for: section)
                            .padding(.top, 6)
                            .padding(.leading, 4)
                    } label: {
                        Label(section.title, systemImage: section.symbolName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(section.isRaw ? .secondary : .primary)
                    }
                }
            }
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func rows(for section: PhotoInfo.Section) -> some View {
        if section.isRaw {
            // Raw keys can be long ("MakerApple.14"), so stack label over value.
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(row.value)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(6)
                    }
                }
            }
            .textSelection(.enabled)
        } else {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(row.label)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        Text(row.value)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.callout)
            .textSelection(.enabled)
        }
    }

    private var toggledSections: Set<String> {
        Set(toggledSectionsStorage.split(separator: "|").map(String.init))
    }

    private func expansionBinding(for section: PhotoInfo.Section) -> Binding<Bool> {
        Binding(
            get: { toggledSections.contains(section.id) != !section.isRaw },
            set: { expanded in
                var toggled = toggledSections
                if expanded == !section.isRaw {
                    toggled.remove(section.id)
                } else {
                    toggled.insert(section.id)
                }
                toggledSectionsStorage = toggled.sorted().joined(separator: "|")
            }
        )
    }

    private func openInMaps(_ coordinate: PhotoInfo.Coordinate) {
        let ll = String(format: "%.6f,%.6f", coordinate.latitude, coordinate.longitude)
        if let url = URL(string: "https://maps.apple.com/?ll=\(ll)&q=\(ll)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Reloads when the highlight moves or the file changes on disk.
private struct InfoKey: Equatable {
    let id: String
    let modified: Date
    let size: Int64

    init(photo: Photo) {
        id = photo.id
        modified = photo.fileModified
        size = photo.fileSize
    }
}
