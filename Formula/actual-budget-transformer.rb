class ActualBudgetTransformer < Formula
  desc "Launcher for the bank statement import CLI (afrossard/actual-budget-transformer)"
  homepage "https://github.com/afrossard/actual-budget-transformer"
  url "https://github.com/afrossard/actual-budget-transformer/archive/refs/tags/0.1.0.tar.gz"
  sha256 "0a54237d2df94def1ff11daea64f0afd207beef3a422f2c5b8cdc17d43b6dc2a"
  license "Unlicense"

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
