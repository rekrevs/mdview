import AppKit

// Replay the actual WebKit clipboard captured by ReaderChecks into Word.
// Restore every original pasteboard representation even if Word rejects the test.
let board = NSPasteboard.general
let saved = (board.pasteboardItems ?? []).map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } }
let args = CommandLine.arguments
let folder = URL(fileURLWithPath: args[1], isDirectory:true)
let destination = folder.appendingPathComponent("word-paste-\(UUID().uuidString).docx")
func run() throws {
    let html = try String(contentsOf:folder.appendingPathComponent("office-clipboard.html"),encoding:.utf8)
    let text = try String(contentsOf:folder.appendingPathComponent("office-clipboard.txt"),encoding:.utf8)
    defer {
        board.clearContents()
        board.writeObjects(saved.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type,data) in entries { item.setData(data,forType:type) }
            return item
        })
    }
    board.clearContents()
    board.setString(html,forType:.html); board.setString(text,forType:.string)
    let process = Process()
    process.executableURL = URL(fileURLWithPath:"/usr/bin/osascript")
    process.arguments = [args[2], destination.path]
    try process.run(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw NSError(domain:"WordPaste",code:Int(process.terminationStatus)) }
    print(destination.path)
}
do { try run() } catch { fputs("\(error)\n",stderr); exit(1) }
