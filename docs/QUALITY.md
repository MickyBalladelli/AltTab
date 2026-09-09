# Quality

## Automated coverage

`Tests/AltTabTests/QualityTests.swift` covers:

- window layer, size, display, utility, minimized, off-screen, and exclusion filtering;
- MRU restoration and stale identifier handling;
- default F1-F12 mapping and custom shortcut persistence;
- cycling, reverse cycling, selection, canceling, committing, search, and distinct same-app windows.

The switcher behavior lives in `SwitcherState`, a UI-independent state model used by the AppKit controller. This keeps keyboard and selection behavior testable without needing to activate real user windows.

The GitHub Actions matrix runs these tests on macOS 13, macOS 14, macOS 15, and `macos-latest`. macOS 13 covers Intel runners; macOS 14 and later cover Apple Silicon runners. The moving `macos-latest` entry keeps coverage on the current GitHub macOS release.

## Window catalog profiling

`WindowCatalog` records the last enumeration duration, number of returned windows, and icon- and thumbnail-cache hits/misses in `WindowCatalog.lastProfile`. The values appear in **Diagnostics & Permissions...**.

Icons are cached by bundle identifier. Thumbnails use a bounded, size-aware cache with a short freshness window because their content changes. Window catalog loads are debounced and run away from the main thread.

Run the repeatable cold/warm catalog benchmark with:

```sh
./scripts/benchmark-window-catalog.sh
```

For deeper inspection, use Instruments or Time Profiler while opening the switcher in a release build.
