#!/usr/bin/env bash
# Offline test suite for superpowers.sh: fake checkouts and releases
# (fixtures.sh), so it needs no network. helpers.sh has the assertions; the
# tests are the test_* functions in cases/<area>.sh, found and run in order.
#
#   scripts/tests/run.sh          run everything
#   scripts/tests/run.sh guard    run the tests whose name contains "guard"

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP="$TESTS_DIR/../superpowers.sh"
FILTER="${1:-}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export NO_COLOR=1 HOME="$WORK/home"
mkdir -p "$HOME/.ssh" && : > "$HOME/.ssh/id_rsa"
# PATH without any real rg, plus a fake one, so no test downloads ripgrep
NO_RG_PATH="$(echo "$PATH" | tr ':' '\n' | while IFS= read -r d; do [ -x "$d/rg" ] || echo "$d"; done | paste -sd: -)"
mkdir -p "$WORK/fakebin" && printf '#!/bin/sh\necho "ripgrep 15.2.0 (fake)"\n' > "$WORK/fakebin/rg" && chmod +x "$WORK/fakebin/rg"
export PATH="$WORK/fakebin:$NO_RG_PATH"

# shellcheck source=/dev/null
. "$TESTS_DIR/helpers.sh"
# shellcheck source=/dev/null
. "$TESTS_DIR/fixtures.sh"
for f in "$TESTS_DIR"/cases/*.sh; do
  # shellcheck source=/dev/null
  . "$f"
done

# every test_* function, the shared install first (other tests use it), then
# each case file's in the order they are written
run_test test_install_all
for f in "$TESTS_DIR"/cases/*.sh; do
  for t in $(sed -n 's/^\(test_[a-z0-9_]*\)() {$/\1/p' "$f"); do
    [ "$t" = test_install_all ] || run_test "$t"
  done
done

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
