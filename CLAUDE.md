# mdview

> Native macOS markdown viewer using SwiftUI and MarkdownUI

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
- **Markdown**: [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) (cmark-gfm based)
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
├── backlog.json          # Task index
└── dev-log/              # Task details
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

## Task Management

Use `/wotan` to manage tasks:
- `/wotan` - list active tasks
- `/wotan continue` - pick up next task
- `/wotan add "description"` - add new task
