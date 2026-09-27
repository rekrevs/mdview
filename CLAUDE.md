# mdview

Read `README.md` for supported features and user commands. Use Wotan for task work: `wotan/backlog.json` owns task state; `wotan/dev-log/` records plans, evidence and outcomes. Old completed tasks describe historical versions, not the current architecture.

## Architecture

Version 2 uses a SwiftUI document app with one `WKWebView` per reader window. The HTML document keeps selection, copying, math and text layout in one continuous DOM. Do not reintroduce individual SwiftUI text views for Markdown blocks.

- `Sources/mdviewApp.swift`: native document app and keyboard commands.
- `Sources/ContentView.swift`: document state, per-window zoom/find and reload integration.
- `Sources/ReaderWebView.swift`: WebKit hosting, navigation and keyboard scrolling.
- `Sources/LinkDestination.swift`: URL classification for anchors, local files and external destinations.
- `Sources/Resources/Web/`: offline page, renderer, CSS, vendored libraries/fonts/licenses.
- `Tests/mdviewTests/`: Swift regression tests.
- `Tests/Renderer/`: Node renderer regression tests.
- `scripts/check-reader.py`: native GUI verification entry point.

Rendering uses markdown-it, KaTeX and highlight.js, with raw HTML disabled. Libraries and fonts are pinned local assets; the installed reader must work without access to the source checkout or a CDN. `Package.swift` copies the complete `Resources` directory. Bundle lookup must prefer resources inside the installed app before SwiftPM's development fallback.

## Build and verification

```bash
make build
make check
make gui-test
make release
make validate-bundle
```

`make install` builds release by default and preserves the old installed app as a timestamped backup. Use `CONFIGURATION=debug` to override. Do not delete an existing user installation. For development, launch the intended bundle explicitly; Launch Services can otherwise choose an older copy in `~/Applications`.

Use `scripts/swift-tool.sh` for repository builds/tests. It normally invokes SwiftPM unchanged, but selects an installed SDK 26.5 with `--build-system native` when SDK 27 is selected (observed SwiftUI macro incompatibility). `MDVIEW_SDK` overrides that choice. Do not mutate global SDK/toolchain settings. A filesystem sandbox may require running builds outside it so Swift can access its compiler caches.

Swift tests use Swift Testing. When only Command Line Tools are installed (Testing.framework present and XCTest.framework absent), the wrapper supplies the shipped Testing framework, macro plugin and runtime search paths for `test` only. Xcode builds and the shipped app do not need those test paths.

For rendering or interaction changes, reproduce the issue and test the actual WebKit page. Require clipboard/selection, link destinations and repeated atomic-save evidence as relevant; compile success and process presence are insufficient. GUI checks require an active macOS desktop. Tests that inspect DOM or route classification are complementary to real window interaction, not substitutes for it.

## Implementation constraints

- Keep keyboard character shortcuts in SwiftUI commands to preserve keyboard layout behavior. Physical scrolling keys may use macOS key codes.
- Scope zoom and find actions to the active document; avoid broadcasting state changes to every window.
- Preserve nested Markdown content, whitespace and math environments. On unsupported input, show source or a clear error instead of dropping content.
- Keep raw Markdown HTML inert; only bundled scripts execute. Explicitly classify link destinations before opening them.
- File reload must survive inode replacement during atomic saves and close every watcher descriptor. Keep last good document content visible if a reload temporarily fails.
- Keep SwiftPM and app-bundle resources in sync. Validate a relocated bundle with no build-tree resource fallback before declaring packaging complete.
- Update README and dependency licenses/manifest when supported behavior or vendored libraries change.
