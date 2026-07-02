#!/usr/bin/env bash
# discord-stack-facts.sh — Discord-wide stack fact sheet for closing-time-fleet.
#
# READ-ONLY and idempotent. Running this NEVER changes state (the one write is the
# optional `--emit` bus event, which is fire-and-forget telemetry, not state).
#
# It replaces session-fact-sheet.py for a Discord agent fleet, where the CLI-session-bound
# extractor grabs the wrong session. This script builds the agent roster, captures
# VERIFIED liveness (tmux pane ground truth, not a proxy probe), pulls today's
# work-shipped from the bus, consumes the auth-heartbeat, and emits a per-agent table
# plus a stack-wide synthesis section.
#
# Usage:
#   discord-stack-facts.sh                 # human-readable report to stdout
#   discord-stack-facts.sh --date 2026-06-25
#   discord-stack-facts.sh --emit          # also emit a bus telemetry event (the ONLY write)
#   discord-stack-facts.sh --ghost-hours   # also print the home-channel Ghost Hours timing first-cut
#
# CONFIGURATION — this script probes a specific fleet runtime shape (tmux panes,
# a JSONL event bus, an auth-heartbeat, a message-archive SQLite store). Adapt
# these probes to your fleet's runtime. All knobs are env vars, optionally set in
# a config file sourced at startup:
#
#   FLEET_CONF                 config file to source (default ~/.closing-time/fleet.conf)
#   FLEET_OPERATOR_USER_ID     the operator's Discord user id      (REQUIRED for --ghost-hours)
#   FLEET_HOME_CHANNEL_ID      the coordinator's home channel id   (REQUIRED for --ghost-hours)
#   FLEET_BUS_FILE             JSONL event bus                     (default ~/.closing-time/events.jsonl)
#   FLEET_CHANNELS_JSON        map of agent name -> home channel id (optional)
#   FLEET_HEARTBEAT_STATE      auth-heartbeat baseline-expiry dir  (optional)
#   FLEET_MESSAGE_DB           message-archive SQLite store with a `messages`
#                              table (channel_id, author_id, created_at) (optional)
#   FLEET_AGENT_DIRS           space-separated dirs whose subdirs name agents
#                              (default "$HOME/agents $HOME/.claude-agents")
#   FLEET_GATEWAY_LIST_CMD     command printing gateway-runtime agent names,
#                              one per line (optional; e.g. "mygateway list")
#   FLEET_BUS_ONLY_AGENTS      agents that ship on the bus but have no dir/pane
#   FLEET_DECOMMISSIONED       agents to exclude from the roster
#   FLEET_COORDINATOR          the agent running this close (default "coordinator")
#   FLEET_EMIT_BIN             bus emit script (default: the closing-time emit adapter)
#
# Honesty contract (the whole reason this skill exists — see SKILL.md):
#   - Liveness is VERIFIED against the agent's real tmux pane, never a proxy probe.
#   - Every captured fact names its evidence source.
#   - If a source is UNREACHABLE for an agent, this prints "UNREACHABLE" for THAT agent.
#     One silent source must never read as "all clean" (the false-green failure mode).
#   - When the pane and the auth-heartbeat DISAGREE, both are printed and the divergence
#     is flagged.

set -uo pipefail

# ---- config -----------------------------------------------------------------
FLEET_CONF="${FLEET_CONF:-$HOME/.closing-time/fleet.conf}"
# shellcheck disable=SC1090
[ -f "$FLEET_CONF" ] && . "$FLEET_CONF"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUS_FILE="${FLEET_BUS_FILE:-$HOME/.closing-time/events.jsonl}"
CHANNELS_JSON="${FLEET_CHANNELS_JSON:-}"
HEARTBEAT_STATE="${FLEET_HEARTBEAT_STATE:-}"
MESSAGE_DB="${FLEET_MESSAGE_DB:-}"
AGENT_DIRS="${FLEET_AGENT_DIRS:-$HOME/agents $HOME/.claude-agents}"
GATEWAY_LIST_CMD="${FLEET_GATEWAY_LIST_CMD:-}"
BUS_ONLY_AGENTS="${FLEET_BUS_ONLY_AGENTS:-}"
EMIT_BIN="${FLEET_EMIT_BIN:-$SCRIPT_DIR/../../closing-time/scripts/adapters/emit-event.sh}"
COORDINATOR="${FLEET_COORDINATOR:-coordinator}"

