class Shipit < Formula
  desc "Swift-native CLI toolkit for iOS and Android release automation"
  homepage "https://github.com/shipitswifty/shipitswifty"
  license "MIT"
  # Stable releases are added in the tap after a tag exists, because the
  # GitHub source archive checksum is only knowable after publication.
  # Add these lines in shipitswifty/homebrew-tap after tagging a release:
  # url "https://github.com/shipitswifty/shipitswifty/archive/refs/tags/<version>.tar.gz"
  # sha256 "<computed-sha256>"
  head "https://github.com/shipitswifty/shipitswifty.git", branch: "main"

  uses_from_macos "swift" => :build

  def install
    args = if OS.mac?
      ["--disable-sandbox"]
    else
      ["--static-swift-stdlib"]
    end

    system "swift", "build", *args, "--configuration", "release", "--product", "shipit"
    bin.install ".build/release/shipit"
  end

  test do
    assert_match "OVERVIEW: Swift-native CLI for iOS and Android app release automation.", shell_output("#{bin}/shipit --help")
  end
end
