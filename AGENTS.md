# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that travel with the code.

## Bottle

Every formula ships an `all:` bottle on GHCR so `brew install` needs no compiler on the host.
The flow copies homebrew-core's: `build-bottles.yml` builds on the PR, `publish-bottles.yml` uploads once and merges.
See the README's "Bottle" section and `docs/adr/0002-publish-bottles-like-homebrew-core.md` for how and why.

- Never replace a published bottle: no `--clobber`, `--keep-old` or `--warn-on-upload-failure` on the publish path. `pr-upload` refusing an existing GHCR tag is what stops two PRs for the same version from breaking `main` (issue #36).
- `brew test-bot` must keep `--only-json-tab`. Without it the install receipt goes into the tarball, the two Linux builds differ, `brew bottle --merge` writes no `all:` bottle, and `published-bottle` stays red.
- Every keg brew builds records the tap's own git HEAD, so a rebuild never reproduces the bottle already committed. Whether to publish is decided from the formula's state (`.github/scripts/verify-published-bottles.sh`), never from what a commit or a branch changed - see `test/verify-published-bottles.bats`.
- `published-bottle` must stay out of `build-bottles.yml`. It is red until the publish runs, and the publish only triggers when the whole `Build bottles` run succeeds.
- The publish job pushes its bottle commit with a GitHub App token, never `GITHUB_TOKEN`. A `GITHUB_TOKEN` push onto a PR branch creates `pull_request` runs that GitHub holds at `action_required` until someone with write access approves them, and any still held at merge close as zero-job failures on `main`. On a repo where the App is still a first-time contributor, its push is held the same way.
- `publish-bottles.yml` only runs by dispatch or `workflow_run` from the default branch, so a change to it takes effect after merge, not on its own PR.

## CI checkout sharp edges

- `Homebrew/actions/setup-homebrew` auto-taps a checkout in place (zero-copy symlink) whenever `GITHUB_REPOSITORY` names a Homebrew tap. Do not `brew tap` it again afterward - a second tap call rewrites that already-tapped directory's git `origin` remote to whatever path you pass, and since the tap dir *is* the checkout, this silently redirects any later `git push` away from GitHub even though the push reports success. Use the action's `tap-name` output instead.
- That same setup step's internal fetch/checkout can leave `HEAD` on the `pull_request` event's synthetic merge-with-base commit rather than the real branch tip. Re-checkout the branch's own tip (e.g. `git checkout -B <branch> origin/<branch>`) before committing anything back to the PR branch, or you'll splice a phantom merge commit into its real history.

## Maintaining this file

Keep entries to knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones, and keep entries concise.
