#!/usr/bin/env bats
#
# What this script prints is the only thing that stops a bottle workflow run
# on a branch that already carries its bottle from building and pushing
# another one: brew stamps the tap's git HEAD into every keg it builds, so a
# rebuild from a later commit always yields a different sha256 and the
# "nothing to commit" guard downstream can never catch it. PR #8 pushed two
# bottle commits before an unrelated CI failure broke the loop by accident.
#
# It must also answer from the tree alone. PRs #12 and #13 merged stale
# bottles to main because a diff against a moving, shallow-fetched base failed
# silently and reported nothing to rebuild.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../.github/scripts/formulas-needing-bottle.sh"
  export BREW="${BATS_TEST_DIRNAME}/helpers/fake-brew"
  export TAP_NAME="example/tap"

  cd "$BATS_TEST_TMPDIR"
  mkdir -p Formula
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

@test "rebuilds when a version bump leaves the committed bottle behind" {
  write_formula agent-runtime 4.0.0 2.1.2

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "Formula/agent-runtime.rb" ]
}

@test "does not rebuild a bottle that matches the formula's version" {
  write_formula agent-runtime 4.0.0 4.0.0

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "rebuilds a formula that carries no bottle yet" {
  write_formula agent-runtime 4.0.0

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "Formula/agent-runtime.rb" ]
}

@test "lists only the stale formulas among several" {
  write_formula agent-runtime 4.0.4 4.0.1
  write_formula other-tool 3.0.0 3.0.0
  write_formula third-tool 0.2.2 0.1.0

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "${lines[*]}" = "Formula/agent-runtime.rb Formula/third-tool.rb" ]
}

@test "does not mistake a version prefix for a match" {
  write_formula agent-runtime 4.0.10 4.0.1

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "Formula/agent-runtime.rb" ]
}

@test "prints nothing when there are no formulas" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "fails instead of reporting nothing when brew fails" {
  write_formula agent-runtime 4.0.0 2.1.2
  export BREW=false

  run "$SCRIPT"
  [ "$status" -ne 0 ]
}
