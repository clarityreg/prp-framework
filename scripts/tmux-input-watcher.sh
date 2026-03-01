#!/usr/bin/env bash
# tmux-input-watcher.sh — Notify when Claude Code or OpenCode needs input
#
# Hybrid detection:
#   Claude Code → screen-scrape via tmux capture-pane
#   OpenCode   → HTTP API at localhost:4096
#
# Usage:
#   ./scripts/tmux-input-watcher.sh          # run in foreground
#   ./scripts/tmux-input-watcher.sh &        # background
#   ./scripts/tmux-input-watcher.sh --kill   # stop background instance
#
# Requires: tmux, terminal-notifier (brew install terminal-notifier)

set -euo pipefail

POLL_INTERVAL="${POLL_INTERVAL:-3}"
OPENCODE_PORT="${OPENCODE_PORT:-4096}"
PIDFILE="${TMPDIR:-/tmp}/tmux-input-watcher.pid"
STATE_DIR="${TMPDIR:-/tmp}/tmux-input-watcher-state"
TERMINAL_APP="ghostty"

# ── Kill mode ─────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--kill" ]; then
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null && echo "Stopped watcher (PID $(cat "$PIDFILE"))" || echo "Process already gone"
        rm -f "$PIDFILE"
    else
        echo "No running watcher found"
    fi
    rm -rf "$STATE_DIR"
    exit 0
fi

# ── Dependency check ──────────────────────────────────────────────────────────
if ! command -v terminal-notifier >/dev/null 2>&1; then
    echo "Error: terminal-notifier not found. Run: brew install terminal-notifier" >&2
    exit 1
fi
if ! command -v tmux >/dev/null 2>&1; then
    echo "Error: tmux not found" >&2
    exit 1
fi

# Write PID for --kill
echo $$ > "$PIDFILE"
mkdir -p "$STATE_DIR"
trap 'rm -f "$PIDFILE"; rm -rf "$STATE_DIR"' EXIT

echo "tmux-input-watcher started (PID $$, polling every ${POLL_INTERVAL}s)"

# ── State helpers (file-based, bash 3 compatible) ─────────────────────────────
is_notified() {
    [ -f "$STATE_DIR/notified_${1}" ]
}
set_notified() {
    touch "$STATE_DIR/notified_${1}"
}
clear_notified() {
    rm -f "$STATE_DIR/notified_${1}"
}
get_pane_type() {
    local safe=$(echo "$1" | tr -d '%')
    if [ -f "$STATE_DIR/type_${safe}" ]; then
        cat "$STATE_DIR/type_${safe}"
    else
        echo ""
    fi
}
set_pane_type() {
    local safe=$(echo "$1" | tr -d '%')
    echo "$2" > "$STATE_DIR/type_${safe}"
}

# ── Detect what's running in a pane ───────────────────────────────────────────
detect_pane_type() {
    local pane_id="$1"

    # Check cache first
    local cached
    cached=$(get_pane_type "$pane_id")
    if [ -n "$cached" ]; then
        echo "$cached"
        return
    fi

    # Get the command running in the pane
    local cmd
    cmd=$(tmux display-message -t "$pane_id" -p '#{pane_current_command}' 2>/dev/null || echo "")

    # Check pane content for identifying markers
    local content
    content=$(tmux capture-pane -t "$pane_id" -p -S -20 2>/dev/null || echo "")

    if echo "$cmd" | grep -qi "claude"; then
        set_pane_type "$pane_id" "claude"
        echo "claude"
    elif echo "$cmd" | grep -qi "opencode"; then
        set_pane_type "$pane_id" "opencode"
        echo "opencode"
    elif echo "$content" | grep -qiE 'claude|anthropic'; then
        set_pane_type "$pane_id" "claude"
        echo "claude"
    elif echo "$content" | grep -qiE 'opencode|open-code'; then
        set_pane_type "$pane_id" "opencode"
        echo "opencode"
    else
        echo "unknown"
    fi
}

