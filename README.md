# homebrew-tap

Personal Homebrew tap.
This repo carries no code of its own - each formula installs a release tarball from its source repo.

## Formulae

- **container-base**: the `launch-agent-runtime` launcher and `cleanup-agent-sessions` cleanup script from [afrossard/container-base](https://github.com/afrossard/container-base).

```
brew install afrossard/tap/container-base
```

`brew upgrade` picks up new releases automatically - Renovate's `homebrew` manager bumps this tap's formula whenever the source repo tags a new version, by downloading the new release tarball and recomputing its checksum.
No CI job or cross-repo credential is involved; it runs entirely as a Renovate PR against this repo.
