import AppKit
import AVKit
import SwiftUI

/// Full-size viewer: fit-to-window by default (never upscaled past 100%),
/// toggleable 100% actual-pixels with pan/zoom, prev/next within the
/// current filtered+sorted list, in-place classification (spec §8). Videos
/// play back via AVKit instead of the zoomable image, autoplaying on open.
struct FullSizeImageView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    let photos: [Photo]
    let thumbnailService: ThumbnailService
    let imageLoader: FullSizeImageLoader
    let onClassify: (Category, [String]) -> Void
    let onClose: () -> Void

    @State private var image: NSImage?
    @State private var isFullResolution = false
    @State private var isLoadingFullResolution = false
    @State private var loadedPhotoID: String?
    /// nil = fit-to-window; otherwise an absolute scale where 1.0 = 100%.
    @State private var absoluteScale: CGFloat?
    /// Pan committed by finished drags; `activeDrag` is the in-flight
    /// gesture's translation on top of it, folded in on gesture end so a new
    /// drag continues from where the last one left off.
    @State private var dragOffset: CGSize = .zero
    @State private var activeDrag: CGSize = .zero
    @FocusState private var isFocused: Bool

    // Kept as a single persistent instance; the view swaps the player's
    // item rather than recreating the player per photo.
    @State private var videoPlayer = AVPlayer()
    @State private var isVideoReady = false
    @State private var videoLoadFailed = false
    @State private var playbackFailureObserver: NSObjectProtocol?

    private var currentPhoto: Photo? {
        photos.first(where: { $0.id == appState.highlightedPhotoID })
    }

    private var currentIndex: Int? {
        guard let id = appState.highlightedPhotoID else { return nil }
        return photos.firstIndex(where: { $0.id == id })
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    Color.black.opacity(0.001) // catches taps for focus without a visible layer

                    if let photo = currentPhoto, photo.isVideo, isVideoReady {
                        VideoPlayerView(player: videoPlayer)
                    }

                    if let photo = currentPhoto, photo.isVideo {
                        if !isVideoReady {
                            if videoLoadFailed {
                                VStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 32))
                                    Text("Can't play this video")
                                }
                                .foregroundStyle(Color(white: 0.85))
                            } else {
                                ProgressView()
                            }
                        }
                    } else if let image {
                        let fitScale = fitScale(for: image.size, in: geometry.size)
                        let scale = absoluteScale ?? fitScale
                        let offset = clampedOffset(
                            CGSize(width: dragOffset.width + activeDrag.width, height: dragOffset.height + activeDrag.height),
                            imageSize: image.size, scale: scale, container: geometry.size
                        )
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: image.size.width * scale, height: image.size.height * scale)
                            .offset(offset)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in activeDrag = value.translation }
                                    .onEnded { value in
                                        dragOffset = clampedOffset(
                                            CGSize(width: dragOffset.width + value.translation.width, height: dragOffset.height + value.translation.height),
                                            imageSize: image.size, scale: scale, container: geometry.size
                                        )
                                        activeDrag = .zero
                                    }
                            )
                    } else {
                        ProgressView()
                    }
                }
            }
            // Fixed, fully opaque neutral grey (the semantic system greys can
            // be translucent): nothing behind the viewer bleeds through, and
            // photos are judged against the same backdrop in light and dark
            // mode.
            .background(Color(white: 0.22))
            Divider()
            StatusBarView()
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear {
            isFocused = true
            loadCurrentMedia()
        }
        .onDisappear {
            teardownVideo()
        }
        .onChange(of: appState.highlightedPhotoID) { _, _ in
            resetView()
            loadCurrentMedia()
        }
        .onKeyPress(.escape) { onClose(); return .handled }
        .onKeyPress(.return) { onClose(); return .handled }
        .onKeyPress(.space) { onClose(); return .handled }
        .onKeyPress(.leftArrow) { step(by: -1); return .handled }
        .onKeyPress(.rightArrow) { step(by: 1); return .handled }
        .onKeyPress(.upArrow) { step(by: -1); return .handled }
        .onKeyPress(.downArrow) { step(by: 1); return .handled }
        .onKeyPress(.home) { jump(toIndex: 0); return .handled }
        .onKeyPress(.end) { jump(toIndex: photos.count - 1); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "01234")) { press in
            guard press.modifiers.isDisjoint(with: [.command, .option, .control]),
                  let value = Int(press.characters), let category = Category(rawValue: value),
                  let id = appState.highlightedPhotoID
            else { return .ignored }
            onClassify(category, [id])
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "+=")) { _ in zoom(by: 1.25); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "-_")) { _ in zoom(by: 0.8); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "?")) { _ in
            openWindow(id: "shortcuts")
            return .handled
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    guard currentPhoto?.isVideo != true else { return }
                    absoluteScale = (absoluteScale ?? 1.0) * value
                    ensureFullResolution()
                }
        )
        .toolbar {
            ToolbarItemGroup {
                if currentPhoto?.isVideo != true {
                    Button {
                        absoluteScale = (absoluteScale == nil) ? 1.0 : nil
                        dragOffset = .zero
                        activeDrag = .zero
                        if absoluteScale != nil { ensureFullResolution() }
                    } label: {
                        Image(systemName: absoluteScale == nil ? "1.magnifyingglass" : "arrow.up.left.and.arrow.down.right")
                    }
                    .help(absoluteScale == nil ? "Actual Size (100%)" : "Fit to Window")
                }

                Button(action: onClose) {
                    Image(systemName: "xmark.circle")
                }
                .help("Close")
            }
        }
    }

    /// Margin of background kept visible on every side in fit-to-window mode.
    private static let fitMargin: CGFloat = 6

    private func fitScale(for imageSize: CGSize, in containerSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1.0 }
        let available = CGSize(
            width: max(containerSize.width - Self.fitMargin * 2, 1),
            height: max(containerSize.height - Self.fitMargin * 2, 1)
        )
        let widthScale = available.width / imageSize.width
        let heightScale = available.height / imageSize.height
        return min(widthScale, heightScale, 1.0)
    }

    private func zoom(by factor: CGFloat) {
        let base = absoluteScale ?? 1.0
        absoluteScale = min(max(base * factor, 0.05), 8.0)
        ensureFullResolution()
    }

    /// Keeps the image at least partially anchored to the container: no
    /// panning when it fits, and never further than its own edges when
    /// zoomed in.
    private func clampedOffset(_ proposed: CGSize, imageSize: CGSize, scale: CGFloat, container: CGSize) -> CGSize {
        let maxX = max(0, (imageSize.width * scale - container.width) / 2)
        let maxY = max(0, (imageSize.height * scale - container.height) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func resetView() {
        absoluteScale = nil
        dragOffset = .zero
        activeDrag = .zero
    }

    private func step(by delta: Int) {
        guard let currentIndex else { return }
        jump(toIndex: currentIndex + delta)
    }

    private func jump(toIndex index: Int) {
        guard photos.indices.contains(index) else { return }
        appState.select(photos[index].id)
    }

    private func loadCurrentMedia() {
        guard let photo = currentPhoto, photo.id != loadedPhotoID else { return }
        teardownVideo()
        loadedPhotoID = photo.id
        image = nil
        if photo.isVideo {
            loadVideo(photo)
        } else {
            loadImage(photo)
        }
    }

    /// Pixel budget for the fit-to-window decode: the largest screen's long
    /// side in device pixels. More is wasted work; the full-resolution tier
    /// covers zooming.
    private var fitDecodeMaxPixel: Int {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let size = screen?.frame.size ?? CGSize(width: 1920, height: 1080)
        let scale = screen?.backingScaleFactor ?? 2
        return max(1600, Int(max(size.width, size.height) * scale))
    }

    private func loadImage(_ photo: Photo) {
        isFullResolution = false
        isLoadingFullResolution = false
        let maxPixel = fitDecodeMaxPixel
        Task {
            // Instant placeholder: the grid's cached thumbnail, stretched to
            // the photo's real dimensions so the layout doesn't jump when
            // the sharp decode replaces it.
            if let width = photo.pixelWidth, let height = photo.pixelHeight,
               let thumbnailURL = await thumbnailService.cachedThumbnailURL(path: photo.id, fileModified: photo.fileModified, fileSize: photo.fileSize),
               loadedPhotoID == photo.id, image == nil,
               let placeholder = NSImage(contentsOf: thumbnailURL) {
                placeholder.size = NSSize(width: width, height: height)
                image = placeholder
            }

            let loaded = await imageLoader.fitImage(for: photo, maxPixel: maxPixel)
            guard loadedPhotoID == photo.id else { return }
            if let loaded {
                image = loaded.image
                isFullResolution = loaded.isFullResolution
                if absoluteScale != nil { ensureFullResolution() }
            }
            prefetchNeighbors(around: photo)
        }
    }

    /// Decodes the two photos ahead and one behind so arrow-key navigation
    /// hits the loader's cache.
    private func prefetchNeighbors(around photo: Photo) {
        guard let index = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        let neighbors = [index + 1, index - 1, index + 2]
            .filter { photos.indices.contains($0) }
            .map { photos[$0] }
        guard !neighbors.isEmpty else { return }
        let maxPixel = fitDecodeMaxPixel
        Task {
            await imageLoader.prefetch(neighbors, maxPixel: maxPixel)
        }
    }

    /// Swaps the downsampled bitmap for a full decode when the user zooms —
    /// the layout is unaffected because both share the same logical size.
    private func ensureFullResolution() {
        guard let photo = currentPhoto, !photo.isVideo,
              !isFullResolution, !isLoadingFullResolution else { return }
        isLoadingFullResolution = true
        Task {
            let loaded = await imageLoader.fullImage(for: photo)
            isLoadingFullResolution = false
            guard loadedPhotoID == photo.id, absoluteScale != nil, let loaded else { return }
            image = loaded.image
            isFullResolution = true
        }
    }

    private func loadVideo(_ photo: Photo) {
        let url = photo.fileURL
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        playbackFailureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            Task { @MainActor in
                guard loadedPhotoID == photo.id else { return }
                reportPlaybackFailure()
            }
        }

        Task {
            let playable = (try? await asset.load(.isPlayable)) ?? false
            guard loadedPhotoID == photo.id else { return }
            if playable {
                videoPlayer.replaceCurrentItem(with: item)
                isVideoReady = true
                videoPlayer.play()
            } else {
                reportPlaybackFailure()
            }
        }
    }

    private func reportPlaybackFailure() {
        videoPlayer.pause()
        videoPlayer.replaceCurrentItem(with: nil)
        isVideoReady = false
        videoLoadFailed = true
        NSSound(named: "Basso")?.play()
    }

    private func teardownVideo() {
        videoPlayer.pause()
        videoPlayer.replaceCurrentItem(with: nil)
        isVideoReady = false
        videoLoadFailed = false
        if let playbackFailureObserver {
            NotificationCenter.default.removeObserver(playbackFailureObserver)
        }
        playbackFailureObserver = nil
    }
}

/// AppKit `AVPlayerView` wrapper. Must be used instead of AVKit's SwiftUI
/// `VideoPlayer`: instantiating that type's generic metadata aborts
/// (getSuperclassMetadata fatal error in _AVKit_SwiftUI) on some macOS 26
/// builds, crashing the app as soon as the viewer opens.
private struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
