#!/usr/bin/env bash
# Prints, one per line, the paths of Formula/*.rb files whose *source*
# (the url/sha256/version lines above any `bottle do` block) differ from the
# given base ref. A bottle-only commit (CI rewriting the bottle block)
# produces no output here, which is what stops the workflow from rebuilding
# itself in a loop after it pushes back onto the PR branch.
set -euo pipefail

base_ref="$1"

source_lines() {
  local ref="$1" file="$2"
  git show "${ref}:${file}" 2>/dev/null | awk '/^[[:space:]]*bottle do/{exit} /^[[:space:]]*(url|sha256|version) /{print}'
}

git diff --name-only "${base_ref}...HEAD" -- 'Formula/*.rb' | while read -r f; do
  [ -f "$f" ] || continue
  old="$(source_lines "$base_ref" "$f")"
  new="$(awk '/^[[:space:]]*bottle do/{exit} /^[[:space:]]*(url|sha256|version) /{print}' "$f")"
  if [ "$old" != "$new" ]; then
    echo "$f"
  fi
done
