import AppKit
import SwiftUI

/// Right-click menu shared by the thumbnail grid and the full-size viewer:
/// one item per category, then "Show in Finder". `targets` are the photo
/// paths the menu acts on.
struct PhotoContextMenu: View {
    let targets: [String]
    let onClassify: (Category, [String]) -> Void

    var body: some View {
        ForEach(Category.allCases) { category in
            Button {
                onClassify(category, targets)
            } label: {
                Label(category.displayName, systemImage: category.symbolName)
            }
        }
        Divider()
        Button {
            NSWorkspace.shared.activateFileViewerSelecting(targets.map { URL(fileURLWithPath: $0) })
        } label: {
            Label("Show in Finder", systemImage: "finder")
        }
    }
}
