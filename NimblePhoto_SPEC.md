# NimblePhoto — Build Specification

**Audience:** an engineer/model implementing the app from scratch.
**Goal:** a fast, keyboard-driven, native macOS app for browsing and classifying large photo collections (5,000–50,000 images), distributed via the Mac App Store.

This document is the source of truth. Where it says **MUST**, do exactly that. Where it says **SHOULD**, follow unless there is a concrete technical blocker. Anything marked **TODO(owner)** is a placeholder to be filled by the project owner, not invented.

---

## 1. Product summary

NimblePhoto lets a user point at a root folder of photos, browse folders in a tree, view thumbnails in a grid, and classify each photo into exactly one of five categories using single keystrokes. Classification is stored as **macOS Finder tags** on the files themselves — the app **never moves, renames, copies, or deletes any image file**. A local SQLite database and a thumbnail cache exist only as a performance index and can be rebuilt at any time from the files on disk.

### Non-negotiable invariants
1. **The app never modifies image file contents, names, or locations.** The only on-disk writes to user files are to the Finder-tags extended attribute (see §6).
2. **Only NP_ tags are ever touched.** Any other Finder tags on a file MUST be preserved exactly.
3. The DB and thumbnail cache are disposable. Deleting them and relaunching MUST fully restore behavior (by re-scanning).
4. The app targets the Mac App Store: it MUST run under the App Sandbox (see §5).

---

## 2. Platform, project, and tooling

| Item | Value |
|---|---|
| Language | Swift (latest stable, Swift 6 mode acceptable) |
| UI | SwiftUI, using the `@Observable` macro (Observation framework) for models |
| Minimum deployment target | **macOS 15.0 (Sequoia)** |
| App name | **NimblePhoto** |
| Bundle identifier | **`pm.ad0.Nimble-photo`** |
| Distribution | Mac App Store (sandboxed) |
| Dependencies | **Zero third-party dependencies.** Use the system SQLite via `import SQLite3` (the C library ships with macOS and needs no linking or package setup) wrapped in a small Swift helper. Do NOT add Swift Package dependencies — the project is intentionally configured so the build is code-only. Do not invent another database. |

### 2.1 Scaffolding cleanup (do this first)
The existing Xcode project is the default template named **"Untitled Project"** with a Hello-world `ContentView`. Treat all existing source as disposable.

- Rename the project, target, scheme, and product to **NimblePhoto**.
- Set the bundle identifier to `pm.ad0.Nimble-photo`.
- Remove the `import Playgrounds` / `#Playground` block and the placeholder `ContentView`.
- Organize source into folders: `App/`, `Models/`, `Services/`, `Views/`, `Views/FullSize/`, `Persistence/`, `Support/`.
- Set the display name to "NimblePhoto".

---

## 3. High-level architecture

Use MVVM with `@Observable` model objects injected via SwiftUI `Environment`.

```
App
 └─ NimblePhotoApp (App entry, WindowGroup, Commands/menus)
     └─ MainWindowView  (NavigationSplitView)
         ├─ Sidebar:  FolderTreeView            ← folder hierarchy
         └─ Detail:   VStack {
                        FilterBarView           ← category chips + counts (top)
                        ThumbnailGridView       ← lazy grid (center)
                        StatusBarView           ← highlighted-photo info (bottom)
                      }
     └─ FullSizeImageView  (overlay / separate view state)

Services (singletons or environment-injected @Observable):
 - AppState               overall selection/focus/filter/grid-size state
 - RootFolderStore        security-scoped bookmark persistence for the root
 - FolderTreeModel        builds and caches the folder tree
 - FolderContentsModel    photos of the currently selected folder
 - MetadataService        EXIF/dimensions extraction via ImageIO
 - ThumbnailService       thumbnail generation + disk cache
 - TagService             read/write NP_ Finder tags (extended attribute)
 - DatabaseService        SQLite index (import SQLite3)
 - FolderWatcher          FSEvents live watching of the current folder
 - Settings               persisted user prefs (grid size, last root, etc.)
```

Threading: all file I/O, ImageIO decoding, thumbnail generation, and DB access run **off the main thread** (async/await with a background task/actor). UI state mutations happen on the main actor. The grid MUST stay responsive while thumbnails generate in the background.

---

## 4. Data model

### 4.1 Category (the five classes) — **mutually exclusive**
A photo has **exactly one** category at a time. Categories map to keystrokes and Finder tags:

