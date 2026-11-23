#!/usr/bin/env bats
#
# This script backs the required `published-bottle` check and decides whether
# the publish job has anything to upload. In issue #36, main pinned a bottle
# sha256 whose release asset another PR had replaced, and nothing went red
# until a user's `brew upgrade` failed. It must fail for every formula whose
# published bottle is missing or differs, and for any formula without an
# `all:` bottle.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../.github/scripts/verify-published-bottles.sh"
  export BREW="${BATS_TEST_DIRNAME}/helpers/fake-brew"

  cd "$BATS_TEST_TMPDIR"
  mkdir -p Formula published
}

# write_formula <name> [tag] [sha256]
# Omitting tag writes a formula with no bottle block at all.
write_formula() {
  local name="$1" tag="${2:-}" sha="${3:-$(printf '%064d' 1)}"
  {
    echo "class $name < Formula"
    echo "  url \"https://example.invalid/${name}-1.0.0.tar.gz\""
    if [ -n "$tag" ]; then
      echo "  bottle do"
      echo "    root_url \"https://ghcr.io/v2/example/tap\""
      echo "    sha256 cellar: :any_skip_relocation, ${tag}: \"${sha}\""
      echo "  end"
    fi
    echo "end"
  } >"Formula/${name}.rb"
}

# publish <name> [sha256]: the bottle file that root_url serves.
publish() {
  printf '%s' "${2:-$(printf '%064d' 1)}" >"published/$1"
}

@test "passes when every formula's published bottle matches its sha256" {
  write_formula agent-runtime all
  write_formula actual-budget-transformer all
  publish agent-runtime
  publish actual-budget-transformer

  run "$SCRIPT" example/tap
  [ "$status" -eq 0 ]
}

@test "fails when the published bottle was replaced after the formula pinned it" {
  write_formula agent-runtime all
  publish agent-runtime "$(printf '%064d' 2)"

  run "$SCRIPT" example/tap
  [ "$status" -eq 1 ]
  [[ "$output" == *"agent-runtime's published bottle is missing or does not match"* ]]
}

@test "fails when the bottle was never published" {
  write_formula agent-runtime all

  run "$SCRIPT" example/tap
  [ "$status" -eq 1 ]
}

@test "fails for a formula with no bottle block" {
  write_formula agent-runtime

  run "$SCRIPT" example/tap
  [ "$status" -eq 1 ]
  [[ "$output" == *"agent-runtime has no all: bottle"* ]]
}

@test "fails for a formula with only a platform-specific bottle" {
  write_formula agent-runtime x86_64_linux
  publish agent-runtime

  run "$SCRIPT" example/tap
  [ "$status" -eq 1 ]
  [[ "$output" == *"agent-runtime has no all: bottle"* ]]
}

@test "reports every failing formula, not only the first" {
  write_formula actual-budget-transformer
  write_formula agent-runtime all

  run "$SCRIPT" example/tap
  [ "$status" -eq 1 ]
  [[ "$output" == *"actual-budget-transformer has no all: bottle"* ]]
  [[ "$output" == *"agent-runtime's published bottle is missing"* ]]
}
