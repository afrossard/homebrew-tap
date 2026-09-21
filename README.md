# homebrew-tap

Personal Homebrew tap.
This repo carries no code of its own; each formula installs a release tarball from its source repo.

## Formulae

- **agent-runtime**: the `launch-agent-runtime` launcher and `cleanup-agent-sessions` cleanup script from [afrossard/container-base](https://github.com/afrossard/container-base).

```
brew install afrossard/tap/agent-runtime
```

`brew upgrade` picks up new releases automatically.
Renovate's `homebrew` manager bumps this tap's formula whenever the source repo tags a new version, by downloading the new release tarball and recomputing its checksum.
No CI job or cross-repo credential is involved in that bump; it runs entirely as a Renovate PR against this repo.

## Bottle

`agent-runtime` ships a platform-independent (`all:`) bottle, hosted as a [GitHub Release](../../releases) asset on this repo.
The formula's `install` block only copies two bash scripts and a shared lib into `libexec`; it never compiles anything.
Without a bottle, though, Homebrew still refuses to install on Linux unless a `gcc`/`cc` binary is on `PATH`.
Its `DevelopmentTools.installed?` check fires whenever no bottle can be poured, with no flag or DSL directive to bypass it (confirmed upstream as intentional in [Homebrew/brew#23252](https://github.com/Homebrew/brew/issues/23252)).
The bottle removes that compiler requirement entirely.
`brew install afrossard/tap/agent-runtime` pours a prebuilt tarball instead of building from source, so it works on any machine regardless of what's on `PATH`.
See [issue #3](../../issues/3) for the full investigation.

### Rebuild automation

Renovate's version bump alone leaves the formula without a matching bottle, since Renovate only rewrites the source `url`/`sha256`.
The [`Bottle formula`](.github/workflows/bottle.yml) workflow closes that gap automatically:

1. Renovate opens its usual same-repo PR bumping `Formula/agent-runtime.rb`'s `url`/`sha256` to a new container-base release.
2. That PR triggers the workflow, which sees the formula has no bottle for its new version, builds a fresh `all:` bottle with Homebrew's own `brew bottle` tooling, and publishes the tarball to a GitHub Release in this repo.
3. The workflow commits the updated bottle block back onto the same PR branch, so the single Renovate PR carries both the version bump and its matching bottle.
4. Merging that one PR is the only manual step. No separate bottle PR and no cross-repo credential is needed, since the PR branch already lives in this repo.

The workflow rebuilds a formula only when the bottle committed next to it is stale, meaning its `bottle do` block's `root_url` no longer points at the release tag for the formula's current version.
That is deliberately a question about the state the formula is in, not about what a commit or a branch changed: step 3 pushes onto the branch the workflow is running on, so the workflow always runs again on its own bottle commit and has to recognise its own work.
Nothing downstream can catch a wrong answer there.
Brew stamps the tap's own git HEAD into every keg it builds, so the rebuild that follows a bottle commit bakes in that commit and yields a different tarball every time; it can never settle by reproducing the bottle already committed.
`workflow_dispatch` rebuilds a formula's bottle on demand, which is also how to force one when a source changed without the version changing.
