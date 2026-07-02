#!/usr/bin/env bash
# advance.sh -- Ghost Hours state machine. The agent calls this, never emulates it.
# Usage: advance.sh [--reset | --start | --answer "response"]
# Reads/writes: ~/.claude/state/ghost-hours/current.json
# Returns: exactly one output for the agent to relay verbatim. Nothing more.
set -euo pipefail

STATE_FILE="$HOME/.claude/state/ghost-hours/current.json"
CONFIG_FILE="$HOME/.ghost-hours/config.json"

# --- Helpers ---
read_state() { python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('$1',''))" 2>/dev/null; }
write_state() {
  python3 -c "
import json,sys
f='$STATE_FILE'
d=json.load(open(f))
d['$1']=$2
json.dump(d,open(f,'w'),indent=2)
"
}

# --- Reset ---
if [[ "${1:-}" == "--reset" ]]; then
  rm -f "$STATE_FILE"
  echo "STATE_RESET"
  exit 0
fi

# --- Start ---
if [[ "${1:-}" == "--start" ]]; then
  mkdir -p "$(dirname "$STATE_FILE")"
  cat > "$STATE_FILE" << 'EOF'
{
  "step": "summary",
  "fwc_eom": null,
  "fwc": null,
  "type": null,
  "subtype": null,
  "gh_mins": null,
  "human_mins": null,
  "gh_confidence": null,
  "backlog": null,
  "note": null,
  "desc": null,
  "tags": ""
}
EOF
  echo "STEP:summary"
  echo "OUTPUT:Give the user 3-5 bullets summarizing what was accomplished in this session. Then compute your FW-C silently (do NOT display it). Then call: advance.sh --answer \"fwc_eom=YOUR_SCORE\""
  exit 0
fi

# --- Answer ---
if [[ "${1:-}" != "--answer" ]]; then
  echo "ERROR: Usage: advance.sh [--reset | --start | --answer \"response\"]"
  exit 1
fi

ANSWER="${2:-}"
STEP=$(read_state "step")

