# homebrew-tap

Personal Homebrew tap.
This repo carries no code of its own - each formula installs a release tarball from its source repo.

## Formulae

- **agent-runtime**: the `launch-agent-runtime` launcher and `cleanup-agent-sessions` cleanup script from [afrossard/container-base](https://github.com/afrossard/container-base).

```
brew install afrossard/tap/agent-runtime
```

`brew upgrade` picks up new releases automatically - Renovate's `homebrew` manager bumps this tap's formula whenever the source repo tags a new version, by downloading the new release tarball and recomputing its checksum.
No CI job or cross-repo credential is involved in that bump; it runs entirely as a Renovate PR against this repo.

## Bottle

`agent-runtime` ships a platform-independent (`all:`) bottle, hosted as a [GitHub Release](../../releases) asset on this repo.
The formula's `install` block only copies two bash scripts and a shared lib into `libexec` - it never compiles anything.
Without a bottle, though, Homebrew still refuses to install on Linux unless a `gcc`/`cc` binary is on `PATH`: its `DevelopmentTools.installed?` check fires whenever no bottle can be poured, with no flag or DSL directive to bypass it (confirmed upstream as intentional in [Homebrew/brew#23252](https://github.com/Homebrew/brew/issues/23252)).
The bottle removes that compiler requirement entirely: `brew install afrossard/tap/agent-runtime` pours a prebuilt tarball instead of building from source, so it works on any machine regardless of what's on `PATH`.
See [issue #3](../../issues/3) for the full investigation.

### Rebuild automation

Renovate's version bump alone leaves the formula without a matching bottle, since Renovate only rewrites the source `url`/`sha256`.
The [`Bottle formula`](.github/workflows/bottle.yml) workflow closes that gap automatically:

1. Renovate opens its usual same-repo PR bumping `Formula/agent-runtime.rb`'s `url`/`sha256` to a new container-base release.
2. That PR triggers the workflow, which detects the source change, builds a fresh `all:` bottle with Homebrew's own `brew bottle` tooling, and publishes the tarball to a GitHub Release in this repo.
3. The workflow commits the updated bottle block back onto the same PR branch, so the single Renovate PR carries both the version bump and its matching bottle.
4. Merging that one PR is the only manual step - no separate bottle PR, and no cross-repo credential is needed, since the PR branch already lives in this repo.

The workflow only rebuilds when a formula's source actually changed (not on every PR that happens to touch `Formula/`), and can also be run by hand via `workflow_dispatch` to rebuild a formula's bottle on demand.
