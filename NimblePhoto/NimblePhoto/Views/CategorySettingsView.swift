import SwiftUI

/// `⌘,` Settings window content: lists all 5 categories for renaming.
/// `Unclassified` is shown read-only — its name and tag are fixed.
struct CategorySettingsView: View {
    @Environment(RootFolderStore.self) private var rootFolderStore

    /// Unclassified listed first here since it's the fixed, always-present default;
    /// the rest keep their spec order.
    private static let displayOrder: [Category] = [.unclassified, .delete, .keep, .star, .select]

    var body: some View {
        Form {
            Section {
                LabeledContent("Folder") {
                    HStack {
                        Text(rootFolderStore.rootURL?.path ?? "None selected")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(rootFolderStore.rootURL == nil ? "Select…" : "Change…") {
                            rootFolderStore.presentPicker()
                        }
                    }
                }
            } header: {
                SectionHeader(
                    title: "Root Folder",
                    subtitle: "The folder Nimble Photo scans for photos and subfolders."
                )
            }
            Section {
                ForEach(Self.displayOrder) { category in
                    if category == .unclassified {
                        LabeledContent {
                            Text("NP_Unclassified").foregroundStyle(.secondary)
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(category.color).frame(width: 8, height: 8)
                                Text(category.displayName)
                                Text("(fixed)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        CategoryRenameRow(category: category, rootURL: rootFolderStore.rootURL)
                    }
                }
            } header: {
                SectionHeader(
                    title: "Categories",
                    subtitle: "Rename the categories used to classify your photos as Finder tags."
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
    }
}

/// Section header with a bold title and a lighter explanatory subtitle below it.
private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.7))
                .textCase(nil)
        }
        .padding(.bottom, 4)
    }
}

/// Inline row embedding the category rename form, with its own edit state.
private struct CategoryRenameRow: View {
    let category: Category
    let rootURL: URL?

    @State private var isEditing = false

    var body: some View {
        if isEditing {
            CategoryRenameView(category: category, rootURL: rootURL) {
                isEditing = false
            }
        } else {
            let naming = CategoryNamingStore.naming(for: category)
            LabeledContent {
                HStack {
                    Text("NP_\(naming.tagSuffix)").foregroundStyle(.secondary)
                    Button("Edit…") { isEditing = true }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(category.color).frame(width: 8, height: 8)
                    Text(naming.displayName)
                }
            }
        }
    }
}
