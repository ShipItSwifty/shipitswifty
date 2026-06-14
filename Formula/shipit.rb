class Shipit < Formula
  desc "Swift-native CLI toolkit for iOS and Android release automation"
  homepage "https://github.com/shipitswifty/shipitswifty"
  license "MIT"
  version "0.2.0"

  on_macos do
    url "https://github.com/ShipItSwifty/shipitswifty/releases/download/v#{version}/shipit-#{version}-macos-universal.tar.gz"
    sha256 "MACOS_SHA256_PLACEHOLDER"
  end

  on_linux do
    url "https://github.com/ShipItSwifty/shipitswifty/releases/download/v#{version}/shipit-#{version}-linux-static.tar.gz"
    sha256 "LINUX_SHA256_PLACEHOLDER"
  end

  def install
    bin.install "shipit"
  end

  test do
    assert_match "OVERVIEW: Swift-native CLI for iOS and Android app release automation.", shell_output("#{bin}/shipit --help")
  end
end
