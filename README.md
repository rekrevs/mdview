# mdview 2

![mdview icon](AppIcon.iconset/icon_128x128.png)

A macOS Markdown reader with a native document window and one continuous, selectable WebKit page. Version 2 replaces the old per-block SwiftUI renderer with locally bundled markdown-it, KaTeX and highlight.js.

## Reading

- Open `.md` and `.markdown` files from Finder or the Open dialog; each document has its own window.
- Select and copy across paragraphs, lists, tables and code blocks. The clipboard includes plain text and portable HTML: partial selections keep their formatting, tables carry borders/alignment, code retains a monospace font and indentation, and numbered-list excerpts retain their starting number. Relative links become absolute links back to the source files.
- Formulas copy as LaTeX and images as alt text in both clipboard formats; copying does not yet create Office equations or embed images.
- Follow heading anchors, relative Markdown links and external web/email links.
- Read tables with column alignment, nested lists and quotes, task checkboxes, local images and syntax-highlighted code.
- Render inline `$…$`, display `$$…$$` and fenced `math` blocks with KaTeX, including matrices and multiline environments supported by KaTeX.
- Find prose and code with `⌘F`, navigate the heading outline, and zoom the active document without changing other windows. Search matches across inline formatting; it excludes formula internals.
- Reload external file changes, including repeated atomic saves by editors.
- Follow the macOS light/dark appearance.

The renderer, syntax highlighter, math library and fonts are included in the app. They require no CDN or runtime download. Images using HTTP/HTTPS still require a network connection.

This is a read-only viewer. Raw HTML is shown as text rather than executed; Mermaid, MDX, PDF export and Finder Quick Look are not implemented. KaTeX supports a subset of LaTeX, and is not identical to GitHub's MathJax renderer. Unsupported formulas remain visible as source with an error indication. Task checkboxes display the document state without editing it.

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
