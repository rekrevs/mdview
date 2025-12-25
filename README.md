# mdview

![mdview icon](AppIcon.iconset/icon_128x128.png)

> Native macOS markdown viewer

A lightweight markdown viewer for macOS built with SwiftUI and [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui).

## Features

- Native macOS app with SwiftUI
- Double-click `.md` files to open
- Each file opens in its own window
- Keyboard navigation (arrows, space, page up/down)
- Text selection enabled
- Syntax highlighting via MarkdownUI

## Installation

```bash
# Clone and build
git clone https://github.com/sverker/mdview.git
cd mdview
make install
```

This builds the app and installs it to `~/Applications`.

## Requirements

- macOS 13.0+
- Swift 5.9+

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `↑` / `↓` | Scroll line by line |
| `Space` | Page down |
| `Shift+Space` | Page up |
| `Option+↑` / `Option+↓` | Page up/down |
| `⌘+↑` / `⌘+↓` | Jump to top/bottom |
| `Home` / `End` | Jump to top/bottom |
| `Page Up` / `Page Down` | Page scroll |

## Set as Default Viewer

```bash
# Using duti
brew install duti
duti -s com.mdview.app net.daringfireball.markdown viewer
```

## License

MIT