# Operator + home-channel identities. Placeholders by design — set your own.
OPERATOR_USER_ID="${FLEET_OPERATOR_USER_ID:-}"      # e.g. 000000000000000001
HOME_CHANNEL_ID="${FLEET_HOME_CHANNEL_ID:-}"        # e.g. 000000000000000002

# Decommissioned agents — excluded from the roster.
DECOMMISSIONED="${FLEET_DECOMMISSIONED:-}"

# Pane evidence is WEAK on its own and must never be the sole basis for an ALIVE verdict.
# The startup banner prints at LAUNCH, before any API call — a freshly-relaunched but
# 401-dead agent shows the banner and an empty prompt. So banner-present == LAUNCHED, not
# ALIVE. The real liveness authority is the auth-heartbeat (it actually probes the token);
# the final verdict FUSES heartbeat + pane (see fuse_verdict). The pane is only used to
# distinguish process-up (ZOMBIE) from process-down (DOWN) once the heartbeat says FAILED,
# and to detect a real post-banner turn for the ALIVE upgrade.
#
# BANNER_RE: the launch banner shape ("Sonnet 4.6 ... Claude Max", "Claude Code vN").
# Anchored so a grep echo / chat mention can't false-positive. Adapt to your runtime's banner.
BANNER_RE='(Sonnet|Opus|Haiku)[[:space:]]+[0-9].*(Claude Max|Claude Pro|effort)|Claude Code v[0-9]'
# DEAD_PANE_RE: a real auth error as it renders in the pane. Anchored to line-start (the
# error chrome begins the line) so a "401" echoed mid-scrollback by a grep, a log paste,
# or a chat about errors does NOT false-zombie. We also scope the capture to the tail
# after the last prompt (see pane_read) to keep stray scrollback out.
DEAD_PANE_RE='^[[:space:]]*(API Error: 401|Invalid authentication credentials|401 Unauthorized|Error: 401|invalid_request_error)'

# ---- args -------------------------------------------------------------------
DATE="$(date +%Y-%m-%d)"
DO_EMIT=0
DO_GH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --date) DATE="$2"; shift 2 ;;
    --emit) DO_EMIT=1; shift ;;
    --ghost-hours|--gh) DO_GH=1; shift ;;
    -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

have() { command -v "$1" >/dev/null 2>&1; }

# ---- roster build (union of sources, minus decommissioned) ------------------
# Each roster line: name|runtime|home_channel_id|tmux_session
# tmux_session empty => no dedicated pane (liveness via heartbeat/bus only).

is_decommissioned() {
  local n="$1"
  for d in $DECOMMISSIONED; do [ "$n" = "$d" ] && return 0; done
  return 1
}