| Key | Category | Finder tag name | Finder color | Color index* |
|----|----------|-----------------|--------------|--------------|
| `0` | Delete | `NP_Delete` | Red | 6 |
| `1` | Unclassified | `NP_Unclassified` | Gray | 1 |
| `2` | Keep | `NP_Keep` | Green | 2 |
| `3` | Star | `NP_Star` | Yellow | 5 |
| `4` | Select | `NP_Select` | Blue | 4 |

\* Color index is the value used in the `_kMDItemUserTags` encoding (see §6). Reference: 0=none, 1=Gray, 2=Green, 3=Purple, 4=Blue, 5=Yellow, 6=Red, 7=Orange.

Rules:
- Setting a category MUST remove any other `NP_*` tag from the file and add the chosen one. (At most one NP_ tag per file.)
- A file with **no** `NP_*` tag is treated as **Unclassified** for display, counting, and filtering. Reading a folder does not write tags; tags are only written on an explicit user classification action.
- `NP_Delete` is purely a marker. It does **not** delete anything. (A future "reveal delete-marked files in Finder" convenience is out of scope.)

### 4.2 Photo (in-memory / DB row)
```
Photo {
  id: stable identifier (absolute file path is acceptable as the key)
  folderPath: String
  fileName: String
  fileURL: URL
  pixelWidth: Int?
  pixelHeight: Int?
  dateTaken: Date?          // EXIF DateTimeOriginal
  dateSource: enum { exif, fileModified }
  effectiveDate: Date       // dateTaken ?? fileModificationDate
  cameraMake: String?
  cameraModel: String?
  fileSize: Int64
  fileModified: Date        // file mtime, used for cache invalidation
  category: Category        // derived from NP_ tag; .unclassified if none
  thumbnailPath: URL?       // cached thumbnail on disk, nil until generated
}
```

### 4.3 Supported image formats
Load, thumbnail, and read EXIF for: **JPG/JPEG, PNG, WEBP, HEIF/HEIC, TIFF, and RAW (CR2, DNG, RAF)**. Detect by file extension (case-insensitive) AND rely on ImageIO's supported-type list; if ImageIO can create an image source for the file, treat it as an image. Non-image files in a folder MUST be ignored silently.

---

## 5. Sandbox & file access (Mac App Store)

The app MUST be sandboxed. Configure the entitlements:

- `com.apple.security.app-sandbox` = true
- `com.apple.security.files.user-selected.read-write` = true (user picks the root folder; the app reads images and writes NP_ tag xattrs)
- `com.apple.security.files.bookmarks.app-scope` = true (security-scoped bookmarks)

Folder access flow:
1. The root folder is chosen by the user via `NSOpenPanel` (directories only). This grants access to that folder **and its descendants**.
2. Immediately create a **security-scoped bookmark** and persist it (see §11). On next launch, resolve the bookmark and call `startAccessingSecurityScopedResource()` before any file access; call the matching stop when appropriate (keep it active for the app session while the root is in use).
3. All image reads, thumbnail generation, and tag writes happen through URLs under this scoped root.
4. If the bookmark is stale or access fails, prompt the user to re-select the root.

Cache and DB locations (container-relative, i.e. inside the sandbox container):
- Thumbnails: `Library/Caches/NimblePhoto/thumbnails/` within the app container (obtained via `FileManager.url(for: .cachesDirectory, ...)`). The description's `~/Library/Caches/NimblePhoto/thumbnails` maps to the container path under sandbox — that is correct and expected.
- Database: `Library/Application Support/NimblePhoto/index.sqlite` within the container (via `.applicationSupportDirectory`).

---

## 6. Finder tags — reading and writing (critical detail)

Finder tags are stored in the extended attribute **`com.apple.metadata:_kMDItemUserTags`** on each file. The value is a **binary property list** encoding an **array of strings**. Each string is either:
- `"TagName"` (no color), or
- `"TagName\nN"` where `N` is the color index (0–7).

The app MUST manipulate this xattr directly to preserve non-NP tags and to control colors. Do **not** rely solely on `URLResourceValues.tagNames`, because that API strips color information.

### 6.1 Reading tags
- Read the `_kMDItemUserTags` xattr (via `getxattr`, or `URL` extended-attribute helpers). Decode the binary plist to `[String]`.
- Split each entry on `\n`; the part before is the tag name.
- Determine category: if exactly one `NP_*` tag is present, map it to its category; if none, `.unclassified`; if (unexpectedly) several NP_ tags exist, pick the highest-priority one for display using order `Star > Select > Keep > Delete > Unclassified` and self-heal on next write. Non-NP tags are ignored for categorization but retained.

