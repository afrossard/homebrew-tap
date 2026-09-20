class ContainerBase < Formula
  desc "Agent runtime launcher and cleanup script for afrossard/container-base"
  homepage "https://github.com/afrossard/container-base"
  url "https://github.com/afrossard/container-base/archive/refs/tags/2.1.2.tar.gz"
  sha256 "d2e659d64fb38de2f1b363d45faf269bfb3309d1e779623cd67e1fbd67e28cc0"
  license "Unlicense"

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
