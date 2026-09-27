import Testing
import Foundation
@testable import mdview

@Suite(.serialized)
final class FileWatcherTests {
    private var directory: URL!
    private var file: URL { directory.appendingPathComponent("document.md") }

    private final class Changes {
        private let lock = NSLock()
        private var callbacks = 0
        private var allOnMain = true
        var count: Int { lock.lock(); defer { lock.unlock() }; return callbacks }
        var deliveredOnMain: Bool { lock.lock(); defer { lock.unlock() }; return allOnMain }
        func record() {
            lock.lock()
            callbacks += 1
            allOnMain = allOnMain && Thread.isMainThread
            lock.unlock()
        }
    }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("initial".utf8).write(to: file)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func eventually(_ predicate: () -> Bool) async throws -> Bool {
        for _ in 0..<100 {
            if predicate() { return true }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return predicate()
    }

    private func waitForChange(_ changes: Changes, after count: Int) async throws {
        let changed = try await eventually { changes.count > count }
        #expect(changed, "Expected a callback for the watched pathname")
        #expect(changes.deliveredOnMain)
    }

    @Test func testRepeatedAtomicReplacementAndInPlaceEdit() async throws {
        let changes = Changes()
        let watcher = try #require(FileWatcher(url: file, onChange: changes.record))
        defer { watcher.stop() }
        for index in 1...3 {
            let count = changes.count
            try Data("replacement \(index)".utf8).write(to: file, options: .atomic)
            try await waitForChange(changes, after: count)
        }
        let count = changes.count
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(" appended".utf8))
        try handle.close()
        try await waitForChange(changes, after: count)
    }

    @Test func testDeleteRecreateAndInitiallyAbsentFile() async throws {
        let changes = Changes()
        let watcher = try #require(FileWatcher(url: file, onChange: changes.record))
        defer { watcher.stop() }
        try FileManager.default.removeItem(at: file)
        try await waitForChange(changes, after: 0)
        let count = changes.count
        try Data("recreated".utf8).write(to: file)
        try await waitForChange(changes, after: count)

        let absent = directory.appendingPathComponent("absent.md")
        let appeared = Changes()
        let absentWatcher = try #require(FileWatcher(url: absent, onChange: appeared.record))
        defer { absentWatcher.stop() }
        try Data("new".utf8).write(to: absent)
        try await waitForChange(appeared, after: 0)
    }

    @Test func testSameSizeInPlaceEditIsDetected() async throws {
        let changes = Changes()
        let watcher = try #require(FileWatcher(url: file, onChange: changes.record))
        defer { watcher.stop() }
        let handle = try FileHandle(forWritingTo: file)
        try handle.write(contentsOf: Data("updated".utf8))
        try handle.close()
        try await waitForChange(changes, after: 0)
    }

    @Test func testUnrelatedFilesAreFilteredAndRapidWritesAreCoalesced() async throws {
        let changes = Changes()
        let watcher = try #require(FileWatcher(url: file, onChange: changes.record))
        defer { watcher.stop() }
        try Data("unrelated".utf8).write(to: directory.appendingPathComponent("other.md"))
        try await Task.sleep(nanoseconds: 250_000_000)
        #expect(changes.count == 0)
        for index in 0..<5 {
            try Data("rapid \(index)".utf8).write(to: file, options: .atomic)
        }
        try await waitForChange(changes, after: 0)
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(changes.count == 1)
    }

    @Test func testStopCancelsPendingAndFutureCallbacks() async throws {
        let changes = Changes()
        let watcher = try #require(FileWatcher(url: file, onChange: changes.record))
        try Data("pending".utf8).write(to: file, options: .atomic)
        watcher.stop()
        watcher.stop()
        try Data("after stop".utf8).write(to: file, options: .atomic)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(changes.count == 0)
    }

    @Test func testLifecyclesReleaseDescriptors() async throws {
        func descriptors() -> Set<Int32> {
            Set((0..<1024).compactMap { fcntl(Int32($0), F_GETFD) >= 0 ? Int32($0) : nil })
        }
        // Warm libdispatch's shared resources before measuring watcher ownership.
        var warmup = FileWatcher(url: file, onChange: {})
        warmup?.stop()
        warmup = nil
        try await Task.sleep(nanoseconds: 100_000_000)
        let baseline = descriptors()
        for index in 0..<50 {
            var watcher = FileWatcher(url: file, onChange: {})
            try #require(watcher != nil)
            if index.isMultiple(of: 2) { watcher?.stop() }
            watcher = nil
        }
        let released = try await eventually { descriptors().subtracting(baseline).isEmpty }
        #expect(released, "Extra descriptors: \(descriptors().subtracting(baseline))")
    }

    @Test func testMissingParentFailsCleanly() {
        let missing = directory.appendingPathComponent("missing/document.md")
        #expect(FileWatcher(url: missing, onChange: {}) == nil)
    }
}
