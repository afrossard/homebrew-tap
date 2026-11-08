class ActualBudgetTransformer < Formula
  desc "Launcher for the bank statement import CLI (afrossard/actual-budget-transformer)"
  homepage "https://github.com/afrossard/actual-budget-transformer"
  url "https://github.com/afrossard/actual-budget-transformer/archive/refs/tags/0.5.0.tar.gz"
  sha256 "612d0f4a9e4ab1e2e0670556c7a022dd1f9711b5be8e8fdb420fbe4d247719ee"
  license "Unlicense"

  bottle do
    root_url "https://github.com/afrossard/homebrew-tap/releases/download/actual-budget-transformer-0.4.0"
    sha256 cellar: :any_skip_relocation, all: "404bfb4af82f697e9cd7039e9725598059077be17c4edfe4379b5626f9c8da17"
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
