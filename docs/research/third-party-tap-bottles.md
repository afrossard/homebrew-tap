# How established third-party taps build and publish bottles

Research for [issue #36][i36], where two PRs bumped `agent-runtime` to 5.1.1, the second PR's `gh release upload --clobber` replaced the first PR's bottle, and `main` ended up pinning a sha256 that no longer existed.
Gathered on 2026-11-16 from the taps' own repositories, Homebrew/brew source at [`b63354c`][brew-main] (checked against the locally installed 7.0.12, which differs only in unrelated lines), docs.brew.sh and GitHub's docs.
Every link to a repository file is pinned to the commit that was read.

Statements marked **Inference** are my own reading, not something a source says.

## Terms used below

- **Bottle**: a prebuilt tarball of an installed formula, listed in the formula's `bottle do` block by `root_url` and one `sha256` per platform tag ([Bottles docs][doc-bottles-rooturl]).
- **`all:` bottle**: a single bottle tag that serves every platform. `brew bottle --merge` only writes it when every per-platform build in the merge has the same cellar and sha256 ([`bottle.rb`][src-bottle-all]).
- **`brew test-bot`**: Homebrew's CI command. On a PR it builds and tests the changed formulae and writes bottle tarballs plus JSON next to them ([BrewTestBot docs][doc-testbot]).
- **`brew pr-pull`**: downloads a PR's bottle artifacts from its CI run, puts the PR's commits on top of the local default branch (cherry-pick, unless `--no-cherry-pick`), and calls `pr-upload` ([`pr-pull.rb`][src-prpull]).
- **`brew pr-upload`**: runs `brew bottle --merge --write` to commit the bottle block, then uploads the tarballs to GitHub Releases or GitHub Packages, depending on `root_url` ([`pr-upload.rb`][src-prupload]).
- **GHCR / GitHub Packages**: GitHub's container registry. Homebrew stores bottles there as OCI images, the way homebrew-core does ([Bottles docs][doc-bottles-core]).
- **Pre-merge / post-merge publishing**: whether a bottle is uploaded somewhere public before or after the PR's formula change reaches the default branch.

## Summary

**What established taps do.**
Every tap surveyed that ships real bottles builds them in PR CI with `brew test-bot` and keeps them as workflow artifacts until a deliberate publish step.
None of them uploads a bottle on every push to a PR branch the way our `bottle.yml` does.
The publish step comes in two shapes:

1. **The stock `brew tap-new` shape** (osx-cross/avr, mas-cli, qmk, dunglas/frankenphp, gromgit/fuse): a maintainer triggers `brew pr-pull`, which uploads the bottles and pushes the formula change plus its bottle commit straight onto `main`, in place of a GitHub merge.
   All five still run the old `pr-pull` *label* trigger, which Homebrew replaced with a manual `workflow_dispatch` in June 2026 for security reasons ([Homebrew/brew#22815][pr22815]).
2. **The homebrew-core shape** (Homebrew/homebrew-core itself, chenrui333/tap, and with variations shivammathur/php): the publish step uploads to GHCR, pushes the bottle commit onto the *PR branch*, then merges the PR through GitHub with `gh pr merge --match-head-commit`.
   This works with a `main` that only accepts PRs.

Two other patterns exist: brewsci/bio publishes after merge from the PR's CI artifacts and then pushes the bottle commit to its branches, and osrf/simulation (Jenkins, S3) and aws/tap (the upstream project's release CI) publish from their own release pipelines.
HashiCorp's and MongoDB's taps ship no bottles at all, only formulae that download vendor binaries.

**How they avoid the #36 race.**
The Homebrew tooling never silently overwrites a published bottle.
`pr-upload` to GHCR aborts if the image tag already exists ([`github_packages.rb`][src-ghp-exists]), and `pr-upload` to GitHub Releases only replaces an asset on a *draft* release; on a published release, GitHub itself refuses a second asset with the same name ([`github_releases.rb`][src-ghr-draft], [GitHub REST docs][gh-asset-422]).
On top of that, publishing happens once per PR, at the moment it is about to land, and `brew bottle` gives a rebuild of an already-published version a new file name (`rebuild` counter) ([`bottle.rb`][src-bottle-rebuild]).
Our flow breaks both rules: it publishes on every PR push, and it uses `--clobber`.

**Which pattern fits our case (Inference).**
The homebrew-core shape fits best: it is Homebrew's own production flow, it keeps `main` PR-only with no bypass actor (matching [ADR 0001][adr1]), and it keeps "one Renovate PR carries the bump and its bottle".
Concretely, bottles would be built as artifacts on the PR, and a publish job would upload them with `pr-upload` (never `--clobber`) and push the bottle commit to the PR branch only when the PR is ready to merge, then merge it.
The stock `tap-new` shape would need either a ruleset bypass for the App, which ADR 0001 rejected, or a personal access token, and it would turn every Renovate bump into a manual dispatch.
The issue comment's description of the stock flow ("when a PR gets the `pr-pull` label") is out of date for Homebrew 7.

## Comparison table

| Tap | Bottles? | Workflow | Host | Release tag / name | Built | Published | Bottle commit reaches the default branch by | `all:`? | Publish trigger |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [osx-cross/homebrew-avr][avr-publish] | yes | stock tap-new (old label version) | GitHub Releases | `<name>-<version>`, e.g. [`avr-gcc@14-14.4.0`][avr-formula] | pre-merge (PR CI artifact) | at publish, before push | `pr-pull` direct push to `main` with a PAT | no, macOS per-platform | `pr-pull` label |
| [mas-cli/homebrew-tap][mas-publish] | yes | stock tap-new (old label version) | GitHub Releases | `mas-7.0.0` ([formula][mas-formula]) | pre-merge artifact | at publish | `pr-pull` direct push with `GITHUB_TOKEN` | no | `pr-pull` label |
| [qmk/homebrew-qmk][qmk-publish] | yes | stock tap-new (old label version) | GHCR `ghcr.io/v2/qmk/qmk` ([formula][qmk-formula]) | OCI tag `<version>` | pre-merge artifact | at publish | `pr-pull` direct push with `GITHUB_TOKEN` | no | `pr-pull` label |
| [dunglas/homebrew-frankenphp][fp-publish] | yes | stock tap-new (old label version) | GHCR ([formula][fp-formula]) | OCI tag | pre-merge artifact | at publish | `pr-pull` direct push with `GITHUB_TOKEN` | no (macOS + Linux tags) | `pr-pull` label |
| [gromgit/homebrew-fuse][fuse-publish] | yes | stock tap-new (old label version) | GHCR ([formula][fuse-formula]) | OCI tag | pre-merge artifact | at publish | `pr-pull` direct push with `GITHUB_TOKEN` | no | `pr-pull` label |
| [Homebrew/homebrew-core][core-publish] (reference) | yes | Homebrew's own | GHCR | OCI tag `<version>[-<rebuild>]` | pre-merge artifact | at publish, before merge | bottle commit pushed to PR branch, then `gh pr merge --auto --merge --match-head-commit` | yes when builds match | manual dispatch (or `brew pr-automerge --publish`) |
| [chenrui333/homebrew-tap][cr-publish] | yes | homebrew-core style | GHCR | OCI tag | pre-merge artifact | at publish, before merge | bottle commit pushed to PR branch, then [`gh pr merge --match-head-commit`][cr-merge] | yes, e.g. [`snip.rb`][cr-formula] | `pr-pull` label or dispatch, serialised |
| [shivammathur/homebrew-php][php-publish] | yes | custom around `pr-pull` | GHCR ([formula][php-formula]) | OCI tag | pre-merge artifact | at publish | `pr-pull --clean`, `gh pr merge --auto --rebase`, then `git-try-push` to `main` | no | [`pr-automerge --publish`][php-auto] on a schedule, for PRs labelled `build-complete` |
| [brewsci/homebrew-bio][bio-upload] | yes | custom around `pr-upload` | GHCR ([formula][bio-formula]) | OCI tag | pre-merge artifact | **post-merge** | direct push to `develop` and `master` by a bot PAT, falling back to a bot PR | no | push to `develop` (the PR merge) |
| [osrf/homebrew-simulation][osrf-wf] | yes | Jenkins ([release-tools][osrf-upload]) | S3 `osrf-distributions/bottles-simulation` ([formula][osrf-formula]) | flat directory, Homebrew file name | pre-merge (Jenkins) | pre-merge, `s3cmd put` | bot commit "update bottle" on the PR branch ([#3640][osrf-pr]), human merges | no | Jenkins job after the bump PR |
| [aws/homebrew-tap][aws-formula] (`cbmc-viewer`) | yes, 4 of 28 formulae | upstream release CI ([`release-brew.yaml`][cbmcv-wf]) | upstream repo's GitHub Release | the source release's own tag, `viewer-3.11.1` | pre-merge | pre-merge, once per upstream release | bot commit on the bump PR branch in a fork, human merges | no | upstream `release: created` |
| [hashicorp/homebrew-tap][hc-formula] | **no** | own scripts, `repository_dispatch` | vendor binaries | n/a | n/a | n/a | direct push | n/a | release dispatch |
| [mongodb/homebrew-brew][mdb-formula] | **no** | none for bottles | vendor binaries | n/a | n/a | n/a | n/a | n/a | n/a |

Taps checked and dropped: [messense/homebrew-macos-cross-toolchains][messense] has no `bottle do` block in any of its 12 formulae.
Five of the stock taps were found with [`gh search code "brew pr-pull" --filename publish.yml`][search-note]; most results of that search are small personal taps.

## Question 1: what each tap's workflow does

### The stock `brew tap-new` workflow, as Homebrew generates it today

- `brew tap-new` writes `tests.yml`, `publish.yml` and `autobump.yml` from templates in Homebrew/brew ([`tap-new.rb`][src-tapnew-render]).
- `tests.yml` runs `brew test-bot --only-formulae` on `pull_request` and uploads `*.bottle.*` as a workflow artifact named `bottles_<os>`, with a matrix of `macos-26` and `ubuntu-latest` ([template][tpl-tests]).
  Nothing is published from this workflow.
- `publish.yml` is **`workflow_dispatch` only**, with inputs `pull_request` (required) and `head_sha` (optional); it runs `brew pr-pull --tap=$GITHUB_REPOSITORY [--head-sha=…] <PR>`, attests the tarballs, and pushes with `Homebrew/actions/git-try-push` to the default branch ([template][tpl-publish]).
  This confirms the local 7.0.12 observation.
- Unless `--github-packages` is passed, `test-bot` sets the root URL of a non-core tap's bottle to `<tap remote>/releases/download/<formula name>-<pkg_version>` ([`test_bot/formulae.rb`][src-testbot-rooturl]).
  This confirms the local observation, and it is the same tag scheme our tap uses.
- `brew tap-new --github-packages` instead sets `root_url` to GHCR ([`tap-new.rb`][src-tapnew-ghp]).
- The docs tell the maintainer to review the PR, check that CI passed, then run `brew pr-pull --head-sha=<reviewed sha> <PR>` locally or dispatch the workflow; with `--head-sha`, `pr-pull` fails rather than publish a head that moved after review ([How to Create and Maintain a Tap][doc-tap]).
- `pr-pull` amends the last commit with a `Closes #<PR>.` line ([`pr-pull.rb`][src-prpull-closes]), so GitHub shows the PR as closed rather than merged; osx-cross records exactly this ("successfully published PRs can show as **closed, not merged**") in [osx-cross/homebrew-avr#413][avr-413].

### History of the label trigger

- The label-triggered `publish.yml` (`on: pull_request_target: types: [labeled]`, gated on the `pr-pull` label) was introduced by [`843dffe`][c-843dffe] in [Homebrew/brew#8762][pr8762] (merged 2020-10-03), together with `tap-new --pull-label`.
- [`ac1b5e0`][c-ac1b5e0] in [Homebrew/brew#22815][pr22815] (merged 2026-06-19, first released in 6.0.3) replaced it with `workflow_dispatch`, deprecated `--pull-label`, and added `--head-sha`.
  Its stated reasons: "Avoid generating privileged `pull_request_target` publishing workflows", "Require manual publishing so reviewed PR state is intentional", and "Prefer `--head-sha` pinning to avoid publishing moved PR heads".
- The trigger was [Homebrew/brew#22812][is22812] (reported by simnalamburt), which called the generated workflow "a privileged `pull_request_target` workflow" with write permissions.
- [`15069d1`][c-15069d1] (first released in 7.0.0) moved `--pull-label` from deprecated to disabled ([current flag][src-tapnew-flag]).
- Existing taps keep whatever `publish.yml` they generated; all five stock taps in the table still use the label trigger.

### Per-tap notes

- **osx-cross/homebrew-avr** pushes with a dedicated secret `OSX_CROSS_AVR_HOMEBREW_GITHUB_API_TOKEN` and runs on `macos-latest` ([publish.yml][avr-publish]); its release for `avr-gcc@14-14.4.0` holds one asset per macOS tag, named `avr-gcc@14-14.4.0.<tag>.bottle.tar.gz`.
- **Homebrew/homebrew-core** runs `brew pr-pull --no-upload --clean --no-cherry-pick` to fetch the artifacts and write the bottle commit on the PR's branch, then `brew pr-upload` to GHCR, then pushes that commit to the PR's own branch with `git-try-push`, then enables auto-merge with `--match-head-commit` ([publish-commit-bottles.yml][core-publish]).
  Its `main` requires PRs and a merge queue ([`rules/branches/main`][core-rules-note]).
- **chenrui333/homebrew-tap** copies the homebrew-core sequence (`pr-pull --clean --no-cherry-pick`, separate `pr-upload`, push to `head_branch`), runs every publish in one concurrency group `brew-pr-pull` with `queue: max`, and merges in a separate [`formula-merge.yml`][cr-merge] with `gh pr merge --merge --match-head-commit` ([publish.yml][cr-publish]).
  Its owner is a public member of the Homebrew GitHub organisation (`gh api orgs/Homebrew/members/chenrui333` returns 204).
- **shivammathur/homebrew-php** edits Homebrew's own source at runtime with `sed` (removing `pending` from `pr-automerge.rb`, and replacing `Closes #` with `[skip ci]` in `pr-pull.rb`) before calling it ([autopublish.yml][php-auto], [publish-commit-bottles.yml][php-publish]).
- **brewsci/homebrew-bio** builds with `brew test-bot --only-formulae --only-json-tab --root-url=https://ghcr.io/v2/brewsci/bio` ([build-bottles.yml][bio-build]); after a PR merges into `develop`, [upload-bottles.yml][bio-upload] finds that PR's `build-bottles` run, downloads its `all-bottles` artifact, runs `brew pr-upload`, and pushes the result to `develop` and `master`, opening a bot PR labelled `bottles` if the push fails three times.
- **osrf/homebrew-simulation**: a Jenkins bot opens the version-bump PR, a Jenkins job builds the bottle, uploads it to S3 with `s3cmd put` ([`repository_uploader.bash`][osrf-upload]), and pushes an "update bottle" commit to the PR branch; a maintainer merges the PR ([#3640][osrf-pr]).
- **aws/homebrew-tap**: the `cbmc-viewer` source repo's [`release-brew.yaml`][cbmcv-wf] runs on `release: created`, opens a `bump-formula-pr` from a bot fork, builds bottles with `test-bot` on Linux and macOS, attaches them to the *source* repo's release with `softprops/action-gh-release`, and pushes the bottle block to the bump PR branch.

## Question 2: does each approach prevent the #36 overwrite race?

### What Homebrew's upload code does with a name that already exists

- **GitHub Releases** ([`github_releases.rb`][src-ghr]): `pr-upload` reuses an existing release for the tag; it creates a *draft* release only when none exists, uploads, then publishes the draft.
  It deletes a same-named asset only `if draft_release`, that is only while resuming its own interrupted upload ([L35][src-ghr-draft], [L75-L83][src-ghr-find]).
  On an already-published release it simply POSTs the asset ([`upload_release_asset`][src-gh-upload]), and GitHub answers **422** "if you upload an asset with the same filename as another uploaded asset" ([GitHub REST docs][gh-asset-422]).
  This confirms the local 7.0.12 observation.
  The draft behaviour was added on 2026-10-30 by [Homebrew/brew#24403][pr24403] and refined by [#24416][pr24416], both to make uploads work on repositories with immutable releases.
- **GitHub Packages** ([`github_packages.rb`][src-ghp-exists]): before uploading, `pr-upload` inspects the image tag and stops with "`<image> already exists!`" unless `--keep-old` or `--warn-on-upload-failure` is passed.
- **Rebuilds**: `brew bottle` compares the formula with `origin/HEAD`; if the default branch already has the same version, the new bottle gets `rebuild` set to that bottle's rebuild plus one, which changes the file name (`….1.bottle.tar.gz`) and GHCR tag ([`bottle.rb`][src-bottle-rebuild]).
  A deliberate rebuild of a published version therefore never collides with the original.

### Applied to the race

| Approach | Two PRs bump to the same version | Re-run on the same PR | PR closed after publishing |
| --- | --- | --- | --- |
| Stock `pr-pull` (any host) | Prevented. The first `pr-pull` publishes and pushes. The second either fails to cherry-pick (both PRs edit the same lines) or fails the upload (422 or "already exists"), and the push step never runs. | Not applicable: nothing is published until `pr-pull`. | Not applicable: publishing *is* landing. |
| homebrew-core / chenrui333 | Prevented on GHCR by the tag check. A failed second publish leaves its PR unmerged. chenrui333 also serialises all publishes. | Not applicable: publish runs once per PR. | Possible but rare: an image stays in GHCR without a commit, and `main` is unaffected. |
| brewsci (post-merge) | Prevented: only merged PRs publish, and GHCR refuses duplicates. | Not applicable. | Not applicable. |
| osrf (S3, pre-merge) | **Not prevented** (Inference): `s3cmd put` overwrites, and the S3 key is just the Homebrew file name. In practice one Jenkins job per version bump makes two writers unlikely. | Not prevented, same reason. | Not prevented. |
| aws cbmc-viewer | Single writer per upstream release event, so not observed. Whether `action-gh-release` overwrites a same-named asset was not checked. | Same. | Same. |
| **Ours** (`bottle.yml`) | **Not prevented**: `--clobber` replaces the asset ([#36][i36]). | Not prevented: every Bottle run on a branch replaces the asset. | Not prevented. |

**Inference:** the race in #36 has two causes, and the established flows remove both.
The first cause is publishing on every PR update instead of once, when the PR is about to land.
The second is overwriting a published asset instead of failing.
Dropping `--clobber` alone would turn the silent overwrite into a red Bottle run, but a Renovate force-push would then fail too, because the second build gets the same file name.
That is exactly why Homebrew pairs "never overwrite" with "publish once, at landing time".

### Taps that hit this or something like it

- I found no issue in the surveyed taps describing two branches overwriting each other's bottle.
  A search for "reports different checksum" across GitHub returns mostly source tarballs or casks whose upstream release asset was re-uploaded, which is the same failure class (a published file replaced after its sha256 was recorded) but not a bottle race.
- [osx-cross/homebrew-avr#413][avr-413] describes a related *ordering* problem: a GCC PR was published before the Binutils bottle it depends on existed, so it shipped without macOS 27 bottles and needed a revision bump.
- [mas-cli/homebrew-tap#16][mas-16] (2020) was a 404 because the bottle was referenced before it was uploaded to Bintray, the inverse of #36.

## Question 3: what Homebrew documents and recommends

- [How to Create and Maintain a Tap][doc-tap] recommends keeping the generated workflows, letting GitHub Actions build bottles, and publishing "after reviewing a pull request and checking that the pull request checks passed" with `brew pr-pull --head-sha`, or by dispatching the generated workflow.
  It names GitHub Packages (`brew tap-new --github-packages`) as the alternative to GitHub Releases.
  It does not discuss branch protection, `all:` bottles, or races.
- The [Bottles][doc-bottles-rooturl] page documents `root_url` as being "useful for taps that wish to provide bottles for their formulae", and describes homebrew-core's process as BrewTestBot building on the PR and uploading "if … a maintainer approves the change" ([Creation section][doc-bottles-core]).
- The [BrewTestBot][doc-testbot] page only describes the PR status checks; it defers to "the workflow definitions" as authoritative.
- The 2020 announcement linked from the tap docs, [Homebrew tap with bottles uploaded to GitHub Releases][blog-2020], describes the label flow that existed then.
- Homebrew/brew's own source verifies all three local observations: the dispatch-only `publish.yml` ([template][tpl-publish]), the `<remote>/releases/download/<name>-<pkg_version>` default ([`test_bot/formulae.rb`][src-testbot-rooturl]), and draft-only replacement ([`github_releases.rb`][src-ghr-draft]).

**Inference:** Homebrew's recommendation is "build on the PR, publish deliberately, once, from the reviewed commit".
It does not endorse publishing from every PR push.

## Question 4: how taps reconcile `pr-pull`'s direct push with branch protection

What GitHub's public "rules for a branch" and "get branch" endpoints show for each default branch (classic protection details need admin access and were not visible):

| Tap | Rules on the default branch | Push credential |
| --- | --- | --- |
| osx-cross/homebrew-avr | none, `protected: false` | personal access token secret |
| mas-cli/homebrew-tap | none, `protected: false` | `GITHUB_TOKEN` |
| qmk/homebrew-qmk | none, `protected: false` | `GITHUB_TOKEN` |
| gromgit/homebrew-fuse | none, `protected: false` | `GITHUB_TOKEN` |
| dunglas/homebrew-frankenphp | ruleset: block deletion and non-fast-forward only | `GITHUB_TOKEN` |
| chenrui333/homebrew-tap | ruleset: deletion, non-fast-forward, Copilot review; no PR requirement | pushes to the PR branch, then merges the PR |
| Homebrew/homebrew-core | rulesets: PR required, merge queue, required status checks, merge commits only | pushes to the PR branch, then merges the PR |
| brewsci/homebrew-bio | classic protection on `develop` (details not visible) | bot PAT pushes directly, so presumably an admin or allowed actor |
| osrf/homebrew-simulation | classic protection, required checks enforced for non-admins | bot commits to the PR branch, human merges |

**Facts**: every stock `pr-pull` tap surveyed pushes straight to a default branch that does not require PRs.
None of them uses a PR-required ruleset with a bypass actor.
The taps that require PRs on `main` (homebrew-core, and osrf through its human merge) put the bottle commit on the PR branch and merge the PR.

**GitHub's options** ([rulesets docs][gh-rulesets]): bypass can be granted to admins, roles, teams, GitHub Apps and Dependabot, either "always" or "for pull requests only", where the latter still requires a PR.
A `pr-pull` direct push would therefore need an "always" bypass, which [ADR 0001][adr1] rejected ("a stolen App key could write to `main`").

**Inference:** under ADR 0001, the stock `pr-pull` push is not available, and the homebrew-core pattern is the established way to keep a PR-only `main`.

## What this means for our options in #36 (Inference)

- **Adopt the homebrew-core pattern.** Build in PR CI (`test-bot` or our script) as an artifact only.
  A publish job then runs `pr-upload` (no `--clobber`), pushes the bottle commit with the App to the PR branch, and merges with `--match-head-commit`.
  Renovate automerge would become "the publish job merges once checks pass", much like `brew pr-automerge --publish` ([`pr-automerge.rb`][src-prautomerge]) or chenrui333's [`formula-merge.yml`][cr-merge].
- **Stock `tap-new`.** It is closest to "use the established tool unchanged", but it needs a `main` bypass or a PAT, plus a manual or scripted dispatch for every bump.
- **Keep pre-merge publishing but make assets unique.** For example, a release tag per commit.
  No surveyed tap does this.
  `pr-upload` accepts any tag in a GitHub Releases `root_url` ([`URL_REGEX`][src-ghr]), but this would be our own convention.
- **Host on GHCR instead of Releases.** GHCR gives the "refuse duplicates" behaviour, does not interact with ADR 0001's tag ruleset, and is where homebrew-core, chenrui333, shivammathur, brewsci, qmk, frankenphp and gromgit all publish.

## Open questions and unverified points

- Whether `--only-json-tab` (used by brewsci) makes macOS and Linux builds of our script-only formula byte-identical, which would let the stock merge produce `all:` bottles without our relabelling hack; chenrui333 gets `all:` bottles without it, but I did not test our formula.
- Whether stock `pr-upload` works with **immutable releases** for a *rebuild*: a rebuild goes into the existing published `<name>-<version>` release, and Homebrew's commit message for [#24403][pr24403] says immutable releases reject "uploading assets to published releases".
  From the code, this looks like it would fail, but I did not test it.
  ADR 0001 rejected immutable releases for the same reason.
- Whether the `GITHUB_TOKEN` pushes in mas-cli, qmk, frankenphp and gromgit trigger CI on `main` (GitHub suppresses workflow runs for `GITHUB_TOKEN` pushes), and whether those taps care.
- brewsci's and osrf's classic branch protection settings, which need admin access to read.
- Whether `softprops/action-gh-release` (aws/cbmc-viewer) overwrites a same-named asset.
- The survey favours taps found via code search for `brew pr-pull`, so it may under-count taps using other hosts or tooling.

[i36]: https://github.com/afrossard/homebrew-tap/issues/36
[adr1]: ../adr/0001-protect-the-tap-and-its-source-repos.md
[brew-main]: https://github.com/Homebrew/brew/tree/b63354cf393a1779a8e0d7ab6a52eed05c61171d
[src-tapnew-render]: https://github.com/Homebrew/brew/blob/b63354cf393a1779a8e0d7ab6a52eed05c61171d/Library/Homebrew/dev-cmd/tap-new.rb#L83-L95
[src-tapnew-ghp]: https://github.com/Homebrew/brew/blob/b63354cf393a1779a8e0d7ab6a52eed05c61171d/Library/Homebrew/dev-cmd/tap-new.rb#L44
[src-tapnew-flag]: https://github.com/Homebrew/brew/blob/b63354cf393a1779a8e0d7ab6a52eed05c61171d/Library/Homebrew/dev-cmd/tap-new.rb#L22-L24
[tpl-publish]: https://github.com/Homebrew/brew/blob/b63354cf393a1779a8e0d7ab6a52eed05c61171d/.github/workflows/tap-new-publish.yml
[tpl-tests]: https://github.com/Homebrew/brew/blob/b63354cf393a1779a8e0d7ab6a52eed05c61171d/.github/workflows/tap-new-tests.yml
[src-testbot-rooturl]: https://github.com/Homebrew/brew/blob/b63354cf393a1779a8e0d7ab6a52eed05c61171d/Library/Homebrew/test_bot/formulae.rb#L464-L468
[src-prpull]: https://github.com/Homebrew/brew/blob/b63354cf393a1779a8e0d7ab6a52eed05c61171d/Library/Homebrew/dev-cmd/pr-pull.rb
[src-prpull-closes]: https://github.com/Homebrew/brew/blob/b63354cf393a1779a8e0d7ab6a52eed05c61171d/Library/Homebrew/dev-cmd/pr-pull.rb#L233
[src-prupload]: https://github.com/Homebrew/brew/blob/b63354cf393a1779a8e0d7ab6a52eed05c61171d/Library/Homebrew/dev-cmd/pr-upload.rb#L59-L116
[src-prautomerge]: https://github.com/Homebrew/brew/blob/b63354cf393a1779a8e0d7ab6a52eed05c61171d/Library/Homebrew/dev-cmd/pr-automerge.rb
[src-ghr]: https://github.com/Homebrew/brew/blob/b63354cf393a1779a8e0d7ab6a52eed05c61171d/Library/Homebrew/github_releases.rb
[src-ghr-draft]: https://github.com/Homebrew/brew/blob/b63354cf393a1779a8e0d7ab6a52eed05c61171d/Library/Homebrew/github_releases.rb#L35
[src-ghr-find]: https://github.com/Homebrew/brew/blob/b63354cf393a1779a8e0d7ab6a52eed05c61171d/Library/Homebrew/github_releases.rb#L75-L83
[src-gh-upload]: https://github.com/Homebrew/brew/blob/b63354cf393a1779a8e0d7ab6a52eed05c61171d/Library/Homebrew/utils/github.rb#L285
[src-ghp-exists]: https://github.com/Homebrew/brew/blob/b63354cf393a1779a8e0d7ab6a52eed05c61171d/Library/Homebrew/github_packages.rb#L561-L569
[src-bottle-rebuild]: https://github.com/Homebrew/brew/blob/b63354cf393a1779a8e0d7ab6a52eed05c61171d/Library/Homebrew/dev-cmd/bottle.rb#L643-L656
[src-bottle-all]: https://github.com/Homebrew/brew/blob/b63354cf393a1779a8e0d7ab6a52eed05c61171d/Library/Homebrew/dev-cmd/bottle.rb
[c-843dffe]: https://github.com/Homebrew/brew/commit/843dffea78fb63aadd6a03f1b6763c5243525f9b
[c-ac1b5e0]: https://github.com/Homebrew/brew/commit/ac1b5e0f13980339cb54ae2e227001fa3afb6ca7
[c-15069d1]: https://github.com/Homebrew/brew/commit/15069d12a0
[pr8762]: https://github.com/Homebrew/brew/pull/8762
[pr22815]: https://github.com/Homebrew/brew/pull/22815
[is22812]: https://github.com/Homebrew/brew/issues/22812
[pr24403]: https://github.com/Homebrew/brew/pull/24403
[pr24416]: https://github.com/Homebrew/brew/pull/24416
[doc-tap]: https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap
[doc-bottles-rooturl]: https://docs.brew.sh/Bottles#root-url-root_url
[doc-bottles-core]: https://docs.brew.sh/Bottles#creation
[doc-testbot]: https://docs.brew.sh/BrewTestBot
[blog-2020]: https://brew.sh/2020/11/18/homebrew-tap-with-bottles-uploaded-to-github-releases
[gh-asset-422]: https://docs.github.com/en/rest/releases/assets#upload-a-release-asset
[gh-rulesets]: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository
[avr-publish]: https://github.com/osx-cross/homebrew-avr/blob/c347896c561cba89aad4bfd2e53969ff6801aeb1/.github/workflows/publish.yml
[avr-formula]: https://github.com/osx-cross/homebrew-avr/blob/c347896c561cba89aad4bfd2e53969ff6801aeb1/Formula/avr-gcc@14.rb#L13-L18
[avr-413]: https://github.com/osx-cross/homebrew-avr/issues/413
[mas-publish]: https://github.com/mas-cli/homebrew-tap/blob/4545d1594a7b09df87e0035329cd8545dcb29651/.github/workflows/publish.yml
[mas-formula]: https://github.com/mas-cli/homebrew-tap/blob/4545d1594a7b09df87e0035329cd8545dcb29651/Formula/mas.rb#L15-L19
[mas-16]: https://github.com/mas-cli/homebrew-tap/issues/16
[qmk-publish]: https://github.com/qmk/homebrew-qmk/blob/e4d46a447766bd02c12a2b8824bb787fee1e9ccc/.github/workflows/publish.yml
[qmk-formula]: https://github.com/qmk/homebrew-qmk/blob/e4d46a447766bd02c12a2b8824bb787fee1e9ccc/Formula/qmk.rb#L10-L14
[fp-publish]: https://github.com/dunglas/homebrew-frankenphp/blob/b220dd47d553c0d45446775b65bec24b893f305e/.github/workflows/publish.yml
[fp-formula]: https://github.com/dunglas/homebrew-frankenphp/blob/b220dd47d553c0d45446775b65bec24b893f305e/Formula/frankenphp.rb#L9-L13
[fuse-publish]: https://github.com/gromgit/homebrew-fuse/blob/1b8918c2e4956e92d13a7fc906e60f1f52337827/.github/workflows/publish.yml
[fuse-formula]: https://github.com/gromgit/homebrew-fuse/blob/1b8918c2e4956e92d13a7fc906e60f1f52337827/Formula/archivemount-mac.rb#L11-L15
[core-publish]: https://github.com/Homebrew/homebrew-core/blob/405d08a0c9c7ea042112e059916402eaa234393f/.github/workflows/publish-commit-bottles.yml#L347-L497
[core-rules-note]: https://docs.github.com/en/rest/repos/rules#get-rules-for-a-branch
[cr-publish]: https://github.com/chenrui333/homebrew-tap/blob/858897e4ea85bf842c49e26bb107cbea52d976a5/.github/workflows/publish.yml#L14-L17
[cr-merge]: https://github.com/chenrui333/homebrew-tap/blob/858897e4ea85bf842c49e26bb107cbea52d976a5/.github/workflows/formula-merge.yml#L286-L289
[cr-formula]: https://github.com/chenrui333/homebrew-tap/blob/858897e4ea85bf842c49e26bb107cbea52d976a5/Formula/s/snip.rb#L11-L15
[php-publish]: https://github.com/shivammathur/homebrew-php/blob/bd9284dcd4c609fd1b2f7090e327888211a7110c/.github/workflows/publish-commit-bottles.yml#L65-L100
[php-auto]: https://github.com/shivammathur/homebrew-php/blob/bd9284dcd4c609fd1b2f7090e327888211a7110c/.github/workflows/autopublish.yml#L20-L25
[php-formula]: https://github.com/shivammathur/homebrew-php/blob/bd9284dcd4c609fd1b2f7090e327888211a7110c/Formula/php@8.4.rb#L38-L45
[bio-build]: https://github.com/brewsci/homebrew-bio/blob/f96aba07fafb68d75a24af5407cc1274c7899527/.github/workflows/build-bottles.yml#L59
[bio-upload]: https://github.com/brewsci/homebrew-bio/blob/f96aba07fafb68d75a24af5407cc1274c7899527/.github/workflows/upload-bottles.yml
[bio-formula]: https://github.com/brewsci/homebrew-bio/blob/f96aba07fafb68d75a24af5407cc1274c7899527/Formula/abacas.rb#L8-L12
[osrf-wf]: https://github.com/osrf/homebrew-simulation/blob/dbea568cc54a453d94872f42b2bd8776c557bcc5/.github/workflows/main.yml
[osrf-formula]: https://github.com/osrf/homebrew-simulation/blob/dbea568cc54a453d94872f42b2bd8776c557bcc5/Formula/gz-math9.rb#L11-L15
[osrf-upload]: https://github.com/gazebo-tooling/release-tools/blob/933c1dd4d67e1c37ed1bcaa597a5ef9d33d2d863/jenkins-scripts/lib/repository_uploader.bash#L5-L30
[osrf-pr]: https://github.com/osrf/homebrew-simulation/pull/3640
[aws-formula]: https://github.com/aws/homebrew-tap/blob/0e0119e9418fce57606890a2a0b2b40c3a30c5fe/Formula/cbmc-viewer.rb#L11-L15
[cbmcv-wf]: https://github.com/model-checking/cbmc-viewer/blob/bf452b2c9337bfc40c83507a735c938ff0cafe7a/.github/workflows/release-brew.yaml
[hc-formula]: https://github.com/hashicorp/homebrew-tap/blob/ec38e601175a15b85a6e48dfa76ac9f7414a1609/Formula/terraform.rb
[mdb-formula]: https://github.com/mongodb/homebrew-brew/blob/9c6c258de723b1773dfdc40cdf28e6ee9a147512/Formula/mongodb-community.rb
[messense]: https://github.com/messense/homebrew-macos-cross-toolchains/tree/473d950430a5149f71a82e8c546638f581bb7e0d
[search-note]: https://cli.github.com/manual/gh_search_code