build_roster() {
  # Source 1: tmux *-discord sessions (the Discord runtimes — strongest live signal).
  local tmux_sessions
  tmux_sessions="$(tmux ls 2>/dev/null | sed 's/:.*//' || true)"

  # Source 2: agent workspace dirs (subdirectory name == agent name).
  local cc_agents=""
  local root d b
  for root in $AGENT_DIRS; do
    for d in "$root"/*; do
      [ -d "$d" ] || continue
      b="$(basename "$d")"
      case "$b" in _*|*.sh) continue ;; esac
      cc_agents="$cc_agents $b"
    done
  done

  # Source 3: gateway-runtime agents (optional external command, one name per line).
  local gateway_agents=""
  if [ -n "$GATEWAY_LIST_CMD" ]; then
    gateway_agents="$($GATEWAY_LIST_CMD 2>/dev/null | tr '\n' ' ' || true)"
  fi

  # Source 4: channels JSON agent home channels (gives us channel ids).

  # Union all names.
  local all="$cc_agents $gateway_agents"
  # Add agents inferred from tmux session names (strip -discord suffix).
  local s
  for s in $tmux_sessions; do
    case "$s" in *-discord) all="$all ${s%-discord}" ;; esac
  done
  # Bus-only agents ship on the bus but have no agent dir / gateway profile.
  all="$all $BUS_ONLY_AGENTS"

  # Dedup + drop decommissioned + drop non-agent noise.
  local seen=" " n
  for n in $all; do
    [ -n "$n" ] || continue
    case "$n" in default|""|current) continue ;; esac   # 'default' gateway profile == plumbing, not an agent
    is_decommissioned "$n" && continue
    case "$seen" in *" $n "*) continue ;; esac
    seen="$seen$n "

    # Resolve a tmux session for this agent if one exists.
    local tsession=""
    for s in $tmux_sessions; do [ "$s" = "${n}-discord" ] && tsession="$s"; done

    # Resolve a home channel id from channels JSON (best-effort).
    local chan=""
    if [ -n "$CHANNELS_JSON" ] && [ -f "$CHANNELS_JSON" ] && have jq; then
      chan="$(jq -r --arg k "$n" '.channels[$k] // empty' "$CHANNELS_JSON" 2>/dev/null)"
    fi
    [ "$n" = "$COORDINATOR" ] && [ -n "$HOME_CHANNEL_ID" ] && chan="$HOME_CHANNEL_ID"

    # Runtime classification.
    local runtime="unknown"
    for root in $AGENT_DIRS; do [ -d "$root/$n" ] && runtime="agent-dir"; done
    case " $gateway_agents " in *" $n "*) runtime="gateway" ;; esac
    [ -n "$tsession" ] && runtime="discord-pane"

    echo "${n}|${runtime}|${chan}|${tsession}"
  done
}

# sanitize: strip the field delimiter (|), newlines, and control chars out of any string
# that becomes a TABLE_ROWS field. A raw | inside evidence shifts every downstream column
# when the row is re-parsed with `IFS='|' read`. We build rows with a US (0x1f)
# control-char delimiter that cannot appear in captured text, AND scrub | from evidence as
# belt-and-suspenders so the human-readable evidence stays clean too.
sanitize() { printf '%s' "$1" | tr '|\n\r\t' '/   ' | tr -s ' '; }

# ---- pane read (PROCESS-level signal only — NOT the liveness authority) ------
# The pane tells us whether the process is up and whether it is rendering a 401 error.
# It does NOT decide ALIVE — that is fuse_verdict's job (heartbeat is the auth authority).
# Returns: PANE_STATE|EVIDENCE
#   BANNER   — launch banner present, no 401 error in the tail (process up, auth UNPROVEN)
#   TURN     — banner present AND a real post-banner response/tool line (process up + did work)
#   PANE-401 — a real auth error renders at line-start in the pane tail
#   NO-PANE  — no dedicated tmux session
#   QUIET    — pane present but neither banner nor 401 (e.g. banner scrolled out — UNPROVEN)
#   UNREACHABLE — capture failed
pane_read() {
  local tsession="$1"
  if [ -z "$tsession" ]; then echo "NO-PANE|no dedicated *-discord tmux session"; return; fi
  # Full scrollback for the banner (printed once at launch, may have scrolled).
  # </dev/null: this runs inside a `while read` here-string loop; tmux would eat its stdin.
  local full tail
  full="$(tmux capture-pane -p -S - -t "$tsession" 2>/dev/null </dev/null)"
  if [ -z "$full" ]; then echo "UNREACHABLE|tmux capture-pane returned empty for $tsession"; return; fi
  # For the 401 check, scope to the LAST prompt onward (the current turn), so a "401"
  # echoed earlier in scrollback by a grep/log-paste/chat cannot false-zombie.
  # The Claude Code prompt line is "❯". Take everything from the last "❯" to the end;
  # if no prompt found, fall back to the last 25 lines.
  tail="$(awk 'BEGIN{buf=""} /❯/{buf=""} {buf=buf $0 "\n"} END{print buf}' <<<"$full")"
  [ -z "$tail" ] && tail="$(tail -n 25 <<<"$full")"

  # DEAD: a real auth error at line-start in the current-turn tail (not stray scrollback).
  if grep -qiE "$DEAD_PANE_RE" <<<"$tail"; then
    local hit; hit="$(grep -iE "$DEAD_PANE_RE" <<<"$tail" | head -1 | sed 's/^[[:space:]]*//')"
    echo "PANE-401|$(sanitize "tail shows: ${hit:0:50}")"
    return
  fi
  # Banner present?
  if grep -qiE "$BANNER_RE" <<<"$full"; then
    local model; model="$(grep -iE 'Claude Max|Sonnet|Opus|Haiku|Claude Code v' <<<"$full" | head -1)"
    # Post-banner TURN: a real response/tool line after the banner. Claude Code renders
    # assistant turns with a "⏺" bullet and tool runs with "⎿"/"◯". If any of those appear
    # in the scrollback the process has actually transacted past launch.
    if grep -qE '⏺|⎿|◯' <<<"$full"; then
      echo "TURN|$(sanitize "banner + post-launch turn: ${model}")"
    else
      echo "BANNER|$(sanitize "launch banner only (no post-launch turn): ${model}")"
    fi
    return
  fi
  echo "QUIET|pane present, banner scrolled out / not visible (liveness UNPROVEN from pane)"
}

