#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

lid_open="$ROOT/bin/omarchy-system-lid-open"
utilities="$ROOT/default/hypr/bindings/utilities.lua"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mock_bin="$tmpdir/bin"
call_log="$tmpdir/calls"
mkdir -p "$mock_bin"

# $1 is the exit status of the shell call, so a lock that is not running can
# be played as well as one that answers.
setup_mocks() {
  : >"$call_log"
  cat >"$mock_bin/omarchy-shell" <<SH
#!/bin/bash
echo "omarchy-shell \$*" >>"\$CALL_LOG"
exit $1
SH
  cat >"$mock_bin/omarchy-hyprland-monitor-clamshell" <<'SH'
#!/bin/bash
echo omarchy-hyprland-monitor-clamshell >>"$CALL_LOG"
SH
  chmod +x "$mock_bin"/*
}

run_lid_open() {
  CALL_LOG="$call_log" PATH="$mock_bin:$PATH" "$lid_open"
  mapfile -t calls <"$call_log"
}

# A docked lid opens without a resume, so this call is the only word the lock
# gets that a reader hidden while the lid was shut is back.
setup_mocks 0
run_lid_open

[[ ${calls[0]} == "omarchy-shell lock lidOpened" ]] ||
  fail "an opening lid tells the lock to look for the reader again" "calls: ${calls[*]}"
pass "an opening lid tells the lock to look for the reader again"

[[ ${calls[1]} == "omarchy-hyprland-monitor-clamshell" ]] ||
  fail "an opening lid reconciles displays" "calls: ${calls[*]}"
pass "an opening lid reconciles displays"

# The handler runs from a Hyprland binding, so a shell that is not running
# must not stop the display reconciliation behind it.
setup_mocks 1
run_lid_open

[[ ${calls[1]} == "omarchy-hyprland-monitor-clamshell" ]] ||
  fail "a missing shell still reconciles displays" "calls: ${calls[*]}"
pass "a missing shell still reconciles displays"

grep -F 'switch:off:Lid Switch", nil, "omarchy-system-lid-open", { locked = true }' "$utilities" >/dev/null &&
  grep -F 'switch:off:Apple SMC power/lid events", nil, "omarchy-system-lid-open", { locked = true }' "$utilities" >/dev/null ||
  fail "both lid switches run the lid-open handler, also while locked"
pass "both lid switches run the lid-open handler, also while locked"
