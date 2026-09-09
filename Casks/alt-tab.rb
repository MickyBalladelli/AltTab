cask "alt-tab" do
  version "0.1.0"
  sha256 :no_check

  url "https://github.com/MickyBalladelli/AltTab/releases/download/v#{version}/AltTab.dmg"
  name "AltTab"
  desc "Customizable keyboard-first window switcher for macOS"
  homepage "https://github.com/MickyBalladelli/AltTab"

  app "AltTab.app"

  zap trash: [
    "~/Library/Preferences/com.alttab.AltTab.plist",
    "~/Library/Application Support/AltTab"
  ]
end
