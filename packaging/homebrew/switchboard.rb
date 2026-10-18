cask "switchboard" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/jpc4729/switchboard/releases/download/v#{version}/Switchboard-#{version}.zip"
  name "Switchboard"
  desc "Menu bar app to switch the input of each connected monitor"
  homepage "https://github.com/jpc4729/switchboard"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "Switchboard.app"
  binary "#{appdir}/Switchboard.app/Contents/Resources/switchboard"

  zap trash: "~/Library/Preferences/io.github.jpc4729.switchboard.plist"

  caveats <<~EOS
    Switchboard is not notarized by Apple. On first launch, open it once, then go to
      System Settings > Privacy & Security > Open Anyway
    or run:
      xattr -dr com.apple.quarantine #{appdir}/Switchboard.app
  EOS
end
