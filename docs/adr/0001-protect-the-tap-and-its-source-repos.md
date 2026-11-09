---
status: accepted
---

# Protect the tap and its two source repos with rulesets and required checks

A commit on `main` of this tap executes on users' machines through `brew install`, and `container-base` and `actual-budget-transformer` feed it through automerged Renovate bumps ([issue #2](https://github.com/afrossard/homebrew-tap/issues/2)).
We protect all three repos with a default branch ruleset that has no bypass actors, a tag ruleset, squash-only merges and per-repo required checks.
We deliberately keep zero required approvals and keep Renovate automerge for the two formula bumps, because this is a single-maintainer tap.

## Decision

- **Default branch ruleset, all three repos:** block deletion and non-fast-forward updates, require a pull request with 0 approvals and `allowed_merge_methods` of squash only, and require status checks, with `bypass_actors` empty.
- **Tag ruleset, all three repos:** on all tags, block deletion and updates, with `bypass_actors` empty.
- **Repo merge settings, all three repos:** only squash enabled, with the commit title from the PR title and the body from the PR body.
- **Stale bottles become a required check.**
  A job named `stale-bottle` in `test.yml` with no path filter fails when `formulas-needing-bottle.sh` prints anything, and `bottle.yml` stops committing to `main`.
- **Required checks per repo:**
  - `homebrew-tap`: `bats`, `stale-bottle`, `tap-syntax`, `zizmor` and `pr-title-lint`.
  - `container-base`: `format`, `scripts`, `host-scripts`, `pr-title-lint` and `zizmor`.
  - `actual-budget-transformer`: `pr-title-lint`, `typescript`, `node-follows-actual`, `container` and `zizmor`.
  - Path-filtered jobs cannot be required, because they stay pending forever on PRs they skip.
    That excludes `bottle`, `agent-image` and `dev-image`.
- **Scanners:** zizmor at `min-severity: high` on all three repos, and a `tap-syntax` job running `brew test-bot --only-tap-syntax` on the tap.
  zizmor's 4 high findings in `bottle.yml` must be fixed before `zizmor` becomes required.
- **Pin `Homebrew/actions/setup-homebrew` to a hash** and keep it current with the Renovate config below.
- **Enable `sha_pinning_required` on all three repos, after that pin lands.**
  GitHub then enforces the hash-pinning rule at job setup, and pinned `setup-homebrew` still runs under it.
  That pin is the only unpinned action reference across the three repos, but actions nested inside third-party composite actions were not tested.

The custom manager is needed because Renovate's `github-actions` manager truncates the action's four-part tags, so `2026.10.26.1` reads as `2026.10.26` and no update is proposed.

```json
{
  "customManagers": [
    {
      "customType": "regex",
      "managerFilePatterns": ["/^\\.github/workflows/.+\\.ya?ml$/"],
      "matchStrings": ["uses: Homebrew/actions/setup-homebrew@(?<currentDigest>[a-f0-9]{40}) # (?<currentValue>\\S+)"],
      "depNameTemplate": "Homebrew/actions",
      "datasourceTemplate": "github-tags",
      "versioningTemplate": "regex:^(?<major>\\d+)\\.(?<minor>\\d+)\\.(?<patch>\\d+)\\.(?<build>\\d+)$"
    }
  ],
  "packageRules": [
    { "matchManagers": ["github-actions"], "matchPackageNames": ["Homebrew/actions"], "enabled": false }
  ]
}
```

## Considered options

- **Turning off "Allow GitHub Actions to create and approve pull requests" on `container-base` and `actual-budget-transformer`:** rejected, because release-please opens the release PRs there with `GITHUB_TOKEN`.
  GitHub documents that this setting also blocks PR creation, although that was not tested here.
  With 0 required approvals, an approval from Actions grants nothing, so turning it off would cost releases and gain no protection.
- **`brew audit --strict`:** rejected, because it adds a way to block merges without a demonstrated benefit.
  `tap-syntax` runs `brew audit` without `--strict`, and it already fails on a formula with no `sha256`.
  Strict mode passes on both formulas today but was not shown to catch anything further, and a new strict rule from Homebrew could block automerged formula bumps.
- **One or more required approvals:** rejected, because the sole maintainer could then never merge.
  GitHub refuses to let an author approve their own PR, and `gh pr merge --admin` is rejected as well.
- **GitHub App as a bypass actor:** rejected, because a stolen App key could write to `main`.
- **A fix PR opened by the workflow for stale bottles:** rejected, because the App would need `pull_requests: write` and stale bottles could still reach users.
- **Manual merges of formula bumps:** rejected, because a bottle diff is only a hash and a URL, so review adds little.
- **Required signed commits:** rejected, because the rule adds nothing here.
  A squash of unsigned commits merged under the rule, and the resulting commit is signed by GitHub anyway.
- **Immutable releases:** rejected, because they break the rebuild path.
  `gh release upload --clobber` and adding a new asset are both refused on a published immutable release, and a bottle rebuilt for the same version needs to replace its asset.
  They would not stop removal either, since an immutable release can still be deleted, although its tag cannot then be reused for a new release.

## What each layer is worth

Enforced, and tested for the owner's own login:

