#!/usr/bin/env bash
# Prints, one per line, the paths of the Formula/*.rb files whose committed
# bottle is stale: the bottle block's `root_url` does not point at the release
# tag for the formula's current version, or there is no bottle block at all.
#
# This asks what state each formula is *in*, deliberately not what a commit
# or a branch changed. A diff against a base branch answers wrongly whenever
# history moves under it: Renovate force-pushes its branches (dropping the
# bottle commit this workflow added), the base branch advances, and a PR can
# be merged before the run for its last commit finishes. A state check gives
# the same answer however the tree was reached, so the same check serves both
# PR branches and main, and a stale bottle that lands on main gets repaired by
# the next run there.
#
# Nothing downstream can catch a wrong answer here. Brew stamps the tap's own
# git HEAD into every keg it builds (INSTALL_RECEIPT.json "tap_git_head"), so
# a rebuild from any later commit produces a different tarball, and so a
# different sha256, every single time. A rebuild can never settle by producing
# the bottle that is already committed: this check is the only thing that
# stops a run on a branch that already carries its bottle from building and
# pushing another one.
#
# Usage: formulas-needing-bottle.sh
# Run from the root of the checkout.
# Requires: brew, jq, and TAP_NAME (e.g. afrossard/tap) naming the tap this
# checkout is tapped as - see build-and-publish-bottle.sh for how the workflow
# arranges that.
set -euo pipefail

tap="${TAP_NAME:?TAP_NAME must be set (e.g. afrossard/tap), already tapped}"
brew_cmd="${BREW:-brew}"

# Brew parses the version out of the formula itself, which is also how
# build-and-publish-bottle.sh derives the release tag it bottles into - so the
# two agree on what "current" means by construction.
#
# Kept inline rather than in a function called as `f || echo`: bash ignores
# `set -e` inside anything evaluated as a condition, so a failing `brew info`
# there would silently read as "stale" instead of stopping the run.
shopt -s nullglob
for f in Formula/*.rb; do
  name="$(basename "$f" .rb)"
  info="$("$brew_cmd" info --json=v2 "${tap}/${name}")"
  version="$(jq -er '.formulae[0].versions.stable' <<<"$info")"
  root_url="$(jq -r '.formulae[0].bottle.stable.root_url // empty' <<<"$info")"

  case "$root_url" in
    */"${name}-${version}") ;;
    *) echo "$f" ;;
  esac
done
