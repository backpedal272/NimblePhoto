# Nimble Photo

**Cull thousands of photos on your Mac with one key per photo, without moving a single file.**

Open any folder, press a number key to sort each photo, then filter to see what's left. Your choices are saved as standard macOS Finder tags, so they show up in Finder and Spotlight and stay with the files even if you uninstall the app.

> Free and open source (GPL-3.0). Part of [Nimble Apps](https://nimbleapps.ch).

## How it works

1. **Pick a folder.** No import, no catalog. Photos stay where they are.
2. **Press a key.** `0` Delete · `1` Unclassified · `2` Keep · `3` Star · `4` Select
3. **Filter.** Show one category at a time, with live counts.

Nimble Photo never moves, renames, copies or deletes photos. Category names can be changed (for example "Star" to "Portfolio"), and the app updates the tags for you.

## Features

- Handles 5,000 to 50,000+ photos per folder
- Keyboard first: arrows to move, numbers to sort, Space to open
- Full-size viewer with zoom to 100% for checking focus
- Videos in the same grid (MP4, MOV, M4V)
- JPEG, HEIC, PNG, WebP, TIFF and RAW (CR2, DNG, RAF)
- Sorted by capture date
- EXIF panel: camera, lens, aperture, shutter speed, ISO, location
- **Copy All Text**: right-click to copy the text recognized in a photo (whiteboards, menus, receipts)
- Notices files added or removed in Finder

## Requirements

- macOS 15 Sequoia or later

## Install

Nimble Photo is in beta. [Join the beta on TestFlight](https://testflight.apple.com/join/kqkYP4Jw). It's free. More on [nimbleapps.ch](https://nimbleapps.ch/nimblephoto/index.html).

## Build from source

You need Xcode.

```sh
git clone https://github.com/backpedal272/NimblePhoto.git
cd NimblePhoto
open NimblePhoto/NimblePhoto.xcodeproj
```

Then choose **Product › Run**. To run it signed on your own Mac, pick your team under **Signing & Capabilities**.

## Project layout

| Path | Contents |
|---|---|
| `NimblePhoto/NimblePhoto/Models/` | Photos, categories, folder tree |
| `NimblePhoto/NimblePhoto/Services/` | Thumbnails, metadata, Finder tags, text recognition, folder watching |
| `NimblePhoto/NimblePhoto/Persistence/` | Local cache database |
| `NimblePhoto/NimblePhoto/Views/` | SwiftUI views |

## Contributing

Bug reports and suggestions are welcome in [Issues](https://github.com/backpedal272/NimblePhoto/issues). Contact: info@nimbleapps.ch.

## License

GPL-3.0. See [LICENSE](LICENSE).
