# mdview

> Native macOS markdown viewer using SwiftUI and MarkdownUI

## Quick Start

```bash
# Build
swift build

# Run directly
.build/debug/mdview

# Or build and run the app bundle
swift build && ./scripts/bundle.sh && open mdview.app
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

## Creating App Bundle

After building, create the .app bundle:

```bash
# Create bundle structure
mkdir -p mdview.app/Contents/MacOS
mkdir -p mdview.app/Contents/Resources

# Copy binary
cp .build/debug/mdview mdview.app/Contents/MacOS/

# Sign (ad-hoc for local use)
codesign --sign - --force --deep mdview.app
```

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
