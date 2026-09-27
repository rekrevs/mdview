import Testing
import Foundation
@testable import mdview

struct LinkDestinationTests {
    let document = URL(fileURLWithPath: "/tmp/docs/report.md")
    @Test func testExternalLinksAndUnsafeSchemes() {
        #expect(LinkDestination.resolve("https://example.com/a?q=1#two", relativeTo: document) == .external(URL(string: "https://example.com/a?q=1#two")!))
        #expect(LinkDestination.resolve("mailto:test@example.com", relativeTo: nil) == .external(URL(string: "mailto:test@example.com")!))
        for href in ["javascript:alert(1)", "data:text/html,test", "ssh://host", "file://server/path.md", ""] {
            #expect(LinkDestination.resolve(href, relativeTo: document) == .blocked)
        }
    }
    @Test func testRelativeDocumentsAndEncodedCharacters() {
        #expect(LinkDestination.resolve("../other/a%20b.markdown#s%C3%B6k", relativeTo: document) == .document(URL(fileURLWithPath: "/tmp/other/a b.markdown"), fragment: "sök"))
        #expect(LinkDestination.resolve("a%23b.MD", relativeTo: document) == .document(URL(fileURLWithPath: "/tmp/docs/a#b.MD"), fragment: nil))
    }
    @Test func testCurrentDocumentAndPureAnchor() {
        #expect(LinkDestination.resolve("#s%C3%B6k", relativeTo: document) == .anchor("sök"))
        #expect(LinkDestination.resolve("report.md#two", relativeTo: document) == .anchor("two"))
        #expect(LinkDestination.resolve("./report.md", relativeTo: document) == .anchor(""))
    }
    @Test func testFileLinksAndMissingBase() {
        #expect(LinkDestination.resolve("plot.png", relativeTo: document) == .localFile(URL(fileURLWithPath: "/tmp/docs/plot.png")))
        #expect(LinkDestination.resolve("relative.md", relativeTo: nil) == .blocked)
    }
}
