import CoreServices
import Foundation

/// Watches one folder (non-recursive) for file add/remove/modify via
/// FSEvents, reporting changes to `onChange`. Bursts are debounced by the
/// FSEvents latency window itself (spec §10.3).
@Observable
final class FolderWatcher {
    enum Change {
        case added(URL)
        case removed(URL)
        case modified(URL)
    }

    private var stream: FSEventStreamRef?
    private var onChange: ((Change) -> Void)?
    private var watchedPath: String?

    func start(path: String, latency: TimeInterval = 0.5, onChange: @escaping (Change) -> Void) {
        stop()
        self.onChange = onChange
        self.watchedPath = path

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let pathsToWatch = [path] as CFArray
        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (streamRef, clientCallbackInfo, numEvents, eventPaths, eventFlags, eventIds) in
                guard let clientCallbackInfo else { return }
                let watcher = Unmanaged<FolderWatcher>.fromOpaque(clientCallbackInfo).takeUnretainedValue()
                watcher.handleEvents(numEvents: numEvents, eventPaths: eventPaths, eventFlags: eventFlags)
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return }

        stream = newStream
        FSEventStreamSetDispatchQueue(newStream, DispatchQueue.main)
        FSEventStreamStart(newStream)
    }

    private func handleEvents(numEvents: Int, eventPaths: UnsafeRawPointer, eventFlags: UnsafePointer<FSEventStreamEventFlags>) {
        guard let paths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] else { return }
        for i in 0..<numEvents {
            let path = paths[i]
            // Only report direct children of the watched folder; ignore
            // events bubbling up from subfolders.
            guard let watchedPath, path.deletingLastPathComponentString == watchedPath else { continue }
            let flags = eventFlags[i]
            let url = URL(fileURLWithPath: path)
            if flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
                onChange?(.removed(url))
            } else if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 {
                onChange?(.added(url))
            } else if flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 || flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
                onChange?(.modified(url))
            }
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        onChange = nil
        watchedPath = nil
    }

    deinit {
        stop()
    }
}

private extension String {
    var deletingLastPathComponentString: String {
        (self as NSString).deletingLastPathComponent
    }
}
