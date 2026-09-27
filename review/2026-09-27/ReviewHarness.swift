import AppKit
import SwiftUI
import Markdown
import SwiftMath

extension Notification.Name {
    static let zoomIn = Notification.Name("zoomIn")
    static let zoomOut = Notification.Name("zoomOut")
    static let zoomReset = Notification.Name("zoomReset")
}

@main struct ReviewHarness {
    static let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    static func pump(_ seconds: Double = 0.2) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
    static func allViews(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(allViews)
    }
    static func snapshot(_ view: NSView, _ name: String) {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
    }
    static func window<V: View>(_ view: V, width: Double = 640, height: Double = 650) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 80, y: 80, width: width, height: height), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.title = "mdview Review Harness"
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        w.contentView = host
        w.setContentSize(NSSize(width: width, height: height))
        w.makeKeyAndOrderFront(nil)
        pump()
        return w
    }
    static func render(_ name: String, _ md: String, width: Double = 640, height: Double = 650) {
        let doc = Document(parsing: md)
        print("\nCASE \(name) AST:\n\(doc.debugDescription())")
        let fixture = output.appendingPathComponent(name + ".md")
        try! md.write(to: fixture, atomically: true, encoding: .utf8)
        let w = window(ContentView(document: MarkdownDocument(text: md), fileURL: fixture), width: width, height: height)
        snapshot(w.contentView!, name)
        let labels = allViews(w.contentView!).compactMap { $0 as? MTMathUILabel }
        print("MATH LABELS \(name): \(labels.map { $0.latex })")
        print("VIEWS \(name): \(allViews(w.contentView!).map { String(describing: type(of: $0)) })")
        w.close()
    }
    static func fdSet() -> Set<Int32> { Set((0..<1024).map(Int32.init).filter { fcntl($0, F_GETFD) != -1 }) }
    static func mouse(_ type: NSEvent.EventType, _ point: NSPoint, _ w: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    }
    static func drag(_ from: NSPoint, _ to: NSPoint, _ w: NSWindow) {
        for n in 1...10 {
            let t = CGFloat(n)/10
            NSApp.postEvent(mouse(.leftMouseDragged, NSPoint(x: from.x+(to.x-from.x)*t,y: from.y+(to.y-from.y)*t), w), atStart: false)
        }
        NSApp.postEvent(mouse(.leftMouseUp, to, w), atStart: false)
        NSApp.sendEvent(mouse(.leftMouseDown, from, w))
        while let event = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: Date(), inMode: .default, dequeue: true) {
            NSApp.sendEvent(event)
        }
        pump()
    }
    static func interactionTests() {
        let md = "Alpha first paragraph.\n\nBravo second paragraph.\n\n[External link](https://example.com)\n\n$E=mc^2$"
        let w = window(ContentView(document: MarkdownDocument(text: md), fileURL: nil))
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        pump(0.5)
        print("INTERACTION key=\(w.isKeyWindow) appActive=\(NSApp.isActive)")
        let views = allViews(w.contentView!)
        let texts = views.filter { String(describing: type(of: $0)) == "AppKitTextInteractionView" }
        for (i,v) in texts.enumerated() { print("INTERACTION text \(i) frame \(v.convert(v.bounds, to: nil))") }
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } }
        defer {
            board.clearContents()
            let restored = saved.map { entries -> NSPasteboardItem in
                let item = NSPasteboardItem(); for (type,data) in entries { item.setData(data, forType: type) }; return item
            }
            board.writeObjects(restored)
            w.close()
        }
        if texts.count >= 3 {
            let a = texts[0].convert(texts[0].bounds, to: nil)
            let b = texts[1].convert(texts[1].bounds, to: nil)
            board.clearContents()
            drag(NSPoint(x:a.minX+1,y:a.midY), NSPoint(x:a.maxX-1,y:a.midY), w)
            let single = NSApp.sendAction(Selector(("copy:")), to:nil, from:nil)
            print("COPY single handled=\(single) value=\(String(reflecting:board.string(forType:.string))) responder=\(String(describing:w.firstResponder))")
            NSApp.sendEvent(mouse(.leftMouseDown, NSPoint(x:a.maxX,y:a.midY), w))
            NSApp.sendEvent(mouse(.leftMouseUp, NSPoint(x:a.maxX,y:a.midY), w))
            board.clearContents()
            drag(NSPoint(x:a.minX+1,y:a.midY), NSPoint(x:b.maxX-1,y:b.midY), w)
            let cross = NSApp.sendAction(Selector(("copy:")), to:nil, from:nil)
            print("COPY cross handled=\(cross) value=\(String(reflecting:board.string(forType:.string))) responder=\(String(describing:w.firstResponder))")
            snapshot(w.contentView!, "07-cross-selection")
            let link = texts[2]
            print("LINK accessibility role=\(String(describing:link.accessibilityRole())) actions=\(link.accessibilityActionNames())")
            board.clearContents()
            let selectAll = NSApp.sendAction(Selector(("selectAll:")), to:nil, from:nil)
            let copiedAll = NSApp.sendAction(Selector(("copy:")), to:nil, from:nil)
            print("COPY select-all handled=\(selectAll)/\(copiedAll) value=\(String(reflecting:board.string(forType:.string)))")
        }
        let w2 = window(ContentView(document: MarkdownDocument(text:"Second window $E=mc^2$"),fileURL:nil))
        func mathWidth(_ w: NSWindow) -> Double { Double(allViews(w.contentView!).compactMap{$0 as? MTMathUILabel}.first!.frame.width) }
        let before = [mathWidth(w),mathWidth(w2)]
        NotificationCenter.default.post(name: .zoomIn, object:nil); pump()
        print("ZOOM two windows before=\(before) after=\([mathWidth(w),mathWidth(w2)])")
        w2.close()
        let long = (0..<200).map { "Paragraph \($0): ordinary reading text." }.joined(separator:"\n\n")
        let begin = Date()
        let scrolling = window(ContentView(document:MarkdownDocument(text:long),fileURL:nil))
        print("PERF 200 paragraphs host+layout+0.2s pump seconds=\(Date().timeIntervalSince(begin))")
        let capture = allViews(scrolling.contentView!).compactMap{$0 as? KeyboardCaptureView}.first!
        let scroll = allViews(scrolling.contentView!).compactMap{$0 as? NSScrollView}.first!
        for (key, modifiers) in [(UInt16(125),NSEvent.ModifierFlags()),(UInt16(125),NSEvent.ModifierFlags.command),(UInt16(115),NSEvent.ModifierFlags())] {
            let event = NSEvent.keyEvent(with:.keyDown, location:.zero, modifierFlags:modifiers, timestamp:0, windowNumber:scrolling.windowNumber, context:nil, characters:"", charactersIgnoringModifiers:"", isARepeat:false,keyCode:key)!
            capture.keyDown(with:event); pump(0.3)
            print("SCROLL key=\(key) modifiers=\(modifiers.rawValue) y=\(scroll.contentView.bounds.origin.y)")
        }
        scrolling.close()
    }
    static func linkTests() {
        var opened: [URL] = []
        let root = VStack(alignment: .leading, spacing: 0) {
            MarkdownContentView(text: "[External](https://example.com) — [Relative](README.md) — [Anchor](#target)", baseURL:URL(fileURLWithPath:FileManager.default.currentDirectoryPath),fontSize:14).frame(height:40)
            Link("Positive control", destination:URL(string:"https://example.com/control")!).frame(height:40)
        }.padding(20).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .environment(\.openURL, OpenURLAction { url in opened.append(url); return .handled })
        let w = window(root, height:400)
        w.makeKeyAndOrderFront(nil); pump()
        for x in [40.0,115.0,190.0] {
            NSApp.sendEvent(mouse(.leftMouseDown,NSPoint(x:x,y:360),w))
            NSApp.sendEvent(mouse(.leftMouseUp,NSPoint(x:x,y:360),w))
            pump()
        }
        print("LINK markdown click callbacks=\(opened)")
        NSApp.sendEvent(mouse(.leftMouseDown,NSPoint(x:65,y:320),w))
        NSApp.sendEvent(mouse(.leftMouseUp,NSPoint(x:65,y:320),w)); pump()
        print("LINK after positive control callbacks=\(opened)")
        w.close()
    }
    static func watchTests() {
        let url = output.appendingPathComponent("watch-scratch.md")
        try! "initial".write(to: url, atomically: false, encoding: .utf8)
        var changes: [String] = []
        var watcher: FileWatcher? = FileWatcher(url: url) { changes.append((try? String(contentsOf: url)) ?? "MISSING") }
        try! "in-place-1".write(to: url, atomically: false, encoding: .utf8); pump(0.4)
        print("WATCH in-place: \(changes)"); changes = []
        try! "atomic-1".write(to: url, atomically: true, encoding: .utf8); pump(0.4)
        print("WATCH atomic-1: \(changes)"); changes = []
        try! "atomic-2".write(to: url, atomically: true, encoding: .utf8); pump(0.4)
        print("WATCH atomic-2: \(changes)"); changes = []
        try! "in-place-after-atomic".write(to: url, atomically: false, encoding: .utf8); pump(0.4)
        print("WATCH in-place-after-atomic: \(changes)")
        withExtendedLifetime(watcher) {}; watcher = nil; pump()
        let before = fdSet()
        for _ in 0..<25 {
            var short: FileWatcher? = FileWatcher(url: url) {}
            withExtendedLifetime(short) {}; short = nil
            pump(0.01)
        }
        pump()
        print("WATCH descriptor growth after 25 lifecycles: \(fdSet().subtracting(before).count)")
        try! FileManager.default.removeItem(at: url)
    }
    static func main() {
        FileManager.default.changeCurrentDirectoryPath(output.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path)
        if CommandLine.arguments.contains("--watch-only") {
            // DispatchQueue.main callbacks must run outside the GUI test's
            // main-queue block; nested run loops cannot drain that block's queue.
            watchTests()
            print("WATCH COMPLETE")
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            runTests()
            fflush(stdout)
            exit(0)
        }
        app.run()
    }
    static func runTests() {
        let app = NSApplication.shared
        app.appearance = NSAppearance(named: .aqua)
        print("OS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        render("01-reading", """
        # Reading and links
        Alpha first paragraph with **bold** and *italic* and ~~deleted~~.

        Bravo second paragraph to select together with Alpha.

        [External link](https://example.com) — [Local link](../../../README.md) — [Heading](#target)

        - [ ] Pending item
        - [x] Completed item
        - Normal item

        ![Existing icon](../../../AppIcon.iconset/icon_128x128.png)

        ## Target
        End of document.
        """)
        render("02-math", #"""
        # Math contexts
        Simple: $E = mc^2$.

        Display one line: $$x^2 + y^2 = z^2$$

        $$
        \int_0^1 x^2 dx = \frac{1}{3}
        $$

        **Math inside bold: $x^2$**

        ## Heading $x^2$
        | Formula | Meaning |
        | --- | --- |
        | $x^2$ | square |

        ```math
        x^2 + y^2 = z^2
        ```
        Escaped dollars: \$5 and \$10.
        """#)
        render("03-structure", #"""
        # Nested content
        > Visible paragraph
        >
        > ## Quote heading SHOULD APPEAR
        >
        > - Quote item SHOULD APPEAR
        >
        > ```swift
        > print("QUOTE CODE SHOULD APPEAR")
        > ```

        - Visible list item

          ```swift
          print("LIST CODE SHOULD APPEAR")
          ```

        | Left | Right | Centre |
        | :--- | ---: | :---: |
        | short | 123 | value |
        | considerably longer | 456789 | other |

        ```python
            first_line_indent = 4
            second_line_indent = 4
        ```
        """#)
        render("04-math-integrity", #"""
        # Formula integrity
        $$\begin{pmatrix} a & b \\ c & d \end{pmatrix}$$

        $a_1 + b_2 + c_3$

        $a*b*c$

        Inline before display: $a$ then $$b$$.

        `literal $x$` and a code block:

        ```text
        $x$ and $$y$$
        ```
        """#)
        render("05-flow-narrow", "A long introductory sentence that should wrap continuously with the formula $x^2$ and a long continuation of the same paragraph which should continue on the same baseline and flow naturally onto the next line.", width: 500, height: 400)
        let existing = try! String(contentsOfFile: "test-math.md")
        render("06-existing-fixture", existing, height: 1100)
        app.appearance = NSAppearance(named: .darkAqua)
        render("08-dark", "# Dark mode\n\nOrdinary **bold** text with $x^2$.\n\n```swift\nlet value = 42\n```\n\n> A quote")
        app.appearance = NSAppearance(named: .aqua)
        interactionTests()
        linkTests()
        print("HARNESS COMPLETE")
    }
}
