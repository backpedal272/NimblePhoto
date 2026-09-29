# CLAUDE.md — NimblePhoto

Guidance for building NimblePhoto. **Read [`NimblePhoto_SPEC.md`](NimblePhoto_SPEC.md) in full before writing code — it is the source of truth.** This file is the quick operating manual.

## What this app is
A fast, keyboard-driven **macOS** app (Mac App Store) for browsing and classifying large photo collections (5,000–50,000 images). Folder tree (left) · filter bar (top) · thumbnail grid (center) · status bar (bottom), plus a full-size viewer. Classification = one of five mutually-exclusive categories written as **macOS Finder tags**.

## Non-negotiable rules (do not violate)
1. **Never move, rename, copy, or delete any image file.** The only writes to user files are to the Finder-tags extended attribute (`com.apple.metadata:_kMDItemUserTags`).
2. **Only touch `NP_*` tags.** Preserve every non-NP tag on a file exactly.
3. **Exactly one category per photo.** Setting a category removes any other `NP_*` tag. No NP tag == `NP_Unclassified`.
4. The SQLite DB and thumbnail cache are **disposable** — deleting them and relaunching must fully restore behavior by re-scanning.
5. Categories & colors are fixed: `0` Delete/Red · `1` Unclassified/Gray · `2` Keep/Green · `3` Star/Yellow · `4` Select/Blue. Colors are encoded in the tag string as `"NP_Name\n<colorIndex>"` (see spec §6).

## The build is "code only" — do not touch project config
The Xcode project is **already fully configured**. You should only ever add/edit `.swift` files. Specifically, do NOT:
- change the bundle id, deployment target, platforms, or signing;
- add Swift Package / third-party dependencies (use `import SQLite3` for the database — the C library ships with macOS, no linking needed);
- edit `NimblePhoto.xcodeproj/project.pbxproj` or `NimblePhoto.entitlements` unless the spec explicitly requires a new entitlement (it should not).

Already set up for you:
- Target **NimblePhoto**, macOS-only, **deployment target 15.0**, bundle id **`pm.ad0.Nimble-photo`**.
- **App Sandbox** ON with `files.user-selected.read-write` + `files.bookmarks.app-scope` (see `NimblePhoto/NimblePhoto.entitlements`).
- Hardened runtime ON; Info.plist auto-generated; app category = Photography.
- The source folder uses an Xcode **file-system-synchronized group**: any `.swift` file you drop under `NimblePhoto/NimblePhoto/` is compiled automatically — no need to register it in the project file.

## Project layout
```
NimblePhoto/                       ← repo root (working dir)
  CLAUDE.md                        ← this file
  NimblePhoto_SPEC.md              ← the spec (authoritative)
  NIMBLE_PHOTO_DESCRIPTION.md      ← original product description
  NimblePhoto/                     ← Xcode project container
    NimblePhoto.xcodeproj
    NimblePhoto/                   ← put ALL your Swift here (auto-compiled)
      NimblePhotoApp.swift         ← app entry + menu commands (skeleton)
      NimblePhoto.entitlements     ← sandbox entitlements (do not edit)
```
Organize new code into subfolders per spec §3: `Models/`, `Services/`, `Views/`, `Views/FullSize/`, `Persistence/`, `Support/` (all under `NimblePhoto/NimblePhoto/`).

## Build & run
```bash
cd "NimblePhoto"
# Build (Debug)
xcodebuild -project NimblePhoto.xcodeproj -scheme NimblePhoto -configuration Debug build
# Or open in Xcode and press ⌘R
open NimblePhoto.xcodeproj
```
The project builds green out of the box (a placeholder view). Replace `PlaceholderRootView` in `NimblePhotoApp.swift` with the real `MainWindowView`.

## Tech conventions
- **SwiftUI** + **`@Observable`** models injected via `Environment`. Target macOS 15 APIs freely.
- Default actor isolation is **MainActor** (set project-wide). Move file I/O, ImageIO decoding, thumbnail generation, and DB work to background tasks/actors; publish results back to the main actor.
- **ImageIO** for EXIF + thumbnails (`CGImageSourceCopyPropertiesAtIndex`, `CGImageSourceCreateThumbnailAtIndex` with orientation transform). Supports JPG/PNG/WEBP/HEIC/TIFF/RAW.
- **FSEvents** for live folder watching; debounce bursts.
- Finder tags: read/write the `_kMDItemUserTags` xattr directly (binary plist of strings) — do NOT rely on `URLResourceValues.tagNames` (it drops color info).
- Sandbox file access: `NSOpenPanel` → security-scoped **bookmark** persisted in `UserDefaults`; `startAccessingSecurityScopedResource()` on launch. Caches/DB go in the app container (`.cachesDirectory` / `.applicationSupportDirectory`).

## Suggested order (see spec §16)
M1 shell/sandbox → M2 tree & listing → M3 thumbnails → M4 classification → M5 full-size viewer → M6 live watch & polish. Keep the app building green after each milestone.

## Definition of done
Work to the acceptance criteria in spec §15. Verify tag writes by inspecting a file's tags in Finder, and verify the never-modify-files invariant holds.
