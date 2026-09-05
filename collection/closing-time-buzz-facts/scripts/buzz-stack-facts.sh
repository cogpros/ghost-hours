#!/usr/bin/env bash
# Read-only Buzz collection using an already authenticated buzz CLI.
# Required: BUZZ_RELAY_URL and BUZZ_OPERATOR_NAME or BUZZ_OPERATOR_PUBKEY.
# Local writes: state directory and public-key/display-name cache only.
set -euo pipefail
TARGET_DATE=$(date +%Y-%m-%d)
EXPLICIT_DATE=0
OUTPUT_JSON=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --date) [[ $# -ge 2 ]] || { echo "--date needs YYYY-MM-DD" >&2; exit 2; }
            TARGET_DATE="$2"; EXPLICIT_DATE=1; shift 2 ;;
    --json) OUTPUT_JSON=1; shift ;;
    *) echo "Usage: buzz-stack-facts.sh [--date YYYY-MM-DD] [--json]" >&2; exit 2 ;;
  esac
done
: "${BUZZ_RELAY_URL:?Set BUZZ_RELAY_URL for your read-only Buzz credentials}"
if [[ -z "${BUZZ_OPERATOR_NAME:-}" && -z "${BUZZ_OPERATOR_PUBKEY:-}" ]]; then
  echo "Set BUZZ_OPERATOR_NAME or BUZZ_OPERATOR_PUBKEY" >&2
  exit 2
fi
export EXPLICIT_DATE BUZZ_RELAY_URL OUTPUT_JSON
STATE_DIR="${CLOSING_TIME_STATE:-$HOME/.closing-time/state}/closing-time-buzz"
mkdir -p "$STATE_DIR"

TARGET_DATE="$TARGET_DATE" STATE_DIR="$STATE_DIR" python3 - <<'PY'
import json, os, subprocess, sys, time, glob
from datetime import datetime, timezone, timedelta

TARGET = os.environ["TARGET_DATE"]
STATE = os.environ["STATE_DIR"]
OPERATOR = os.environ.get("BUZZ_OPERATOR_NAME", "operator")
OPERATOR_PUBKEY = os.environ.get("BUZZ_OPERATOR_PUBKEY", "")
GAP_CAP = 30 * 60          # cap any single human/agent gap at 30 min
QUIET_HOURS = 6            # thread with no msg in 6h of day-end = went-quiet

# Window: seal-to-seal rather than calendar midnight. The operator-day runs
# from the last buzz-stack seal to now; the close stamps it with today's label.
# Explicit --date falls back to calendar-day mode (backfills only).
EXPLICIT_DATE = os.environ.get("EXPLICIT_DATE") == "1"
day_start = int(datetime.strptime(TARGET, "%Y-%m-%d").timestamp())
day_end = int((datetime.strptime(TARGET, "%Y-%m-%d") + timedelta(days=1)).timestamp())
window_note = f"calendar day {TARGET}"
if not EXPLICIT_DATE:
    seals = sorted(glob.glob(os.path.join(STATE, "buzz-stack-*.json")))
    last_seal = 0
    for s in seals:
        try:
            ts = json.load(open(s)).get("sealed_at", "")
            last_seal = max(last_seal, int(datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp()))
        except Exception:
            pass
    now = int(time.time())
    if last_seal and 0 <= (now - last_seal) < 48 * 3600:
        day_start = last_seal
        window_note = f"seal-to-seal (last seal {datetime.fromtimestamp(last_seal).strftime('%m-%d %H:%M')} -> now)"
    else:
        window_note = f"no prior seal inside 48h — calendar day {TARGET}"
    day_end = now + 60