### 6.2 Writing a category
Given a file and a target category:
1. Read the current tag array (or empty if none / xattr absent).
2. Remove **all** entries whose name starts with `NP_`.
3. If the target category is a real class the user selected, append `"<TagName>\n<colorIndex>"` for it. (Note: for `Unclassified`, prefer to write the explicit `NP_Unclassified` tag when the user presses `1`, so the classification is visible in Finder. Removing a tag to return to "no tag" is not required unless a future "clear" action is added.)
4. Re-encode as a binary plist and write it back to the `_kMDItemUserTags` xattr.
5. Update the DB row and the in-memory `Photo.category`, and refresh that cell in the grid.

All tag writes MUST be atomic per file and happen off the main thread, then publish the result back to the main actor. Writing MUST fail gracefully (e.g., read-only volume) with a non-blocking error surfaced in the status bar; never crash.

### 6.3 Colors / system registration (SHOULD)
Writing the color index in the tag string is sufficient for Finder to show the color. Optionally, register the NP_ tags in the user's known-tags list so they appear in Finder's sidebar with consistent colors; if this is non-trivial under sandbox, skip it — per-file color encoding is the requirement.

---

## 7. UI layout & behavior

Traditional three-region layout inside a `NavigationSplitView`:

### 7.1 Folder tree (left sidebar)
- Hierarchical, expandable tree of **all** folders beneath the selected root (recursive directory listing; folders only).
- Lazy/async construction so a deep tree does not block the UI. Show a subtle loading state while building.
- Selecting a folder loads **only its direct image files** (non-recursive) into the grid.
- The currently selected folder is highlighted.
- Empty folders (no images, subfolders only) are still shown in the tree.

### 7.2 Filter bar (top of detail)
- One chip per category (Delete, Unclassified, Keep, Star, Select), each showing an icon/color, a label, and a **count** for the currently selected folder.
- **Counts always reflect the full folder** (unfiltered), so the user sees totals per category regardless of active filters.
- **Multi-select toggles**: each chip independently toggles whether that category is visible in the grid. Provide an **"All"** affordance/state that shows everything. Example: enabling Keep + Star shows only photos in those two categories.
- Default state on opening a folder: All (everything visible).

### 7.3 Thumbnail grid (center)
- Lazy grid (`LazyVGrid`) of **square cells**. Thumbnails are scaled to fit the square, preserving aspect ratio (letterboxed), not cropped-distorted.
- **Grid size is a continuous slider** ranging **120–400 px** per cell (default **300 px**). Persist the last value. Provide the slider in a toolbar and/or a `View` menu item.
- Below each thumbnail show the **file name** and a small **category indicator** (colored dot/label).
- Thumbnails render lazily and asynchronously; show a lightweight placeholder until the cached/generated thumbnail is ready.
- Sort: **EXIF DateTimeOriginal ascending**, with **file modification date** as fallback for photos lacking EXIF, and **filename** as a final tie-breaker. This sort is fixed (no user sort UI).
- The currently highlighted photo is visually highlighted.

### 7.4 Status bar (bottom)
Shows info for the currently **highlighted** photo:
- File name
- Dimensions in pixels (e.g. `6000 × 4000`)
- Date & time taken (EXIF `DateTimeOriginal`; if absent, file modification date — indicate the fallback subtly, e.g. italic or a small "(file date)" note)
- Camera make and model (from EXIF/TIFF; omit gracefully if absent)

Also use the status bar to surface transient errors (e.g., "Couldn't write tag: read-only volume").

---

## 8. Full-size image viewer

Opened via **Enter**, **Space**, or **click** on a highlighted/clicked thumbnail. Behavior:
- Display the full image, **scaled down to fit** the window by default (never upscaled beyond 100% by default).
- **Left/Right arrow** (and Up/Down) move to the previous/next photo **within the current folder's filtered, sorted list**, staying in full-size mode.
- **Esc**, **Enter**, or **Space** closes the viewer and returns to the grid, keeping the just-viewed photo highlighted.
- **Category keystrokes `0`–`4` still classify** the currently displayed photo without leaving the viewer; the category indicator updates live.
- **Zoom / pan**: allow toggling to **100% (actual pixels)** and panning (drag), plus zoom in/out (e.g. `+`/`-` or scroll/pinch). Provide a way to reset to fit.

