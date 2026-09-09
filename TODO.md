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
- [x] Create a GitHub release workflow for signed and notarized DMGs.
- [x] Publish a Homebrew tap and replace `Casks/alt-tab.rb` placeholders with release URLs and SHA-256 values.
- [x] Support `brew install --cask alt-tab` from the tap.
- [x] Add Sparkle or an equivalent signed update mechanism.
- [x] Document uninstall, permissions reset, and troubleshooting.

## Quality
- [x] Unit test window filtering, MRU ordering, shortcut persistence, and F-key mapping.
- [x] Add UI tests for cycling, canceling, committing, and same-app window selection.
- [x] Test macOS 13 through the current macOS release on Intel and Apple Silicon.
- [x] Profile window enumeration and cache icons to keep the overlay instant.

## Improvements

### Reliability and safety
- [x] (P0) Replace volatile CG window IDs with a stable app/title/frame fallback for MRU entries across relaunches.
- [x] (P0) Handle windows that close, move, or lose Accessibility access while the switcher is open.
- [x] (P0) Make close and move actions report failure clearly, with confirmation for close.
- [x] (P1) Add a safe recovery path when Accessibility permission is revoked during use.
- [x] (P1) Detect activation-shortcut conflicts before saving a binding.

### Speed
- [x] (P0) Move window enumeration and thumbnail capture off the main thread.
- [x] (P1) Add thumbnail caching with size-aware invalidation and memory limits.
- [x] (P1) Debounce repeated refreshes and avoid rebuilding unchanged switcher items.
- [x] (P2) Add a repeatable performance benchmark for cold and warm switcher opens.

### Keyboard and window workflow
- [x] (P1) Add fuzzy search, recent search terms, and a visible result count.
- [x] (P1) Add a contextual menu for actions on the currently selected window.
- [x] (P1) Show clearer Space and display names, including the target display before a move.
- [x] (P2) Add configurable shortcuts for every window action.
- [x] (P2) Add launch-at-login and an option to reopen the last switcher mode.

### Accessibility and settings
- [x] (P0) Expose every switcher card as a VoiceOver element with title, app, selected state, and keyboard hint.
- [x] (P1) Add full keyboard navigation and focus restoration to Settings, Diagnostics, and the Command Palette.
- [x] (P1) Add settings export/import for all preferences, not only F1-F12 bindings.
- [x] (P2) Add per-app profiles for content mode, filters, and appearance.

### Release and maintenance
- [ ] (P1) Add an opt-in automatic update download after signature and notarization verification.
- [ ] (P1) Add release smoke checks for the DMG, cask URL, checksum, and install/uninstall path.
- [ ] (P2) Add a reproducible release checklist and certificate-rotation instructions.
- [ ] (P2) Add local crash diagnostics without collecting or transmitting telemetry.
