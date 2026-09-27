import AppKit
import WebKit

@MainActor
final class Checks: NSObject, NSApplicationDelegate {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    var failures = 0
    var count = 0
    var windows: [NSWindow] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await run() } catch { check(false, "Unhandled: \(error)") }
            print("RESULT \(count-failures)/\(count) passed")
            fflush(stdout)
            exit(failures == 0 ? 0 : 1)
        }
    }
    func check(_ value: Bool, _ label: String) {
        count += 1; if !value { failures += 1 }
        print("\(value ? "PASS" : "FAIL") \(label)"); fflush(stdout)
    }
    func delay(_ seconds: Double = 0.1) async { try? await Task.sleep(nanoseconds: UInt64(seconds*1_000_000_000)) }
    func until(_ label: String, _ predicate: () async throws -> Bool) async throws {
        for _ in 0..<150 { if try await predicate() { return }; await delay() }
        throw NSError(domain:"ReaderChecks",code:1,userInfo:[NSLocalizedDescriptionKey:"Timed out: \(label)"])
    }
    func js(_ reader: ReaderController, _ script: String) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            reader.webView!.evaluateJavaScript(script) { value,error in
                if let error { continuation.resume(throwing:error) }
                else { continuation.resume(returning:value ?? NSNull()) }
            }
        }
    }
    func bool(_ reader: ReaderController, _ script: String) async throws -> Bool { try await js(reader,script) as? Bool ?? false }
    func open(_ reader: ReaderController, width: Double = 760, height: Double = 820) async throws -> NSWindow {
        let w = NSWindow(contentRect:NSRect(x:100,y:100,width:width,height:height),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        w.isReleasedWhenClosed = false; w.title = "mdview verification"
        w.contentView = reader.makeWebView(); w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true); windows.append(w)
        try await until("renderer ready") { !reader.isLoading }
        if let error = reader.errorMessage { throw NSError(domain:"ReaderChecks",code:2,userInfo:[NSLocalizedDescriptionKey:error]) }
        await delay(0.2)
        return w
    }
    func snapshot(_ reader: ReaderController, _ name: String) async throws {
        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            reader.webView!.takeSnapshot(with:nil) { image,error in
                if let image { continuation.resume(returning:image) } else { continuation.resume(throwing:error ?? URLError(.unknown)) }
            }
        }
        let rep = NSBitmapImageRep(data:image.tiffRepresentation!)!
        try rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
    }
    func mouse(_ type:NSEvent.EventType, _ point:NSPoint, _ window:NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
    }
    func drag(_ from:NSPoint,_ to:NSPoint,_ window:NSWindow) async {
        for i in 1...10 { let t=CGFloat(i)/10; NSApp.postEvent(mouse(.leftMouseDragged,NSPoint(x:from.x+(to.x-from.x)*t,y:from.y+(to.y-from.y)*t),window),atStart:false) }
        NSApp.postEvent(mouse(.leftMouseUp,to,window),atStart:false)
        NSApp.sendEvent(mouse(.leftMouseDown,from,window))
        while let event=NSApp.nextEvent(matching:[.leftMouseDragged,.leftMouseUp],until:Date(),inMode:.default,dequeue:true) { NSApp.sendEvent(event) }
        await delay()
    }
    func copy(_ reader: ReaderController) async -> String {
        NSPasteboard.general.clearContents()
        reader.focusDocument()
        let accepted=NSApp.sendAction(#selector(NSText.copy(_:)),to:nil,from:nil)
        await delay(0.2)
        let text=NSPasteboard.general.string(forType:.string) ?? ""
        if !accepted { print("Copy action not accepted") }
        return text
    }
    func run() async throws {
        let board=NSPasteboard.general
        let saved=(board.pasteboardItems ?? []).map { item in item.types.compactMap { type in item.data(forType:type).map{(type,$0)} } }
        defer {
            board.clearContents(); board.writeObjects(saved.map{ entries -> NSPasteboardItem in let item=NSPasteboardItem(); for(type,data) in entries { item.setData(data,forType:type) }; return item })
            windows.forEach { $0.close() }
        }
        let fixture=output.appendingPathComponent("document.md")
        let other=output.appendingPathComponent("other file.markdown")
        try "# Other\n\n## Sök".write(to:other,atomically:true,encoding:.utf8)
        let icon=output.appendingPathComponent("image with space.png")
        try? FileManager.default.removeItem(at:icon)
        try FileManager.default.copyItem(at:root.appendingPathComponent("AppIcon.iconset/icon_128x128.png"),to:icon)
        let markdown = #"""
        Alpha first paragraph.

        Bravo second paragraph.

        # Reader checks

        Styled **bold** text. Other **bold** text.

        [External](https://example.com) · [Local](other%20file.markdown#s%C3%B6k) · [Anchor](#target)

        - [ ] Pending
        - [x] Complete

        > ## Nested heading
        > - Nested list
        > ```swift
        > let nested = 42
        > ```

        ```python
            first_line = 1
            second_line = 2
        ```

        ![Existing icon](image%20with%20space.png)

        ## Target

        Inline $E=mc^2$ and **bold $x^2$**.

        $$
        \begin{pmatrix} a & b \\ c & d \end{pmatrix}
        $$

        ```math
        \frac{1}{2}
        ```

        | Left | Right | Centre |
        | :--- | ---: | :---: |
        | $x^2$ | 123 | c |
        """#
        try markdown.write(to:fixture,atomically:true,encoding:.utf8)
        let reader=ReaderController(markdown:markdown,fileURL:fixture)
        let w=try await open(reader)
        check(w.isKeyWindow && NSApp.isActive,"active native test window")
        check(ReaderResources.indexURL!.path.contains(".app/Contents/Resources/"),"resources resolved from relocated app, not build tree")
        check(try await bool(reader,"document.querySelectorAll('.katex').length===5"),"inline, styled, block, fenced and table math render")
        check(try await bool(reader,"document.querySelectorAll('mtr').length===2"),"matrix retains both rows")
        check(try await bool(reader,"document.querySelectorAll('input[type=checkbox]').length===2 && document.querySelectorAll('input:checked').length===1"),"task list states retained")
        check(try await bool(reader,"document.querySelector('blockquote h2')!==null && document.querySelector('blockquote pre').textContent.includes('nested')"),"nested heading/list/code retained")
        check(try await bool(reader,"document.querySelector('code.language-python').textContent==='    first_line = 1\\n    second_line = 2\\n'"),"code whitespace exact")
        check(try await bool(reader,"getComputedStyle(document.querySelectorAll('th')[1]).textAlign==='right' && getComputedStyle(document.querySelectorAll('th')[2]).textAlign==='center'"),"GFM table alignment")
        try await until("local image") { try await self.bool(reader,"document.querySelector('img')?.naturalWidth===128") }
        check(true,"relative image with encoded space loaded through local handler")
        // Reproduce the user's mouse drag across paragraphs, then use native Copy.
        let positions=try await js(reader,"(()=>{const p=document.querySelectorAll('main>p'); const a=p[0].firstChild,b=p[1].firstChild; const r=document.createRange(); r.selectNodeContents(a); const x=r.getBoundingClientRect(); r.selectNodeContents(b); const y=r.getBoundingClientRect(); return {ax:x.left+1,ay:x.top+x.height/2,bx:y.right-1,by:y.top+y.height/2};})()") as! [String:Double]
        let web=reader.webView!
        func point(_ x:Double,_ y:Double)->NSPoint { web.convert(NSPoint(x:x,y:web.isFlipped ? y : web.bounds.height-y),to:nil) }
        await drag(point(positions["ax"]!,positions["ay"]!),point(positions["bx"]!,positions["by"]!),w)
        var copied=await copy(reader)
        print("CROSS COPY \(String(reflecting:copied))")
        check(copied.contains("Alpha first paragraph.") && copied.contains("Bravo second paragraph."),"native drag + Copy spans two paragraphs")
        try await snapshot(reader,"selection")
        _ = try await js(reader,"(()=>{const range=document.createRange();range.selectNodeContents(document.querySelector('main'));const s=getSelection();s.removeAllRanges();s.addRange(range);})()")
        copied=await copy(reader)
        check(copied.contains("$E=mc^2$") && copied.components(separatedBy:"$E=mc^2$").count==2,"native Copy includes each formula's LaTeX once")
        check(copied.contains("[ ] Pending") && copied.contains("[x] Complete") && copied.contains("    first_line = 1\n    second_line = 2"),"native Copy spans lists and preserves code indent")
        let rich = board.string(forType:.html) ?? ""
        check(rich.contains("border-collapse") && rich.contains("Courier New"),"native HTML clipboard carries table and code formatting")
        check(rich.contains(other.absoluteString+"#s%C3%B6k"),"native HTML clipboard resolves relative document links")
        try rich.write(to:output.appendingPathComponent("office-clipboard.html"),atomically:true,encoding:.utf8)
        try copied.write(to:output.appendingPathComponent("office-clipboard.txt"),atomically:true,encoding:.utf8)
        _ = try await js(reader,"(()=>{const n=document.querySelector('strong').firstChild; const r=document.createRange();r.setStart(n,0);r.setEnd(n,3);getSelection().removeAllRanges();getSelection().addRange(r);})()")
        let partial = await copy(reader)
        check(partial=="bol" && (board.string(forType:.html) ?? "").contains("<strong"),"native partial selection retains bold without unselected characters")
        _ = try await js(reader,"getSelection().removeAllRanges()")
        _ = try await js(reader,"document.querySelector('code.language-python').closest('.code-block').querySelector('button').click()")
        await delay()
        check(board.string(forType:.string)=="    first_line = 1\n    second_line = 2\n","code-copy button preserves exact source")
        var external:URL?, local:URL?, fragment:String?
        reader.openExternal={external=$0;return true}
        reader.openDocument={local=$0;fragment=$1}
        _ = try await js(reader,"document.querySelector('a[href^=https]').click()")
        try await until("external link callback") { external != nil }
        check(external?.absoluteString=="https://example.com","clicked external link routes to system endpoint")
        _ = try await js(reader,"document.querySelector('a[href^=other]').click()")
        try await until("local link callback") { local != nil }
        check(local==other && fragment=="sök","relative .markdown click decodes path and fragment")
        _ = try await js(reader,"document.querySelector('a[href=\"#target\"]').click()")
        await delay()
        check(try await bool(reader,"window.scrollY>0 && document.querySelector('#target').getBoundingClientRect().top>=0 && document.querySelector('#target').getBoundingClientRect().bottom<innerHeight"),"heading link scrolls to target")
        try await snapshot(reader,"math-and-table")
        reader.scrollToHeading(""); await delay()
        check(try await bool(reader,"window.scrollY===0"),"same-file link without fragment returns to top")
        reader.findQuery="bold text"; reader.showFind()
        try await until("find across inline formatting") { reader.findCount==2 }
        check(reader.findIndex==1,"Find matches across bold/plain text nodes")
        reader.nextMatch(); try await until("next match") { reader.findIndex==2 }
        reader.findQuery="bold text"; await delay(0.3)
        check(reader.findIndex==2,"unchanged search binding does not reset active match")
        reader.previousMatch(); try await until("previous match") { reader.findIndex==1 }
        check(true,"Find next and previous update match index")
        reader.hideFind(); await delay(0.25)
        let second=ReaderController(markdown:"# Second window",fileURL:nil)
        let w2=try await open(second)
        reader.zoomIn(); await delay()
        check(reader.zoom>1 && second.zoom==1,"zoom state isolated per document")
        check(try await bool(second,"document.documentElement.style.fontSize==='16px'"),"other document's rendered zoom unchanged")
        reader.resetZoom(); w2.close(); w.makeKeyAndOrderFront(nil)
        reader.startWatching()
        for n in 1...3 {
            let changed=markdown+"\n\nReload \(n)"
            try changed.write(to:fixture,atomically:true,encoding:.utf8)
            try await until("atomic reload \(n)") { guard reader.markdown==changed else { return false }; return try await self.bool(reader,"document.body.innerText.includes('Reload \(n)')") }
        }
        check(true,"three consecutive atomic saves reload actual reader")
        reader.stopWatching()
        _ = try await js(reader,"window.scrollTo(0,0)")
        try await snapshot(reader,"reader-light")
        w.appearance=NSAppearance(named:.darkAqua)
        try await until("dark appearance") { try await self.bool(reader,"matchMedia('(prefers-color-scheme: dark)').matches") }
        check(try await bool(reader,"getComputedStyle(document.body).backgroundColor==='rgb(13, 17, 23)'"),"dark mode updates document colors")
        try await snapshot(reader,"reader-dark")
        w.appearance=NSAppearance(named:.aqua)
        w.setContentSize(NSSize(width:500,height:700))
        reader.updateMarkdown("A long introductory sentence that should wrap continuously with the formula $x^2$ and a long continuation of the same paragraph which should continue on the same baseline and flow naturally onto the next line.")
        try await until("narrow document") { try await self.bool(reader,"document.body.innerText.includes('introductory')") }
        check(try await bool(reader,"document.documentElement.scrollWidth<=window.innerWidth"),"inline math flows within 500-point window")
        try await snapshot(reader,"narrow-math")
        let big=(0..<2000).map{"Paragraph \($0): ordinary reading text."}.joined(separator:"\n\n")
        let start=Date(); reader.updateMarkdown(big)
        try await until("2000 paragraphs") { try await self.bool(reader,"document.querySelectorAll('p').length===2000") }
        print("2000 paragraphs ready in \(Date().timeIntervalSince(start)) s (single warm observation)")
        check(true,"2000-paragraph document renders")
        reader.focusDocument()
        let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:w.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:125)!
        web.keyDown(with:event); await delay()
        check(try await bool(reader,"window.scrollY>10000"),"Cmd+Down reading key reaches document end")
        reader.updateMarkdown(big+"\n\nLast update"); await delay(0.3)
        check(try await bool(reader,"window.scrollY>10000"),"reload retains reading position")
        reader.updateMarkdown("Bad formula: $\\notARealCommand{x}$\n\n<script>window.injected=true</script>\n\n[javascript](javascript:alert(1))")
        try await until("invalid formula fallback") { try await self.bool(reader,"document.querySelector('.math-error')!==null") }
        check(try await bool(reader,"!window.injected && !document.querySelector('main script') && !document.querySelector('a[href^=javascript]')"),"document scripts and unsafe link schemes cannot execute")
        check(reader.errorMessage==nil,"no native load errors during checks")
    }
}

@main enum ReaderChecks {
    static func main() {
        let app=NSApplication.shared; app.setActivationPolicy(.regular)
        let delegate=Checks(); app.delegate=delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
