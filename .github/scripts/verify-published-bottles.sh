#!/usr/bin/env bash
# Fails unless every formula in this tap has an `all:` bottle, and the bottle
# published at its root_url has exactly the sha256 the formula pins.
# `brew fetch` does the download and the checksum comparison, so this checks
# what `brew install` would actually get, wherever the bottle is hosted.
#
# A formula whose builds stop being identical across platforms gets
# per-platform bottles and no `all:` one, so this fails for it too.
#
# Usage: verify-published-bottles.sh <tap-name>, run from the tap's root.
# BREW overrides the brew binary, for the tests.
set -euo pipefail

tap="$1"
brew="${BREW:-brew}"
status=0

for path in Formula/*.rb; do
  name="$(basename "$path" .rb)"
  sha="$("$brew" info --json=v2 "$tap/$name" | jq -r '.formulae[0].bottle.stable.files.all.sha256 // empty')"
  if [ -z "$sha" ]; then
    echo "::error file=$path::$name has no all: bottle"
    status=1
    continue
  fi
  if ! "$brew" fetch --formula --force-bottle --retry "$tap/$name"; then
    echo "::error file=$path::$name's published bottle is missing or does not match sha256 $sha"
    status=1
  fi
done

exit "$status"
