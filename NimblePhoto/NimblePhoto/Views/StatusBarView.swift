import SwiftUI

/// Info for the currently highlighted photo, plus transient error messages
/// (spec §7.4).
struct StatusBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(FolderContentsModel.self) private var contentsModel

    private var highlightedPhoto: Photo? {
        guard let id = appState.highlightedPhotoID else { return nil }
        return contentsModel.photos.first { $0.id == id }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        // Refreshes the category label after a rename in Settings.
        let _ = CategoryNamingTicker.shared.version
        HStack(spacing: 16) {
            if let message = appState.statusMessage {
                // Orange is retired in the Nimble palette (style guide §2):
                // the warning glyph carries the accent, the text stays primary.
                Label {
                    Text(message)
                } icon: {
                    Image(systemName: appState.statusSymbol ?? "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.nimbleBlue)
                }
                .lineLimit(1)
            } else if let photo = highlightedPhoto {
                if appState.selectedPhotoIDs.count > 1 {
                    Text("\(appState.selectedPhotoIDs.count) selected")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.nimbleBlue)
                }
                Text(photo.fileName).fontWeight(.medium)

                if let width = photo.pixelWidth, let height = photo.pixelHeight {
                    Text("\(width) × \(height)")
                }

                HStack(spacing: 4) {
                    Text(Self.dateFormatter.string(from: photo.effectiveDate))
                    if photo.dateSource == .fileModified {
                        Text("(file date)").italic().foregroundStyle(.secondary)
                    }
                }

                if let make = photo.cameraMake, let model = photo.cameraModel {
                    Text("\(make) \(model)")
                } else if let model = photo.cameraModel {
                    Text(model)
                }

                Spacer()

                Label(photo.category.displayName, systemImage: photo.category.symbolName)
                    .foregroundStyle(photo.category.color)
            } else {
                Text("No photo selected").foregroundStyle(.secondary)
                Spacer()
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}
