cask "agent-island" do
  version "0.0.0"
  sha256 "REPLACE_WITH_RELEASE_SHA256"

  url "https://github.com/Lando-C/agent-island/releases/download/v#{version}/Agent-Island-macOS.zip"
  name "Agent Island"
  desc "Operations island for local AI agent sessions on macOS"
  homepage "https://github.com/Lando-C/agent-island"

  depends_on macos: ">= :ventura"

  app "Agent Island.app"

  zap trash: [
    "~/Library/Preferences/local.agent-island.plist",
    "~/.agent-island",
  ]
end
