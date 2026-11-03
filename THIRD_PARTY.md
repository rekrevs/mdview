# Third-party components

mdview bundles these libraries locally; no CDN is needed to render a document:

| Component | Version | License | Purpose |
|---|---|---|---|
| markdown-it | 15.0.2 | MIT | Markdown parsing |
| KaTeX | 0.18.9 | MIT | Math rendering and bundled fonts |
| highlight.js CDN assets | 11.12.0 | BSD-3-Clause | Code syntax highlighting |
| markdown-it-footnote | 4.0.0 | MIT | Footnote parsing |
| Primer Octicons | 19.42.0 | MIT | GitHub alert icons (five 16px SVG paths embedded in `renderer.js`; source SVGs kept in `vendor/octicons`) |

The authoritative source archives, SHA-256 checksums and file inventory are in [vendor/manifest.json](Sources/Resources/Web/vendor/manifest.json). License texts are preserved in [vendor/licenses](Sources/Resources/Web/vendor/licenses) and copied into the installed app alongside the libraries. `scripts/vendor-renderer.py` records the pinned vendoring procedure.

The SwiftUI, AppKit and WebKit frameworks are provided by macOS. The old SwiftMath and swift-markdown implementation is no longer used by version 2.
