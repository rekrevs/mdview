# mdview 2

![mdview icon](AppIcon.iconset/icon_128x128.png)

A macOS Markdown reader with a native document window and one continuous, selectable WebKit page. Version 2 replaces the old per-block SwiftUI renderer with locally bundled markdown-it (with footnote and emoji plugins), KaTeX, highlight.js and Mermaid.

## Reading

- Open `.md` and `.markdown` files from Finder or the Open dialog; each document has its own window.
- Paragraphs reflow to the available window width as you resize, with smaller margins in narrow windows.
- Select and copy across paragraphs, lists, tables and code blocks. The clipboard includes plain text and portable HTML: partial selections keep their formatting, tables carry borders/alignment, code retains a monospace font and indentation, and numbered-list excerpts retain their starting number. Relative links become absolute links back to the source files.
- Formulas copy as LaTeX and images as alt text in both clipboard formats; copying does not yet create Office equations or embed images.
- Follow heading anchors, relative Markdown links and external web/email links.
- Read tables with column alignment, nested lists and quotes, task checkboxes, local images and syntax-highlighted code.
- Render GitHub alerts (`> [!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`) with GitHub's title, icon and light/dark colours. As on GitHub, the marker must be alone on the first line of a top-level quote; otherwise the quote stays an ordinary quote.
- Render `[^label]` footnotes as on GitHub: references are numbered by first use, link to the notes at the end of the document, and the notes link back to every reference. Labels are case-insensitive, unused definitions are hidden, and `^[inline]` notes are not supported. Copying gives references as `[1]` and notes as `[1] text`, without icons, back-links or hidden labels.
- Show leading YAML front matter as a GitHub-style metadata table. Values are plain text; nested or unusual YAML and `+++` TOML front matter are shown as highlighted source. A document that starts with a `---` line and has a later `---` line is treated as front matter, as on GitHub.
- Render the HTML subset GitHub READMEs use: `<details>`/`<summary>`, `<kbd>`, `<sub>`, `<sup>`, `<br>`, `<img width height align>`, `<p align>`/`<div align>`, `<picture>`/`<source>` (including `prefers-color-scheme` variants), raw tables, definition lists, `<a name>` anchors and inline formatting such as `<mark>`, `<abbr>`, `<del>` and `<ruby>`. Markdown inside an HTML block needs a blank line after the opening tag and before the closing tag, as on GitHub. Links and images in HTML follow the same rules as Markdown links and images. Disallowed tags (for example `<script>`, `<style>`, `<iframe>`, `<svg>`, `<form>`, `<center>`, `<font>`, `<u>`) stay visible as text, unsafe attributes (`style`, `class`, event handlers, …) and unsafe URLs are removed, HTML comments are hidden, and `id`/`name` values get GitHub's `user-content-` prefix (links to `#name` still work). Inside a paragraph, heading or table cell only inline tags are rendered; block tags such as `<li>`, `<td>` or `<hr>` there stay visible as text so they cannot break the surrounding structure. Formulas inside raw HTML blocks stay literal, and raw HTML headings are not listed in the outline.
- Render GitHub emoji shortcodes such as `:rocket:` or `:+1:` as Unicode emoji (the gemoji names in markdown-it-emoji 3.1.0). Unknown names, GitHub's custom image emoji (`:octocat:`, `:shipit:`), emoticons such as `:)`, and shortcodes in code, math, link destinations and autolinked URLs stay text; text inside HTML `<code>`, `<pre>` and `<tt>` too. As on GitHub, a shortcode needs no surrounding space (`a:tada:b` converts) and heading anchors keep the name (`# :rocket: Launch` is `#rocket-launch`), while the outline shows the emoji. Copy and find use the emoji.
- Show images whose address ends in `#gh-dark-mode-only` or `#gh-light-mode-only` (Markdown or HTML) only in the matching appearance, switching live with the window appearance. Copying and find skip the hidden variant.
- Render inline `$…$`, display `$$…$$` and fenced `math` blocks with KaTeX, including matrices and multiline environments supported by KaTeX.
- Render ` ```mermaid ` fences as diagrams with a bundled Mermaid 12.2.0, in light or dark colours following the window appearance. Diagrams are sized with the text, so zoom scales them, and they never get wider than the window. The source appears dimmed until the diagram is ready. An invalid diagram stays visible as source with the error message. Copying a diagram, or any part of it, gives its source as a fenced ` ```mermaid ` block in both clipboard formats (never the drawing); the diagram's Copy button copies the bare source. Find does not match text inside diagrams or their source. Mermaid runs in strict security mode, which a diagram's own `%%{init}%%` directive cannot loosen: click actions and links are disabled and labels are sanitized. Layout uses dagre as on GitHub (a diagram may still choose `layout: elk`); icon packs are not available. Mermaid is loaded only for documents that contain a diagram, needs the WebKit of Safari 17.4 or later (otherwise diagrams stay as source with an error), and adds about 5.5 MB to the app.
- Find prose and code with `⌘F`, navigate the heading outline, and zoom the active document without changing other windows. Search matches across inline formatting; it excludes formula internals and diagrams.
- Reload external file changes, including repeated atomic saves by editors.
- Follow the macOS light/dark appearance.

