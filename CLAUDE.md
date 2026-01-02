# mdview

> Native macOS markdown viewer with LaTeX math support

## Quick Start

```bash
# Build and install
make install

# Or manually
swift build
./bundle.sh
cp -r mdview.app ~/Applications/
```

## Tech Stack

- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI
- **Markdown**: [swift-markdown](https://github.com/swiftlang/swift-markdown) (Apple's cmark-gfm based parser)
- **Math**: [SwiftMath](https://github.com/mgriebling/SwiftMath) (LaTeX rendering)
- **Target**: macOS 13.0+
- **Build**: Swift Package Manager (no Xcode required)

## Project Structure

```
mdview/
├── Package.swift         # SPM package definition
├── Sources/
│   ├── mdviewApp.swift   # App entry point
│   └── ContentView.swift # Main view with markdown rendering
├── mdview.app/           # Built app bundle
├── CLAUDE.md             # This file
└── wotan/                # Task management
```

## Development

```bash
# Build
swift build

# Build release
swift build -c release

# Clean
swift package clean

# Update dependencies
swift package update
```

## Build & Install

```bash
# Full build, bundle, and install to ~/Applications
make install

# Just build
make build

# Just create app bundle (after build)
make bundle

# Clean everything
make clean
```

The `bundle.sh` script handles creating the .app structure and code signing.

## Verification

Before committing:
```bash
# Build succeeds
swift build

# SwiftLint (if installed)
swiftlint
```

## Implementation Notes

### Custom Markdown Renderer

Uses swift-markdown for AST parsing and custom SwiftUI view composition for rendering:

- **Math Support**: Inline `$...$` and block `$$...$$` LaTeX via SwiftMath
- **GFM support**: Tables, strikethrough, task lists
- **No HTML rendering**: Raw HTML tags are ignored (by design)
- **Code blocks**: Math delimiters in code blocks are NOT rendered (AST-aware)

Key files:
- `ContentView.swift` - Main renderer with `MarkdownContentView`, `MathAwareParagraph`
- `MathView.swift` - NSViewRepresentable wrapper for MTMathUILabel

### macOS Keyboard Shortcuts

- **Character shortcuts** (+, -, 0, etc.): Use SwiftUI `CommandGroup` with `.keyboardShortcut()`
  - Handles keyboard localization automatically (Swedish, German, etc.)
  - DON'T use NSView `keyDown` with `charactersIgnoringModifiers` - fails on non-US keyboards
- **Physical keys** (arrows, space, home, end): CAN use `keyCode` - hardware-based, same on all keyboards

### Build/Test Workflow

- macOS may launch old version from `~/Applications` instead of newly built version
- Always run: `cp -R mdview.app ~/Applications/` after `./bundle.sh` to test correct version
- Or use `make install` which does this automatically

### File Watching

- `DispatchSource.makeFileSystemObjectSource` (kqueue) - efficient kernel-based file monitoring
- Store markdown text as `@State` separate from `FileDocument` for live updates on external changes
