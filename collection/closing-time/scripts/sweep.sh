#!/usr/bin/env bash
# closing-time sweep — background worker
# Runs during the interactive Q&A phases of closing-time. Pushes already-committed
# work, auto-commits new files under whitelist paths, and optionally refreshes a
# code index where configured. Writes status to a file the seal phase reads at
# the end.
#
# Usage:
#   bash sweep.sh start <session_tag>   # fires and exits, leaving a background worker
#   bash sweep.sh status <session_tag>  # prints the status file contents
#   bash sweep.sh push <session_tag>    # push pending commits (operator-approved)
#   bash sweep.sh cancel <session_tag>  # kill the background worker
#
# State root defaults to ~/.closing-time/state; override with CLOSING_TIME_STATE.
# The status file lives at: $STATE_ROOT/sweep/closing-sweep-<session_tag>.status

set -u

# Self-locating: derive script + config dirs from this file's own location so
# the sweep always references its own bundled config.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STATE_ROOT="${CLOSING_TIME_STATE:-$HOME/.closing-time/state}"
SWEEP_DIR="$STATE_ROOT/sweep"
mkdir -p "$SWEEP_DIR"

MODE="${1:-}"
TAG="${2:-$(date +%s)}"
STATUS_FILE="$SWEEP_DIR/closing-sweep-${TAG}.status"
LOG_FILE="$SWEEP_DIR/closing-sweep-${TAG}.log"
PID_FILE="$SWEEP_DIR/closing-sweep-${TAG}.pid"
CONFIG="$DIR/../config/sweep-paths.conf"

if [ -z "$MODE" ]; then
    echo "Usage: sweep.sh <start|status|worker|push|cancel> [session_tag]" >&2
    exit 2
fi