The renderer, syntax highlighter, math library, diagram library and fonts are included in the app. They require no CDN or runtime download. Images using HTTP/HTTPS still require a network connection.

This is a read-only viewer. Author HTML is limited to the sanitized subset above and never runs scripts; MDX, PDF export and Finder Quick Look are not implemented. KaTeX supports a subset of LaTeX, and is not identical to GitHub's MathJax renderer. Unsupported formulas remain visible as source with an error indication. Task checkboxes display the document state without editing it.

## Build and install

Requirements: macOS 13 or later and a Swift 5.9-or-newer toolchain with macOS SDK (Xcode or Command Line Tools). Development checks use Swift Testing (Swift 6 or later, macOS 14 or later), Node.js with npm and Python 3; the installed app does not need those test tools.

```bash
git clone https://github.com/sverker/mdview.git
cd mdview
make install
```

Installation builds a release app and copies it to `~/Applications/mdview.app`. If an app already exists there, it is retained as `mdview.app.backup-<timestamp>-<pid>`; documents and preferences are untouched. Quit an older running instance before opening the replacement.

```bash
make build                         # Debug executable
make bundle                        # Build and bundle debug
make release                       # Build and bundle release
make install CONFIGURATION=debug  # Explicit debug installation
make install INSTALL_DIR=/path/to/Applications
open -a "$HOME/Applications/mdview.app" /path/to/report.md
```

`./bundle.sh --configuration debug|release` packages an already-built configuration, with debug as its default. It never selects a binary by modification time. All generated bundles include the complete rendering resources and licenses, are ad-hoc signed, and are validated before replacing the previous build. Ad-hoc signing is for local builds; the app is not notarized for distribution.

The build wrapper automatically uses the installed macOS 26.5 SDK when the selected SDK is 27.x and 26.5 is available, to avoid the SwiftUI macro failure observed with this machine's preview toolchain. This affects only the invoked process. Override SDK selection explicitly when needed:

```bash
MDVIEW_SDK=/path/to/MacOSX.sdk make build
```

To make mdview the default in Finder, select a Markdown file, use **Get Info → Open with → mdview → Change All**.

## Keyboard shortcuts

| Key | Action |
|---|---|
| `⌘O` | Open document |
| `⌘A`, `⌘C` | Select all, copy |
| `⌘F` | Find in the current document |
| `⌘G`, `⌘Shift+G` | Next, previous match |
| `Return`, `Shift+Return`, `Escape` in Find | Next match, previous match, close Find |
| `⌘+`, `⌘−`, `⌘0` | Zoom in, out, actual size |
| `⌘R` | Reload the document |
| `⌘Option+T` | Show or hide the outline |
| `↑`, `↓` | Scroll line by line |
| `Space`, `Shift+Space` | Page down, up |
| `Option+↑`, `Option+↓` | Page up, down |
| `⌘↑`, `⌘↓`, `Home`, `End` | Jump to top, bottom |
| `Page Up`, `Page Down` | Page scroll |

## Verification

```bash
make check            # Swift unit tests and Node renderer regression tests
make gui-test         # Build app and run native WebKit interaction checks
make validate-bundle  # Check bundled assets and code signature
```

GUI checks require an active macOS desktop. They are separate from `make check` so unit tests can run without a window session. A successful build or a living process alone is not evidence that rendering, selection, clipboard, links or reloading work.

The first renderer test run installs the lockfile-pinned jsdom development dependency with npm; subsequent runs use the installed dependency. This network setup is only needed for development tests, not for building or using the viewer. The GUI entry point uses the `python` command (Python 3).

The [2.0.1 clipboard verification](verification/2026-09-27-v2.0.1/REPORT.md) includes actual paste tests in Word for Mac.

The [version 2 verification report](verification/2026-09-27-v2/REPORT.md) maps every review finding to its fix and test evidence.

The original review and fixtures are in [review/2026-09-27](review/2026-09-27/REVIEW.md). Implementation and verification records are tracked in [wotan/dev-log](wotan/dev-log).

## License

mdview is [MIT licensed](LICENSE). Vendored dependency versions, source archive checksums and individual license texts are in [the renderer vendor directory](Sources/Resources/Web/vendor). See [THIRD_PARTY.md](THIRD_PARTY.md).
