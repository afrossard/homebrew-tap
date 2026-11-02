class AgentRuntime < Formula
  desc "Launcher and cleanup script for the agent runtime (afrossard/container-base)"
  homepage "https://github.com/afrossard/container-base"
  url "https://github.com/afrossard/container-base/archive/refs/tags/5.0.0.tar.gz"
  sha256 "07372118ad2c8cae4795a01d86d010c75d6b61b223c6f537cb54b54ffa6287cc"
  license "Unlicense"

  bottle do
    root_url "https://github.com/afrossard/homebrew-tap/releases/download/agent-runtime-5.0.0"
    sha256 cellar: :any_skip_relocation, all: "c90a26c2462fedb5b595b986d18bba20dc151b708b2e017c7f130d75626f3c64"
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