def buzz(*args):
    r = subprocess.run(["buzz", *args], capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        return None
    try:
        return json.loads(r.stdout)
    except Exception:
        return None

def buzz_raw(*args):
    # canvas get returns raw markdown, not JSON
    r = subprocess.run(["buzz", *args], capture_output=True, text=True, timeout=60)
    return r.stdout if r.returncode == 0 else None

def fail(msg):
    print(f"FATAL: {msg}", file=sys.stderr)
    sys.exit(2)

channels = buzz("channels", "list")
if not isinstance(channels, list):
    fail("channels list failed — check relay and read-only authentication")

# ---- collect messages per channel (today) --------------------------------
cache_path = os.path.join(STATE, "pubkey-cache.json")
try:
    cache = json.load(open(cache_path))
except Exception:
    cache = {}

ledger_path = os.path.join(STATE, "threads-closed.jsonl")
closed_roots = set()
if os.path.exists(ledger_path):
    for line in open(ledger_path):
        try:
            closed_roots.add(json.loads(line)["root"])
        except Exception:
            pass

all_pub = set()
chan_data = {}
for ch in channels:
    cid, cname = ch["channel_id"], ch["name"]
    msgs = buzz("messages", "get", "--channel", cid, "--since", str(day_start), "--limit", "500")
    if not isinstance(msgs, list):
        fail(f"messages unreadable for channel {cname}; capture incomplete")
    if len(msgs) >= 500:
        fail(f"channel {cname} reached the 500-message limit; capture may be truncated")
    msgs = [m for m in msgs if int(m.get("created_at", 0)) < day_end]
    canvas = buzz_raw("canvas", "get", "--channel", cid)
    if canvas is None:
        fail(f"canvas unreadable for channel {cname}; capture incomplete")
    for m in msgs:
        all_pub.add(m["pubkey"])
    chan_data[cid] = {"name": cname, "msgs": msgs, "canvas": canvas, "created": int(ch.get("created_at", 0))}

# ---- resolve pubkeys (cached, fail-loud on unknown) ----------------------
unknown = []
for pk in sorted(all_pub):
    if pk == OPERATOR_PUBKEY:
        cache[pk] = OPERATOR
        continue
    if cache.get(pk):
        continue
    prof = buzz("users", "get", "--pubkey", pk)
    if prof and isinstance(prof, list) and prof and prof[0].get("display_name"):
        cache[pk] = prof[0]["display_name"]
    else:
        cache[pk] = None
json.dump(cache, open(cache_path, "w"), indent=1)
unknown = sorted(pk for pk in all_pub if not cache.get(pk))
if unknown:
    fail("unknown writers: " + ", ".join(unknown) + "; resolve profiles before sealing")
if not OPERATOR_PUBKEY:
    operator_keys = [pk for pk in all_pub if cache.get(pk) == OPERATOR]
    if len(operator_keys) > 1:
        fail("operator name matches multiple writers; set BUZZ_OPERATOR_PUBKEY")
def who(pk):
    n = cache.get(pk)
    if n is None:
        unknown.append(pk)
        return f"UNKNOWN({pk[:8]})"
    return n

# ---- thread reconstruction + timing --------------------------------------
def hms(ts):
    return datetime.fromtimestamp(ts).strftime("%H:%M")

roster = {}   # name -> {msgs, last_ts, channels:set}
threads_out = []
day_human = 0
day_agent = {}  # agent name -> secs

for cid, d in chan_data.items():
    trees = {}
    for m in d["msgs"]:
        etags = [t for t in m.get("tags", []) if len(t) >= 2 and t[0] == "e"]
        explicit_roots = [t[1] for t in etags if len(t) >= 4 and t[3] == "root"]
        root = explicit_roots[0] if explicit_roots else (etags[0][1] if etags else m.get("id"))
        if not root:
            fail(f"message missing thread identity in channel {d['name']}")
        trees.setdefault(root, []).append(m)
    for root, ms in trees.items():
        ms.sort(key=lambda m: int(m["created_at"]))
        first, last = int(ms[0]["created_at"]), int(ms[-1]["created_at"])
        # timing inside thread
        t_human = t_agent = 0
        prev = None
        pending_op = None
        for m in ms:
            ts, name = int(m["created_at"]), who(m["pubkey"])
            roster.setdefault(name, {"msgs": 0, "last": 0, "chans": set()})
            roster[name]["msgs"] += 1
            roster[name]["last"] = max(roster[name]["last"], ts)
            roster[name]["chans"].add(d["name"])
            if (m["pubkey"] == OPERATOR_PUBKEY if OPERATOR_PUBKEY else name == OPERATOR):
                if prev is not None:
                    t_human += min(ts - prev, GAP_CAP)
                pending_op = ts
            else:
                if pending_op is not None:
                    t_agent += min(ts - pending_op, GAP_CAP)
                    day_agent[name] = day_agent.get(name, 0) + min(ts - pending_op, GAP_CAP)
                    pending_op = None
            prev = ts
        day_human += t_human
        state = ("CLOSED" if root in closed_roots
                 else "active" if (day_end - last) < QUIET_HOURS * 3600 or last >= day_end - 1
                 else "went-quiet")
        title = (ms[0].get("content") or "").split("\n")[0][:80]
        threads_out.append({
            "channel": d["name"], "root": root, "n": len(ms),
            "first_ts": first, "last_ts": last,
            "span": f"{hms(first)}->{hms(last)}", "mins": round((last - first) / 60),
            "human_min": round(t_human / 60), "agent_min": round(t_agent / 60), "state": state, "title": title,
        })

if os.environ.get("OUTPUT_JSON") == "1":
    work_log_dir = os.path.expanduser(os.environ.get("BUZZ_WORK_LOGS_DIR", "~/.buzz/WORK_LOGS"))
    print(json.dumps({
        "date": TARGET, "window_start": day_start, "window_end": day_end,
        "window_note": window_note, "relay": os.environ["BUZZ_RELAY_URL"],
        "complete": True, "human_mins": day_human / 60,
        "agent_mins": sum(day_agent.values()) / 60,
        "agent_mins_by_writer": {name: secs / 60 for name, secs in day_agent.items()},
        "timing_source": "message gaps capped at 30 minutes",
        "threads": threads_out, "unknown_writers": [],
        "roster": {name: {"msgs": r["msgs"], "last": r["last"], "channels": sorted(r["chans"])}
                   for name, r in roster.items()},
        "canvases": {d["name"]: d["canvas"] for d in chan_data.values()},
        "work_logs": sorted(glob.glob(os.path.join(work_log_dir, f"*{TARGET}*"))),
        "closed_thread_count": len(closed_roots),
    }))
    sys.exit(0)

# ---- output --------------------------------------------------------------
print(f"# BUZZ STACK FACT SHEET — {TARGET}")
print(f"relay: {os.environ.get('BUZZ_RELAY_URL')}  (preconfigured read-only authentication)")
print(f"window: {window_note}")
print()
print("## ROSTER (message-active today)")
if roster:
    for name, r in sorted(roster.items(), key=lambda kv: -kv[1]["last"]):
        print(f"- {name}: {r['msgs']} msgs | last {hms(r['last'])} | {', '.join(sorted(r['chans']))}")
else:
    print("- (no messages on the relay today)")
print()
print("## THREADS")
if threads_out:
    for t in sorted(threads_out, key=lambda t: t["channel"]):
        print(f"- [{t['channel']}] {t['state']:10} {t['n']:3} msgs {t['span']} ({t['mins']}m, human {t['human_min']}m) root={t['root'][:8]}")
        print(f"    {t['title']}")
else:
    print("- none today")
print()
print("## GH DAY TALLY (machine half — units feed the day)")
print(f"- operator human-time (in-thread, capped {GAP_CAP//60}m/gap): {round(day_human/60)} min")
for name, secs in sorted(day_agent.items(), key=lambda kv: -kv[1]):
    print(f"- agent-time {name}: {round(secs/60)} min")
print()
print("## CANVAS")
for cid, d in chan_data.items():
    c = (d["canvas"] or "").strip()
    if c and c.lower() != "null":
        refreshed = ""
        for line in c.split("\n"):
            if "refreshed" in line.lower() or "updated" in line.lower():
                refreshed = " | " + line.strip().lstrip("*# ")[:60]
                break
        print(f"- {d['name']}: present ({len(c)} chars){refreshed}")
    else:
        print(f"- {d['name']}: MISSING")
print()
work_log_dir = os.path.expanduser(os.environ.get("BUZZ_WORK_LOGS_DIR", "~/.buzz/WORK_LOGS"))
logs = sorted(glob.glob(os.path.join(work_log_dir, f"*{TARGET}*")))
print(f"## WORK_LOGS ({TARGET})")
for p in logs:
    print(f"- {os.path.basename(p)}")
if not logs:
    print("- none")
print()
if unknown:
    print("## UNKNOWN WRITERS (fail-loud — resolve before sealing)")
    for pk in sorted(set(unknown)):
        print(f"- {pk}")
print(f"\nclosed-thread ledger: {len(closed_roots)} roots on file ({ledger_path})")
PY
