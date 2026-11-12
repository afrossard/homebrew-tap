class AgentRuntime < Formula
  desc "Launcher and cleanup script for the agent runtime (afrossard/container-base)"
  homepage "https://github.com/afrossard/container-base"
  url "https://github.com/afrossard/container-base/archive/refs/tags/5.1.0.tar.gz"
  sha256 "2e893b684b37968555b00bb3983a7a5ca19f56081789a5ebf5d9275888b25c91"
  license "Unlicense"

  bottle do
    root_url "https://github.com/afrossard/homebrew-tap/releases/download/agent-runtime-5.1.0"
    sha256 cellar: :any_skip_relocation, all: "b73272296f2249cefceef1b4db49e77012c0142264adf7c96f9eb5f48e78e4d3"
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