# ---- fused liveness verdict (heartbeat = authority, pane = process signal) ----
# Banner-present must NEVER yield ALIVE on its own.
# Verdict precedence:
#   heartbeat FAILED  -> ZOMBIE if process up (pane present), else DOWN. Banner cannot override.
#   heartbeat OK/NONE + pane TURN     -> ALIVE   (auth not-failed AND a real post-launch turn)
#   heartbeat OK      + pane BANNER   -> LAUNCHED (up, auth not-failed, but no proven turn)
#   heartbeat NONE    + pane BANNER   -> LAUNCHED (untracked: cannot prove ALIVE)
#   pane NO-PANE      + heartbeat OK/NONE -> UNVERIFIED (no pane, heartbeat didn't fail)
#   pane QUIET/UNREACHABLE            -> UNVERIFIED (cannot confirm; never ALIVE)
# Returns: VERDICT|EVIDENCE
fuse_verdict() {
  local pane_state="$1" pane_ev="$2" hb="$3" hb_ev="$4"
  if [ "$hb" = "FAILED" ]; then
    case "$pane_state" in
      NO-PANE|UNREACHABLE) echo "DOWN|heartbeat FAILED, no live pane — agent is down ($(sanitize "$hb_ev"))" ;;
      PANE-401)            echo "ZOMBIE|heartbeat FAILED + pane shows 401 — process up, auth dead" ;;
      *)                   echo "ZOMBIE|heartbeat FAILED, process up — banner does NOT override a dead token ($(sanitize "$hb_ev"))" ;;
    esac
    return
  fi
  # heartbeat is OK or NONE (not FAILED) below.
  case "$pane_state" in
    PANE-401)    echo "ZOMBIE|pane shows 401 (no heartbeat record, but pane proves auth error)" ;;
    TURN)        echo "ALIVE|$pane_ev" ;;
    BANNER)      echo "LAUNCHED|$pane_ev — up, auth not-flagged, but no proven post-launch turn" ;;
    QUIET)       echo "UNVERIFIED|pane up but liveness unproven; heartbeat ${hb} ($(sanitize "$hb_ev"))" ;;
    NO-PANE)     echo "UNVERIFIED|no pane; liveness from heartbeat only — ${hb} ($(sanitize "$hb_ev"))" ;;
    UNREACHABLE) echo "UNVERIFIED|pane capture failed; heartbeat ${hb} ($(sanitize "$hb_ev"))" ;;
    *)           echo "UNVERIFIED|unclassified pane state" ;;
  esac
}

