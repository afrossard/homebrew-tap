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
  When both bottle builds on a Renovate PR pass, the build workflow calls the publish workflow, which publishes and merges the PR, so bumps still land with no one stepping in.
  A Renovate PR that changes no formula builds no bottles, and the publish workflow leaves it alone.
  Renovate's own automerge is turned off for the two formula bumps, so only the publish workflow merges them.
  Any other PR is published by dispatching the publish workflow with the PR number and the head commit that was reviewed, so a head that moved after review is never published.
- **No privileged triggers and no scanner exceptions.**
  The publish workflow is a reusable workflow, called from the build workflow's `pull_request` run or dispatched by hand, never started by `workflow_run` or `pull_request_target`.
  It takes the bottles from the build run's artifacts with `actions/download-artifact` instead of `brew pr-pull`, which only fetches artifacts from another run.
  The builds run on the runner itself rather than in Homebrew's unpinned `brew` container image, so zizmor at `min-severity: high` passes with no ignore comments.
- **Decide what to do from the PR's current state.**
  The publish workflow publishes when the build of the PR's head produced bottles, only merges when that head is already the App's bottle commit or a dispatched PR changes no formula, and otherwise does nothing.
  It never skips a publish because an existing bottle still matches, so a formula change without a version change still gets a bottle built from it, with the next `rebuild` number.
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
- `GITHUB_TOKEN` gets write access in two jobs only: `packages: write` in the job that uploads, and `contents` and `pull-requests: write` in the job that turns on auto-merge.
  This replaces ADR 0001's "`bottle.yml` is the only workflow here with `contents: write`"; the App still has Contents write and nothing more.
- ADR 0001's `stale-bottle` required check becomes `published-bottle`, and `test-bot (ubuntu-latest)` and `test-bot (ubuntu-24.04-arm)` join the required checks.
- A force-push to a PR after its bottle was published, such as a Renovate rebase, makes the next publish fail with "already exists", because the rebuilt bottle gets the same tag.
  That tag is never one `main` uses, so deleting its package version and publishing again recovers; the README says how.
- Auto-merge must be allowed in the tap's repo settings, which ADR 0001's merge settings did not include.
- The publish job waits until GitHub reports the pushed bottle commit as the PR's head before turning on auto-merge, as homebrew-core does; without that wait the merge request failed with "expected head oid does not match the current head oid".
- `setup-homebrew` must not get a `token` input in the publish workflow.
  It stores that token as a global git `extraheader`, so the bottle commit is then pushed as `GITHUB_TOKEN` whatever credentials the push URL carries.
  In the scratch tap that made GitHub hold the bottle commit's CI for approval, which an earlier version of this ADR blamed on the App being a first-time contributor; with `contents: read`, the push was refused outright as `github-actions[bot]`.
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
| Reusable publish workflow, formula PR from the automatic actor (scratch #10) | Built on both Linux runners without a container, published `5.2.0-1`, the App's push got ordinary CI with nothing held, and the PR merged |
| Same, but `setup-homebrew` given `token: github.token` (scratch #8) | Upload succeeded, then the push was refused as `github-actions[bot]` |
| README-only PR from the automatic actor (scratch #9) | No bottles built, and the publish workflow left it unmerged |
| Dispatching the publish workflow on that PR | `plan` chose merge only, and the PR merged |

## Considered triggers for the publish job

- **Always manual, as in the stock `brew tap-new` workflow:** rejected, because every Renovate bump would then wait for the maintainer, against ADR 0001's automerged bumps.
- **`workflow_run` on the build workflow:** rejected, because zizmor reports it as a high-severity dangerous trigger, and passing would need an ignore comment.
  Calling the publish workflow from the build workflow's own `pull_request` run gives the same result, since a same-repo PR's run already has the secrets.
- **A schedule that publishes every ready PR, like homebrew-core's `brew pr-automerge --publish`:** rejected, because it adds up to one interval of delay and more machinery than two formulas need.
