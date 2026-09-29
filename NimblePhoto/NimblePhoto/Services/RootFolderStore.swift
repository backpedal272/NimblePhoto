import AppKit
import Foundation

/// Owns the user-selected root folder: presents the picker, persists a
/// security-scoped bookmark across launches, and keeps sandbox access active
/// for the app session while the root is in use.
@Observable
final class RootFolderStore {
    private(set) var rootURL: URL?
    private(set) var isAccessing = false
    private(set) var needsReselect = false

    init() {
        resolveBookmarkIfNeeded()
    }

    deinit {
        stopAccessing()
    }

    private func resolveBookmarkIfNeeded() {
        guard let data = UserDefaults.standard.data(forKey: SettingsKeys.rootBookmark) else { return }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard url.startAccessingSecurityScopedResource() else {
                needsReselect = true
                return
            }
            isAccessing = true
            rootURL = url
            if isStale {
                refreshBookmark(for: url)
            }
        } catch {
            needsReselect = true
        }
    }

    /// Presents an NSOpenPanel restricted to directories and adopts the chosen
    /// folder as the new root, persisting a fresh security-scoped bookmark.
    @MainActor
    func presentPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Select Root Folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        adopt(url)
    }

    private func adopt(_ url: URL) {
        stopAccessing()
        guard url.startAccessingSecurityScopedResource() else {
            needsReselect = true
            return
        }
        isAccessing = true
        needsReselect = false
        rootURL = url
        refreshBookmark(for: url)
    }

    private func refreshBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: SettingsKeys.rootBookmark)
        } catch {
            // Non-fatal: access still works for this session, just won't
            // persist cleanly to next launch. Surfaced via needsReselect on
            // next launch if resolution then fails.
        }
    }

    private func stopAccessing() {
        if isAccessing {
            rootURL?.stopAccessingSecurityScopedResource()
            isAccessing = false
        }
    }
}