case "$STEP" in

  summary)
    # The agent sends fwc_eom=N (its silent, blind FW-C estimate)
    FWC_EOM=$(echo "$ANSWER" | grep -oE 'fwc_eom=[0-9]+' | cut -d= -f2)
    if [[ -z "$FWC_EOM" ]]; then
      echo "ERROR: Expected fwc_eom=N, got: $ANSWER"
      exit 1
    fi
    write_state "fwc_eom" "$FWC_EOM"
    write_state "step" '"fwc"'
    echo "STEP:fwc"
    echo "OUTPUT:How heavy was this? (1-10)"
    ;;

  fwc)
    FWC=$(echo "$ANSWER" | grep -oE '[0-9]+')
    if [[ -z "$FWC" ]] || [[ "$FWC" -lt 1 ]] || [[ "$FWC" -gt 10 ]]; then
      echo "ERROR: Expected number 1-10, got: $ANSWER"
      exit 1
    fi
    write_state "fwc" "$FWC"
    if [[ "$FWC" -ge 5 ]]; then
      write_state "step" '"note"'
      echo "STEP:note"
      echo "OUTPUT:Want to say anything about why?"
    else
      write_state "step" '"type"'
      echo "STEP:type"
      echo "OUTPUT:Could this have happened without AI?"
    fi
    ;;

  type)
    LOWER=$(echo "$ANSWER" | tr '[:upper:]' '[:lower:]')
    if echo "$LOWER" | grep -qE 'yes|speed'; then
      write_state "type" '"speed"'
      write_state "step" '"gh_estimate"'
      echo "STEP:gh_estimate"
      echo "OUTPUT:AGENT_PROVIDES_GH_RANGE"
    elif echo "$LOWER" | grep -qE 'no|unlock'; then
      write_state "type" '"unlock"'
      # Check if event_label exists in config
      EVENT_LABEL=$(python3 -c "import json; d=json.load(open('$CONFIG_FILE')); print(d.get('event_label') or '')" 2>/dev/null)
      if [[ -n "$EVENT_LABEL" ]]; then
        write_state "step" '"subtype_restore"'
        echo "STEP:subtype_restore"
        echo "OUTPUT:Is this something you could do before $EVENT_LABEL?"
      else
        write_state "subtype" '"augmentation"'
        write_state "step" '"gh_estimate"'
        echo "STEP:gh_estimate"
        echo "OUTPUT:AGENT_PROVIDES_GH_RANGE"
      fi
    else
      echo "ERROR: Expected yes/no, got: $ANSWER"
      exit 1
    fi
    ;;

  subtype_restore)
    LOWER=$(echo "$ANSWER" | tr '[:upper:]' '[:lower:]')
    if echo "$LOWER" | grep -qE 'yes'; then
      write_state "subtype" '"restoration"'
      RECOVERY_TAG=$(python3 -c "import json; d=json.load(open('$CONFIG_FILE')); print(d.get('recovery_tag') or '')" 2>/dev/null)
      if [[ -n "$RECOVERY_TAG" ]]; then
        write_state "tags" "\"$RECOVERY_TAG\""
      fi
      write_state "step" '"gh_estimate"'
      echo "STEP:gh_estimate"
      echo "OUTPUT:AGENT_PROVIDES_GH_RANGE"
    elif echo "$LOWER" | grep -qE 'no'; then
      write_state "step" '"subtype_bypass"'
      EVENT_LABEL=$(python3 -c "import json; d=json.load(open('$CONFIG_FILE')); print(d.get('event_label') or '')" 2>/dev/null)
      echo "STEP:subtype_bypass"
      echo "OUTPUT:Could you have learned to do this before $EVENT_LABEL?"
    else
      echo "ERROR: Expected yes/no, got: $ANSWER"
      exit 1
    fi
    ;;

  subtype_bypass)
    LOWER=$(echo "$ANSWER" | tr '[:upper:]' '[:lower:]')
    if echo "$LOWER" | grep -qE 'yes'; then
      write_state "subtype" '"bypass"'
    else
      write_state "subtype" '"augmentation"'
    fi
    RECOVERY_TAG=$(python3 -c "import json; d=json.load(open('$CONFIG_FILE')); print(d.get('recovery_tag') or '')" 2>/dev/null)
    SUBTYPE=$(read_state "subtype")
    if [[ "$SUBTYPE" == "restoration" || "$SUBTYPE" == "bypass" ]] && [[ -n "$RECOVERY_TAG" ]]; then
      write_state "tags" "\"$RECOVERY_TAG\""
    fi
    write_state "step" '"gh_estimate"'
    echo "STEP:gh_estimate"
    echo "OUTPUT:AGENT_PROVIDES_GH_RANGE"
    ;;

  gh_estimate)
    # The agent sends gh=MINS,human=MINS
    GH=$(echo "$ANSWER" | grep -oE 'gh=[0-9]+' | cut -d= -f2)
    HUMAN=$(echo "$ANSWER" | grep -oE 'human=[0-9]+' | cut -d= -f2)
    if [[ -z "$GH" ]] || [[ -z "$HUMAN" ]]; then
      echo "ERROR: Expected gh=MINS,human=MINS got: $ANSWER"
      exit 1
    fi
    write_state "gh_mins" "$GH"
    write_state "human_mins" "$HUMAN"
    RATIO=$(python3 -c "print(round($GH/$HUMAN, 1))")
    if python3 -c "exit(0 if $GH/$HUMAN > 25 else 1)"; then
      write_state "step" '"gh_sanity"'
      echo "STEP:gh_sanity"
      echo "OUTPUT:That's a ${RATIO}x ratio. Does that feel right?"
    else
      write_state "step" '"gh_confidence"'
      echo "STEP:gh_confidence"
      echo "OUTPUT:How confident is that estimate? (low / medium / high)"
    fi
    ;;

  gh_sanity)
    LOWER=$(echo "$ANSWER" | tr '[:upper:]' '[:lower:]')
    if echo "$LOWER" | grep -qE 'yes|right|correct|confirmed'; then
      CURRENT_TAGS=$(read_state "tags")
      write_state "tags" "\"${CURRENT_TAGS:+$(echo $CURRENT_TAGS | tr -d '"'),}gh_confidence:review\""
      write_state "step" '"gh_confidence"'
      echo "STEP:gh_confidence"
      echo "OUTPUT:How confident is that estimate? (low / medium / high)"
    elif echo "$LOWER" | grep -qE 'gh=[0-9]'; then
      # User provided adjusted numbers
      GH=$(echo "$LOWER" | grep -oE 'gh=[0-9]+' | cut -d= -f2)
      HUMAN=$(echo "$LOWER" | grep -oE 'human=[0-9]+' | cut -d= -f2)
      [[ -n "$GH" ]] && write_state "gh_mins" "$GH"
      [[ -n "$HUMAN" ]] && write_state "human_mins" "$HUMAN"
      write_state "step" '"gh_confidence"'
      echo "STEP:gh_confidence"
      echo "OUTPUT:How confident is that estimate? (low / medium / high)"
    else
      write_state "step" '"gh_confidence"'
      echo "STEP:gh_confidence"
      echo "OUTPUT:How confident is that estimate? (low / medium / high)"
    fi
    ;;

  gh_confidence)
    LOWER=$(echo "$ANSWER" | tr '[:upper:]' '[:lower:]')
    if echo "$LOWER" | grep -qE 'low|medium|high'; then
      CONF=$(echo "$LOWER" | grep -oE 'low|medium|high')
      write_state "gh_confidence" "\"$CONF\""
    else
      write_state "gh_confidence" '"medium"'
    fi
    write_state "step" '"backlog"'
    echo "STEP:backlog"
    echo "OUTPUT:How long was this waiting? (months, or 0 if new)"
    ;;

  backlog)
    MONTHS=$(echo "$ANSWER" | grep -oE '[0-9]+')
    write_state "backlog" "${MONTHS:-0}"
    write_state "step" '"desc"'
    echo "STEP:desc"
    echo "OUTPUT:AGENT_PROVIDES_DESC"
    ;;

  note)
    if echo "$ANSWER" | grep -qiE '^(no|nope|nah|skip|pass)\b|^(cant|can.t) remember'; then
      write_state "step" '"type"'
      echo "STEP:type"
      echo "OUTPUT:Could this have happened without AI?"
      exit 0
    else
      # Escape for JSON
      ESCAPED=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$ANSWER")
      write_state "note" "$ESCAPED"
    fi
    write_state "step" '"type"'
    echo "STEP:type"
    echo "OUTPUT:Could this have happened without AI?"
    ;;





  desc)
    # The agent provides the session description (max 280 chars)
    ESCAPED=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1][:280]))" "$ANSWER")
    write_state "desc" "$ESCAPED"
    write_state "step" '"log"'
    echo "STEP:log"
    echo "OUTPUT:READY_TO_LOG"
    # Dump the full state for the logging command
    cat "$STATE_FILE"
    ;;

  log)
    echo "STEP:done"
    echo "OUTPUT:LOGGED"
    write_state "step" '"done"'
    ;;

  done)
    echo "STEP:done"
    echo "OUTPUT:Already complete. Use --reset to start over."
    ;;

  *)
    echo "ERROR: Unknown step: $STEP"
    exit 1
    ;;
esac
