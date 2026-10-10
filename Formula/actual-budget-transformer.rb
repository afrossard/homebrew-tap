class ActualBudgetTransformer < Formula
  desc "Launcher for the bank statement import CLI (afrossard/actual-budget-transformer)"
  homepage "https://github.com/afrossard/actual-budget-transformer"
  url "https://github.com/afrossard/actual-budget-transformer/archive/refs/tags/0.2.2.tar.gz"
  sha256 "dccb7c102717361fc22faa7c5b9c5a3266554fc32731f1d551a2ea9b01a25664"
  license "Unlicense"

  bottle do
    root_url "https://github.com/afrossard/homebrew-tap/releases/download/actual-budget-transformer-0.1.0"
    sha256 cellar: :any_skip_relocation, all: "705cc0d6581ff371421b65b3411c9da86c98df09a5322c91325775c00586044b"
  end

  def install
    bin.install "scripts/abt-import"
  end

  # Not a dependency: msb may already be installed by its own installer, and a
  # second copy from brew would shadow or be shadowed by it.
  def caveats
    <<~EOS
      abt-import runs the CLI's image under msb, which this formula does not install.
      If `msb` is not on your PATH yet, install it with either of:
        brew install superradcompany/tap/microsandbox
        curl -fsSL https://install.microsandbox.dev | sh
    EOS
  end

  test do
    # A stub msb that records its arguments: the real one needs a hypervisor.
    (testpath/"msb").write <<~SH
      #!/bin/sh
      printf '%s\\n' "$@" > "#{testpath}/msb-args"
    SH
    chmod 0755, testpath/"msb"
    ENV.prepend_path "PATH", testpath

    system bin/"abt-import", "--help"
    args = (testpath/"msb-args").read
    assert_match "ghcr.io/afrossard/actual-budget-transformer:#{version}\n", args
    assert_match "--help\n", args
  end
end
