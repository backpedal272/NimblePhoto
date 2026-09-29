# NimblePhoto — Marketing Brief

**Purpose of this document:** source material for another model/writer to produce (1) the marketing website and (2) the Mac App Store listing (name, subtitle, description, keywords, promotional text, screenshots plan). This is a brief, not final copy — pull facts from here, but write in whatever voice/format fits the target medium.

---

## 1. One-line positioning

**NimblePhoto is a fast, keyboard-driven photo culling app for macOS that lets you sort thousands of photos and videos into custom categories — without ever touching, moving, or duplicating a single file.**

## 2. The problem it solves

Anyone who imports photos off a camera or phone — hobbyists, semi-pro and pro photographers, family archivists — ends up with a folder of 5,000–50,000+ images they need to triage: what's a keeper, what's trash, what's a favorite worth editing. Existing tools force a bad tradeoff:
- **Full DAM/catalog apps** (Lightroom, Photos, etc.) import, duplicate, or take ownership of files into a managed library — heavy, slow to set up, and your files stop being "just files" on disk.
- **Finder itself** has no fast keyboard-driven way to rate/flag large batches, and no real-time counts or filtering.
- **Most lightweight culling tools** are either Windows-only, subscription-gated, or still copy/move files around.

NimblePhoto's answer: point it at a folder you already have, and classify at keyboard speed — one keystroke per photo — with zero risk to the original files. It reads and writes nothing but a Finder tag. Delete the app's cache tomorrow and every file, in every folder, is exactly as it was.

## 3. Core promise / non-negotiables (safe to feature prominently in marketing)

- **Your files never move.** Not renamed, not copied, not deleted, not relocated into a "library." NimblePhoto works directly on your existing folder structure, in place.
- **Classification lives in the file itself**, as a native **macOS Finder tag** — so it shows up in Finder, Spotlight, and any other tag-aware tool, and survives moving the file to another Mac.
- **Fully disposable index.** The app keeps a local cache/database purely for speed. Trash it, relaunch, and NimblePhoto rebuilds itself from your files in seconds — nothing is ever "only known" to the app.
- **Native and sandboxed.** Built with SwiftUI for macOS 15+, distributed through the Mac App Store, fully sandboxed — no hidden background processes, no phoning home, no cloud account required.

This "never touches your files" guarantee is the single most differentiating, most trustworthy claim in the product — it should anchor both the website hero and the App Store subtitle/first paragraph.

## 4. Key features

### Browse
- Three-pane layout: folder tree (left) · filter bar (top) · thumbnail grid (center) · status bar (bottom) — the layout every Mac user already expects from Finder and Mail, so there's zero learning curve for navigation.
- Recursive folder tree of everything under your chosen root; select a folder to see just its photos and videos.
- Square, lazy-loading thumbnail grid with a continuous size slider (120–400px) — zoom out to scan thousands at a glance, or zoom in to compare detail.
- Sorted by date taken (EXIF), automatically, so a shoot tells its story in order — even across cameras and file types.
- Live folder watching: add, remove, or edit a file in Finder while NimblePhoto is open, and the grid updates itself.

### Classify at keyboard speed
- Single keystrokes (`0`–`4`) classify the highlighted photo instantly — no mouse required, no dialogs, no confirmation clicks. This is the heart of the "fast" in NimblePhoto.
- Five mutually-exclusive categories, color-coded to match Finder's own tag colors (e.g. Delete=red, Keep=green, Star=yellow, Select=blue, Unclassified=gray by default).
- **Categories are yours to name.** Rename any of the four working categories (their color and keystroke stay put) — "Delete" can become "Reject," "Star" can become "Portfolio," "Select" can become "Client Picks" — whatever matches how you actually work. NimblePhoto safely migrates the Finder tags on every already-classified file to match.
- A live filter bar shows a running count per category for the open folder and lets you toggle any combination on/off — e.g. show only "Keep" and "Star" to review your shortlist.
- Right-click any thumbnail for the same classification options, for a mouse-first moment.

### View
- Full-size viewer opens instantly with Enter, Space, or a click.
- Arrow keys page through the current filtered set without leaving full-size view — cull an entire shoot without ever going back to the grid.
- Zoom to 100% actual pixels and pan to check focus/detail; classify with `0`–`4` right from the viewer.
- **Videos play inline**, right alongside your photos, in the same grid and the same full-size viewer — no separate app, no export. Shoots that mix stills and video clips (common on modern phones and mirrorless cameras) get one unified workflow.

### Built for big libraries
- Designed and tuned for **5,000 to 50,000+ images** per collection without stutter.
- Supports every format a modern photographer touches: **JPEG, PNG, WEBP, HEIC/HEIF, TIFF, and RAW (CR2, DNG, RAF)** — plus common video formats (MP4, MOV, M4V).
- Background thumbnail generation and metadata reads never block scrolling or keyboarding — the grid stays responsive at every library size.

### Respectful of your Mac and your privacy
- Fully sandboxed, App Store-distributed, no third-party dependencies.
- No account, no sign-in, no cloud sync, no network access required — everything happens locally on your Mac.
- Remembers your chosen root folder, grid size, and last folder between launches.

## 5. Who it's for

