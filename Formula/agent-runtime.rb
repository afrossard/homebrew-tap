class AgentRuntime < Formula
  desc "Launcher and cleanup script for the agent runtime (afrossard/container-base)"
  homepage "https://github.com/afrossard/container-base"
  url "https://github.com/afrossard/container-base/archive/refs/tags/4.0.4.tar.gz"
  sha256 "f93cf1a69b97b7a7d2ae941d2a721653e3368655bef3746ed1161a733cf1e8b2"
  license "Unlicense"

  bottle do
    root_url "https://github.com/afrossard/homebrew-tap/releases/download/agent-runtime-4.0.1"
    sha256 cellar: :any_skip_relocation, all: "4fc0105aa32722900b229b1fe1fe49c51ac94687b271f5dffbcd9db9abf4fce5"
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