# ---- last-response timestamp -------------------------------------------------
# For silent-zombie detection: when did this agent's bot last post in its home channel?
# Source: the message-archive SQLite store, keyed by the agent's home channel id. The
# store is a lagging archive — if it has no record we say UNREACHABLE for THIS agent
# (never silent-clean).
last_response() {
  local agent="$1" chan="$2"
  if [ -z "$chan" ]; then echo "no-home-channel"; return; fi
  if [ -z "$MESSAGE_DB" ] || [ ! -f "$MESSAGE_DB" ] || ! have sqlite3; then echo "UNREACHABLE(message-db)"; return; fi
  # Most recent non-operator message in the channel = an agent post.
  local ts
  ts="$(sqlite3 "$MESSAGE_DB" "SELECT MAX(created_at) FROM messages WHERE channel_id='$chan' AND author_id<>'$OPERATOR_USER_ID';" 2>/dev/null)"
  [ -z "$ts" ] && { echo "none-in-message-db"; return; }
  echo "$(sanitize "$ts")"
}

# ---- loose ends ---------------------------------------------------------------
# Open/flagged items the agent left today: bus failures it emitted + severity signals.
# This is a first-cut from the bus (the machine record); transcript-level open items in
# private channels the coordinator can't read are NOT covered here (documented limitation
# in SKILL.md).
loose_ends() {
  local agent="$1"
  if [ ! -f "$BUS_FILE" ]; then echo "UNREACHABLE(bus)"; return; fi
  local lines
  lines="$(grep "\"ts\": \"$DATE" "$BUS_FILE" 2>/dev/null \
    | grep -iE "\"source\": \"(${agent}|${agent}:[^\"]*|gateway:${agent}[^\"]*|auth-heartbeat:${agent})\"" \
    | grep -iE 'cron_failed|_failed|severity_signal|divergence|error|stalled|blocked')"
  if [ -z "$lines" ]; then echo "none on bus"; return; fi
  local n; n="$(printf '%s\n' "$lines" | grep -c .)"; n="${n//[^0-9]/}"
  local first; first="$(printf '%s\n' "$lines" | python3 -c "import sys,json; l=sys.stdin.readline(); print(json.loads(l).get('event_type','?')+': '+json.loads(l).get('subject','')[:45])" 2>/dev/null)"
  echo "$(sanitize "${n} flagged — e.g. ${first}")"
}

# ---- auth-heartbeat read (consume, don't reimplement) -------------------------
# Returns: HB_STATUS|detail  (read from today's bus *_auth_failed events + baseline-expiry files)
heartbeat_status() {
  local agent="$1"
  # Most recent auth-failed event today for this agent, if any.
  local failed
  failed="$(grep "\"ts\": \"$DATE" "$BUS_FILE" 2>/dev/null \
    | grep "\"source\": \"auth-heartbeat:$agent\"" \
    | grep "auth_failed" | tail -1)"
  if [ -n "$failed" ] && have python3; then
    local subj
    subj="$(echo "$failed" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('subject',''))" 2>/dev/null)"
    echo "FAILED|$(sanitize "$subj")"
    return
  fi
  # Baseline expiry file (informational — when the credential is set to expire).
  if [ -n "$HEARTBEAT_STATE" ]; then
    local bexp="$HEARTBEAT_STATE/$agent.baseline-expiry"
    if [ -f "$bexp" ]; then
      echo "OK|baseline-expiry $(cat "$bexp" 2>/dev/null)"
      return
    fi
  fi
  echo "NONE|no auth-heartbeat record (agent may not be heartbeat-tracked)"
}

