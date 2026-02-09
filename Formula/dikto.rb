class Dikto < Formula
  desc "Voice-to-text transcription powered by local AI models"
  homepage "https://github.com/nicokosi/dikto"  # TODO: Update with actual repo URL
  license "MIT"

  # CLI: build from source
  head "https://github.com/nicokosi/dikto.git", branch: "main"  # TODO: Update URL

  depends_on "rust" => :build

  def install
    system "cargo", "install", *std_cargo_args(path: "crates/dikto-cli")
  end

  test do
    assert_match "dikto", shell_output("#{bin}/dikto --version")
  end
end

# Cask for the macOS GUI app (Dikto.app)
# To be placed in a separate homebrew-dikto tap or added as:
#
# cask "dikto" do
#   version "2.0.0"
#   sha256 "TODO"  # SHA-256 of the DMG
#
#   url "https://github.com/USER/dikto/releases/download/v#{version}/Dikto-#{version}.dmg"
#   name "Dikto"
#   desc "Voice-to-text transcription for macOS"
#   homepage "https://github.com/USER/dikto"
#
#   app "Dikto.app"
#
#   zap trash: [
#     "~/.config/dikto",
#     "~/.local/share/dikto",
#   ]
# end
