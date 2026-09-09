# AltTab for macOS

A fast, keyboard-first window switcher for macOS. The first native slice runs as a menu-bar utility and provides an Option-Tab overlay with app icons, window titles, MRU-style cycling, Escape cancel, and Return activation.

## Run locally

```sh
swift run
```

## Create the app

Build a release `.app` bundle in `build/`:

```sh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open build/AltTab.app
```

The script creates a locally ad-hoc signed app. Distribution through Homebrew still requires a Developer ID signature and notarization.

The app needs macOS Accessibility permission before global keyboard monitoring can work. Grant it in **System Settings > Privacy & Security > Accessibility**.

## F1-F12 quick app slots

The shortcut engine reads bundle identifiers from `UserDefaults`:

```sh
defaults write com.alttab.AltTab AltTab.quickSlot.1 com.apple.Safari
```

Slots `1` through `12` map to F1 through F12. The settings UI for editing these bindings is tracked in [TODO.md](TODO.md).

## Homebrew

The intended release command is:

```sh
brew tap alttab/tap
brew install --cask alt-tab
```

The tap and signed notarized release still need to be published; see [TODO.md](TODO.md).