# ---- work shipped today (bus, deduped to REAL outputs) ------------------------
# Counts the agent's real outputs on the bus today. A cron that ran and did nothing
# (posted=0 / filed=0 / "no new events" / 0 candidates) is NOT work shipped — it's an idle
# tick. We filter those no-op bodies out so the count reflects actual throughput, not the
# cron heartbeat. The filtering is done in python against each event's body.
work_shipped() {
  local agent="$1"
  if [ ! -f "$BUS_FILE" ]; then echo "0|UNREACHABLE: bus file missing"; return; fi
  local lines
  lines="$(grep "\"ts\": \"$DATE" "$BUS_FILE" 2>/dev/null \
    | grep -iE "\"source\": \"(${agent}|${agent}:[^\"]*|gateway:${agent}[^\"]*)\"" \
    | grep -iE 'cron_completed|cron_failed|severity_signal|commit_shipped|subagent_complete|session_stop|task_completed|_emitted')"
  if [ -z "$lines" ]; then echo "0|no work events on bus today"; return; fi
  # Python: drop no-op ticks, count the rest, summarize top event types. Emits "N|summary".
  local out
  out="$(printf '%s\n' "$lines" | python3 -c '
import sys,json,collections,re
NOOP = re.compile(r"posted=0|filed=0|no new events|0 new |0 candidate|count=0|nothing to|no candidates", re.I)
real=collections.Counter(); noop=0
for l in sys.stdin:
    try: j=json.loads(l)
    except: continue
    body=(j.get("body","") or "")+" "+(j.get("subject","") or "")
    et=j.get("event_type","?")
    if NOOP.search(body):
        noop+=1; continue
    real[et]+=1
n=sum(real.values())
summ="; ".join(f"{k}x{v}" for k,v in real.most_common(4)) or "—"
tag=f" (+{noop} idle ticks excluded)" if noop else ""
print(f"{n}|{summ}{tag}")
' 2>/dev/null)"
  [ -z "$out" ] && out="0|work-shipped parse failed"
  # sanitize the evidence half (after the first |) so it can't field-shift the row.
  local n="${out%%|*}" ev="${out#*|}"
  n="${n//[^0-9]/}"; n="${n:-0}"
  echo "${n}|$(sanitize "$ev")"
}

# ---- per-agent capture render -----------------------------------------------
ROSTER="$(build_roster)"
US=$'\x1f'   # row field delimiter — a control char that cannot appear in captured text

ALIVE_LIST=""; LAUNCHED_LIST=""; ZOMBIE_LIST=""; DOWN_LIST=""
UNVERIFIED_LIST=""; DIVERGENCE_LIST=""
ALIVE_COUNT=0; TOTAL_COUNT=0
declare -a TABLE_ROWS

while IFS='|' read -r name runtime chan tsession; do
  [ -n "$name" ] || continue
  TOTAL_COUNT=$((TOTAL_COUNT+1))

  IFS='|' read -r pane_state pane_ev <<<"$(pane_read "$tsession")"
  IFS='|' read -r hb hb_ev <<<"$(heartbeat_status "$name")"
  IFS='|' read -r work work_ev <<<"$(work_shipped "$name")"
  lastresp="$(last_response "$name" "$chan")"   # last-response timestamp
  loose="$(loose_ends "$name")"                 # loose ends

  # FUSED verdict — heartbeat is the auth authority, pane is the process signal.
  IFS='|' read -r live live_ev <<<"$(fuse_verdict "$pane_state" "$pane_ev" "$hb" "$hb_ev")"

  case "$live" in
    ALIVE)      ALIVE_COUNT=$((ALIVE_COUNT+1)); ALIVE_LIST="$ALIVE_LIST $name" ;;
    LAUNCHED)   LAUNCHED_LIST="$LAUNCHED_LIST $name" ;;
    ZOMBIE)     ZOMBIE_LIST="$ZOMBIE_LIST $name" ;;
    DOWN)       DOWN_LIST="$DOWN_LIST $name" ;;
    UNVERIFIED) UNVERIFIED_LIST="$UNVERIFIED_LIST $name" ;;
  esac

  # TRUE divergence only: pane proves a LIVE turn (process ALIVE) yet heartbeat says FAILED.
  # NO-PANE / QUIET / DOWN with a FAILED heartbeat is AGREEMENT it's down, not divergence.
  if [ "$live" = "ALIVE" ] && [ "$hb" = "FAILED" ]; then
    DIVERGENCE_LIST="$DIVERGENCE_LIST $name"
  fi

  TABLE_ROWS+=("${name}${US}${runtime}${US}${live}${US}${live_ev}${US}${pane_state}${US}${pane_ev}${US}${hb}${US}${hb_ev}${US}${work}${US}${work_ev}${US}${lastresp}${US}${loose}")
