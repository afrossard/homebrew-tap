#!/usr/bin/env bash
# Builds a platform-independent (`all:`) bottle for one formula in this tap,
# publishes the tarball as a GitHub Release asset in this repo, and rewrites
# the formula's bottle block in place (working tree only - the caller commits).
#
# The formula only ever copies plain scripts (never compiles anything), so a
# single build is representative of every platform: Homebrew's bottle tooling
# is told to reuse the same sha256 under the `all:` tag rather than tagging it
# for the one platform the runner happens to be. See Formula/agent-runtime.rb
# and README.md for why this bottle exists at all.
#
# Usage: build-and-publish-bottle.sh <path/to/Formula/name.rb>
# Requires: brew, jq, gh (authenticated via GH_TOKEN), GITHUB_REPOSITORY and
# TAP_NAME (e.g. afrossard/tap) set, and TAP_NAME already tapped by the
# caller against this checkout. The workflow relies on
# Homebrew/actions/setup-homebrew's own auto-tap (it symlinks this checkout
# in as TAP_NAME with zero copy, since GITHUB_REPOSITORY names a Homebrew
# tap) rather than tapping again here: a second `brew tap` against an
# already-tapped repo rewrites its `origin` remote to whatever path you pass,
# which - since the tap dir *is* this checkout - corrupts the very remote
# `git push` later relies on to reach GitHub.
set -euo pipefail

formula_file="$1"
name="$(basename "$formula_file" .rb)"
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"
tap="${TAP_NAME:?TAP_NAME must be set (e.g. afrossard/tap), already tapped}"

version="$(brew info --json=v2 "${tap}/${name}" | jq -r '.formulae[0].versions.stable')"
release_tag="${name}-${version}"
root_url="https://github.com/${repo}/releases/download/${release_tag}"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

brew install --build-bottle "${tap}/${name}"
(cd "$workdir" && brew bottle --json --root-url="$root_url" "${tap}/${name}")

json="$(ls "$workdir"/*.bottle.json)"
built_tag="$(jq -r '.[keys[0]].bottle.tags | keys[0]' "$json")"

# Relabel the single-platform build as `all:` - see the comment above.
jq --arg old "$built_tag" '
  .[keys[0]].bottle.tags |= (
    to_entries
    | map(
        if .key == $old then
          .key = "all"
          | .value.filename |= sub($old; "all")
          | .value.local_filename |= sub($old; "all")
        else . end
      )
    | from_entries
  )
' "$json" > "$json.tmp"
mv "$json.tmp" "$json"

old_tarball="$(ls "$workdir"/*.tar.gz)"
asset_name="$(jq -r '.[keys[0]].bottle.tags.all.filename' "$json")"
new_tarball="$workdir/$asset_name"
mv "$old_tarball" "$new_tarball"

# --no-all-checks: we already forced the `all:` tag above, so skip brew's own
# (single-platform) all-bottle auto-detection - it would otherwise try to post
# a "should have had an all: bottle" PR comment using a token scope CI's
# GITHUB_TOKEN doesn't have, which is harmless but noisy.
brew bottle --merge --write --no-commit --no-all-checks "$json"

tap_formula="$(brew --repository "$tap")/Formula/${name}.rb"
if [ "$tap_formula" -ef "$formula_file" ]; then
  : # the tap is this checkout (symlinked in place); brew already wrote here.
else
  cp "$tap_formula" "$formula_file"
fi

if gh release view "$release_tag" --repo "$repo" >/dev/null 2>&1; then
  gh release upload "$release_tag" "$new_tarball" --repo "$repo" --clobber
else
  gh release create "$release_tag" "$new_tarball" \
    --repo "$repo" \
    --title "${name} ${version} (bottle)" \
    --notes "Platform-independent (\`all:\`) bottle for ${name} ${version}, built by CI from ${formula_file}. See README.md for how this is produced."
fi

echo "Published ${asset_name} to release ${release_tag} and updated ${formula_file}"
