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
        check(try await bool(reader,"window.mermaid===undefined && !document.querySelector('script[src*=mermaid]')"),"a document without diagrams never loads Mermaid")
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
        reader.updateMarkdown(String(repeating: "A paragraph with ordinary reading text and inline $x^2$ that should reflow whenever the window width changes. ", count: 12))
        try await until("resize fixture") { try await self.bool(reader,"document.body.innerText.includes('whenever the window width changes')") }
        func resizeLayout(_ width: Double) async throws -> [String:Double] {
            w.setContentSize(NSSize(width:width,height:700))
            try await until("viewport width \(width)") { try await self.bool(reader,"innerWidth===\(Int(width))") }
            return try await js(reader,"({viewport:innerWidth,main:document.querySelector('main').getBoundingClientRect().width,paragraph:document.querySelector('p').getBoundingClientRect().height,scroll:document.documentElement.scrollWidth})") as! [String:Double]
        }
        let medium = try await resizeLayout(1000)
        let wide = try await resizeLayout(1200)
        check(medium["main"]==medium["viewport"] && wide["main"]==wide["viewport"],"content uses window width beyond the former 864-point limit")
        check(wide["paragraph"]! < medium["paragraph"]!,"widening an already wide window reflows text into fewer lines")
        try await snapshot(reader,"resize-wide")
        let narrow = try await resizeLayout(500)
        check(narrow["paragraph"]! > wide["paragraph"]! && narrow["scroll"]==narrow["viewport"],"narrowing the same window reflows text without horizontal overflow")
        try await snapshot(reader,"resize-narrow")
        let restored = try await resizeLayout(1200)
        check(restored["paragraph"]==wide["paragraph"],"widening again restores the layout without reloading")
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
        reader.updateMarkdown("---\ntitle: GUI front matter\ntags: [one, two]\n---\n\n# After front matter\n\nBody $x^2$")
        try await until("front matter table") { try await self.bool(reader,"document.querySelector('main').firstElementChild?.matches('table.front-matter')===true") }
        await delay(0.2)
        check(try await bool(reader,"!document.querySelector('main hr') && document.querySelector('table.front-matter').getBoundingClientRect().height>0 && document.querySelectorAll('.front-matter td td').length===2"),"front matter renders as a visible metadata table instead of a rule")
        check(reader.headings.map(\.title)==["After front matter"],"front matter keys stay out of the native outline")
        _ = try await js(reader,"(()=>{const range=document.createRange();range.selectNodeContents(document.querySelector('main'));const s=getSelection();s.removeAllRanges();s.addRange(range);})()")
        let frontCopy=await copy(reader)
        check(frontCopy.contains("GUI front matter") && frontCopy.contains("$x^2$"),"native Copy includes front matter values and body")
        _ = try await js(reader,"getSelection().removeAllRanges()")
        try await snapshot(reader,"front-matter")
        // GitHub alerts and footnotes (T-0020).
        let filler=(1...40).map{"Filler paragraph \($0) keeps the notes below the first screen."}.joined(separator:"\n\n")
        reader.updateMarkdown("# Alerts and notes\n\n> [!NOTE]\n> Note body with a reference[^b].\n\n> [!TIP]\n> Tip body.\n\n> [!IMPORTANT]\n> Important body.\n\n> [!WARNING]\n> ## Heading inside alert\n> Warning body $x^2$.\n\n> [!CAUTION]\n> Caution body.\n\nPlain paragraph with notes[^a] and again[^b].\n\n\(filler)\n\n[^a]: Alpha footnote text.\n[^b]: Bravo footnote text.\n[^unused]: Unused footnote text.")
        try await until("alerts and footnotes") { try await self.bool(reader,"document.querySelectorAll('.markdown-alert').length===5 && document.querySelector('section.footnotes')!==null") }
        _ = try await js(reader,"window.scrollTo(0,0)"); await delay(0.2)
        func alertColors() async throws -> [String] {
            try await js(reader,"Array.from(document.querySelectorAll('.markdown-alert'),a=>{const t=a.querySelector('.markdown-alert-title');return getComputedStyle(a).borderLeftColor+'|'+getComputedStyle(t).color+'|'+getComputedStyle(a).borderLeftStyle+'|'+t.textContent})") as? [String] ?? []
        }
        let lightAlerts=try await alertColors()
        print("ALERTS LIGHT \(lightAlerts)")
        check(lightAlerts==["rgb(9, 105, 218)|rgb(9, 105, 218)|solid|Note","rgb(26, 127, 55)|rgb(26, 127, 55)|solid|Tip","rgb(130, 80, 223)|rgb(130, 80, 223)|solid|Important","rgb(154, 103, 0)|rgb(154, 103, 0)|solid|Warning","rgb(209, 36, 47)|rgb(209, 36, 47)|solid|Caution"],"five alerts show GitHub light border and title colours")
        check(try await bool(reader,"Array.from(document.querySelectorAll('.markdown-alert-title svg.octicon')).every(s=>{const r=s.getBoundingClientRect();return r.width===16&&r.height===16&&getComputedStyle(s).fill===getComputedStyle(s.parentElement).color})"),"alert icons are visible 16-point octicons in the title colour")
        check(try await bool(reader,"!document.body.innerText.includes('[!') && !document.body.innerText.includes('Unused footnote') && getComputedStyle(document.querySelector('#footnote-label')).width==='1px'"),"alert markers, unused notes and the Footnotes label are not visible")
        check(reader.headings.map(\.title)==["Alerts and notes","Heading inside alert"],"outline includes heading inside alert and excludes Footnotes")
        try await snapshot(reader,"alerts-light")
        func inView(_ selector:String) async throws -> Bool {
            try await bool(reader,"(()=>{const r=document.querySelector('\(selector)').getBoundingClientRect();return r.top>=0&&r.bottom<=innerHeight})()")
        }
        func clickElement(_ selector:String) async throws {
            let rect=try await js(reader,"(()=>{const r=document.querySelector('\(selector)').getBoundingClientRect();return {x:r.left+r.width/2,y:r.top+r.height/2};})()") as! [String:Double]
            let p=point(rect["x"]!,rect["y"]!)
            NSApp.postEvent(mouse(.leftMouseUp,p,w),atStart:false)
            NSApp.sendEvent(mouse(.leftMouseDown,p,w))
            while let event=NSApp.nextEvent(matching:[.leftMouseDragged,.leftMouseUp],until:Date(),inMode:.default,dequeue:true) { NSApp.sendEvent(event) }
            await delay(0.4)
        }
        let noteHidden=try await !inView("#fn-b")
        check(noteHidden,"footnote starts below the visible page")
        try await clickElement("#fnref-b")
        let scrolledToNote=try await bool(reader,"window.scrollY>0"), noteVisible=try await inView("#fn-b")
        check(scrolledToNote && noteVisible,"mouse click on a footnote reference scrolls its note into view")
        try await snapshot(reader,"footnotes")
        try await clickElement("#fn-b .footnote-backref")
        check(try await inView("#fnref-b"),"mouse click on the back-link returns to the reference")
        _ = try await js(reader,"(()=>{const range=document.createRange();range.selectNodeContents(document.querySelector('main'));const s=getSelection();s.removeAllRanges();s.addRange(range);})()")
        let footCopy=await copy(reader)
        let footRich=board.string(forType:.html) ?? ""
        try footRich.write(to:output.appendingPathComponent("footnotes-clipboard.html"),atomically:true,encoding:.utf8)
        print("FOOTNOTE COPY \(String(reflecting:String(footCopy.prefix(200)))) … \(String(reflecting:String(footCopy.suffix(80))))")
        check(footCopy.contains("Note\n\nNote body with a reference[1].") && footCopy.contains("notes[2] and again[1].") && footCopy.contains("[1] Bravo footnote text.\n[2] Alpha footnote text.") && !footCopy.contains("↩") && !footCopy.contains("Footnotes"),"native Copy gives alert titles and [n] footnotes without back-links")
        check(!footRich.contains("<svg") && !footRich.contains("↩") && footRich.contains("border-left: 4px solid rgb(9, 105, 218)"),"native HTML clipboard has portable alert styles and no icons or back-links")
        _ = try await js(reader,"getSelection().removeAllRanges()")
        reader.findQuery="Bravo footnote"; reader.showFind()
        try await until("find footnote text") { reader.findCount==1 }
        check(true,"Find locates footnote text once")
        reader.findQuery="Footnotes"; await delay(0.5)
        check(reader.findCount==0,"Find ignores the hidden Footnotes label")
        reader.hideFind(); await delay(0.25)
        _ = try await js(reader,"window.scrollTo(0,0)")
        w.appearance=NSAppearance(named:.darkAqua)
        try await until("dark alerts") { try await self.bool(reader,"matchMedia('(prefers-color-scheme: dark)').matches") }
        await delay(0.2)
        let darkAlerts=try await alertColors()
        print("ALERTS DARK \(darkAlerts)")
        check(darkAlerts==["rgb(68, 147, 248)|rgb(68, 147, 248)|solid|Note","rgb(63, 185, 80)|rgb(63, 185, 80)|solid|Tip","rgb(171, 125, 248)|rgb(171, 125, 248)|solid|Important","rgb(210, 153, 34)|rgb(210, 153, 34)|solid|Warning","rgb(248, 81, 73)|rgb(248, 81, 73)|solid|Caution"],"five alerts show GitHub dark border and title colours")
        try await snapshot(reader,"alerts-dark")
        w.appearance=NSAppearance(named:.aqua)
        try await until("light again") { try await !self.bool(reader,"matchMedia('(prefers-color-scheme: dark)').matches") }
        // Sanitized GitHub HTML subset (T-0021).
        let htmlFiller=(1...30).map{"HTML filler paragraph \($0)."}.joined(separator:"\n\n")
        reader.updateMarkdown("# HTML subset\n\n<details>\n<summary>Show more</summary>\n\nHidden **markdown** inside details.\n\n</details>\n\nPress <kbd>Ctrl</kbd>+<kbd>C</kbd> to copy. H<sub>2</sub>O and x<sup>2</sup>.\n\n<p align=\"center\">\n  <img src=\"image with space.png\" alt=\"Sized icon\" width=\"64\">\n</p>\n\n<a href=\"https://example.com/html\">HTML external</a> · <a href=\"other file.markdown#s%C3%B6k\">HTML local</a> · <a href=\"#user-content-html-target\">HTML anchor</a>\n\n<picture><source media=\"(prefers-color-scheme: dark)\" srcset=\"image%20with%20space.png\"><img src=\"image%20with%20space.png\" alt=\"Picture\" width=\"32\"></picture>\n\n\(htmlFiller)\n\n<h2 id=\"html-target\">HTML target</h2>\n\nEnd.")
        try await until("html subset") { try await self.bool(reader,"document.querySelector('main details')!==null && document.querySelector('main kbd')!==null") }
        _ = try await js(reader,"window.scrollTo(0,0)"); await delay(0.2)
        let closedState=try await js(reader,"(()=>{const d=document.querySelector('details'),p=d.querySelector('p');return d.open+'|'+document.body.innerText.includes('Hidden')+'|'+(p.checkVisibility?p.checkVisibility():'n/a')})()") as? String ?? ""
        print("DETAILS CLOSED \(closedState)")
        check(closedState=="false|false|false" || closedState=="false|false|n/a","details starts closed with its Markdown body not rendered")
        try await clickElement("summary")
        check(try await bool(reader,"(()=>{const d=document.querySelector('details'),p=d.querySelector('p');return d.open && document.body.innerText.includes('Hidden markdown inside details.') && (!p.checkVisibility || p.checkVisibility()) && p.querySelector('strong').getBoundingClientRect().height>0})()"),"mouse click on summary opens details and shows its Markdown")
        let kbdStyle=try await js(reader,"(()=>{const s=getComputedStyle(document.querySelector('kbd'));return s.borderTopStyle+'|'+s.fontFamily+'|'+s.borderRadius})()") as? String ?? ""
        print("KBD STYLE \(kbdStyle)")
        check(kbdStyle.hasPrefix("solid|") && kbdStyle.contains("monospace"),"kbd renders as a bordered monospace key")
        check(try await bool(reader,"['center','-webkit-center'].includes(getComputedStyle(document.querySelector('p[align=center]')).textAlign)"),"p align=center is centred")
        try await until("sized local image") { try await self.bool(reader,"(()=>{const i=document.querySelector('p[align=center] img');return i&&i.complete&&i.naturalWidth===128})()") }
        check(try await bool(reader,"(()=>{const i=document.querySelector('p[align=center] img').getBoundingClientRect(),m=document.querySelector('main').getBoundingClientRect();return i.width===64&&Math.abs((i.left+i.width/2)-(m.left+m.width/2))<2})()"),"HTML img width=64 loads a 128-pixel local image at 64 points, centred")
        try await until("picture image") { try await self.bool(reader,"(()=>{const i=document.querySelector('picture img');return i&&i.complete&&i.naturalWidth===128&&i.getBoundingClientRect().width===32})()") }
        check(true,"picture/source image resolves through the local handler")
        try await snapshot(reader,"html-subset")
        external=nil; local=nil; fragment=nil
        try await clickElement("a[href=\"https://example.com/html\"]")
        try await until("html external link") { external != nil }
        check(external?.absoluteString=="https://example.com/html","mouse click on an HTML link routes to the system endpoint")
        try await clickElement("a[href^=other]")
        try await until("html local link") { local != nil }
        check(local==other && fragment=="sök","HTML relative .markdown link decodes path and fragment like Markdown")
        try await clickElement("a[href=\"#user-content-html-target\"]")
        check(try await inView("#user-content-html-target"),"HTML anchor link scrolls to the prefixed author id")
        // Mermaid diagrams (T-0022): real WebKit layout, strict security, theme, zoom, copy, find.
        func diagramsSettled(_ seconds: Double = 30) async throws {
            _ = try await js(reader,"window.__diagramsSettled=false; window.mdview.diagramsSettled().then(()=>{window.__diagramsSettled=true}); true")
            for _ in 0..<Int(seconds*10) { if try await bool(reader,"window.__diagramsSettled===true") { return }; await delay() }
            throw NSError(domain:"ReaderChecks",code:3,userInfo:[NSLocalizedDescriptionKey:"Timed out: diagrams settled"])
        }
        let diagramFiller=(1...25).map{"Diagram filler paragraph \($0)."}.joined(separator:"\n\n")
        let flowSource="graph TD\n  Start[Begin here] --> Decide{Pick one}\n  Decide -->|yes| Yak[Yakfox label]\n  Decide -->|no| Done[Finish]\n"
        let mermaidDoc="# Diagrams\n\n```mermaid\n"+flowSource+"```\n\n```mermaid\nsequenceDiagram\n  Alice->>Bob: Hello Bob\n  Bob-->>Alice: Hi Alice\n```\n\n```mermaid\ngraph TD\n  A-->\n```\n\n```mermaid\n%%{init: {\"securityLevel\":\"loose\"}}%%\ngraph TD\n  Attack[\"<img src=x onerror=window.__mermaidPwned=1>\"] --> Target\n  click Attack \"javascript:window.__mermaidPwned=1\"\n  click Target href \"javascript:window.__mermaidPwned=1\"\n```\n\n"+diagramFiller
        let mermaidStart=Date()
        reader.updateMarkdown(mermaidDoc)
        try await until("mermaid figures") { try await self.bool(reader,"document.querySelectorAll('figure.mermaid').length===4") }
        try await diagramsSettled()
        print("4 diagrams settled in \(Date().timeIntervalSince(mermaidStart)) s including the first Mermaid load")
        let states=try await js(reader,"Array.from(document.querySelectorAll('figure.mermaid'),f=>f.dataset.state+'|'+f.dataset.theme).join(',')") as? String ?? ""
        print("MERMAID STATES \(states)")
        check(states=="rendered|default,rendered|default,error|default,rendered|default","flowchart, sequence and strict attack diagram render; invalid diagram is an error")
        check(try await bool(reader,"typeof window.mermaid?.render==='function' && document.querySelectorAll('script[src=\"vendor/mermaid.min.js\"]').length===1"),"Mermaid loaded once from the bundled vendor directory")
        check(try await bool(reader,"[0,1,3].every(i=>{const s=document.querySelectorAll('figure.mermaid')[i].querySelector('.mermaid-svg > svg');return s&&s.getBBox().width>0&&s.getBoundingClientRect().height>0})"),"valid diagrams are laid-out SVGs with nonzero bounding boxes")
        check(try await bool(reader,"(()=>{const f=document.querySelectorAll('figure.mermaid')[2],c=f.querySelector('figcaption'),p=f.querySelector('pre.mermaid-source');return !c.hidden&&c.innerText.startsWith('Diagram could not be rendered: ')&&p.getBoundingClientRect().height>0&&p.innerText.includes('A-->')&&!f.querySelector('svg')})()"),"invalid diagram shows a visible error and its source")
        check(try await bool(reader,"getComputedStyle(document.querySelectorAll('figure.mermaid')[0].querySelector('pre.mermaid-source')).display==='none'"),"rendered diagram hides its source")
        let bodyChildren=try await js(reader,"Array.from(document.body.children,n=>n.tagName+'#'+n.id).join(',')") as? String ?? ""
        print("BODY CHILDREN \(bodyChildren)")
        check(bodyChildren=="MAIN#document","no temporary Mermaid elements remain in the page body")
        var diagramOpened:[URL]=[]
        reader.openExternal={diagramOpened.append($0);return true}
        let svgLinks=try await js(reader,"Array.from(document.querySelectorAll('figure.mermaid svg a'),a=>a.getAttribute('href')||a.getAttribute('xlink:href')).join(',')") as? String ?? "?"
        _ = try await js(reader,"document.querySelectorAll('figure.mermaid svg *').forEach(n=>n.dispatchEvent(new MouseEvent('click',{bubbles:true,cancelable:true})))")
        await delay(0.5)
        print("MERMAID LINKS [\(svgLinks)] opened=\(diagramOpened) error=\(reader.errorMessage ?? "nil")")
        check(diagramOpened.isEmpty,"clicking every element of the diagrams opens nothing")
        reader.errorMessage=nil; reader.openExternal={external=$0;return true}
        let attack=try await js(reader,"(()=>{const f=document.querySelectorAll('figure.mermaid')[3];return [window.__mermaidPwned===undefined,!document.querySelector('a[href^=javascript],[href*=\"javascript:\"],[onerror],[onclick]'),!f.querySelector('img[onerror],script'),f.querySelector('svg').textContent.length>0].join('|')})()") as? String ?? ""
        print("MERMAID ATTACK \(attack)")
        check(attack=="true|true|true|true","init directive cannot loosen strict mode: no javascript: links, handlers or script execution")
        let foreign=try await js(reader,"performance.getEntriesByType('resource').map(e=>e.name).filter(n=>!n.startsWith('file:')&&!n.startsWith('mdview-image:'))") as? [String] ?? ["?"]
        // WebKit records no resource-timing entries for file: loads, so check the resolved script URL.
        let bundledScript=try await bool(reader,"(()=>{const u=document.querySelector('script[src=\"vendor/mermaid.min.js\"]').src;return u.startsWith('file:')&&u.includes('.app/Contents/Resources/')})()")
        print("MERMAID RESOURCES foreign=\(foreign) bundled=\(bundledScript)")
        check(foreign.isEmpty && bundledScript,"diagrams cause no network requests; Mermaid comes from the app bundle")
        _ = try await js(reader,"window.scrollTo(0,0)"); await delay(0.2)
        try await snapshot(reader,"mermaid-light")
        let nodeFill="getComputedStyle(document.querySelector('figure.mermaid .mermaid-svg svg .node rect, figure.mermaid .mermaid-svg svg .node polygon, figure.mermaid .mermaid-svg svg .node path')).fill"
        let lightFill=try await js(reader,nodeFill) as? String ?? ""
        w.appearance=NSAppearance(named:.darkAqua)
        try await until("dark diagrams") { try await self.bool(reader,"Array.from(document.querySelectorAll('figure.mermaid')).every(f=>f.dataset.theme==='dark')") }
        try await diagramsSettled()
        let darkFill=try await js(reader,nodeFill) as? String ?? ""
        print("MERMAID FILL light=\(lightFill) dark=\(darkFill)")
        check(!lightFill.isEmpty && lightFill != darkFill,"dark appearance re-renders diagrams with the dark theme")
        try await snapshot(reader,"mermaid-dark")
        w.appearance=NSAppearance(named:.aqua)
        try await until("light diagrams") { try await self.bool(reader,"Array.from(document.querySelectorAll('figure.mermaid')).every(f=>f.dataset.theme==='default')") }
        check(try await js(reader,nodeFill) as? String == lightFill,"switching back to light restores the light diagrams")
        let width1=try await js(reader,"document.querySelector('figure.mermaid svg').getBoundingClientRect().width") as? Double ?? 0
        reader.zoomIn(); await delay(0.3)
        let width2=try await js(reader,"document.querySelector('figure.mermaid svg').getBoundingClientRect().width") as? Double ?? 0
        reader.resetZoom(); await delay(0.2)
        print("MERMAID ZOOM \(width1) -> \(width2)")
        check(width1>0 && abs(width2/width1-1.1)<0.02,"zoom scales diagram width with the text")
        _ = try await js(reader,"(()=>{const range=document.createRange();range.selectNodeContents(document.querySelector('main'));const s=getSelection();s.removeAllRanges();s.addRange(range);})()")
        let diagramCopy=await copy(reader)
        let diagramRich=board.string(forType:.html) ?? ""
        check(diagramCopy.contains("```mermaid\n"+flowSource+"```") && diagramCopy.components(separatedBy:"Yakfox label").count==2 && diagramCopy.components(separatedBy:"```mermaid").count==5,"native Select All + Copy gives each diagram's fenced source once")
        check(!diagramRich.contains("<svg") && !diagramRich.contains("foreignObject") && diagramRich.contains("mermaid"),"native HTML clipboard carries diagram source, not SVG")
        _ = try await js(reader,"(()=>{const t=Array.from(document.querySelectorAll('figure.mermaid svg *')).find(n=>n.textContent.trim()==='Yakfox label'&&!n.children.length);const r=document.createRange();r.selectNodeContents(t);getSelection().removeAllRanges();getSelection().addRange(r);})()")
        let labelCopy=await copy(reader)
        check(labelCopy=="```mermaid\n"+flowSource+"```","copying a selected diagram label gives that diagram's fenced source")
        _ = try await js(reader,"getSelection().removeAllRanges()")
        reader.findQuery="Diagram filler paragraph 2"; reader.showFind()
        try await until("find positive control") { reader.findCount>0 }
        reader.findQuery="Yakfox"; await delay(0.6)
        check(reader.findCount==0,"Find ignores diagram labels and source")
        reader.hideFind(); await delay(0.25)
        // Forty distinct diagrams, read from the middle of the document while they render.
        let many=(1...40).map{"Paragraph before diagram \($0).\n\n```mermaid\ngraph LR\n  N\($0)a[Node \($0)] --> N\($0)b[Next \($0)]\n  N\($0)b --> N\($0)c[Last \($0)]\n```"}.joined(separator:"\n\n")+"\n\nEnd of diagrams."
        let manyStart=Date()
        reader.updateMarkdown(many)
        try await until("forty figures") { try await self.bool(reader,"document.querySelectorAll('figure.mermaid').length===40") }
        let anchorTop=try await js(reader,"(()=>{const p=Array.from(document.querySelectorAll('main > p')).find(n=>n.textContent==='Paragraph before diagram 30.');p.scrollIntoView({block:'start'});return p.getBoundingClientRect().top})()") as? Double ?? -1
        try await diagramsSettled(120)
        print("40 diagrams settled in \(Date().timeIntervalSince(manyStart)) s (single warm observation)")
        let anchorAfter=try await js(reader,"Array.from(document.querySelectorAll('main > p')).find(n=>n.textContent==='Paragraph before diagram 30.').getBoundingClientRect().top") as? Double ?? 999
        print("MERMAID ANCHOR \(anchorTop) -> \(anchorAfter)")
        check(try await bool(reader,"Array.from(document.querySelectorAll('figure.mermaid')).every(f=>f.dataset.state==='rendered')"),"forty diagrams all render")
        check(abs(anchorAfter-anchorTop)<3,"diagrams rendering above the viewport keep the reading position")
        // Emoji shortcodes and appearance-tagged images (T-0025).
        w.appearance=NSAppearance(named:.aqua)
        try await until("light before emoji") { try await !self.bool(reader,"matchMedia('(prefers-color-scheme: dark)').matches") }
        reader.updateMarkdown("# :rocket: Emoji check\n\nLaunch :rocket: today with `:rocket:` in code and :+1: approval.\n\n![Light variant](image%20with%20space.png#gh-light-mode-only)<img src=\"image with space.png#gh-dark-mode-only\" alt=\"Dark variant\">\n\nAfter the images.")
        try await until("emoji document") { try await self.bool(reader,"document.querySelector('main h1')?.id==='rocket-emoji-check'") }
        check(try await bool(reader,"(()=>{const p=document.querySelector('main p');return p.textContent==='Launch 🚀 today with :rocket: in code and 👍 approval.'&&p.querySelector('code').textContent===':rocket:'&&document.querySelector('main h1').textContent==='🚀 Emoji check'})()"),"emoji shortcodes render as Unicode; the code span keeps its shortcode")
        check(reader.headings.map(\.title)==["🚀 Emoji check"] && reader.headings.map(\.id)==["rocket-emoji-check"],"outline shows the emoji; the heading id keeps the shortcode name")
        let variantState="(()=>{const l=document.querySelector('img.gh-light-mode-only'),d=document.querySelector('img.gh-dark-mode-only');const v=i=>getComputedStyle(i).display!=='none'&&i.getBoundingClientRect().width>0;return [v(l),v(d),l.naturalWidth,d.naturalWidth,l===window.__variants?.[0]&&d===window.__variants?.[1]].join('|')})()"
        try await until("variant images load") { try await self.bool(reader,"(()=>{const i=document.querySelectorAll('img.gh-light-mode-only,img.gh-dark-mode-only');return i.length===2&&[...i].every(n=>n.complete&&n.naturalWidth===128)})()") }
        _ = try await js(reader,"window.__variants=[document.querySelector('img.gh-light-mode-only'),document.querySelector('img.gh-dark-mode-only')]; true")
        let lightVariants=try await js(reader,variantState) as? String ?? ""
        print("VARIANTS LIGHT \(lightVariants)")
        check(lightVariants=="true|false|128|128|true","light appearance shows only the #gh-light-mode-only image")
        _ = try await js(reader,"(()=>{const range=document.createRange();range.selectNodeContents(document.querySelector('main'));const s=getSelection();s.removeAllRanges();s.addRange(range);})()")
        let emojiCopy=await copy(reader)
        let emojiRich=board.string(forType:.html) ?? ""
        print("EMOJI COPY \(String(reflecting:emojiCopy))")
        check(emojiCopy.contains("🚀 Emoji check") && emojiCopy.contains("Launch 🚀 today with :rocket: in code and 👍 approval.") && emojiRich.contains("🚀"),"native Select All + Copy carries the emoji in both formats")
        check(emojiCopy.contains("Light variant") && !emojiCopy.contains("Dark variant") && !emojiRich.contains("Dark variant"),"native Copy in light appearance gives only the light image's alt text")
        _ = try await js(reader,"getSelection().removeAllRanges()")
        _ = try await js(reader,"window.scrollTo(0,0)"); await delay(0.2)
        try await snapshot(reader,"emoji-variants")
        reader.findQuery="🚀"; reader.showFind()
        try await until("find emoji") { reader.findCount>0 }
        await delay(0.3)
        check(reader.findCount==2,"Find matches the rendered emoji in heading and paragraph, not the code span")
        reader.findQuery=":rocket:"; await delay(0.6)
        check(reader.findCount==1,"Find matches the shortcode only in the code span")
        reader.hideFind(); await delay(0.25)
        w.appearance=NSAppearance(named:.darkAqua)
        try await until("dark variants") { try await self.bool(reader,"matchMedia('(prefers-color-scheme: dark)').matches") }
        await delay(0.2)
        let darkVariants=try await js(reader,variantState) as? String ?? ""
        print("VARIANTS DARK \(darkVariants)")
        check(darkVariants=="false|true|128|128|true","dark appearance shows only the #gh-dark-mode-only image, on the same DOM nodes")
        _ = try await js(reader,"(()=>{const range=document.createRange();range.selectNodeContents(document.querySelector('main'));const s=getSelection();s.removeAllRanges();s.addRange(range);})()")
        let darkCopy=await copy(reader)
        let darkRich=board.string(forType:.html) ?? ""
        check(darkCopy.contains("Dark variant") && !darkCopy.contains("Light variant") && !darkRich.contains("Light variant"),"native Copy in dark appearance gives only the dark image's alt text")
        _ = try await js(reader,"getSelection().removeAllRanges()")
        try await snapshot(reader,"emoji-variants-dark")
        w.appearance=NSAppearance(named:.aqua)
        try await until("light after variants") { try await !self.bool(reader,"matchMedia('(prefers-color-scheme: dark)').matches") }
        // Adversarial corpus: nothing executes, navigates, or fetches from disallowed contexts.
        var opened:[URL]=[]
        reader.openExternal={opened.append($0);return true}
        let corpus = #"""
        <script>window.__pwned=1</script>

        <img src=x onerror="window.__pwned=1"> <img src="javascript:window.__pwned=1" alt="js image">

        <svg><animate onbegin="window.__pwned=1" attributeName="x" dur="1s"/></svg>

        <math><mtext><table><mglyph><style><img src=x onerror=window.__pwned=1>

        <noscript><p title="</noscript><img src=x onerror=window.__pwned=1>">

        <details open ontoggle="window.__pwned=1"><summary onclick="window.__pwned=1">Hostile summary</summary>body</details>

        <iframe src="https://canary.invalid/iframe" srcdoc="<script>parent.__pwned=1</script>"></iframe>

        <object data="https://canary.invalid/object"></object> <embed src="https://canary.invalid/embed">

        <link rel="stylesheet" href="https://canary.invalid/link.css">

        <meta http-equiv="refresh" content="0;url=https://canary.invalid/refresh">

        <base href="https://canary.invalid/">

        <video poster="https://canary.invalid/poster.png"></video> <table background="https://canary.invalid/bg.png"><tr><td>t</td></tr></table>

        <a href="javascript:window.__pwned=1">js link</a> <a href="jav&#x09;ascript:window.__pwned=1">tab link</a> <a href="data:text/html,x">data link</a> <a href="//canary.invalid/x.md">host link</a>

        <form action="https://canary.invalid/form"><button formaction="javascript:window.__pwned=1">Go</button></form>

        <a href="https://ok.example/safe" target="_blank" onclick="window.__pwned=1">safe link</a> <a href="#x">anchor</a>

        <p style="position:fixed;inset:0;background:red" class="markdown-alert">overlay</p>
        """#
        reader.updateMarkdown(corpus)
        try await until("adversarial corpus") { try await self.bool(reader,"document.body.innerText.includes('safe link')") }
        await delay(0.5)
        _ = try await js(reader,"document.querySelectorAll('main a, main summary').forEach(n=>n.click())")
        await delay(0.5)
        let canaries=try await js(reader,"performance.getEntriesByType('resource').map(e=>e.name).filter(n=>n.includes('canary'))") as? [String] ?? ["?"]
        print("ADVERSARIAL opened=\(opened) canaries=\(canaries)")
        check(try await bool(reader,"window.__pwned===undefined && window.parent.__pwned===undefined && !document.querySelector('main script,main iframe,main object,main embed,main link,main meta,main base,main form,main svg,main [onerror],main [onclick],main [style],main .markdown-alert')"),"adversarial HTML corpus is inert after clicking every link and summary")
        check(opened.map(\.absoluteString)==["https://ok.example/safe"],"only the safe HTML link reached the system endpoint")
        check(canaries.isEmpty,"no resource requests for disallowed iframe/object/embed/link/meta/base/poster/background URLs")
        check(try await bool(reader,"location.href.endsWith('/index.html') && document.querySelector('main').innerText.includes('<script>')"),"page did not navigate; disallowed tags remain visible text")
        check(reader.errorMessage==nil,"no blocked-link or load errors from adversarial HTML")
        reader.openExternal={external=$0;return true}
        // CSP proof: even markup inserted without the sanitizer cannot run inline handlers.
        _ = try await js(reader,"(()=>{document.querySelector('main').insertAdjacentHTML('beforeend','<img id=\"csp-probe\" src=\"x\" onerror=\"window.__csp=1\">');document.getElementById('csp-probe').addEventListener('error',()=>{window.__cspError=1});})()")
        try await until("csp probe error") { try await self.bool(reader,"window.__cspError===1") }
        await delay(0.3)
        check(try await bool(reader,"window.__csp===undefined"),"CSP blocks an inline onerror handler inserted directly into the page")
        reader.updateMarkdown("Bad formula: $\\notARealCommand{x}$\n\n<script>window.__documentScript=true</script>\n\n[javascript](javascript:alert(1))")
        try await until("invalid formula fallback") { try await self.bool(reader,"document.querySelector('.math-error')!==null") }
        check(try await bool(reader,"!window.__documentScript && !document.querySelector('main script') && !document.querySelector('a[href^=javascript]')"),"document scripts and unsafe link schemes cannot execute")
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
