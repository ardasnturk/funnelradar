# Homebrew cask for FunnelRadar.
#
#   brew tap ardasnturk/funnelradar https://github.com/ardasnturk/funnelradar
#   brew install --cask funnelradar
#
# `version` and `sha256` are updated by scripts/prepare-release.sh.
cask "funnelradar" do
  version "0.1.0"
  sha256 "30667a820d19ff956fe5dec1290b8aed8b373d0306ef1d7841609a2aaba1d0ca"

  url "https://github.com/ardasnturk/funnelradar/releases/download/v#{version}/FunnelRadar-#{version}.dmg"
  name "FunnelRadar"
  desc "Menu bar product analytics for your Mixpanel projects"
  homepage "https://github.com/ardasnturk/funnelradar"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sequoia"

  app "FunnelRadar.app"

  uninstall quit: "com.jastech.funnelradar"

  zap trash: [
    "~/Library/Application Support/FunnelRadar",
    "~/Library/Preferences/com.jastech.funnelradar.plist",
  ]
end
