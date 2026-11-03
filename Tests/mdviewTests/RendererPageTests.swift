import Testing
import Foundation
import ReaderCore

struct RendererPageTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mdview-renderer-page-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func makeIndex(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("<!doctype html>".utf8).write(to: url)
    }

    // SwiftPM's native build system emits a flat resource bundle (the layout shipped today).
    @Test func testFlatResourceBundle() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = root.appendingPathComponent("mdview_mdview.bundle/Resources/Web/index.html")
        try makeIndex(at: index)
        #expect(RendererPage.indexURL(searching: [root])?.standardizedFileURL == index.standardizedFileURL)
    }

    // The Swift Build backend emits a macOS-style bundle with Contents/Resources.
    @Test func testContentsResourceBundle() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("mdview_mdview.bundle")
        let index = bundle.appendingPathComponent("Contents/Resources/Resources/Web/index.html")
        try makeIndex(at: index)
        let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "mdview.resources"], format: .xml, options: 0)
        try info.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        #expect(RendererPage.indexURL(searching: [root])?.standardizedFileURL == index.standardizedFileURL)
    }

    @Test func testSearchOrderAndMissingResources() throws {
        let empty = try makeRoot(), filled = try makeRoot()
        defer { try? FileManager.default.removeItem(at: empty); try? FileManager.default.removeItem(at: filled) }
        #expect(RendererPage.indexURL(searching: [empty]) == nil)
        let index = filled.appendingPathComponent("mdview_mdview.bundle/Resources/Web/index.html")
        try makeIndex(at: index)
        #expect(RendererPage.indexURL(searching: [empty, filled])?.standardizedFileURL == index.standardizedFileURL)
    }

    @Test func testRenderOptions() {
        let file = URL(fileURLWithPath: "/tmp/docs/a b.md")
        let options = RendererPage.renderOptions(for: file)
        #expect(options["baseURL"] as? String == "file:///tmp/docs/")
        #expect(options["documentURL"] as? String == "file:///tmp/docs/a%20b.md")
        #expect(options["diagrams"] == nil)
        #expect(RendererPage.renderOptions(for: file, diagrams: false)["diagrams"] as? Bool == false)
        let untitled = RendererPage.renderOptions(for: nil)
        #expect(untitled["baseURL"] as? String == "" && untitled["documentURL"] as? String == "")
    }
}

struct PreviewTextTests {
    @Test func testWithinLimit() {
        let result = PreviewText.decode(Data("# Title ✓".utf8), limit: 100)
        #expect(result?.text == "# Title ✓" && result?.truncated == false)
    }
    @Test func testTruncationKeepsWholeCharacters() {
        let data = Data("ab✓cd".utf8) // ✓ is 3 bytes at offsets 2-4
        for limit in 2...4 {
            let result = PreviewText.decode(data, limit: limit)
            #expect(result?.text == "ab", "limit \(limit)")
            #expect(result?.truncated == true)
        }
        #expect(PreviewText.decode(data, limit: 5)?.text == "ab✓")
    }
    @Test func testInvalidUTF8() {
        #expect(PreviewText.decode(Data([0x23, 0x20, 0xE5, 0xE4, 0xF6]), limit: 100) == nil)
        #expect(PreviewText.decode(Data([0xE5, 0x61, 0x62, 0x63, 0x64, 0x65]), limit: 4) == nil)
    }
}
