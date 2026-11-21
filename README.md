# Pagedrop

A tiny menu bar app to export, trim, reorder and annotate PDFs.

Drag a PDF onto the icon in the menu bar, pick what you want to do, and get on with your day.

## Screenshots

_Screenshots coming soon._

## Features

- **Drop on the menu bar icon.** The icon reacts while you drag a file over it. PDFs open the popover; anything else is politely refused.
- **Export as images.** Turn all or some pages into PNG or JPEG, at the resolution you choose, with progress and cancellation.
- **Remove pages.** Pick pages in a thumbnail grid and remove them.
- **Reorder pages.** Drag thumbnails into a new order.
- **Annotate.** Highlight text, draw with a pen and add text notes in a dedicated window, with undo.
- **Menu bar only.** No Dock icon. Right-click the icon for Launch at Login and Quit.

## Requirements

- macOS 14 Sonoma or later
- Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) only if you want to modify the project

## Install

1. Download `Pagedrop.zip` from the [latest release](https://github.com/MINTYdv/Pagedrop/releases/latest) and unzip it.
2. Move `Pagedrop.app` to `/Applications`.
3. The app is signed ad hoc (there is no paid Apple Developer ID behind it), so macOS blocks the first launch. Either:
   - right-click `Pagedrop.app`, choose **Open**, then confirm; or
   - run `xattr -dr com.apple.quarantine /Applications/Pagedrop.app` in Terminal, then open it normally.

## Build from source

The Xcode project is committed, so you can simply open `Pagedrop.xcodeproj`.

```sh
# Build
xcodebuild -project Pagedrop.xcodeproj -scheme Pagedrop -configuration Debug build

# Run the tests
xcodebuild -project Pagedrop.xcodeproj -scheme Pagedrop test

# Build a distributable zip at build/Pagedrop.zip
scripts/release.sh
```

If you change `project.yml`, regenerate the project with `brew install xcodegen && xcodegen generate`.
The app icon is drawn by `scripts/generate-icon.swift`.

## Architecture

```
Pagedrop/
├── App/                 Entry point, status item, drop target, popover and window management
├── Core/                PDF editing, rendering and image export (no views; built as its own library)
├── Features/
│   ├── Popover/         Empty state and tool list shown in the popover
│   ├── Export/          Export options and progress
│   ├── PageEditor/      Thumbnail grid used to remove and reorder pages
│   └── Annotate/        PDFView wrapper with highlight, pen and note tools
├── Shared/              Thumbnails, file panels, small helpers
└── Resources/           Asset catalog, Info.plist, entitlements
PagedropTests/           Unit tests for the Core layer
scripts/                 Icon generator and release script
```

- **App** is AppKit: `StatusBarController` owns the `NSStatusItem` and `NSPopover`, `StatusItemIconView` receives drops, and `WindowCoordinator` opens the larger windows.
- **Core** is pure and testable. `PDFDocumentEditor` returns edited copies of documents, `PDFPageRenderer` and `PDFImageExporter` draw and write pages, and the export runs off the main actor with `@concurrent`.
- **Features** are SwiftUI views driven by `@Observable` models. `DocumentSession` is the single source of truth for the loaded document.
- The app runs in the App Sandbox with the user-selected file read/write entitlement and the hardened runtime.

## License

MIT. See [LICENSE](LICENSE).
