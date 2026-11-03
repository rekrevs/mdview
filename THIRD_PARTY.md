# Third-party components

mdview bundles these libraries locally; no CDN is needed to render a document:

| Component | Version | License | Purpose |
|---|---|---|---|
| markdown-it | 15.0.2 | MIT | Markdown parsing |
| KaTeX | 0.18.9 | MIT | Math rendering and bundled fonts |
| highlight.js CDN assets | 11.12.0 | BSD-3-Clause | Code syntax highlighting |
| markdown-it-footnote | 4.0.0 | MIT | Footnote parsing |
| Primer Octicons | 19.42.0 | MIT | GitHub alert icons (five 16px SVG paths embedded in `renderer.js`; source SVGs kept in `vendor/octicons`) |
| Mermaid | 12.2.0 | MIT | Diagram rendering (`dist/mermaid.min.js`, a single self-contained bundle loaded only for documents with diagrams) |

### Components bundled inside Mermaid

`mermaid.min.js` contains third-party code. The complete list, with versions and licenses, is the `bundled` array of the Mermaid entry in [vendor/manifest.json](Sources/Resources/Web/vendor/manifest.json), and their license texts are in [vendor/licenses/mermaid-bundled.txt](Sources/Resources/Web/vendor/licenses/mermaid-bundled.txt). The list is the runtime dependency closure in Mermaid's `pnpm-lock.yaml` at tag `mermaid@12.2.0` (plus langium, which Mermaid's parser bundles), without type-only `@types` packages. It may name packages that the bundler left out. Licenses other than MIT:

| Component | Version | License | Notes |
|---|---|---|---|
| elkjs | 0.9.3 | EPL-2.0 | Distributed in object-code form; source code at https://github.com/kieler/elkjs (tag 0.9.3) and in its npm archive |
| DOMPurify | 3.4.12 | MPL-2.0 or Apache-2.0 | Used under Apache-2.0; source at https://github.com/cure53/DOMPurify (tag 3.4.12) |
| chevrotain, @chevrotain/* | 13.2.0 | Apache-2.0 | Diagram parsers |
| d3, d3-* modules, delaunator, internmap | various | ISC | |
| d3-sankey 0.12.3, d3-array 2.12.1, d3-path 1.0.9, d3-shape 1.3.7, d3-ease 3.0.1, rw 1.3.3 | | BSD-3-Clause | |
| robust-predicates | 3.0.2 | Unlicense | |

The other bundled components (for example cytoscape, dagre-d3-es, dayjs, katex, khroma, langium, lodash-es, marked, roughjs, stylis, uuid and the vscode-languageserver modules) are MIT licensed.

The authoritative source archives, SHA-256 checksums and file inventory are in [vendor/manifest.json](Sources/Resources/Web/vendor/manifest.json). License texts are preserved in [vendor/licenses](Sources/Resources/Web/vendor/licenses) and copied into the installed app alongside the libraries. `scripts/vendor-renderer.py` records the pinned vendoring procedure; it regenerates `mermaid-bundled.txt` from the npm archives listed, with their lockfile integrity hashes, in `scripts/mermaid-bundled.json`.

The SwiftUI, AppKit and WebKit frameworks are provided by macOS. The old SwiftMath and swift-markdown implementation is no longer used by version 2.
