# Nimble Icons style guide v2

How app icons for the Nimble family of apps should be designed. Derived from the Nimble Bot icon (the reference implementation) and Apple's icon rules.

**What changed since v1:** exact sRGB color values (v1's hex codes were not what the icons actually render), the in-app accent now matches the icon, NimbleTask added as a second reference, concrete proportions for square marks and strokes, a concept review sheet, a clean asset catalog setup, and a pixel check before shipping.

## 1. Hard rules

- **No SF Symbols in app icons.** Apple prohibits it. SF Symbols are fine as in-app UI elements. Every icon is drawn as original vector paths.
- **Full-bleed square, 1024×1024 px, opaque.** No rounded corners, no drop shadow, no transparency, no baked-in bezel. iOS and macOS apply their own mask.
- **No text or wordmark.** A single letter monogram is the only exception, and only as a deliberate design choice.
- **No screenshots, photos or third-party logos.** Nothing that needs an outside license.
- **One idea per icon.** It must read at 16×16 px (the Mac Dock and Finder list) as clearly as at 1024.

## 2. Color

All values are **sRGB**. These are the pixel values in the shipped PNGs, and the values to use in code.

| Role        | sRGB      | RGB           | Use                                                        |
| ----------- | --------- | ------------- | ---------------------------------------------------------- |
| Nimble Blue | `#009AD6` | 0, 154, 214   | Top-left of the gradient, detail cut into the mark, in-app accent |
| Deep Blue   | `#006CA5` | 0, 108, 165   | Bottom-right of the gradient                               |
| Cream       | `#FAF8F4` | 250, 248, 244 | The foreground mark                                        |

- **Background:** a diagonal linear gradient from Nimble Blue (top-left) to Deep Blue (bottom-right).
- **Mark:** solid Cream, with Nimble Blue used for detail cut into the mark (the dots in the bubble, the tick in the box).
- **Family recognition:** every Nimble app keeps the blue gradient and cream mark. Only the mark changes per app. If two apps must be told apart at a glance, vary the mark, never the background hue.
- **Accent inside the app:** `#009AD6` sRGB is the in-app accent. Put it in the asset catalog's `AccentColor` (color space sRGB, red `0x00`, green `0x9A`, blue `0xD6`) and use `Color.accentColor` in code. For quieter states (unselected pills, backgrounds), use the accent at reduced opacity, e.g. `Color.accentColor.opacity(0.15)`, rather than gray. Orange and red-orange are retired.
- No pure white, pure black or extra hues. Stay within the three colors above.

### Color space pitfall (why v1's values were wrong)

v1 listed `#0F87CC` / `#085894` / `#F8F6F1`. The Nimble Bot script passed those numbers to `CGColor(red:green:blue:)`, which is **Generic RGB**, not sRGB. Written to an sRGB PNG they come out brighter: `#009AD6` / `#006CA5` / `#FAF8F4`. The icon everyone knows is the brighter one, so v2 adopts it.

- In scripts, always create colors with `CGColor(srgbRed:green:blue:alpha:)` and give gradients an explicit `CGColorSpace(name: CGColorSpace.sRGB)`. Never use `CGColor(red:green:blue:)` or a `nil` color space.
- In asset catalogs, set the color space to sRGB explicitly.

## 3. Composition

- Canvas 1024×1024. Work on a 512 grid with a top-left origin and scale ×2 (flip CG's y axis: `translateBy(0, 1024)`, `scaleBy(2, -2)`).
- **The mark is centered and occupies about 60–65% of the width**, leaving generous padding so the system mask never clips it.
  - A wide mark (Nimble Bot's bubble) can use the upper end: 320 of 512 = 62.5%.
  - A square mark looks heavier than a wide one at the same width. Keep it near the lower end: NimbleTask's box is 312 of 512 = 61%.
- **Flat, single-layer shapes.** No outlines, gradients or shading inside the mark. The background gradient is the only gradient.
- **Soft geometry:** rounded corners and round dots. Corner radius on large shapes is roughly 28% of the shape's short side (bubble: 90 on 210; box: 88 on 312). Avoid sharp, spiky forms. The one sharp element in the Nimble Bot icon is the bubble's tail, which gives it direction.
- **Weight:** bold and chunky. A stroke or detail thinner than about 3% of the canvas (30 px at 1024) disappears at small sizes. In practice, **cut-in detail around 46–48 on the 512 grid (92–96 px)** reads well at 16 px, and keeps apps consistent with each other: Nimble Bot's dots are 46, NimbleTask's tick stroke is 48.
- **Strokes:** use round caps and round joins so strokes match the soft geometry.
- **Asymmetry is allowed when it implies motion** (the tail leans forward and left). The overall mark should still feel balanced.

## 4. Concept

The concept should be the app's core action shown as a **simple object or gesture**, not the app's feature list.

- **Nimble Bot (done):** a chat bubble with three dots, i.e. a conversation with an agent.
- **NimbleTask (done):** a cream rounded box with a Nimble Blue tick cut into it, i.e. a ticked task. Chosen over a bare checkmark (too generic), a single to-do line (the bar turns into a dash at 16 px) and a card of to-dos (too close to Notes and Reminders).
- **Other apps:** pick the one thing the app does and turn it into a single everyday object.
  - Name it in one short phrase: "a conversation", "a task", "a photo", "a note".
  - Draw it in the fewest shapes that still read.
  - Reject any concept that needs a second object to be understood.
- **Family pattern that works:** a single cream object with one Nimble Blue detail cut into it (bubble + dots, box + tick). Prefer this over a bare cream shape; the cut-in detail is what ties the family together.
- Prefer objects over abstract symbols, and avoid clichés that belong to another product (gear, magnifier, generic cloud, paper plane).
- Avoid concepts that look like a system app (Messages, Notes, Photos, Files, Reminders) closely enough to be confused with it.

## 5. Process

1. Write the one-phrase concept for the app.
2. Sketch 3–4 alternatives as vector paths, on the standard gradient, in a throwaway script.
3. **Render a review sheet:** for each concept, a large preview plus 128, 32 and 16 px, with an approximate macOS mask applied (preview only, never in the master) and the one-phrase concept as a caption. Judge at 16 px first; most concepts fail there.
4. Pick one, then refine proportions and padding.
5. Keep the drawing in code (`scripts/generate_icon.swift` in each app) so the icon is reproducible and needs no external asset.
6. Generate the master, then **check its pixels** (section 6) before exporting.
7. Regenerate all sizes from the single 1024 master.

### Reference implementations

**Nimble Bot** (`Nimble Bot/scripts/generate_icon.swift`), on a 512 grid:

- bubble: rounded rectangle 320×210 at (96, 170), corner radius 90, plus a triangular tail from (150,190) to (120,110) to (230,176)
- dots: three circles of 46 px, spaced 62 px apart, starting at x = 182, y = 250, in Nimble Blue
- note: this script predates v2 and uses Generic RGB colors (see section 2). Its output matches v2's sRGB values; switch it to explicit sRGB the next time it's touched.

**NimbleTask** (`NimbleTask/scripts/generate_icon.swift`), on a 512 grid with a top-left origin; this is the v2-conformant template to copy:

- box: rounded rectangle 312×312 at (100, 100), corner radius 88, Cream
- tick: stroked polyline (174,262) → (232,320) → (342,194), width 48, round caps and joins, Nimble Blue

Run either with `swift scripts/generate_icon.swift <output.png>`.

## 6. Export

- Master: `AppIcon.png`, 1024×1024, sRGB, no alpha.
- **Pixel check:** sample the master's top-left corner, bottom-right corner and the mark. They must read exactly `#009AD6`, `#006CA5` and `#FAF8F4`. Also confirm `sips -g hasAlpha AppIcon.png` says `no`.
- macOS sizes, all downscaled from the master: 16, 32, 64, 128, 256, 512 and 1024 px (`AppIcon-mac-<size>.png`) in `Assets.xcassets/AppIcon.appiconset`.
- Downscale with `sips -z <n> <n> AppIcon.png --out AppIcon-mac-<n>.png`.
- The seven files fill the ten macOS slots in `Contents.json`:

  | Slot     | 1x                   | 2x                    |
  | -------- | -------------------- | --------------------- |
  | 16×16    | `AppIcon-mac-16.png`  | `AppIcon-mac-32.png`   |
  | 32×32    | `AppIcon-mac-32.png`  | `AppIcon-mac-64.png`   |
  | 128×128  | `AppIcon-mac-128.png` | `AppIcon-mac-256.png`  |
  | 256×256  | `AppIcon-mac-256.png` | `AppIcon-mac-512.png`  |
  | 512×512  | `AppIcon-mac-512.png` | `AppIcon-mac-1024.png` |

- **One icon source only.** The target's `ASSETCATALOG_COMPILER_APPICON_NAME` must point at `AppIcon`. Remove leftover Icon Composer `.icon` bundles and stray images from `Assets.xcassets` so nobody edits the wrong file.
- After building, confirm `Contents/Resources/AppIcon.icns` exists in the built app and shows the new icon (`sips -s format png AppIcon.icns --out check.png`).
- macOS may keep showing the old icon because of caching. Relaunch the app or run `killall Dock`.

## 7. Checklist

- [ ] No SF Symbol, text, photo or third-party artwork
- [ ] Full-bleed opaque square, no rounded corners or shadow
- [ ] Only Nimble Blue, Deep Blue and Cream, all set in sRGB
- [ ] Pixel check passes: `#009AD6`, `#006CA5`, `#FAF8F4`, no alpha
- [ ] Mark centered, about 60–65% of the width (lower end for square marks), flat, no thin details
- [ ] Cut-in detail about 46–48 on the 512 grid
- [ ] One concept, understandable in one phrase
- [ ] Still reads at 16×16 px on the review sheet
- [ ] Doesn't resemble a system app icon
- [ ] Generated by a script kept in the app's repo
- [ ] `AccentColor` in the app is `#009AD6` sRGB
- [ ] Asset catalog has only `AppIcon.appiconset` as the icon source
