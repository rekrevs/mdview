import SwiftUI
import MarkdownUI

struct ContentView: View {
    let document: MarkdownDocument

    var body: some View {
        ScrollView {
            Markdown(document.text)
                .padding()
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Color(NSColor.textBackgroundColor))
    }
}
