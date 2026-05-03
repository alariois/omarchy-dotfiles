#!/usr/bin/env bash
#
# Integration tests for hypr-nav
# Tests the tmux layer (no Hyprland required — movefocus calls will fail gracefully)
#
# Usage: ./test_integration.sh
#

set -euo pipefail

HYPR_NAV="$(cd "$(dirname "$0")" && pwd)/hypr-nav"
SESSION="hypr-nav-test-$$"
PASSED=0
FAILED=0

# ── Helpers ────────────────────────────────────────────────────────────

cleanup() {
    tmux kill-session -t "$SESSION" 2>/dev/null || true
}
trap cleanup EXIT

pass() { PASSED=$((PASSED + 1)); printf "  %-55s \033[32mPASS\033[0m\n" "$1"; }
fail() { FAILED=$((FAILED + 1)); printf "  %-55s \033[31mFAIL\033[0m: %s\n" "$1" "$2"; }

active_pane() {
    tmux display-message -t "$1" -p '#{pane_id}'
}

pane_list() {
    tmux list-panes -t "$1" -F '#{pane_id}'
}

settle() { sleep 0.15; }

new_session() {
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    tmux new-session -d -s "$SESSION" -x 120 -y 40
    settle
}

# Run hypr-nav inside a tmux pane (so TMUX env is set)
# Uses a marker file to detect completion instead of fixed sleep.
# Usage: run_nav <pane_id> <args...>
run_nav() {
    local pane="$1"; shift
    local marker="/tmp/hypr-nav-done-$$"
    rm -f "$marker"
    tmux send-keys -t "$pane" "$HYPR_NAV $* 2>/dev/null; touch $marker" Enter
    # Wait up to 2s for completion
    for _ in $(seq 1 20); do
        [[ -f "$marker" ]] && break
        sleep 0.1
    done
    rm -f "$marker"
}

# ── Prerequisite checks ───────────────────────────────────────────────

printf "\n=== hypr-nav integration tests ===\n\n"

if ! command -v tmux &>/dev/null; then
    echo "SKIP: tmux not installed"
    exit 0
fi

if [[ ! -x "$HYPR_NAV" ]]; then
    echo "FAIL: hypr-nav not built. Run 'make' first."
    exit 1
fi

# ── Test: tmux pane navigation (--from-vim path) ──────────────────────

printf "tmux pane navigation:\n"

new_session
tmux split-window -h -t "$SESSION"
settle

PANES=($(pane_list "$SESSION"))
LEFT="${PANES[0]}"
RIGHT="${PANES[1]}"

# Focus the left pane
tmux select-pane -t "$LEFT"
settle

# Navigate right from left pane
run_nav "$LEFT" "r --from-vim"

PANE_AFTER=$(active_pane "$SESSION")
if [[ "$PANE_AFTER" == "$RIGHT" ]]; then
    pass "navigate right moves to adjacent pane"
else
    fail "navigate right moves to adjacent pane" "expected=$RIGHT got=$PANE_AFTER"
fi

# At rightmost pane — navigate right should stay
run_nav "$RIGHT" "r --from-vim"

PANE_AFTER=$(active_pane "$SESSION")
if [[ "$PANE_AFTER" == "$RIGHT" ]]; then
    pass "navigate right at edge stays in same pane"
else
    fail "navigate right at edge stays in same pane" "pane changed to $PANE_AFTER"
fi

# Navigate back left
run_nav "$RIGHT" "l --from-vim"

PANE_AFTER=$(active_pane "$SESSION")
if [[ "$PANE_AFTER" == "$LEFT" ]]; then
    pass "navigate left moves back"
else
    fail "navigate left moves back" "expected=$LEFT got=$PANE_AFTER"
fi

# ── Test: wrap-around detection (vertical) ────────────────────────────

printf "\nwrap-around detection:\n"

new_session
tmux split-window -v -t "$SESSION"
settle

PANES=($(pane_list "$SESSION"))
TOP="${PANES[0]}"
BOTTOM="${PANES[1]}"

# Focus bottom pane
tmux select-pane -t "$BOTTOM"
settle

# Down from bottom — should NOT wrap
run_nav "$BOTTOM" "d --from-vim"

PANE_AFTER=$(active_pane "$SESSION")
if [[ "$PANE_AFTER" == "$BOTTOM" ]]; then
    pass "down from bottom pane does not wrap"
else
    fail "down from bottom pane does not wrap" "wrapped to $PANE_AFTER"
fi

# Up from bottom — should move to top
run_nav "$BOTTOM" "u --from-vim"

PANE_AFTER=$(active_pane "$SESSION")
if [[ "$PANE_AFTER" == "$TOP" ]]; then
    pass "up from bottom moves to top"