# ── Claude Code: screen scrape ────────────────────────────────────────────────
check_claude_needs_input() {
    local pane_id="$1"
    local content
    content=$(tmux capture-pane -t "$pane_id" -p -S -8 2>/dev/null || echo "")

    # Permission / approval prompts
    if echo "$content" | grep -qE 'Do you want to proceed|Allow once|Allow always'; then
        echo "permission"
        return
    fi

    # Yes/No selection list
    if echo "$content" | grep -qE '(❯|›)\s*(1\.\s*Yes|Yes$)'; then
        echo "confirmation"
        return
    fi

    # Multi-option question from agent
    if echo "$content" | grep -qE '(❯|›)\s*(1\.|2\.|3\.)'; then
        echo "question"
        return
    fi

    # Explicit Y/n or y/N
    if echo "$content" | grep -qE '\[(Y/n|y/N)\]'; then
        echo "confirm-yn"
        return
    fi

    echo ""
}

# ── OpenCode: HTTP API ────────────────────────────────────────────────────────
check_opencode_needs_input() {
    # Check pending permissions via API
    local perms
    perms=$(curl -sf "http://localhost:${OPENCODE_PORT}/permission/" 2>/dev/null || echo "")

    if [ -n "$perms" ] && [ "$perms" != "[]" ] && [ "$perms" != "null" ]; then
        echo "permission"
        return
    fi

    # Check session status
    local status
    status=$(curl -sf "http://localhost:${OPENCODE_PORT}/session/status" 2>/dev/null || echo "")

    if echo "$status" | grep -q '"idle"'; then
        echo "idle"
        return
    fi

    echo ""
}

# ── Notification ──────────────────────────────────────────────────────────────
notify() {
    local pane_ref="$1"
    local pane_id="$2"
    local tool="$3"
    local reason="$4"
    local window_name="$5"

    local title
    case "$tool" in
        claude)   title="Claude Code" ;;
        opencode) title="OpenCode" ;;
        *)        title="Agent" ;;
    esac

    # Show window name prominently, fall back to numeric ref
    local subtitle
    if [ -n "$window_name" ]; then
        subtitle="${window_name} (${pane_ref})"
    else
        subtitle="$pane_ref"
    fi

    local message
    case "$reason" in
        permission)   message="Needs permission approval" ;;
        confirmation) message="Waiting for Yes/No" ;;
        question)     message="Asking you a question" ;;
        confirm-yn)   message="Waiting for y/n" ;;
        idle)         message="Session idle — waiting for input" ;;
        *)            message="Needs your attention" ;;
    esac

    terminal-notifier \
        -title "$title" \
        -subtitle "$subtitle" \
        -message "$message" \
        -sound "Ping" \
        -group "tmux-${pane_id}" \
        -execute "osascript -e 'tell application \"$TERMINAL_APP\" to activate' && tmux select-pane -t ${pane_id}" \
        2>/dev/null || true
}

# ── Main loop ─────────────────────────────────────────────────────────────────
cycle=0
while true; do
    # Every 30 cycles (~90s), clear the type cache so we re-detect
    cycle=$((cycle + 1))
    if [ $((cycle % 30)) -eq 0 ]; then
        rm -f "$STATE_DIR"/type_* 2>/dev/null || true
    fi

    # Iterate all tmux panes — capture session:window.pane, pane_id, and window_name
    tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_id} #{window_name}' 2>/dev/null | while read -r line; do
        pane_ref=$(echo "$line" | awk '{print $1}')
        pane_id=$(echo "$line" | awk '{print $2}')
        window_name=$(echo "$line" | awk '{$1=""; $2=""; print}' | sed 's/^ *//')

        [ -z "$pane_id" ] && continue

        # Sanitize pane_id for filenames (remove %)
        safe_id=$(echo "$pane_id" | tr -d '%')

        ptype=$(detect_pane_type "$pane_id")
        [ "$ptype" = "unknown" ] && continue

        reason=""
        case "$ptype" in
            claude)
                reason=$(check_claude_needs_input "$pane_id")
                ;;
            opencode)
                reason=$(check_opencode_needs_input)
                ;;
        esac

        if [ -n "$reason" ]; then
            if ! is_notified "$safe_id"; then
                notify "$pane_ref" "$pane_id" "$ptype" "$reason" "$window_name"
                set_notified "$safe_id"
            fi
        else
            clear_notified "$safe_id"
        fi
    done

    sleep "$POLL_INTERVAL"
done
