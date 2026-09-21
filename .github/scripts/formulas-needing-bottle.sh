#!/usr/bin/env bash
# Prints, one per line, the paths of the Formula/*.rb files this branch
# touches whose committed bottle is stale: the bottle block's `root_url` does
# not point at the release tag for the formula's current version, or there is
# no bottle block at all.
#
# This asks what state the formula is *in*, deliberately not what changed.
# The workflow commits the bottle it just built back onto the same branch,
# which re-triggers the workflow, so this runs again on the workflow's own
# commit; only a state check answers "already bottled" correctly however the
# branch reached that state - a second push, a rebase and a squash all leave
# the same tree behind but a different history.
#
# Nothing downstream can catch a wrong answer here. Brew stamps the tap's own
# git HEAD into every keg it builds (INSTALL_RECEIPT.json "tap_git_head"), so
# the rebuild triggered by a bottle commit bakes in that commit's sha and
# produces a different tarball, and so a different sha256, every single time.
# A rebuild can never settle by producing the bottle that is already
# committed: this check is the only thing that ends the loop.
#
# Usage: formulas-needing-bottle.sh <base-ref>
# Requires: brew, jq, and TAP_NAME (e.g. afrossard/tap) naming the tap this
# checkout is tapped as - see build-and-publish-bottle.sh for how the workflow
# arranges that.
set -euo pipefail

base_ref="$1"
tap="${TAP_NAME:?TAP_NAME must be set (e.g. afrossard/tap), already tapped}"
brew_cmd="${BREW:-brew}"

# Brew parses the version out of the formula itself, which is also how
# build-and-publish-bottle.sh derives the release tag it bottles into - so the
# two agree on what "current" means by construction.
bottle_is_current() {
  local name="$1" info version root_url
  info="$("$brew_cmd" info --json=v2 "${tap}/${name}")"
  version="$(jq -r '.formulae[0].versions.stable' <<<"$info")"
  root_url="$(jq -r '.formulae[0].bottle.stable.root_url // empty' <<<"$info")"

  case "$root_url" in
    */"${name}-${version}") return 0 ;;
    *) return 1 ;;
  esac
}

mapfile -t touched < <(git diff --name-only "${base_ref}...HEAD" -- 'Formula/*.rb')

for f in "${touched[@]}"; do
  [ -f "$f" ] || continue
  bottle_is_current "$(basename "$f" .rb)" || echo "$f"
done