---

## 9. Keyboard model (summary)

| Key | Context | Action |
|---|---|---|
| `0`–`4` | grid or full-size | Classify highlighted/displayed photo (mutually exclusive) |
| Arrow keys | grid | Move highlight between thumbnails |
| Arrow keys | folder tree | Move between / expand-collapse folders |
| Arrow keys | full-size | Previous/next photo |
| `Tab` | — | Switch focus between folder tree and thumbnail grid |
| `Enter` / `Space` | grid | Open full-size viewer for highlighted photo |
| `Enter` / `Space` / `Esc` | full-size | Close viewer |
| `+` / `-` / scroll | full-size | Zoom |

Keyboard navigation MUST be smooth and immediate — this is a keyboard-first app. Ensure focus handling between the two panes is reliable (`Tab` toggles focus; the focused pane shows a focus ring/highlight).

---

## 10. Scanning, thumbnails, and live updates

### 10.1 On selecting a folder
1. Enumerate direct children; filter to supported image types.
2. For each image, load from DB if present and `fileModified`/size unchanged; otherwise extract metadata (EXIF, dimensions, camera) via **ImageIO** (`CGImageSourceCopyPropertiesAtIndex`) and read its NP_ tag → category.
3. Populate the grid immediately with placeholders; generate/lookup thumbnails in the background, filling cells as they complete.
4. Update the DB index for this folder (upsert rows, remove rows for files no longer present).

### 10.2 Thumbnail generation & cache
- Generate with **ImageIO** `CGImageSourceCreateThumbnailAtIndex` using `kCGImageSourceCreateThumbnailFromImageAlways`, `kCGImageSourceCreateThumbnailWithTransform` (respect EXIF orientation), and `kCGImageSourceThumbnailMaxPixelSize` sized to the **maximum** grid cell (generate at ~400 px and downscale in-view, or regenerate on large size changes — pick one, document it; generating once at 400 px is preferred).
- Cache thumbnails on disk in the cache dir, keyed by a hash of `absolutePath + fileModified + fileSize` (so edits invalidate the cache). Store as JPEG or HEIC.
- Concurrency: bound the number of simultaneous generations (e.g., an `OperationQueue`/task group with a sensible max) so 50k-image folders don't exhaust memory. Prioritize generating thumbnails for on-screen cells.

### 10.3 Live watching (FSEvents)
While a folder is open, watch it with **FSEvents** for the current folder (non-recursive is sufficient for the grid; the tree may watch the root for folder add/remove). On change:
- **File added** → add to grid (respecting sort/filter).
- **File removed** → remove from grid and DB.
- **File modified** (content or tags changed externally in Finder/another app) → re-read metadata/category and regenerate thumbnail if content changed; update the cell.
Debounce rapid bursts of events. All updates animate/refresh without losing the user's current highlight where possible.

---

## 11. Persistence

**Settings** (`UserDefaults` / `@AppStorage`):
- Security-scoped **bookmark data** for the root folder (persisted, resolved on launch).
- Last-used **grid cell size**.
- Last **selected folder** path (restore selection on launch if still present).
- Window frame (SwiftUI scene restoration is fine).

**Database** (SQLite via `import SQLite3`, at `Library/Application Support/NimblePhoto/index.sqlite`):
- Wrap the C API in a small `DatabaseService` actor (open/close, prepared statements, upsert, query). Use `sqlite3_open_v2`, `sqlite3_prepare_v2`, `sqlite3_bind_*`, `sqlite3_step`. Bind text with `SQLITE_TRANSIENT`. Enable WAL (`PRAGMA journal_mode=WAL`) for concurrent reads.
- Table `photos` mirroring §4.2 (path as primary key), indexed by `folderPath` and by `effectiveDate`.
- Optional table `folders` for cached tree/enumeration if helpful.
- The DB is a cache: always reconcile against disk on folder open and via FSEvents. Handle schema versioning with a `PRAGMA user_version` check and idempotent `CREATE TABLE IF NOT EXISTS` migrations.

---

## 12. Menus (macOS menu bar)

- **File**
  - "Select Root Folder…" (`⌘O`) — opens `NSOpenPanel` (directories only); persists the bookmark; rebuilds the tree.
  - "Refresh" (`⌘R`) — force re-scan of the current folder.
- **View**
  - Grid size slider or Increase/Decrease Thumbnail Size (`⌘+` / `⌘-`).
  - Toggle filters (optional shortcuts).