- Pull requests only on `main`, with no force-push.
- Green required checks before merge.
- No moving or deleting tags.
- Squash as the only merge method.

Ceremony on a single-maintainer repo:

- Required approvals, which only lock the maintainer out.
- Required signed commits.

Formula integrity is already good.
Every `url` and every bottle in both formulas has a `sha256`, and `tap-syntax` fails a formula whose `sha256` is removed.

Workflow token permissions are already narrow.
All three repos default `GITHUB_TOKEN` to read, and `bottle.yml` is the only workflow here with `contents: write`.

Account security stays the owner's job, because no repo setting replaces it.
The owner should use a hardware key or passkey for 2FA, and fine-grained tokens limited to one repo wherever a tool allows it.
The `gh` login used for this work holds the classic `repo` and `workflow` scopes across every repo, which is the widest credential involved.

Established tools adopted:

- Repository rulesets are GitHub's own mechanism.
- `brew test-bot` is Homebrew's own CI tool, so it is the standard for a tap.
- zizmor and Renovate are popular rather than formal standards.

OpenSSF Scorecard and SLSA were not evaluated.

## Consequences

- **A `workflow_dispatch` rebuild can no longer target `main`** and has to run on a PR branch.
- **Rulesets with zero approvals do not stop account compromise.**
  A stolen maintainer credential can open and merge its own PR.
  A stolen admin credential can also delete the rulesets, so they only hold while they exist.
  Tokens without Administration access cannot bypass them.
- **`stale-bottle` only proves the bottle's `root_url` matches the formula's version.**
  A one-line edit turns it green with no bottle built, so it catches forgotten rebuilds rather than a dishonest commit.
- **Automerge leaves two unreviewed paths to users.**
  A compromised source repo's new tag flows through Renovate to `brew upgrade`.
  A stolen bottler App key could add a commit to an open Renovate branch, because `gitIgnoredAuthors` makes Renovate disregard that author's commits.
  The Renovate automerge test merged a branch carrying a commit from such an ignored author, although that commit used a placeholder author rather than a real App key.
- **The tag ruleset does not protect releases.**
  `gh release delete` removes a release and its bottle assets while the tag survives.
  That breaks installs from the bottle but cannot substitute content, because the formula pins the bottle's `sha256`.
- **The formula `sha256` does not cover what `launch-agent-runtime` and `abt-import` run.**
  Both pull GHCR images by version tag rather than digest, so a moved image tag reaches users unchecked.

## Test results

Tested on 2026-11-08 on the public repo `afrossard/homebrew-scratch`, as the repo owner, with the configuration above and copies of the tap's formulas and stale-bottle script.
Immutable releases, required signed commits and required approvals are covered under Considered options.

| Test | Result |
|---|---|
| Direct push to `main` | Rejected, `GH013` |
| Force-push to `main` | Rejected, "Cannot force-push to this branch" |
| Delete `main` | Refused by GitHub's own default branch rule, so the ruleset's deletion rule was not exercised |
| Merge commit or rebase by API | Rejected, HTTP 405 |
| Merge a PR with a red required check | Rejected, including with `gh pr merge --admin` |
| Squash merge | Allowed, with title and body from the PR and a verified GitHub signature |
| Docs PR with bottles current | `stale-bottle` green |
| Version bump, then a `root_url` edit | Red and blocked, then green and mergeable |
| Create a new tag and a release | Allowed |
| Delete a tag by git or API | Rejected |
| Move a tag to a descendant commit by git or API | Rejected |
| `gh release upload --clobber` | Allowed, tag unmoved |
| `gh release delete --cleanup-tag` | Release deleted, tag kept |
| `brew test-bot --only-tap-syntax` | Runs style, readall and audit across the tap, and fails on a formula with no `sha256` |
| `brew audit --strict` | Passes on both formulas |
| zizmor action v0.8.1 at `min-severity: high` | Passes on the pinned workflow, fails on injected high findings |
| Renovate automerge under the ruleset | Stayed blocked while red, then `app/renovate` squashed it once green |
| Renovate maintains the `setup-homebrew` pin | Opened a real PR updating both the hash and the four-part tag |
| Repo setting `sha_pinning_required` | An unpinned action fails at job setup, and pinned `setup-homebrew` still runs |

Not tested:

- The real `bottle.yml` and its GitHub App push under the rulesets.
- Whether the 3 template injections zizmor reports in `bottle.yml` are reachable.
- `pr-title-lint` on the tap.
- release-please in `container-base` after the move to squash, and release PRs under required checks in the two source repos.
- Account 2FA and hardware keys, which the owner needs to confirm.

## State before this was applied

Read from the real repos on 2026-11-08.

| Setting | `homebrew-tap` | `container-base` | `actual-budget-transformer` |
|---|---|---|---|
| Rulesets | none | `main` | `main` |
| Classic branch protection | none | none | none |
| Merge methods | all three | all three | squash only |
| Allowed actions | all | all | all |
| `sha_pinning_required` | false | false | false |
| Default `GITHUB_TOKEN` | read | read | read |
| Actions can approve PRs | no | yes | yes |
| Fork PR approval | first-time contributors | first-time contributors | first-time contributors |
| Secret scanning and push protection | on | on | on |
