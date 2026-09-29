import SwiftUI

/// Editor for a category's display name and Finder tag name, used from the
/// Settings window. Handles validation, the migration-confirmation prompt
/// when the tag name changes, and the (non-cancellable) migration
/// progress + summary.
struct CategoryRenameView: View {
    let category: Category
    let rootURL: URL?
    var onDismiss: () -> Void = {}

    @State private var displayName: String
    @State private var tagSuffix: String
    @State private var validationError: String?
    @State private var pendingRename: PendingRename?
    @State private var isScanning = false
    @State private var isMigrating = false
    @State private var migrationProgress: (completed: Int, total: Int) = (0, 0)
    @State private var migrationSummary: CategoryRenameService.RenameOutcome?

    private struct PendingRename {
        let naming: CategoryNamingStore.Naming
        let paths: [String]
    }

    init(category: Category, rootURL: URL?, onDismiss: @escaping () -> Void = {}) {
        self.category = category
        self.rootURL = rootURL
        self.onDismiss = onDismiss
        let naming = CategoryNamingStore.naming(for: category)
        _displayName = State(initialValue: naming.displayName)
        _tagSuffix = State(initialValue: naming.tagSuffix)
    }

    var body: some View {
        Form {
            Section {
                TextField("Display Name", text: $displayName)
                HStack(spacing: 4) {
                    Text("NP_")
                        .foregroundStyle(.secondary)
                    TextField("Tag Name", text: $tagSuffix)
                }
                if let validationError {
                    Text(validationError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            HStack {
                Button("Cancel") { onDismiss() }
                Spacer()
                Button {
                    save()
                } label: {
                    if isScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Save")
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 280)
        .disabled(isMigrating || isScanning)
        .alert(
            "Update Already-Tagged Files?",
            isPresented: Binding(get: { pendingRename != nil }, set: { if !$0 { pendingRename = nil } })
        ) {
            Button("Cancel", role: .cancel) { pendingRename = nil }
            Button("Rename & Update Tags") {
                if let rename = pendingRename {
                    pendingRename = nil
                    performMigrationAndCommit(naming: rename.naming, paths: rename.paths)
                }
            }
        } message: {
            if let pendingRename {
                Text("Renaming will update the Finder tag on \(pendingRename.paths.count) already-tagged file\(pendingRename.paths.count == 1 ? "" : "s") in the root folder, including subfolders. Image files themselves are never modified.")
            }
        }
        .sheet(isPresented: $isMigrating) {
            VStack(spacing: 16) {
                Text("Updating Finder Tags…")
                    .font(.headline)
                ProgressView(value: Double(migrationProgress.completed), total: Double(max(migrationProgress.total, 1)))
                    .frame(width: 240)
                Text("\(migrationProgress.completed) of \(migrationProgress.total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .interactiveDismissDisabled()
        }
        .sheet(item: $migrationSummary) { summary in
            MigrationSummaryView(summary: summary) {
                migrationSummary = nil
                onDismiss()
            }
        }
    }

    private func save() {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSuffix = tagSuffix.trimmingCharacters(in: .whitespacesAndNewlines)

        if let error = CategoryRenameService.validate(displayName: trimmedName, tagSuffix: trimmedSuffix, excluding: category) {
            validationError = error
            return
        }
        validationError = nil

        let naming = CategoryNamingStore.Naming(displayName: trimmedName, tagSuffix: trimmedSuffix)
        let currentSuffix = CategoryNamingStore.naming(for: category).tagSuffix

        guard naming.tagSuffix != currentSuffix, let rootURL else {
            // Display-name-only change, or no root folder open to migrate
            // anything under — apply immediately.
            Task {
                _ = await CategoryRenameService.commit(naming, for: category)
                onDismiss()
            }
            return
        }

        Task {
            isScanning = true
            let paths = await CategoryRenameService.filesCarryingTag(category.tagName, under: rootURL)
            isScanning = false
            if paths.isEmpty {
                _ = await CategoryRenameService.commit(naming, for: category)
                onDismiss()
            } else {
                pendingRename = PendingRename(naming: naming, paths: paths)
            }
        }
    }

    private func performMigrationAndCommit(naming: CategoryNamingStore.Naming, paths: [String]) {
        isMigrating = true
        migrationProgress = (0, 0)
        Task {
            let outcome = await CategoryRenameService.commit(naming, for: category, migratingPaths: paths) { completed, total in
                Task { @MainActor in
                    migrationProgress = (completed, total)
                }
            }
            isMigrating = false
            if outcome.skipped.isEmpty {
                onDismiss()
            } else {
                migrationSummary = outcome
            }
        }
    }
}

private struct MigrationSummaryView: View {
    let summary: CategoryRenameService.RenameOutcome
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Some Files Couldn't Be Updated")
                .font(.headline)
            Text("Updated \(summary.migratedCount) file(s). \(summary.skipped.count) couldn't be updated and still carry the old tag:")
                .font(.subheadline)
            List(summary.skipped) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.path)
                        .font(.caption)
                        .textSelection(.enabled)
                    Text(item.reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 200)
            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420, height: 340)
    }
}
