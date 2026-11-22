---
status: accepted
---

# Publish bottles once, from the PR, the way homebrew-core does

`bottle.yml` uploads a bottle on every push to a PR branch, to a GitHub Release asset named only after the formula and version, with `gh release upload --clobber`.
In [issue #36](https://github.com/afrossard/homebrew-tap/issues/36), two PRs bumped `agent-runtime` to 5.1.1, the second upload replaced the first, and `main` pinned a sha256 that no longer existed.
We copy homebrew-core's flow and host bottles on GHCR, because it is Homebrew's own production flow, it never overwrites a published bottle, and it keeps the PR-only `main` that [ADR 0001](0001-protect-the-tap-and-its-source-repos.md) requires.
The survey behind this is in [`docs/research/third-party-tap-bottles.md`](../research/third-party-tap-bottles.md).

## Decision

- **Build on the PR, keep the bottle as a workflow artifact.**
  PR CI builds the bottle and publishes nothing, so pushes, force-pushes and closed PRs never touch a published bottle.
- **Publish once, when the PR is about to merge.**
  One publish job uploads the PR's bottle artifact with Homebrew's `brew pr-upload`, pushes the bottle commit onto the PR branch with the GitHub App, and merges the PR with `gh pr merge --squash --match-head-commit`.
  This is the sequence in homebrew-core's `publish-commit-bottles.yml`, with squash instead of merge commits because ADR 0001 allows only squash.
- **Host bottles on GHCR, not GitHub Releases.**
  `pr-upload` refuses an image tag that already exists, so a second publish of the same version fails instead of replacing the bottle `main` uses.
  A deliberate rebuild gets a new `rebuild` number and so a new tag.
  GHCR also sits outside ADR 0001's tag ruleset.
- **Never overwrite a published bottle.**
  No `--clobber`, `--keep-old` or `--warn-on-upload-failure` on the publish path.

## Considered options

- **Stock `brew tap-new` workflows (`brew pr-pull`):** rejected, because `pr-pull` pushes the formula and bottle commit straight onto `main`.
  That needs either an "always" ruleset bypass for the App, which ADR 0001 rejected, or a personal access token.
  Every tap surveyed that uses it has no PR requirement on its default branch.
- **Publish only after merge, from `main`:** rejected, because `main` would briefly reference a version with no bottle, and the bottle commit would need its own PR.
- **Keep publishing on every PR push, with a unique asset name per build:** rejected, because no surveyed tap does it, and it would be our own convention for a problem Homebrew's tooling already solves.
- **Keep GitHub Releases as the host:** rejected, because it departs from the flow we are copying, and its `<name>-<version>` tags overlap with ADR 0001's tag ruleset.
  `pr-upload` would still refuse a duplicate asset on a published release.

## Consequences

- Each formula's `root_url` moves to `https://ghcr.io/v2/afrossard/tap`, and the current 5.2.0 and 0.5.0 bottles have to be republished there once.
- The GHCR package has to be made public after its first push, or `brew install` cannot pull the bottle anonymously.
- The publish job needs `packages: write` on top of the App token it uses to push.
- `--clobber`, the release-tag naming and the replace-in-place rebuild path in `build-and-publish-bottle.sh` and the README go away.
- Whether `brew test-bot` alone can produce our `all:` bottles, or our own build step stays, is still to be tested in a scratch repo.
- What triggers the publish job, and how it relates to Renovate's automerge, is still to be decided.
