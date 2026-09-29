import SwiftUI

@main
struct NimblePhotoApp: App {
    @State private var appState = AppState()
    @State private var rootFolderStore = RootFolderStore()
    @State private var settings = Settings()
    @State private var treeModel = FolderTreeModel()
    @State private var contentsModel: FolderContentsModel
    @Environment(\.openWindow) private var openWindow

    init() {
        let database: DatabaseService
        let thumbnailService: ThumbnailService
        do {
            // Recreates the DB from scratch if it's corrupt/unopenable (it's
            // a disposable cache); only an unusable app container is fatal.
            database = try DatabaseService.openRecreatingIfNeeded(fileURL: DatabaseService.containerURL())
        } catch {
            fatalError("Failed to open NimblePhoto database: \(error)")
        }
        do {
            thumbnailService = ThumbnailService(cacheDirectory: try ThumbnailService.containerCacheDirectory())
        } catch {
            fatalError("Failed to prepare NimblePhoto thumbnail cache: \(error)")
        }
        _contentsModel = State(initialValue: FolderContentsModel(database: database, thumbnailService: thumbnailService))
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .frame(minWidth: 900, minHeight: 600)
                .environment(appState)
                .environment(rootFolderStore)
                .environment(settings)
                .environment(treeModel)
                .environment(contentsModel)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Refresh") {
                    guard let folder = appState.selectedFolderURL else { return }
                    Task { await contentsModel.load(folder: folder) }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
            CommandGroup(after: .toolbar) {
                Button("Increase Thumbnail Size") {
                    settings.gridCellSize = min(Settings.gridCellSizeRange.upperBound, settings.gridCellSize + 20)
                }
                .keyboardShortcut("+", modifiers: [.command])

                Button("Decrease Thumbnail Size") {
                    settings.gridCellSize = max(Settings.gridCellSizeRange.lowerBound, settings.gridCellSize - 20)
                }
                .keyboardShortcut("-", modifiers: [.command])
            }
            CommandGroup(replacing: .help) {
                Button("Welcome to Nimble Photo") {
                    openWindow(id: "welcome")
                }
                Button("Keyboard Shortcuts") {
                    openWindow(id: "shortcuts")
                }
                .keyboardShortcut("/", modifiers: .command)
            }
        }

        Window("Welcome to Nimble Photo", id: "welcome") {
            EmptyRootStateView(showButton: false)
                .environment(rootFolderStore)
                .frame(width: 600)
        }
        .windowResizability(.contentSize)

        Window("Keyboard Shortcuts", id: "shortcuts") {
            KeyboardShortcutsView()
        }
        .windowResizability(.contentSize)

        SwiftUI.Settings {
            CategorySettingsView()
                .environment(rootFolderStore)
                .environment(contentsModel)
        }
    }
}
