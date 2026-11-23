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
- **Renovate's formula bumps publish automatically, every other PR by hand.**
  When the bottle build on a Renovate formula PR succeeds, the publish job runs on its own and merges the PR, so bumps still land with no one stepping in.
  Renovate's own automerge is turned off for the two formula bumps, so only the publish job merges them.
  Any other PR is published by dispatching the job with the PR number and the head commit that was reviewed, so a head that moved after review is never published.
- **Host bottles on GHCR, not GitHub Releases.**
  `pr-upload` refuses an image tag that already exists, so a second publish of the same version fails instead of replacing the bottle `main` uses.
  A deliberate rebuild gets a new `rebuild` number and so a new tag.
  GHCR also sits outside ADR 0001's tag ruleset.
- **Never overwrite a published bottle.**
  No `--clobber`, `--keep-old` or `--warn-on-upload-failure` on the publish path.
- **Build on Linux x86_64 and Linux arm64 only.**
  Our formulas only install shell scripts, so their bottles are byte-identical on every platform, and two Linux builds are enough for `brew bottle --merge` to write an `all:` bottle.
- **A required `published-bottle` check replaces `stale-bottle`.**
  It runs `brew fetch` on every formula and fails unless the formula has an `all:` bottle whose published file matches its `sha256`, so it checks what `brew install` actually gets.
  A formula whose builds stop being identical has no `all:` bottle, so this check turns red instead of a platform-specific bottle reaching users.

## Considered options

- **Stock `brew tap-new` workflows (`brew pr-pull`):** rejected, because `pr-pull` pushes the formula and bottle commit straight onto `main`.
  That needs either an "always" ruleset bypass for the App, which ADR 0001 rejected, or a personal access token.
  Every tap surveyed that uses it has no PR requirement on its default branch.
- **Publish only after merge, from `main`:** rejected, because `main` would briefly reference a version with no bottle, and the bottle commit would need its own PR.
- **Keep publishing on every PR push, with a unique asset name per build:** rejected, because no surveyed tap does it, and it would be our own convention for a problem Homebrew's tooling already solves.
- **Keep GitHub Releases as the host:** rejected, because it departs from the flow we are copying, and its `<name>-<version>` tags overlap with ADR 0001's tag ruleset.
  `pr-upload` would still refuse a duplicate asset on a published release.
- **Building on macOS as well, like the stock `tests.yml`:** rejected, because unattended bumps would then wait on GitHub's macOS runners, and on 2026-11-23 a macOS arm64 job was cancelled after 15 minutes with "The job was not acquired by Runner of type hosted even after multiple attempts".
  A macOS build adds nothing to an identical bottle; what it would add is `brew test` on macOS, which the old flow never ran either.

## Consequences

- Each formula's `root_url` moves to `https://ghcr.io/v2/afrossard/tap`, and the current 5.2.0 and 0.5.0 bottles have to be republished there once.
- GitHub's docs say a new package starts private, but in the scratch tap both packages that the publish job created were public straight away, and `brew fetch` pulled them with no credentials.
  If a new formula's package does start private, `published-bottle` stays red until it is made public in the package settings, which cannot be undone.
- Users need Homebrew 7.0.14 (2026-11-16) or later.
  `brew bottle --merge` writes `manifest_sha256` into every bottle block since [Homebrew/brew#24603](https://github.com/Homebrew/brew/pull/24603), and older versions cannot load the formula at all; a macOS runner on Homebrew 6.0.18 failed this way in the scratch tap.
- The publish job needs `packages: write` on top of the App token it uses to push.
- Auto-merge must be allowed in the tap's repo settings, which ADR 0001's merge settings did not include.
- The publish job waits until GitHub reports the pushed bottle commit as the PR's head before turning on auto-merge, as homebrew-core does; without that wait the merge request failed with "expected head oid does not match the current head oid".
- GitHub holds CI on the App's push for approval while the App counts as a first-time contributor to the repo.
  The tap is past that, but the scratch tap needed it on every push, because a squash merge credits the PR author rather than the App.
- A squash merge's body still gets a `Co-authored-by` trailer for the App, although ADR 0001 sets the body to blank.
- `--clobber`, the release-tag naming and the replace-in-place rebuild path in `build-and-publish-bottle.sh` and the README go away.
- `brew test-bot --only-formulae --only-json-tab` replaces our own build script and its `all:` relabelling.
  On 2026-11-22, in the scratch tap `afrossard/homebrew-scratch`, both formulas built byte-identical bottles on macOS arm64 and Intel and on Linux x86_64 and arm64, and `brew bottle --merge` wrote an `all:` tag by itself.
  Without `--only-json-tab`, even the two Linux builds differed, because the tarball then carries the install receipt; Homebrew's own source says "Without --only-json-tab bottles are never reproducible".
- `--only-json-tab` ties us to GHCR.
  The receipt then lives only in the bottle's JSON, `pr-upload` stores it in the GHCR manifest's `sh.brew.tab` annotation, and `brew install` reads it back from there, which a GitHub Release asset has no place for.

## Tested in the scratch tap

On 2026-11-23, `afrossard/homebrew-scratch` ran this flow under a copy of the tap's `main` ruleset, with workflows that are the starting point for the tap's.

| Test | Result |
|---|---|
| Publish by dispatch (scratch #3) | Bottles uploaded to GHCR, bottle commit pushed by the App, PR squash-merged by auto-merge once checks passed on that commit |
| Automatic publish (scratch #5) | Published and merged with no one stepping in |
| Two PRs bumping to the same version (scratch #4 and #5) | The second publish failed with `agent-runtime:5.2.0 already exists!`, and GHCR and `main` were unchanged |
| `published-bottle` | Red before publishing, green after |
| `brew install` on Linux x86_64 and arm64 and macOS arm64 | Poured the `all:` bottle, `poured_from_bottle=true` |
| `brew install` on a macOS runner with Homebrew 6.0.18 | Could not load the formula, see the Homebrew 7.0.14 consequence above |

## Considered triggers for the publish job

- **Always manual, as in the stock `brew tap-new` workflow:** rejected, because every Renovate bump would then wait for the maintainer, against ADR 0001's automerged bumps.
- **A schedule that publishes every ready PR, like homebrew-core's `brew pr-automerge --publish`:** rejected, because it adds up to one interval of delay and more machinery than two formulas need.
