import SwiftUI
import SwiftMath

/// SwiftUI wrapper for SwiftMath's MTMathUILabel
struct MathView: NSViewRepresentable {
    let latex: String
    var fontSize: CGFloat = 14
    var displayStyle: Bool = false  // true for block math (larger), false for inline

    func makeNSView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.textAlignment = displayStyle ? .center : .left
        label.labelMode = displayStyle ? .display : .text
        return label
    }

    func updateNSView(_ label: MTMathUILabel, context: Context) {
        label.latex = latex
        label.font = MTFontManager().font(withName: MathFont.latinModernFont.rawValue, size: fontSize)
        label.textColor = NSColor.textColor
        label.textAlignment = displayStyle ? .center : .left
        label.labelMode = displayStyle ? .display : .text
    }
}