done <<<"$ROSTER"

# ---- output -----------------------------------------------------------------
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "================================================================================"
echo " DISCORD STACK FACT SHEET — $DATE   (generated $NOW)"
echo " READ-ONLY · verdict FUSES auth-heartbeat (authority) + tmux pane (process signal)"
echo " Banner-present alone == LAUNCHED, never ALIVE. A FAILED heartbeat is never overridden."
echo "================================================================================"
echo
echo "PER-AGENT STATE  (roster: $TOTAL_COUNT agents, decommissioned excluded: ${DECOMMISSIONED:-none})"
echo "--------------------------------------------------------------------------------"
for row in "${TABLE_ROWS[@]}"; do
  IFS="$US" read -r name runtime live live_ev pane_state pane_ev hb hb_ev work work_ev lastresp loose <<<"$row"
  printf '  %-14s [%s]\n' "$name" "$runtime"
  printf '     VERDICT  : %-11s — %s\n' "$live" "$live_ev"
  printf '     pane     : %-11s — %s\n' "$pane_state" "$pane_ev"
  printf '     heartbeat: %-11s — %s\n' "$hb" "$hb_ev"
  printf '     shipped  : %-11s — %s\n' "$work" "$work_ev"
  printf '     last-resp: %s\n' "$lastresp"
  printf '     loose-end: %s\n' "$loose"
  echo
done

echo "================================================================================"
echo "STACK-WIDE SYNTHESIS  (the cross-agent view a per-agent close cannot see)"
echo "--------------------------------------------------------------------------------"
echo "  ALIVE (turn-proven)   : $ALIVE_COUNT / $TOTAL_COUNT  ${ALIVE_LIST:-(none)}"
echo "  LAUNCHED (up, unproven):${LAUNCHED_LIST:- none}   <- banner only, no proven turn — NOT counted alive"
echo "  ZOMBIE (proc-up, auth dead):${ZOMBIE_LIST:- none}"
echo "  DOWN (auth dead, no pane)  :${DOWN_LIST:- none}"
echo "  UNVERIFIED            :${UNVERIFIED_LIST:- none}   <- silence != clean; named per-agent above"
echo "  TRUE divergence       :${DIVERGENCE_LIST:- none}   <- ALIVE turn AND heartbeat FAILED (the real contradiction)"
echo
if [ -n "$ZOMBIE_LIST" ] || [ -n "$DOWN_LIST" ]; then
  echo "  NOTE: ZOMBIE/DOWN agents have a FAILED auth-heartbeat (token expired/empty). The launch"
  echo "        banner in their pane does NOT mean they are alive — it printed before any API call."
  echo "        The heartbeat is the authority here, the banner is not. This is the exact"
  echo "        proxy-vs-ground-truth inversion the skill exists to catch."
  echo
fi
if [ -n "$DIVERGENCE_LIST" ]; then
  echo "  TRUE DIVERGENCE: a pane that proved a live post-launch turn AND a FAILED heartbeat."
  echo "        Surface BOTH and verify by hand before relying on the agent."
  echo
fi

