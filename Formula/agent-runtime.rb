class AgentRuntime < Formula
  desc "Launcher and cleanup script for the agent runtime (afrossard/container-base)"
  homepage "https://github.com/afrossard/container-base"
  url "https://github.com/afrossard/container-base/archive/refs/tags/5.0.2.tar.gz"
  sha256 "d440fc2b9ec78fcd73f5de2b3a0b6af7e9c53d6bbd2b1c4869c4e863cc2d3a93"
  license "Unlicense"

  bottle do
    root_url "https://github.com/afrossard/homebrew-tap/releases/download/agent-runtime-5.0.1"
    sha256 cellar: :any_skip_relocation, all: "bd7272b0bce80435d378611d0c5d788d24c1b132aa025d074f8a719b84f6bba2"
  end

  def install
    libexec.install "scripts/launch-agent-runtime"
    libexec.install "scripts/cleanup-agent-sessions"
    (libexec/"lib").install "scripts/lib/agent-runtime.sh"
    bin.write_exec_script libexec/"launch-agent-runtime"
    bin.write_exec_script libexec/"cleanup-agent-sessions"
  end

  test do
    system "#{bin}/launch-agent-runtime", "--help"
    system "#{bin}/cleanup-agent-sessions", "--help"
  end
end
