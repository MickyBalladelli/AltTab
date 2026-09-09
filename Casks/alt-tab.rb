cask "alt-tab" do
  version "0.1.0"
  sha256 :no_check

  # Replace with the signed, notarized release asset when the tap is published.
  url "https://github.com/alttab/alt-tab/releases/download/v#{version}/AltTab.dmg"
  name "AltTab"
  desc "Customizable keyboard-first window switcher for macOS"
  homepage "https://github.com/alttab/alt-tab"

  app "AltTab.app"

  zap trash: [
    "~/Library/Preferences/com.alttab.AltTab.plist",
    "~/Library/Application Support/AltTab"
  ]
end
