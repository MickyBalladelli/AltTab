# Distribution

AltTab releases use a signed, notarized DMG. The release workflow runs when a `v*` tag is pushed and does this:

1. Imports the Developer ID Application certificate into a temporary keychain.
2. Builds the release app and DMG.
3. Verifies the app signature.
4. Submits the DMG to Apple notarization, staples the ticket, and validates it.
5. Publishes `AltTab.dmg` and `AltTab.dmg.sha256` to the GitHub release.
6. Updates `MickyBalladelli/homebrew-tap` with the release version and checksum.

## GitHub setup

Add these repository secrets before creating a release:

- `APPLE_SIGNING_IDENTITY`: Developer ID Application identity name.
- `APPLE_CERTIFICATE_BASE64`: base64-encoded `.p12` certificate export.
- `APPLE_CERTIFICATE_PASSWORD`: password for the `.p12` export.
- `APPLE_ID`: Apple Developer account email.
- `APPLE_TEAM_ID`: Apple Team ID.
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for `notarytool`.
- `HOMEBREW_TAP_TOKEN`: token that can push to `MickyBalladelli/homebrew-tap`.

The tap repository needs a `Casks/` directory. The workflow copies the checked-in cask there on its first release, then replaces its version and SHA-256 value on every release.

Create a release with:

```sh
git tag v0.1.0
git push origin v0.1.0
```

Or run the workflow manually and enter the version without `v`.

## Homebrew

After the first release is published:

```sh
brew tap MickyBalladelli/tap
brew install --cask alt-tab
```

The cask points at the versioned GitHub release DMG and the tap workflow fills its SHA-256 checksum. The checked-in cask is the bootstrap source used when the tap is first populated.

## Updates

The menu bar has **Check for Updates...**. AltTab checks the latest GitHub release only when asked, compares versions locally, and opens the signed, notarized DMG when a newer release exists. Workflow Settings has an opt-in **Automatically download verified updates** switch. When enabled, AltTab downloads the DMG, checks its SHA-256 checksum, validates the Apple notarization ticket, checks the Developer ID signature and Gatekeeper assessment, then offers to open the verified DMG. There is no background telemetry or update service.

See [RELEASE.md](RELEASE.md) for the release checklist, smoke checks, certificate rotation, and local crash diagnostics.

## Uninstall

Homebrew uninstall:

```sh
brew uninstall --cask alt-tab
```

Remove AltTab preferences from Terminal:

```sh
defaults delete com.alttab.AltTab
```

You can also remove the app by dragging `AltTab.app` to the Trash. The cask `zap` stanza lists the preference and support locations left behind by a full uninstall.

## Reset Accessibility permission

To make macOS show the permission prompt again:

```sh
tccutil reset Accessibility com.alttab.AltTab
```

Then launch AltTab and allow it in **System Settings > Privacy & Security > Accessibility**.

## Troubleshooting

- No switcher appears: confirm Accessibility permission, then quit and relaunch AltTab.
- Some windows are missing: check the content mode, current-display filter, minimized-window setting, utility-window setting, and excluded bundle IDs in Settings.
- The update check fails: open the GitHub Releases page directly and check the network connection.
- A downloaded DMG is rejected: use the release asset from the official GitHub release and confirm its SHA-256 value with `shasum -a 256 AltTab.dmg`.
- Use **Diagnostics & Permissions...** from the menu bar to copy local status details. Use **Open Crash Diagnostics...** to inspect local crash reports. AltTab sends no telemetry.
