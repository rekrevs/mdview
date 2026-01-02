import SwiftUI
import SwiftMath

/// SwiftUI wrapper for SwiftMath's MTMathUILabel
struct MathView: View {
    let latex: String
    var fontSize: CGFloat = 14
    var displayStyle: Bool = false  // true for block math (larger), false for inline

    var body: some View {
        let size = Self.calculateSize(latex: latex, fontSize: fontSize, displayStyle: displayStyle)
        MathViewRepresentable(latex: latex, fontSize: fontSize, displayStyle: displayStyle)
            .frame(width: size.width, height: size.height)
    }

    /// Calculate the size needed for a LaTeX string using MTMathUILabel's fittingSize
    static func calculateSize(latex: String, fontSize: CGFloat, displayStyle: Bool) -> CGSize {
        let label = MTMathUILabel()
        label.latex = latex
        label.font = MTFontManager().font(withName: MathFont.latinModernFont.rawValue, size: fontSize)
        label.labelMode = displayStyle ? .display : .text
        label.textAlignment = .left
        label.layout()

        let size = label.fittingSize
        return CGSize(
            width: max(size.width, 10) + 4,
            height: max(size.height, fontSize) + 4
        )
    }
}

/// The actual NSViewRepresentable wrapper
private struct MathViewRepresentable: NSViewRepresentable {
    let latex: String
    let fontSize: CGFloat
    let displayStyle: Bool

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
