class Shipit < Formula
  # For local tap testing before the public repository and release tarball exist,
  # replace `url`/`sha256` or `head` with local `file://` paths in the tap copy.
  desc "Swift-native CLI toolkit for iOS release automation"
  homepage "https://github.com/arjang/ShipItSwifty"
  url "https://github.com/arjang/ShipItSwifty/archive/refs/tags/1.0.0.tar.gz"
  sha256 "REPLACE_WITH_RELEASE_TARBALL_SHA256"
  license "MIT"
  head "https://github.com/arjang/ShipItSwifty.git", branch: "main"

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
    assert_match "OVERVIEW: A Swift-native CLI toolkit for iOS release automation.", shell_output("#{bin}/shipit --help")
  end
end
