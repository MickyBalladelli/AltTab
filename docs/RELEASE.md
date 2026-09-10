# Release and maintenance

Use the same inputs every time. Release from a clean tag on the pinned `macos-14` runner.

## Release checklist

1. Update the version in the release tag and choose a numeric build number.
2. Record the commit, `swift --version`, runner OS, and runner architecture.
3. Build the signed DMG with explicit values:

   ```sh
   ALT_TAB_VERSION=1.0.0 \
   ALT_TAB_BUILD_NUMBER=100 \
   ALT_TAB_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
   ./scripts/create-dmg.sh
   ```

4. Verify the app signature, submit the DMG to Apple notarization, staple the ticket, and validate it.
5. Run the local smoke check with a cask rendered for this version:

   ```sh
   cp Casks/alt-tab.rb /tmp/alt-tab.rb
   ./scripts/update-cask.sh 1.0.0 "$(awk '{print $1}' build/AltTab.dmg.sha256)" /tmp/alt-tab.rb
   ./scripts/release-smoke-check.sh build/AltTab.dmg /tmp/alt-tab.rb 1.0.0
   ```

   Add `--remote` after publishing when the GitHub release URL should also be checked.
6. Push the `v1.0.0` tag. The GitHub workflow publishes the DMG, checksum, and Homebrew cask.
7. Download the published assets on a clean Mac. Check the checksum, open the DMG, launch the app, and test uninstall.
8. Keep the release checksum and recorded build inputs with the release notes.

The smoke check mounts the DMG read-only, validates the app signature and Gatekeeper assessment, copies the app to a temporary Applications folder, and moves that copy to `Trash/` to prove the uninstall path without touching the real `/Applications` folder.

## Certificate rotation

1. Create a new **Developer ID Application** certificate in the Apple Developer account.
2. Export the certificate and private key as a password-protected `.p12` file.
3. Replace `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, and `APPLE_SIGNING_IDENTITY` in GitHub Actions secrets.
4. Run one release workflow manually. Confirm `codesign`, `spctl`, `notarytool`, and `stapler validate` all pass.
5. Confirm the published DMG opens on a clean Mac and the Homebrew checksum matches.
6. Revoke the old certificate only after the new release is verified. Keep the old certificate until any rollback window closes.

Never print the `.p12` password, private key, app-specific password, or tap token in workflow logs. Rotate the Apple app-specific password and Homebrew token separately if either is exposed.

## Local crash diagnostics

AltTab records uncaught Objective-C exceptions locally in:

`~/Library/Application Support/AltTab/CrashDiagnostics/`

Use **Open Crash Diagnostics...** in the menu bar or the Diagnostics window to open that folder. Reports contain the exception, stack, app version, build, and macOS version. They are never uploaded or sent by AltTab.
