import Foundation

/// Watches a pathname, including editors that save by replacing its inode.
/// Callbacks are coalesced and delivered on the main queue.
final class FileWatcher {
    private struct Snapshot: Equatable {
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int

        init(_ info: stat) {
            device = info.st_dev
            inode = info.st_ino
            size = info.st_size
            modifiedSeconds = info.st_mtimespec.tv_sec
            modifiedNanoseconds = info.st_mtimespec.tv_nsec
            changedSeconds = info.st_ctimespec.tv_sec
            changedNanoseconds = info.st_ctimespec.tv_nsec
        }

        func isSameFile(as other: Snapshot) -> Bool {
            device == other.device && inode == other.inode
        }
    }

    private let url: URL
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "com.mdview.file-watcher")
    private let queueKey = DispatchSpecificKey<Bool>()
    // Serialize callback delivery with stop, including stop called by the callback.
    private let callbackLock = NSRecursiveLock()
    private var stopped = false // protected by callbackLock
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var watchedFile: Snapshot?
    private var lastSnapshot: Snapshot?
    private var pendingChange: DispatchWorkItem?

    /// A missing file is allowed; the directory watch detects its creation.
    init?(url: URL, onChange: @escaping () -> Void) {
        self.url = url.standardizedFileURL
        self.onChange = onChange
        let directoryFD = open(url.deletingLastPathComponent().path, O_EVTONLY)
        guard directoryFD >= 0 else { return nil }
        queue.setSpecific(key: queueKey, value: true)
        queue.sync {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: directoryFD,
                eventMask: [.write, .rename, .delete, .attrib],
                queue: queue
            )
            source.setEventHandler { [weak self] in self?.checkForChange() }
            // Capture the descriptor itself: self can disappear before cancellation runs.
            source.setCancelHandler { close(directoryFD) }
            directorySource = source
            source.resume()
            lastSnapshot = snapshot()
            updateFileWatch(to: lastSnapshot)
        }
    }

    /// Once this returns no new callback can begin. Safe to call repeatedly.
    func stop() {
        callbackLock.lock()
        stopped = true
        callbackLock.unlock()
        let cleanup = {
            self.pendingChange?.cancel()
            self.pendingChange = nil
            self.fileSource?.cancel()
            self.fileSource = nil
            self.directorySource?.cancel()
            self.directorySource = nil
            self.watchedFile = nil
        }
        if DispatchQueue.getSpecific(key: queueKey) == true {
            cleanup()
        } else {
            queue.sync(execute: cleanup)
        }
    }

    deinit { stop() }

    private func snapshot() -> Snapshot? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return Snapshot(info)
    }

    private func updateFileWatch(to current: Snapshot?) {
        if let current, let watchedFile, current.isSameFile(as: watchedFile) { return }
        fileSource?.cancel()
        fileSource = nil
        watchedFile = nil
        guard current != nil else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        var info = stat()
        guard fstat(fd, &info) == 0 else { close(fd); return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.checkForChange() }
        source.setCancelHandler { close(fd) }
        watchedFile = Snapshot(info)
        fileSource = source
        source.resume()
    }

    private func checkForChange() {
        // Sources already queued during cancellation must not re-arm a watch.
        guard directorySource != nil else { return }
        let current = snapshot()
        updateFileWatch(to: current)
        guard current != lastSnapshot else { return }
        lastSnapshot = current
        pendingChange?.cancel()
        let change = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.callbackLock.lock()
                defer { self.callbackLock.unlock() }
                guard !self.stopped else { return }
                self.onChange()
            }
        }
        pendingChange = change
        queue.asyncAfter(deadline: .now() + .milliseconds(100), execute: change)
    }
}
