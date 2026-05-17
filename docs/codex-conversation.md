# Codex Conversation Record

This file records the ClipShelf development conversation and decisions made with Codex.

## Original Goal

ClipShelf started from a macOS screenshot workflow problem:

- macOS normal screenshots save to a file, but do not automatically place the screenshot on the clipboard.
- The desired app should keep screenshot files in the normal folder while also adding the latest screenshot to the clipboard.
- The app should also keep clipboard history for text, files, and images.

The app name was kept as **ClipShelf**.

## Product Direction

The final direction became a simpler, more reliable macOS app:

- Watch a chosen screenshot folder.
- When a new screenshot appears, copy it to the clipboard and add it to history.
- Keep the original file in Finder.
- Record copied text, files, and images.
- Let users search, select, preview, copy, paste, delete, and pin history items.

The original attempt to hook the macOS floating screenshot thumbnail was abandoned because it caused permission prompts, delayed capture behavior, and inconsistent clipboard timing. The simpler version assumes the user disables the macOS floating screenshot thumbnail.

## Implemented Features

- macOS desktop app bundle named `ClipShelf`
- App icon and Dock visibility
- GitHub-ready SwiftPM project
- Screenshot folder watcher
- Clipboard history for:
  - text
  - files
  - images
  - screenshots
- Screenshot-to-clipboard behavior while preserving original screenshot files
- Search with fuzzy matching support
- Keyboard navigation
- Space preview for single selected records
- Multi-select support
- Command-A, Command-C, Command-V support for selected records
- Clear history without deleting original files
- Custom selection color
- Settings overlay
- Global show-window hotkey
- Custom hotkey to clear current selection
- Custom hotkey to pin selected records
- Launch at login toggle
- Three selectable app icons
- Pinned records that stay above normal records
- GitHub Releases distribution

## Important UX Decisions

- Clearing ClipShelf history only removes app records.
- Clearing history does not delete screenshots or original files from Finder.
- Multi-selected records do not open preview with Space.
- Selected row text remains black; only the row background changes.
- Settings opens as an overlay and clicking outside settings returns to the main window.
- The app is distributed for free without Apple notarization.

## Screenshot Setup Guidance

For best screenshot behavior:

1. Set macOS screenshot save location to the same folder configured in ClipShelf.
2. Disable macOS screenshot tool's "Show Floating Thumbnail" option.

This lets screenshots keep saving to disk while ClipShelf copies them into the clipboard and history.

## Publishing Notes

GitHub repository:

https://github.com/Applebook743/ClipShelf

Releases:

- v1.0.0: initial public release
- v1.1.0: added pinned records and custom pin hotkey

Current release download:

https://github.com/Applebook743/ClipShelf/releases/tag/v1.1.0

## Signing And Distribution

The app is currently ad-hoc signed locally.

Because there is no Apple Developer Program membership, the app is not Developer ID signed and not notarized. Users may see a macOS warning on first launch. The documented workaround is:

1. In Finder, right-click `ClipShelf.app`.
2. Choose "Open".
3. Confirm "Open" again in the macOS security dialog.

Users can also build from source if they prefer.

## Known Issues

- Auto-scrolling while three-finger drag-selecting near the top or bottom of the record list was attempted several ways but remains unreliable.
- Basic three-finger drag multi-select works and was restored after the experimental auto-scroll attempts.
- The current recommendation is to keep basic multi-select stable and revisit auto-scroll later with a more native AppKit list/scroll implementation.

## Local Project Paths

Development workspace:

```text
/Users/Zhuanz/Documents/Codex/2026-05-16/macos-windows
```

Installed app:

```text
/Users/Zhuanz/Applications/ClipShelf.app
```

History file:

```text
~/Library/Application Support/ClipShelf/history.json
```

## Release Workflow

Build and package:

```bash
./script/package_release.sh
```

The generated download zip is:

```text
release/ClipShelf.zip
```

Upload this zip to GitHub Releases when creating a new release.