- Photographers (hobbyist through professional) doing first-pass culling after a shoot or event.
- Anyone with a large, unsorted personal photo/video archive (old camera imports, phone backups, family archives) who wants to triage without committing to a heavyweight photo-management ecosystem.
- Users who specifically want to **keep files exactly where they are**, in Finder, in their existing folder structure — e.g. people who already have a NAS/backup workflow built around the raw files and don't want a tool that "adopts" them into its own library.
- Keyboard-first, efficiency-minded Mac users generally — the whole app is designed around never needing to reach for the mouse.

## 6. Competitive framing (for website copy, not for App Store metadata)

Position against, in ascending order of directness:
- **Finder alone**: "You already tag things in Finder. NimblePhoto just makes it fast enough to do at scale, with counts, filters, and a real viewer."
- **Lightroom / Photo Mechanic / other DAM tools**: "No import step, no catalog, no managed library. Point it at a folder you already have and start culling in seconds."
- **Photos.app**: "Doesn't take over your library or reorganize anything into its own hidden storage. Your folder structure stays yours."

Avoid disparaging competitors by name in App Store copy (Apple review guidelines discourage/prohibit direct competitor comparisons in metadata); the differentiation above is fine for the marketing website's own prose.

## 7. Tone & visual language guidance (important — read before designing anything)

NimblePhoto is a native macOS utility, not a consumer lifestyle app. Both the website and the App Store assets should read as **an extension of macOS itself**, echoing Apple's own Human Interface Guidelines aesthetic:

- **Visual language**: clean, content-first, generous whitespace, SF Pro / San Francisco-style typography (or a very close web equivalent for the site — e.g. system-ui/-apple-system font stack). Avoid gradients-as-decoration, avoid stock-photo "lifestyle" imagery, avoid anything that reads as a mobile/consumer app.
- **Color**: let the app's own five category colors (red, gray, green, yellow, blue) do the accenting — they're already Finder-standard tag colors, so they'll feel native rather than "branded." Keep the rest of the palette neutral (system grays, a controlled use of one accent — macOS blue is a safe, on-brand choice given the app already uses it for "Select").
- **Chrome**: prefer real product screenshots (actual NavigationSplitView layout, actual thumbnail grid, actual filter-bar chips) over illustrated mockups. Screenshots should look like genuine sandboxed macOS windows — traffic-light buttons, native toolbar, native fonts/vibrancy — not a web-rendered facsimile.
- **Support both appearances**: every screenshot and every marketing UI mock should be prepared in both **Light and Dark Mode**, since the app itself follows macOS system appearance. This is worth stating explicitly to whoever designs the site/screenshots.
- **Voice**: direct, technical-but-not-jargony, confident and calm — closer to Apple's own product-page copy register ("does exactly what it says, and does it fast") than to hype-driven SaaS marketing. Short sentences. Lead with the concrete benefit ("one keystroke, no mouse"), not adjectives ("revolutionary," "seamless," "powerful").
- **Iconography**: the app already uses SF Symbols for its category glyphs (trash, checkmark-circle, star, hand-point-up, circle-dashed) — reuse these same symbols in marketing materials for consistency between what's promised and what's delivered.

## 8. App Store metadata — raw ingredients

- **Suggested category**: Photography.
- **Platform**: macOS only (15.0 Sequoia and later required — call this out only if space allows; not a headline feature).
- **Price/model**: (not decided — leave placeholder; brief does not assume free vs. paid vs. one-time-purchase).
- **Suggested keyword themes** (for the writer to shape into the App Store keyword field): photo culling, photo sorting, photo rating, Finder tags, photo organizer, RAW photos, photographer tools, keyboard shortcuts, batch classify, photo triage, video and photo browser.
- **Screenshots to plan for** (in order of narrative):
  1. Full three-pane layout with a populated grid and filter-bar counts (the "aha, this is the whole app" shot).
  2. Close-up on classifying — a keystroke, the tag/color landing on a thumbnail, filter counts updating.
  3. Custom category renaming (Settings view) — this is a genuine differentiator, worth its own shot.
  4. Full-size viewer with zoom, on a photo.
  5. Full-size viewer playing a video, to make the mixed-media support visible and concrete.
  6. Grid-size slider in action (same folder, two sizes) to sell "handles huge libraries."
- **What NOT to claim**: cloud sync, AI-powered auto-culling/auto-tagging, multi-platform (Windows/iOS) support, or any editing/retouching capability — none of these exist in the app. Do not imply the app modifies image content in any way.

## 9. Key facts sheet (for quick reference / fact-checking generated copy)

| Fact | Value |
|---|---|
| Platform | macOS 15.0 (Sequoia)+, Mac App Store, sandboxed |
| Handles | 5,000–50,000+ photos/videos per collection |
| Image formats | JPEG, PNG, WEBP, HEIC/HEIF, TIFF, RAW (CR2, DNG, RAF) |
| Video formats | MP4, MOV, M4V (played inline in grid & full-size viewer) |
| Classification mechanism | macOS Finder tags (`NP_*`), single keystroke `0`–`4` |
| Categories | 5 total, 4 fully renameable (name + Finder tag), 1 fixed (Unclassified); colors/keys fixed |
| File safety guarantee | Never moves, renames, copies, or deletes any image/video file |
| Data storage | Local SQLite index + thumbnail cache only, fully disposable/rebuildable |
| Network/cloud | None — fully local, no account required |
| Dependencies | Zero third-party — pure Swift/SwiftUI/ImageIO/AVFoundation/SQLite3 |
