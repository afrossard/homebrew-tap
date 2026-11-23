# homebrew-tap

Personal Homebrew tap.
This repo carries no code of its own; each formula installs a release tarball from its source repo.

## Formulae

- **agent-runtime**: the `launch-agent-runtime` launcher and `cleanup-agent-sessions` cleanup script from [afrossard/container-base](https://github.com/afrossard/container-base).

```sh
brew install afrossard/tap/agent-runtime
```

- **actual-budget-transformer**: the `abt-import` launcher from [afrossard/actual-budget-transformer](https://github.com/afrossard/actual-budget-transformer), which runs that release's import CLI image under [msb](https://github.com/superradcompany/microsandbox).
  msb is not a dependency, because it may already be installed by its own `curl` installer; the formula's caveats say how to get it.

```sh
brew install afrossard/tap/actual-budget-transformer
```

`brew upgrade` picks up new releases automatically.
Renovate's `homebrew` manager bumps each formula whenever its source repo tags a new version, by downloading the new release tarball and recomputing its checksum.
No CI job or cross-repo credential is involved in that bump; it runs entirely as a Renovate PR against this repo.

## Bottle

Every formula here ships a platform-independent (`all:`) bottle, hosted on the [GitHub Container Registry](https://github.com/afrossard?tab=packages&repo_name=homebrew-tap) like homebrew-core's.
A formula's `install` block only copies scripts; none compiles anything.
Without a bottle, though, Homebrew still refuses to install on Linux unless a `gcc`/`cc` binary is on `PATH`.
Its `DevelopmentTools.installed?` check fires whenever no bottle can be poured, with no flag or DSL directive to bypass it (confirmed upstream as intentional in [Homebrew/brew#23252](https://github.com/Homebrew/brew/issues/23252)).
The bottle removes that compiler requirement entirely.
`brew install` pours a prebuilt tarball instead of building from source, so it works on any machine regardless of what's on `PATH`.
See [issue #3](../../issues/3) for the full investigation.

Installing needs Homebrew 7.0.14 or later, because the bottle blocks carry `manifest_sha256`, which older versions cannot load.
`brew install` updates Homebrew first unless auto-update is turned off.

### How bottles are published

The flow copies homebrew-core's, with Homebrew's own `brew test-bot` and `brew pr-upload` ([ADR 0002](docs/adr/0002-publish-bottles-like-homebrew-core.md)):

1. [`Build bottles`](.github/workflows/build-bottles.yml) builds every changed formula on each PR, on Linux x86_64 and arm64, and keeps the bottles as workflow artifacts.
   Nothing is published from a PR branch, so pushes, force-pushes and closed PRs never touch a published bottle.
2. [`Publish bottles`](.github/workflows/publish-bottles.yml) uploads them once, when the PR is ready to merge.
   It merges the two builds into one `all:` bottle, uploads it to GHCR, pushes the bottle commit onto the PR branch as a GitHub App, and turns on squash auto-merge pinned to that commit.
3. The PR merges once every required check has passed on the bottle commit.

For Renovate's PRs, `Build bottles` runs step 2 itself as soon as both builds pass, so formula bumps still land with no one stepping in.
Renovate's PRs that change no formula build no bottles, so `Publish bottles` leaves them alone.

Any other PR that changes a formula is published by running `Publish bottles` by hand with the PR number and the head commit you reviewed.
It refuses a PR whose head has moved since.
Running it on a PR that changes no formula, or whose head is already the bottle commit, only merges it.

The required `published-bottle` check fetches every formula's bottle the way `brew install` does and fails unless the downloaded file matches the formula's `sha256`.
It is red on a formula PR until its bottle is published, and on any PR if a published bottle ever stops matching.

GHCR refuses to replace a bottle that already exists, so two PRs that bump a formula to the same version cannot overwrite each other's bottle ([issue #36](../../issues/36)): the second one's publish fails instead.
Any change to a formula rebuilds its bottle; without a version change, the new bottle gets the next `rebuild` number and so its own tag.

A publish also fails with "already exists" when a PR branch is force-pushed after its bottle was published but before it merged, for example by a Renovate rebase.
The tag it collides with is never one `main` uses, because each publish takes the next version or `rebuild` number after `main`'s.
When the colliding tag came from this same PR's earlier publish, delete that package version in the package's settings on GitHub, then run `Publish bottles` again.
When it came from another open PR, that is the #36 race, and the PR that lost should be closed instead.

A new formula's first publish creates its package on GHCR.
Packages published this way have come out public, but if one does not, `published-bottle` stays red until it is made public in the package's settings.
