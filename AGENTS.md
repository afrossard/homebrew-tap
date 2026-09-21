# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that travel with the code.

## Bottle

`agent-runtime` ships a bottle so `brew install` needs no compiler on the host.
See `.github/workflows/bottle.yml`, `.github/scripts/*.sh`, and the README's "Bottle" section for what it is and how the rebuild automation works.

- `brew bottle --merge --write` only auto-produces an `all:` tag when merging multiple per-platform JSON files with matching checksums (a multi-runner matrix). For a single-build `all:` bottle, build once, then relabel that one tag to `all` in the `--json` output (and its tarball filename) before merging.

## CI checkout sharp edges

- `Homebrew/actions/setup-homebrew` auto-taps a checkout in place (zero-copy symlink) whenever `GITHUB_REPOSITORY` names a Homebrew tap. Do not `brew tap` it again afterward - a second tap call rewrites that already-tapped directory's git `origin` remote to whatever path you pass, and since the tap dir *is* the checkout, this silently redirects any later `git push` away from GitHub even though the push reports success. Use the action's `tap-name` output instead.
- That same setup step's internal fetch/checkout can leave `HEAD` on the `pull_request` event's synthetic merge-with-base commit rather than the real branch tip. Re-checkout the branch's own tip (e.g. `git checkout -B <branch> origin/<branch>`) before committing anything back to the PR branch, or you'll splice a phantom merge commit into its real history.

## Maintaining this file

Keep entries to knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones, and keep entries concise.