# ---- Ghost Hours first-cut (home channel single-channel timing) --------------
if [ "$DO_GH" -eq 1 ]; then
  echo "================================================================================"
  echo "GHOST HOURS — first cut (home channel only, timing from the message-archive SQLite)"
  echo "--------------------------------------------------------------------------------"
  if [ -z "$OPERATOR_USER_ID" ] || [ -z "$HOME_CHANNEL_ID" ]; then
    echo "  UNCONFIGURED: set FLEET_OPERATOR_USER_ID and FLEET_HOME_CHANNEL_ID (see header)."
  elif [ -z "$MESSAGE_DB" ] || [ ! -f "$MESSAGE_DB" ]; then
    echo "  UNREACHABLE: message-archive DB not configured/found (FLEET_MESSAGE_DB=${MESSAGE_DB:-unset})"
  elif ! have sqlite3; then
    echo "  UNREACHABLE: sqlite3 not on PATH"
  else
    DB_FRESH="$(sqlite3 "$MESSAGE_DB" "SELECT MAX(created_at) FROM messages;" 2>/dev/null)"
    echo "  message store freshness (latest message any channel): ${DB_FRESH:-unknown}"
    echo "  (the archive is a LAGGING store synced by cron — if this date < today, GH timing is"
    echo "   stale and the live path is the Discord API via the coordinator's fetch_messages tool.)"
    echo
    # Per-operator-message agent-time = gap from an operator msg to the next agent reply.
    # Human-time = gap before each operator message (idle/thinking). Single-channel only.
    sqlite3 "$MESSAGE_DB" "
      WITH home AS (
        SELECT created_at, author_id,
               CASE WHEN author_id='$OPERATOR_USER_ID' THEN 'operator' ELSE 'agent' END AS who
        FROM messages
        WHERE channel_id='$HOME_CHANNEL_ID' AND created_at >= '${DATE}T00:00:00'
        ORDER BY created_at
      )
      SELECT 'msgs_today=' || COUNT(*) ||
             '  operator_msgs=' || SUM(CASE WHEN who='operator' THEN 1 ELSE 0 END) ||
             '  agent_msgs=' || SUM(CASE WHEN who='agent' THEN 1 ELSE 0 END)
      FROM home;
    " 2>/dev/null | sed 's/^/  /'
    echo
    echo "  Per-message agent-time (operator msg -> next agent reply, seconds), today in home channel:"
    sqlite3 -separator '  ' "$MESSAGE_DB" "
      WITH msgs AS (
        SELECT created_at, author_id,
               LEAD(created_at) OVER (ORDER BY created_at) AS next_at,
               LEAD(author_id)  OVER (ORDER BY created_at) AS next_author
        FROM messages
        WHERE channel_id='$HOME_CHANNEL_ID' AND created_at >= '${DATE}T00:00:00'
      )
      SELECT substr(created_at,12,8),
             CAST((julianday(next_at)-julianday(created_at))*86400 AS INT) || 's'
      FROM msgs
      WHERE author_id='$OPERATOR_USER_ID' AND next_author IS NOT NULL AND next_author <> '$OPERATOR_USER_ID'
      LIMIT 20;
    " 2>/dev/null | sed 's/^/    /'
    GH_ROWS="$(sqlite3 "$MESSAGE_DB" "SELECT COUNT(*) FROM messages WHERE channel_id='$HOME_CHANNEL_ID' AND created_at >= '${DATE}T00:00:00';" 2>/dev/null)"
    GH_ROWS="${GH_ROWS//[^0-9]/}"; GH_ROWS="${GH_ROWS:-0}"
    [ "$GH_ROWS" = "0" ] && echo "    (no home-channel messages in the archive for $DATE — empty today or sync lag; use live Discord API)"
  fi
  echo
  echo "  v2 TODO (NOT implemented — do not fake): multi-agent parallel attribution."
  echo "    Whose human-time when the operator messages across several channels; which agent's"
  echo "    agent-time when N agents run concurrently; serial-vs-parallel billable windows."
  echo "    v1 = single-channel home-channel timing only. FW-C stays operator-confirmed regardless."
  echo
fi

# ---- optional bus telemetry (the ONLY write) --------------------------------
if [ "$DO_EMIT" -eq 1 ] && [ -x "$EMIT_BIN" ]; then
  body="alive=$ALIVE_COUNT/$TOTAL_COUNT launched=${LAUNCHED_LIST:-none} zombie=${ZOMBIE_LIST:-none} down=${DOWN_LIST:-none} diverge=${DIVERGENCE_LIST:-none} date=$DATE"
  "$EMIT_BIN" closing-time-fleet discord_stack_facts_generated "discord-stack $DATE" "$body" ghost-hours >/dev/null 2>&1 \
    && echo "[bus] emitted discord_stack_facts_generated" \
    || echo "[bus] emit failed (non-fatal)"
fi

exit 0
