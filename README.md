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

The script creates a versioned, locally ad-hoc signed app. For a release build, provide a Developer ID identity:

```sh
ALT_TAB_VERSION=1.0.0 \
ALT_TAB_BUILD_NUMBER=100 \
ALT_TAB_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
./scripts/build-app.sh
```

Distribution through Homebrew still requires notarization.

On first launch, AltTab detects missing Accessibility permission and offers a button to open **System Settings > Privacy & Security > Accessibility**. The same link is available from the menu bar and Settings.

The switcher supports Option-Tab cycling, Option-Shift-Tab reverse cycling, arrow keys, number selection, Return, Escape, and mouse selection. It activates the selected window, including a specific window when several belong to one app.

The switcher keeps a local MRU order, supports keyboard search by app or window title, and jumps directly to windows with Option-1 through Option-9. Its panel stays on the active Space and follows the display under the pointer. The Command Palette provides window actions, diagnostics, and app launching. Reduce Motion, Increase Contrast, VoiceOver, and Reduce Transparency settings are respected. Diagnostics are local only; AltTab sends no telemetry.

The Settings window saves switcher contents, thumbnail/icon sizes, columns, labels, corner radius, opacity, accent color, blur, display filtering, activation shortcut, hold-to-preview, window filters, and excluded bundle IDs in `UserDefaults`. By default, utility and minimized windows are hidden. The F1-F12 editor also supports recording triggers plus JSON import/export.

## F1-F12 quick app slots

The shortcut engine reads bundle identifiers from `UserDefaults`:

```sh
defaults write com.alttab.AltTab AltTab.quickSlot.1 com.apple.Safari
```

Slots `1` through `12` start as F1 through F12. Edit their triggers and app bundle IDs in the Settings window's F1-F12 editor.

## Homebrew

Install from the Homebrew tap:

```sh
brew tap MickyBalladelli/tap
brew install --cask alt-tab
```

Release builds are signed with Developer ID, notarized by Apple, and published as `AltTab.dmg` with a SHA-256 checksum. The menu bar's **Check for Updates...** command checks the latest signed release on demand. See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md) for release setup, uninstall, permission reset, and troubleshooting.

Quality checks run in GitHub Actions on macOS 13 through the current macOS release across Intel and Apple Silicon. See [docs/QUALITY.md](docs/QUALITY.md) for test coverage and window-catalog profiling.