# -----------------------------------------------------------------------------
# WORKER — the actual sweep. Forked by 'start'.
# -----------------------------------------------------------------------------
if [ "$MODE" = "worker" ]; then
    exec >> "$LOG_FILE" 2>&1
    echo "[$(date -u +%FT%TZ)] sweep worker starting (tag=$TAG)"

    # Status entries format:
    #   <repo> | <action> | <detail>
    # Actions: push | commit | analyze | skip | error

    : > "$STATUS_FILE"

    [ -f "$CONFIG" ] || {
        echo "[error] no config at $CONFIG" | tee -a "$STATUS_FILE"
        rm -f "$PID_FILE"
        exit 1
    }

    while IFS='|' read -r repo_raw globs_raw gitnexus_raw <&3; do
        # skip comments / blanks
        [[ "$repo_raw" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${repo_raw// }" ]] && continue

        REPO=$(eval echo "${repo_raw// /}")
        GLOBS=$(echo "$globs_raw" | xargs)
        RUN_GITNEXUS=$(echo "$gitnexus_raw" | xargs)

        if [ ! -d "$REPO/.git" ]; then
            echo "$REPO | skip | not a git repo" | tee -a "$STATUS_FILE"
            continue
        fi

        cd "$REPO" || { echo "$REPO | error | cd failed" | tee -a "$STATUS_FILE"; continue; }

        # ----- stage untracked files matching globs -----
        # Staleness guard: skip files modified within STALENESS_THRESHOLD_SEC (5 min).
        # Rationale: any file currently being written by another process will have a
        # recent mtime. Skipping it lets the next closing-time run pick it up after
        # it settles, avoiding a race with in-flight work.
        STALENESS_THRESHOLD_SEC=300
        NOW=$(date +%s)
        STAGED_ANY=0
        SKIPPED_FRESH=0
        if [ -n "$GLOBS" ]; then
            # Expand globs against untracked files
            UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null || true)
            if [ -n "$UNTRACKED" ]; then
                while IFS= read -r file; do
                    [ -z "$file" ] && continue
                    for glob in $GLOBS; do
                        # shellcheck disable=SC2053
                        if [[ "$file" == $glob ]]; then
                            # Check mtime: skip if modified in the last threshold window.
                            if [ -e "$file" ]; then
                                MTIME=$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null || echo 0)
                                AGE=$((NOW - MTIME))
                                if [ "$AGE" -lt "$STALENESS_THRESHOLD_SEC" ]; then
                                    SKIPPED_FRESH=$((SKIPPED_FRESH + 1))
                                    break
                                fi
                            fi
                            git add -- "$file" && STAGED_ANY=1
                            break
                        fi
                    done
                done <<< "$UNTRACKED"
            fi
        fi
        if [ "$SKIPPED_FRESH" -gt 0 ]; then
            echo "$REPO | skip | ${SKIPPED_FRESH} file(s) too fresh (< 5 min old, likely in-flight)" | tee -a "$STATUS_FILE"
        fi

        # ----- secret/sensitivity scan on staged content -----
        # Abort the commit if staged content matches any pattern in
        # config/sensitivity-patterns.txt. Writes matches to a per-repo scan log.
        if [ $STAGED_ANY -eq 1 ] && ! git diff --cached --quiet; then
            SCAN_LOG="$SWEEP_DIR/closing-sweep-${TAG}-scan-$(basename "$REPO").log"
            STAGED_FILES=$(git diff --cached --name-only)
            SCAN_HITS=$(echo "$STAGED_FILES" | bash "$DIR/secret-scan.sh" 2>/dev/null || true)
            if [ -n "$SCAN_HITS" ]; then
                HIT_COUNT=$(echo "$SCAN_HITS" | wc -l | tr -d ' ')
                echo "$SCAN_HITS" > "$SCAN_LOG"
                # Unstage everything we added this pass so we don't commit compromised content
                echo "$STAGED_FILES" | while IFS= read -r f; do [ -n "$f" ] && git reset HEAD -- "$f" >/dev/null 2>&1; done
                echo "$REPO | error | secret-scan blocked commit (${HIT_COUNT} matches; see $SCAN_LOG)" | tee -a "$STATUS_FILE"
                STAGED_ANY=0
            fi
        fi

        # ----- commit staged content (auto-msg) -----
        COMMITTED_HERE=0
        if [ $STAGED_ANY -eq 1 ] && ! git diff --cached --quiet; then
            FILE_COUNT=$(git diff --cached --name-only | wc -l | tr -d ' ')
            MSG="closing-time auto-commit: ${FILE_COUNT} new file(s) [automated]

Whitelisted paths from sweep-paths.conf. Modified tracked files are
intentionally NOT included. Content passed the secret-scan gate.

Automated by: closing-time-sweep (Pollock 2026)"
            if git commit -m "$MSG" --quiet; then
                echo "$REPO | commit | ${FILE_COUNT} new file(s) auto-committed" | tee -a "$STATUS_FILE"
                COMMITTED_HERE=1
            else
                echo "$REPO | error | commit failed" | tee -a "$STATUS_FILE"
            fi
        fi

        # ----- NOTE unpushed commits, but do NOT push automatically -----
        # Push is gated by operator approval at Phase 5. See sweep.sh push mode.
        UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
        if [ -n "$UPSTREAM" ]; then
            AHEAD=$(git rev-list --count "$UPSTREAM"..HEAD 2>/dev/null || echo 0)
            if [ "$AHEAD" -gt 0 ]; then
                echo "$REPO | pending-push | ${AHEAD} commit(s) ready to push (awaiting approval)" | tee -a "$STATUS_FILE"
            fi
        else
            echo "$REPO | skip | no upstream configured" | tee -a "$STATUS_FILE"
        fi

        # ----- code-index refresh if configured + something committed -----
        if [ "$RUN_GITNEXUS" = "true" ] && [ $COMMITTED_HERE -eq 1 ]; then
            if command -v npx >/dev/null 2>&1; then
                if npx --no-install gitnexus analyze >/dev/null 2>&1; then
                    echo "$REPO | analyze | gitnexus index refreshed" | tee -a "$STATUS_FILE"
                else
                    echo "$REPO | error | gitnexus analyze failed" | tee -a "$STATUS_FILE"
                fi
            else
                echo "$REPO | skip | npx not found" | tee -a "$STATUS_FILE"
            fi
        fi

    done 3< "$CONFIG"

    # Emit summary so seal phase can distinguish "worker ran clean" from "worker broken"
    ACTION_COUNT=$(grep -cE '\| (commit|push|analyze|error) \|' "$STATUS_FILE" 2>/dev/null || true)
    ACTION_COUNT=${ACTION_COUNT:-0}
    echo "_summary_ | done | ${ACTION_COUNT} action(s) taken" >> "$STATUS_FILE"

    echo "[$(date -u +%FT%TZ)] sweep worker done"
    rm -f "$PID_FILE"
    exit 0
fi

# -----------------------------------------------------------------------------
# START — fire the worker in background and return immediately.
# Uses POSIX double-fork via inline Python so the worker survives aggressive
# sandbox reaping. Some agent runtimes kill children on tool return;
# `nohup ... &` alone is insufficient on macOS in that environment (reproducibly
# delayed worker fire by 10+ minutes when backgrounded with `& disown`, so the
# seal phase status check missed the file).
# -----------------------------------------------------------------------------
if [ "$MODE" = "start" ]; then
    : > "$STATUS_FILE"
    mkdir -p "$(dirname "$PID_FILE")"
    python3 - "$0" "$TAG" "$PID_FILE" <<'PYEOF'
import os, sys
script, tag, pid_file = sys.argv[1:4]

# First fork
if os.fork() != 0:
    os._exit(0)
# Detach from controlling terminal / pgroup
os.setsid()
# Second fork so we cannot reacquire a TTY and are reparented to init
if os.fork() != 0:
    os._exit(0)

# Close inherited fds and reopen stdio to /dev/null
for fd in (0, 1, 2):
    try:
        os.close(fd)
    except OSError:
        pass
devnull = os.open(os.devnull, os.O_RDWR)
os.dup2(devnull, 0)
os.dup2(devnull, 1)
os.dup2(devnull, 2)

# Record our pid (the now-detached worker)
with open(pid_file, "w") as f:
    f.write(str(os.getpid()))

# Replace this Python process with the bash worker. Exec preserves pid and
# keeps the file descriptors we just set up.
os.execvp("bash", ["bash", script, "worker", tag])
PYEOF
    echo "sweep started (tag=$TAG)"
    exit 0
fi

# -----------------------------------------------------------------------------
# CANCEL — kill the background worker. Called if closing-time is abandoned
# mid-protocol, so the sweep doesn't keep running and committing unattended.
# -----------------------------------------------------------------------------
if [ "$MODE" = "cancel" ]; then
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            kill "$PID" 2>/dev/null && echo "sweep cancelled (tag=$TAG, pid=$PID)"
        else
            echo "sweep worker already done (tag=$TAG)"
        fi
        rm -f "$PID_FILE"
    else
        echo "no sweep pid file for tag=$TAG (worker may have finished or never started)"
    fi
    exit 0
fi

# -----------------------------------------------------------------------------
# STATUS — read and print the status file (for seal phase).
# -----------------------------------------------------------------------------
if [ "$MODE" = "status" ]; then
    # If PID file exists and process is alive, wait up to 15s for it to finish.
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        for _ in $(seq 1 15); do
            if kill -0 "$PID" 2>/dev/null; then
                sleep 1
            else
                break
            fi
        done
        if kill -0 "$PID" 2>/dev/null; then
            echo "[sweep still running in background; pid=$PID]"
            echo "---"
        fi
    fi
    if [ -f "$STATUS_FILE" ]; then
        cat "$STATUS_FILE"
    else
        echo "[no status file found for tag=$TAG]"
    fi
    exit 0
fi

# -----------------------------------------------------------------------------
# PUSH — called by Phase 5 only after operator approval. Pushes all repos in
# the whitelist that have unpushed commits. Writes outcome into STATUS_FILE.
# -----------------------------------------------------------------------------
if [ "$MODE" = "push" ]; then
    [ -f "$CONFIG" ] || { echo "[error] no config at $CONFIG" >&2; exit 1; }
    RESULT=""
    while IFS='|' read -r repo_raw globs_raw gitnexus_raw <&3; do
        [[ "$repo_raw" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${repo_raw// }" ]] && continue
        REPO="${repo_raw// /}"
        REPO="${REPO/#\~/$HOME}"
        [ -d "$REPO/.git" ] || continue
        cd "$REPO" || continue
        UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
        [ -n "$UPSTREAM" ] || continue
        AHEAD=$(git rev-list --count "$UPSTREAM"..HEAD 2>/dev/null || echo 0)
        [ "$AHEAD" -gt 0 ] || continue
        if git push --quiet 2>&1; then
            LINE="$REPO | push | pushed ${AHEAD} commit(s)"
        else
            LINE="$REPO | error | push failed"
        fi
        echo "$LINE"
        [ -f "$STATUS_FILE" ] && echo "$LINE" >> "$STATUS_FILE"
    done 3< "$CONFIG"
    exit 0
fi

echo "Unknown mode: $MODE" >&2
exit 2