else
    fail "up from bottom moves to top" "expected=$TOP got=$PANE_AFTER"
fi

# Up from top — should NOT wrap
run_nav "$TOP" "u --from-vim"

PANE_AFTER=$(active_pane "$SESSION")
if [[ "$PANE_AFTER" == "$TOP" ]]; then
    pass "up from top pane does not wrap"
else
    fail "up from top pane does not wrap" "wrapped to $PANE_AFTER"
fi

# ── Test: vim detection ───────────────────────────────────────────────

printf "\nvim detection:\n"

new_session

PANE=$(active_pane "$SESSION")

# Start nvim in the pane — wait longer for it to initialize
tmux send-keys -t "$PANE" 'nvim --clean -c "set noswapfile"' Enter
sleep 1

CMD=$(tmux display-message -t "$PANE" -p '#{pane_current_command}')
CMD_LOWER=$(echo "$CMD" | tr '[:upper:]' '[:lower:]')

if [[ "$CMD_LOWER" == *vim* ]]; then
    pass "detects vim running in pane (command=$CMD)"
else
    fail "detects vim running in pane" "got command='$CMD'"
fi

# Exit vim
tmux send-keys -t "$PANE" Escape ':q!' Enter
sleep 0.5

CMD=$(tmux display-message -t "$PANE" -p '#{pane_current_command}')
CMD_LOWER=$(echo "$CMD" | tr '[:upper:]' '[:lower:]')

if [[ "$CMD_LOWER" != *vim* ]]; then
    pass "does not detect vim after exit (command=$CMD)"
else
    fail "does not detect vim after exit" "still got command='$CMD'"
fi

# ── Test: 3-pane grid navigation ──────────────────────────────────────

printf "\n3-pane navigation:\n"

new_session
tmux split-window -h -t "$SESSION"
settle
tmux split-window -v -t "$SESSION"
settle

PANES=($(pane_list "$SESSION"))
LEFT="${PANES[0]}"
TOP_RIGHT="${PANES[1]}"
BOTTOM_RIGHT="${PANES[2]}"

# Focus left pane
tmux select-pane -t "$LEFT"
sleep 0.2

# Left → Right
run_nav "$LEFT" "r --from-vim"
PANE_AFTER=$(active_pane "$SESSION")
if [[ "$PANE_AFTER" != "$LEFT" ]]; then
    pass "left to right in 3-pane layout"
else
    fail "left to right in 3-pane layout" "pane didn't change"
fi

# Top-right → Bottom-right (down)
tmux select-pane -t "$TOP_RIGHT"
settle
run_nav "$TOP_RIGHT" "d --from-vim"
PANE_AFTER=$(active_pane "$SESSION")
if [[ "$PANE_AFTER" == "$BOTTOM_RIGHT" ]]; then
    pass "top-right to bottom-right (down)"
else
    fail "top-right to bottom-right (down)" "expected=$BOTTOM_RIGHT got=$PANE_AFTER"
fi

# Bottom-right → Left (left)
run_nav "$BOTTOM_RIGHT" "l --from-vim"
PANE_AFTER=$(active_pane "$SESSION")
if [[ "$PANE_AFTER" == "$LEFT" ]]; then
    pass "bottom-right to left (left)"
else
    fail "bottom-right to left (left)" "expected=$LEFT got=$PANE_AFTER"
fi

# ── Test: verbose output ──────────────────────────────────────────────

printf "\nverbose output:\n"

# Verbose test can run outside tmux since we just check stderr output
new_session
tmux split-window -h -t "$SESSION"
settle

# Run verbose directly (it will fail at tmux commands but still produce debug output)
VERBOSE_OUT=$("$HYPR_NAV" r --from-vim --verbose 2>&1 >/dev/null || true)

if echo "$VERBOSE_OUT" | grep -q "\[hypr-nav\]"; then
    pass "verbose mode produces debug output"
else
    fail "verbose mode produces debug output" "no [hypr-nav] prefix found"
fi

if echo "$VERBOSE_OUT" | grep -q "direction=r"; then
    pass "verbose output includes direction"
else
    fail "verbose output includes direction" "missing direction in output"
fi

if echo "$VERBOSE_OUT" | grep -q "from-vim"; then
    pass "verbose output includes from-vim flag"
else
    fail "verbose output includes from-vim flag" "missing from-vim in output"
fi

# ── Summary ───────────────────────────────────────────────────────────

TOTAL=$((PASSED + FAILED))
printf "\n%d/%d integration tests passed\n\n" "$PASSED" "$TOTAL"
[[ "$FAILED" -eq 0 ]]
