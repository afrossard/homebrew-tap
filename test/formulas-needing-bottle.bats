#!/usr/bin/env bats
#
# The bottle workflow commits the bottle it built back onto the PR branch,
# which re-triggers the workflow on the workflow's own commit. What this
# script prints is the only thing that stops that second run from building
# and pushing again, and again: brew stamps the tap's git HEAD into every keg
# it builds, so a rebuild after a bottle commit always yields a different
# sha256 and the "nothing to commit" guard downstream can never catch it.
# PR #8 pushed two bottle commits before an unrelated CI failure broke the
# loop by accident.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../.github/scripts/formulas-needing-bottle.sh"
  export BREW="${BATS_TEST_DIRNAME}/helpers/fake-brew"
  export TAP_NAME="example/tap"

  cd "$BATS_TEST_TMPDIR"
  mkdir -p Formula
  git init -q .
  git config user.email "test@example.invalid"
  git config user.name "test"
}

# write_formula <name> <version> [bottle-version]
# Omitting bottle-version writes a formula with no bottle block at all.
write_formula() {
  local name="$1" version="$2" bottle_version="${3:-}"
  {
    echo "class $name < Formula"
    echo "  url \"https://example.invalid/archive/refs/tags/${version}.tar.gz\""
    echo "  sha256 \"$(printf '%064d' 0)\""
    if [ -n "$bottle_version" ]; then
      echo "  bottle do"
      echo "    root_url \"https://example.invalid/releases/download/${name}-${bottle_version}\""
      echo "    sha256 cellar: :any_skip_relocation, all: \"$(printf '%064d' 1)\""
      echo "  end"
    fi
    echo "end"
  } >"Formula/${name}.rb"
}

commit() {
  git add -A
  git commit -qm "$1"
}

# Commits a base branch carrying agent-runtime 2.1.2 with a matching bottle.
given_base() {
  write_formula agent-runtime 2.1.2 2.1.2
  commit "base"
  git branch base
}

@test "rebuilds when a version bump leaves the committed bottle behind" {
  given_base
  write_formula agent-runtime 4.0.0 2.1.2
  commit "renovate bumps the formula"

  run "$SCRIPT" base
  [ "$status" -eq 0 ]
  [ "$output" = "Formula/agent-runtime.rb" ]
}

@test "does not rebuild the bottle the workflow just committed" {
  given_base
  write_formula agent-runtime 4.0.0 2.1.2
  commit "renovate bumps the formula"
  write_formula agent-runtime 4.0.0 4.0.0
  commit "chore: rebuild bottle for Formula/agent-runtime.rb"

  run "$SCRIPT" base
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "does not rebuild when bump and bottle arrive as one squashed commit" {
  given_base
  write_formula agent-runtime 4.0.0 4.0.0
  commit "bump and bottle, squashed"

  run "$SCRIPT" base
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "rebuilds a formula that carries no bottle yet" {
  given_base
  write_formula agent-runtime 4.0.0
  commit "drop the bottle block"

  run "$SCRIPT" base
  [ "$status" -eq 0 ]
  [ "$output" = "Formula/agent-runtime.rb" ]
}

@test "ignores a stale formula the branch does not touch" {
  write_formula agent-runtime 2.1.2 2.1.2
  write_formula other-tool 3.0.0 1.0.0
  commit "base"
  git branch base

  write_formula agent-runtime 4.0.0 4.0.0
  commit "touch only agent-runtime"

  run "$SCRIPT" base
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "ignores a formula the branch deletes" {
  given_base
  git rm -q Formula/agent-runtime.rb
  commit "drop the formula"

  run "$SCRIPT" base
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "prints nothing when the branch changes no formula" {
  given_base
  echo "notes" >README.md
  commit "unrelated change"

  run "$SCRIPT" base
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