- Standard app menus (About, Quit, etc.).

The chosen root MUST be remembered for the next session (via the bookmark).

---

## 13. Performance requirements

- Must handle **5,000–50,000 images** across a folder tree without UI stalls.
- Selecting a folder with up to ~10,000 direct images should show the populated grid (with placeholders) within ~1 second; thumbnails stream in afterward.
- Scrolling the grid MUST stay at 60fps with lazy loading and cancellation of off-screen thumbnail work.
- Memory: never hold full-resolution decodes for the whole folder; only thumbnails plus the one full-size image currently viewed.

---

## 14. Edge cases & error handling

- **No root selected (first launch):** show an empty state with a prominent "Select Root Folder…" button.
- **Stale/invalid bookmark:** prompt to re-select; do not crash.
- **Unreadable / corrupt image:** show a broken-image placeholder; keep it listed; don't block the folder.
- **File with pre-existing non-NP tags:** preserve them on every write.
- **File on a read-only volume:** classification fails; surface a non-blocking status-bar message; keep the app usable.
- **Missing EXIF date:** fall back to file modification date; mark the source.
- **Missing camera make/model:** omit from status bar.
- **Folder disappears while open (removed externally):** clear the grid gracefully and reflect it in the tree.
- **Huge folder (50k in one dir):** virtualize aggressively; still usable.
- **Duplicate/odd Finder tag states (multiple NP_ tags):** self-heal to a single tag on next classification per §6.1.

---

## 15. Acceptance criteria (definition of done)

1. App launches sandboxed under bundle id `pm.ad0.Nimble-photo`, macOS 15+, no default-template code remaining.
2. User can select a root folder; it persists across relaunches via security-scoped bookmark.
3. Folder tree shows the full recursive hierarchy; selecting a folder shows its **direct** images only, sorted by EXIF date ascending (fallbacks per spec).
4. Thumbnails render lazily in a square grid; the grid cell size is adjustable via a continuous slider (120–400, default 300) and persists.
5. Each cell shows filename + category indicator. Status bar shows name, pixel dimensions, date (with fallback noted), camera make/model for the highlighted photo.
6. Filter bar shows per-category counts for the folder (always full-folder counts) and supports multi-select toggle filtering plus "All".
7. Pressing `0`–`4` writes the correct single `NP_*` Finder tag with the correct color, removes other NP_ tags, preserves all non-NP tags, and updates the UI immediately. Verified by inspecting the file's tags in Finder.
8. Right-click on a thumbnail offers a context menu to pick a category (same effect as the keystroke).
9. Full-size viewer opens via Enter/Space/click; arrows page prev/next; Esc/Enter/Space closes; `0`–`4` classify in place; zoom/pan to 100% works.
10. Tab switches focus between tree and grid; arrow keys navigate within the focused pane.
11. Editing files/tags externally (in Finder) while a folder is open updates the grid live via FSEvents.
12. Deleting the thumbnail cache and the SQLite DB, then relaunching, fully restores functionality by re-scanning. No image file is ever moved, renamed, or deleted by the app.
13. All supported formats (JPG/JPEG, PNG, WEBP, HEIF/HEIC, TIFF, CR2, DNG, RAF) load, thumbnail, and expose EXIF where present.

---

## 16. Suggested build order (milestones)

1. **M1 — Shell & sandbox:** rename project, entitlements, `NSOpenPanel` root selection, security-scoped bookmark persistence, empty three-region layout.
2. **M2 — Tree & listing:** folder tree, folder selection, enumerate direct images, ImageIO metadata extraction, DB index, status bar.
3. **M3 — Thumbnails:** ImageIO thumbnail generation + disk cache, lazy grid, grid-size slider, sort order, filenames + placeholders.
4. **M4 — Classification:** TagService (read/write `_kMDItemUserTags` with colors, preserve non-NP), keystrokes `0`–`4`, right-click menu, category indicators, filter bar with counts + multi-select.
5. **M5 — Full-size viewer:** fit/zoom/pan, prev/next, in-place classify, close behavior.
6. **M6 — Live & polish:** FSEvents watching, refresh command, focus/keyboard polish, error handling, performance passes for 50k images.

---

## 17. Open placeholders

- **TODO(owner):** confirm the App Store display name and app category before submission.
- **TODO(owner):** provide the code-signing team / provisioning for MAS submission (not needed for local development).
