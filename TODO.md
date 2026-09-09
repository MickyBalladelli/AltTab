# AltTab TODO

## MVP hardening
- [x] Add a real `.app` bundle with `Info.plist`, icon assets, versioning, and a signed release build.
- [x] Add Accessibility permission detection and an onboarding prompt with a direct link to System Settings.
- [x] Make the switcher window-aware: distinguish multiple windows from the same app and activate the selected window, not only its app.
- [x] Support arrow keys, number keys, mouse selection, and repeated reverse cycling with `Option-Shift-Tab`.
- [x] Hide utility windows, minimized windows, and excluded apps using user-configurable filters.
- [x] Replace the demo settings controls with persisted settings backed by `UserDefaults`.

## Customization
- [x] Choose switcher contents: applications, windows, spaces, full-screen apps, or a mixed view.
- [x] Configure thumbnail size, icon size, columns, labels, corner radius, opacity, accent color, and background blur.
- [x] Add per-app exclusions and a "show only windows on this display" option.
- [x] Add configurable activation shortcut, including right/left Option and Command-based alternatives.
- [x] Build an F1-F12 editor: record a key, choose a running app, choose a bundle ID, clear a slot, and import/export bindings.
- [x] Add optional "hold key to preview, release to switch" behavior.

## Must-have Mac features
- [x] Restore the last-used window order and make MRU ordering predictable.
- [x] Search windows by app or title without leaving the keyboard.
- [x] Switch directly to a specific window with `Option-1` through `Option-9`.
- [x] Support Spaces and displays without unexpectedly moving the user between desktops.
- [x] Add window actions: minimize, close, hide app, move to display, and move to Space.
- [x] Add a compact command palette for quick actions and app launching.
- [x] Respect Reduce Motion, Increase Contrast, and VoiceOver accessibility settings.
- [x] Add telemetry-free diagnostics and a permissions/status page.

## Distribution
- [ ] Create a GitHub release workflow for signed and notarized DMGs.
- [ ] Publish a Homebrew tap and replace `Casks/alt-tab.rb` placeholders with release URLs and SHA-256 values.
- [ ] Support `brew install --cask alt-tab` from the tap.
- [ ] Add Sparkle or an equivalent signed update mechanism.
- [ ] Document uninstall, permissions reset, and troubleshooting.

## Quality
- [ ] Unit test window filtering, MRU ordering, shortcut persistence, and F-key mapping.
- [ ] Add UI tests for cycling, canceling, committing, and same-app window selection.
- [ ] Test macOS 13 through the current macOS release on Intel and Apple Silicon.
- [ ] Profile window enumeration and cache icons to keep the overlay instant.
