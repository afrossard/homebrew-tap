#!/usr/bin/env bats
#
# Only container-base's release asset carries a launcher that names the agent
# image by digest (container-base ADR-0028), so only that asset's sha256
# covers the image the formula runs. The tag's source tarball names the image
# by tag alone.
#
# Renovate's `homebrew` manager falls back to that source tarball whenever the
# release asset is missing or misnamed, and the bump then automerges. PR #29
# shipped 5.1.0 unpinned that way. This test keeps such a bump red.

@test "agent-runtime installs from a release asset, not the tag's source tarball" {
  formula="${BATS_TEST_DIRNAME}/../Formula/agent-runtime.rb"
  run grep -E '^  url "https://github\.com/afrossard/container-base/releases/download/[^/]+/[^/]+\.tar\.gz"$' "$formula"
  [ "$status" -eq 0 ]
}
