# Template formula. The release workflow (.github/workflows/release.yml) renders this on each
# tag — substituting VERSION_PLACEHOLDER and the two SHA256 placeholders with real values — and
# publishes the result to the Homebrew tap. Releases use bare semver tags (no `v` prefix), so the
# download URL must not include a `v`. Do not hand-fill the placeholders here.
class Shipit < Formula
  desc "Swift-native CLI toolkit for iOS and Android release automation"
  homepage "https://github.com/shipitswifty/shipitswifty"
  license "MIT"
  version "VERSION_PLACEHOLDER"

  on_macos do
    url "https://github.com/ShipItSwifty/shipitswifty/releases/download/#{version}/shipit-#{version}-macos-universal.tar.gz"
    sha256 "MACOS_SHA256_PLACEHOLDER"
  end

  on_linux do
    url "https://github.com/ShipItSwifty/shipitswifty/releases/download/#{version}/shipit-#{version}-linux-static.tar.gz"
    sha256 "LINUX_SHA256_PLACEHOLDER"
  end

  def install
    bin.install "shipit"
  end

  test do
    assert_match "OVERVIEW: Swift-native CLI for iOS and Android app release automation.", shell_output("#{bin}/shipit --help")
  end
end
