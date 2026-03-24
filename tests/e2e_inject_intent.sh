#!/usr/bin/env bash
# End-to-end: synthetic Cursor-format JSONL transcripts, cursor_extrapolator, edamame_cli verification.
#
# Prerequisites: EDAMAME app (or posture) running, MCP paired, agentic/LLM for raw ingest, edamame_cli.
#
# Environment:
#   EDAMAME_CLI              Path to edamame_cli (optional)
#   CURSOR_EDAMAME_CONFIG    Override config.json path
#   E2E_POLL_ATTEMPTS        Default 36
#   E2E_POLL_INTERVAL_SECS   Default 5
#   E2E_STRICT_HASH          Default 0
#   E2E_DIAGNOSTICS_FILE     JSON diagnosis on poll timeout (optional)
#   E2E_PROGRESS_POLL        If 1, stderr hints each failed poll
#   E2E_SKIP_PROVISION_STRICT If 1, allow missing ~/.../current install and skip version vs repo check

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash tests/e2e_inject_intent.sh [--help]

Local Cursor transcript inject plus get_behavioral_model poll (see script header).
EOF
}

while (($# > 0)); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${CURSOR_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

OS_KERNEL="$(uname -s)"
case "$OS_KERNEL" in
  Darwin)
    CONFIG_HOME="$HOME/Library/Application Support/cursor-edamame"
    DATA_HOME="$HOME/Library/Application Support/cursor-edamame"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    CONFIG_HOME="${APPDATA:-$HOME/AppData/Roaming}/cursor-edamame"
    DATA_HOME="${LOCALAPPDATA:-$HOME/AppData/Local}/cursor-edamame"
    ;;
  *)
    CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/cursor-edamame"
    DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/cursor-edamame"
    ;;
esac

INSTALL_ROOT="$DATA_HOME/current"
CONFIG_PATH="${CURSOR_EDAMAME_CONFIG:-$CONFIG_HOME/config.json}"
CURSOR_MCP_JSON="$CONFIG_HOME/cursor-mcp.json"
POLL_ATTEMPTS="${E2E_POLL_ATTEMPTS:-36}"
POLL_INTERVAL="${E2E_POLL_INTERVAL_SECS:-5}"
LAST_RAW_OUT=""

resolve_edamame_cli() {
  if [[ -n "${EDAMAME_CLI:-}" && -x "$EDAMAME_CLI" ]]; then
    printf '%s' "$EDAMAME_CLI"
    return 0
  fi
  if command -v edamame_cli >/dev/null 2>&1; then
    command -v edamame_cli
    return 0
  fi
  if command -v edamame-cli >/dev/null 2>&1; then
    command -v edamame-cli
    return 0
  fi
  local candidates=(
    "$REPO_ROOT/../edamame_cli/target/release/edamame_cli"
    "$REPO_ROOT/../edamame_cli/target/debug/edamame_cli"
  )
  for c in "${candidates[@]}"; do
    if [[ -x "$c" ]]; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
}

echo "=== Step 1: Provision checks ==="

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "FAIL: config not found at $CONFIG_PATH" >&2
  echo "Run: bash setup/install.sh /path/to/your/workspace" >&2
  exit 1
fi
echo "OK: config $CONFIG_PATH"

if [[ "${E2E_SKIP_PROVISION_STRICT:-0}" != "1" ]]; then
  echo "=== Step 1b: Strict provision vs local repo ==="
  if [[ ! -f "$INSTALL_ROOT/service/cursor_extrapolator.mjs" ]]; then
    echo "FAIL: installed package missing: $INSTALL_ROOT/service/cursor_extrapolator.mjs" >&2
    echo "Run from edamame_cursor: bash setup/install.sh <workspace_root>" >&2
    echo "Or set E2E_SKIP_PROVISION_STRICT=1 for repo-only (CI/dev only)." >&2
    exit 1
  fi
  PACKAGE_ROOT="$INSTALL_ROOT"
  if [[ ! -f "$CURSOR_MCP_JSON" ]]; then
    echo "FAIL: Cursor MCP snippet missing: $CURSOR_MCP_JSON (re-run setup/install.sh)" >&2
    exit 1
  fi
  if ! grep -q "cursor_edamame_mcp" "$CURSOR_MCP_JSON" 2>/dev/null; then
    echo "FAIL: $CURSOR_MCP_JSON must reference cursor_edamame_mcp.mjs (re-run setup/install.sh)" >&2
    exit 1
  fi
  echo "OK: MCP snippet $CURSOR_MCP_JSON"
  REPO_PKG="$REPO_ROOT/package.json"
  INS_PKG="$INSTALL_ROOT/package.json"
  REPO_PLG="$REPO_ROOT/.cursor-plugin/plugin.json"
  INS_PLG="$INSTALL_ROOT/.cursor-plugin/plugin.json"
  for need in "$REPO_PKG" "$INS_PKG" "$REPO_PLG" "$INS_PLG"; do
    if [[ ! -f "$need" ]]; then
      echo "FAIL: required file missing for version check: $need" >&2
      exit 1
    fi
  done
  export _E2E_V_REPO_PKG="$REPO_PKG" _E2E_V_INS_PKG="$INS_PKG" _E2E_V_REPO_PLG="$REPO_PLG" _E2E_V_INS_PLG="$INS_PLG"
  python3 <<'PY'
import json
import os
import sys
from pathlib import Path

def ver(path: str) -> str:
    return json.loads(Path(path).read_text(encoding="utf-8"))["version"]

rp = os.environ["_E2E_V_REPO_PKG"]
ip = os.environ["_E2E_V_INS_PKG"]
rpl = os.environ["_E2E_V_REPO_PLG"]
ipl = os.environ["_E2E_V_INS_PLG"]
vp, vi = ver(rp), ver(ip)
if vp != vi:
    print(f"FAIL: package.json version mismatch repo={vp} installed={vi}", file=sys.stderr)
    raise SystemExit(1)
vpl, vil = ver(rpl), ver(ipl)
if vpl != vil:
    print(f"FAIL: .cursor-plugin/plugin.json version mismatch repo={vpl} installed={vil}", file=sys.stderr)
    raise SystemExit(1)
if vp != vpl:
    print(f"FAIL: package.json ({vp}) vs plugin.json ({vpl}) disagree in repo", file=sys.stderr)
    raise SystemExit(1)
print(f"OK: versions aligned ({vp}) between repo and {Path(ip).parent}")
PY
  unset _E2E_V_REPO_PKG _E2E_V_INS_PKG _E2E_V_REPO_PLG _E2E_V_INS_PLG
else
  PACKAGE_ROOT="$INSTALL_ROOT"
  if [[ ! -f "$INSTALL_ROOT/service/cursor_extrapolator.mjs" ]]; then
    echo "WARN: install root missing ($INSTALL_ROOT); using repo copy for extrapolator"
    PACKAGE_ROOT="$REPO_ROOT"
  fi
fi

if [[ ! -f "$PACKAGE_ROOT/service/cursor_extrapolator.mjs" ]]; then
  echo "FAIL: cursor_extrapolator.mjs not found under $PACKAGE_ROOT/service" >&2
  exit 1
fi
echo "OK: extrapolator package $PACKAGE_ROOT"

export _E2E_CONFIG_PATH="$CONFIG_PATH"
PSK_PATH="$(python3 -c "
import json, os
from pathlib import Path
p = Path(os.environ['_E2E_CONFIG_PATH'])
c = json.loads(p.read_text(encoding='utf-8'))
key = c.get('edamame_mcp_psk_file') or c.get('edamameMcpPskFile')
if not key:
    raise SystemExit('missing edamame_mcp_psk_file in config')
print(Path(key).expanduser().resolve())
")"
unset _E2E_CONFIG_PATH
if [[ ! -s "$PSK_PATH" ]]; then
  echo "FAIL: PSK file missing or empty: $PSK_PATH" >&2
  exit 1
fi
echo "OK: PSK file $PSK_PATH"

EDA_CLI="$(resolve_edamame_cli || true)"
if [[ -z "${EDA_CLI:-}" ]]; then
  echo "FAIL: edamame_cli not found. Set EDAMAME_CLI or build ../edamame_cli" >&2
  exit 1
fi
echo "OK: edamame_cli $EDA_CLI"

echo "=== Step 2: Write synthetic JSONL transcripts under ~/.cursor/projects ==="

export _E2E_CONFIG_PATH="$CONFIG_PATH"
E2E_STATE="$(python3 -c "
import json, os, time
from pathlib import Path

def jl(role: str, text: str) -> str:
    return json.dumps({'role': role, 'message': {'content': [{'type': 'text', 'text': text}]}})

config_path = Path(os.environ['_E2E_CONFIG_PATH'])
cfg = json.loads(config_path.read_text(encoding='utf-8'))
ws = Path(cfg['workspace_root']).expanduser().resolve()
agent_type = (cfg.get('agent_type') or 'cursor').strip()
agent_id = (cfg.get('agent_instance_id') or '').strip()
cur_rel = cfg.get('cursor_projects_root') or cfg.get('cursorProjectsRoot') or '~/.cursor/projects'
cur_root = Path(os.path.expanduser(str(cur_rel))).resolve()
base = ws.name
project_dir = cur_root / f'{base}-edamame-e2e-inject' / 'agent-transcripts' / 'e2e-bucket'
project_dir.mkdir(parents=True, exist_ok=True)
ts = int(time.time())
readme = ws / 'README.md'
markers = []

def write_jsonl(name, lines):
    p = project_dir / f'{name}.jsonl'
    p.write_text(\"\\n\".join(lines) + \"\\n\", encoding='utf-8')
    os.utime(p, None)
    markers.append(name)

write_jsonl(
    f'cu_e2e_api_{ts}',
    [
        jl('user', f'EDAMAME cu_e2e_api {ts}: inspect https://api.openai.com/v1/models and file {readme}'),
        jl('assistant', f'Reading paths. [Tool call] Read{chr(10)}  path: {readme}'),
        jl('assistant', f'Summarized OpenAI API intent for cu_e2e_api_{ts}.'),
    ],
)
write_jsonl(
    f'cu_e2e_shell_{ts}',
    [
        jl('user', f'EDAMAME cu_e2e_shell {ts}: curl npm registry'),
        jl(
            'assistant',
            '[Tool call] Shell' + chr(10) + '  command: curl -sL https://registry.npmjs.org/typescript | head -c 100',
        ),
        jl('assistant', f'Got registry snippet for cu_e2e_shell_{ts}.'),
    ],
)
write_jsonl(
    f'cu_e2e_git_{ts}',
    [
        jl(
            'user',
            f'EDAMAME cu_e2e_git {ts}: sync from git@github.com:edamametechnologies/threatmodels.git',
        ),
        jl('assistant', f'Planning git operations for cu_e2e_git_{ts}.'),
    ],
)
print(str(project_dir))
print(agent_type)
print(agent_id)
print(','.join(markers))
")"
unset _E2E_CONFIG_PATH

TRANSCRIPT_DIR="$(echo "$E2E_STATE" | sed -n '1p')"
AGENT_TYPE="$(echo "$E2E_STATE" | sed -n '2p')"
AGENT_INSTANCE_ID="$(echo "$E2E_STATE" | sed -n '3p')"
MARKERS_CSV="$(echo "$E2E_STATE" | sed -n '4p')"

echo "Wrote 3 JSONL files under $TRANSCRIPT_DIR"
echo "Session keys: $MARKERS_CSV"
echo "Expecting agent_type=$AGENT_TYPE agent_instance_id=$AGENT_INSTANCE_ID"

echo "=== Step 3: Run cursor_extrapolator ==="

E2E_EXTRAP_MAX_ATTEMPTS="${E2E_EXTRAP_MAX_ATTEMPTS:-3}"
E2E_EXTRAP_RETRY_DELAY="${E2E_EXTRAP_RETRY_DELAY:-15}"
EXTRAP_OK=0
for ((ea = 1; ea <= E2E_EXTRAP_MAX_ATTEMPTS; ea++)); do
  echo "--- extrapolator attempt $ea / $E2E_EXTRAP_MAX_ATTEMPTS ---"
  EXTRAP_LOG="$(mktemp)"
  export _E2E_EXTRAP_LOG="$EXTRAP_LOG"
  set +e
  node "$PACKAGE_ROOT/service/cursor_extrapolator.mjs" --config "$CONFIG_PATH" --json >"$EXTRAP_LOG" 2>&1
  EX_CODE=$?
  set -e
  cat "$EXTRAP_LOG"
  if [[ "$EX_CODE" != 0 ]]; then
    echo "WARN: extrapolator exited $EX_CODE (attempt $ea)" >&2
    rm -f "$EXTRAP_LOG"
    unset _E2E_EXTRAP_LOG
    if ((ea < E2E_EXTRAP_MAX_ATTEMPTS)); then
      echo "Retrying in ${E2E_EXTRAP_RETRY_DELAY}s..."
      sleep "$E2E_EXTRAP_RETRY_DELAY"
    fi
    continue
  fi

  if python3 -c "
import json, os, sys
path = os.environ['_E2E_EXTRAP_LOG']
r = json.load(open(path, encoding='utf-8'))
if not r.get('success'):
    print('FAIL: extrapolator result success=false', file=sys.stderr)
    sys.exit(1)
reasons = r.get('reasons') or []
if 'raw_ingest' not in reasons and 'cached_window_repush_no_active_sessions' not in reasons and 'payload_unchanged_remote_current' not in reasons:
    print('WARN: unexpected reasons:', reasons, file=sys.stderr)
print('OK: extrapolator success; window_hash=', r.get('windowHash'))
"; then
    EXTRAP_OK=1
    break
  else
    echo "WARN: extrapolator result validation failed (attempt $ea)" >&2
    rm -f "$EXTRAP_LOG"
    unset _E2E_EXTRAP_LOG
    if ((ea < E2E_EXTRAP_MAX_ATTEMPTS)); then
      echo "Retrying in ${E2E_EXTRAP_RETRY_DELAY}s..."
      sleep "$E2E_EXTRAP_RETRY_DELAY"
    fi
  fi
done

if [[ "$EXTRAP_OK" != 1 ]]; then
  echo "FAIL: extrapolator failed after $E2E_EXTRAP_MAX_ATTEMPTS attempts" >&2
  rm -f "$EXTRAP_LOG" 2>/dev/null
  unset _E2E_EXTRAP_LOG 2>/dev/null
  exit 1
fi

EXPECTED_HASH="$(python3 -c "import json, os; print(json.load(open(os.environ['_E2E_EXTRAP_LOG'])).get('windowHash') or '')")"
rm -f "$EXTRAP_LOG"
unset _E2E_EXTRAP_LOG

echo "=== Step 4: Poll edamame_cli get_behavioral_model ==="

export _E2E_AGENT_TYPE="$AGENT_TYPE"
export _E2E_AGENT_ID="$AGENT_INSTANCE_ID"
export _E2E_SESSION_KEYS="$MARKERS_CSV"
export _E2E_EXPECT_HASH="$EXPECTED_HASH"
export _E2E_STRICT_HASH="${E2E_STRICT_HASH:-0}"

for ((i = 1; i <= POLL_ATTEMPTS; i++)); do
  echo "--- poll $i / $POLL_ATTEMPTS ---"
  export _E2E_POLL_INDEX="$i"
  if [[ "${E2E_PROGRESS_POLL:-0}" == "1" ]]; then
    export _E2E_PROGRESS_POLL=1
  else
    unset _E2E_PROGRESS_POLL
  fi
  set +e
  RAW_OUT="$("$EDA_CLI" rpc get_behavioral_model --pretty 2>/dev/null)"
  CLI_CODE=$?
  set -e
  if [[ "$CLI_CODE" != 0 ]]; then
    echo "WARN: edamame_cli failed (exit $CLI_CODE); is the app running?"
    sleep "$POLL_INTERVAL"
    continue
  fi
  LAST_RAW_OUT="$RAW_OUT"

  if python3 -c "
import json, os, sys

def behavioral_from_cli_output(text):
    text = text.strip()
    if not text:
        raise ValueError('empty cli output')
    if text.startswith('Result: '):
        payload = text.split('Result: ', 1)[1].strip()
        first = json.loads(payload)
    else:
        first = json.loads(text)
    if isinstance(first, str):
        return json.loads(first)
    return first

agent_type = os.environ['_E2E_AGENT_TYPE'].strip()
agent_id = os.environ['_E2E_AGENT_ID'].strip()
session_keys = [k.strip() for k in os.environ['_E2E_SESSION_KEYS'].split(',') if k.strip()]
expect = os.environ['_E2E_EXPECT_HASH'].strip()
strict = os.environ.get('_E2E_STRICT_HASH', '0').strip() == '1'
progress = os.environ.get('_E2E_PROGRESS_POLL', '0').strip() == '1'
poll_index = int(os.environ.get('_E2E_POLL_INDEX', '0'))
raw = sys.stdin.read()
try:
    m = behavioral_from_cli_output(raw)
except (json.JSONDecodeError, TypeError, ValueError) as exc:
    if progress:
        print(f'WARN: parse_error poll={poll_index}: {exc}', file=sys.stderr)
    sys.exit(1)
if m == {'model': None} or (len(m) == 1 and m.get('model') is None):
    if progress:
        print(f'WARN: model_null poll={poll_index}', file=sys.stderr)
    sys.exit(1)
contribs = m.get('contributors') if isinstance(m.get('contributors'), list) else []
found = None
for c in contribs:
    if c.get('agent_type') == agent_type and c.get('agent_instance_id') == agent_id:
        found = c
        break
if not found and m.get('agent_type') == agent_type and m.get('agent_instance_id') == agent_id:
    found = m
if not found:
    if progress:
        types_ids = [(c.get('agent_type'), c.get('agent_instance_id')) for c in contribs[:12]]
        print(f'WARN: no_contributor_match poll={poll_index} want=({agent_type},{agent_id}) contributors={types_ids}', file=sys.stderr)
    sys.exit(1)
h = (found.get('hash') or '').strip()
if not h:
    if progress:
        print(f'WARN: contributor_hash_empty poll={poll_index}', file=sys.stderr)
    sys.exit(1)
if strict and expect and h != expect:
    if progress:
        print(f'WARN: strict_hash_mismatch poll={poll_index} expect={expect[:24]}... got={h[:24]}...', file=sys.stderr)
    sys.exit(1)
preds = m.get('predictions') if isinstance(m.get('predictions'), list) else []
missing = []
for sk in session_keys:
    ok = any(
        p.get('agent_type') == agent_type
        and p.get('agent_instance_id') == agent_id
        and p.get('session_key') == sk
        for p in preds
    )
    if not ok:
        missing.append(sk)
if missing:
    if progress:
        ours = [p.get('session_key') for p in preds if p.get('agent_type') == agent_type and p.get('agent_instance_id') == agent_id]
        print(f'WARN: missing_session_keys poll={poll_index} missing={missing} have_count={len(ours)} sample_have={ours[:8]}', file=sys.stderr)
    sys.exit(1)
print(h)
sys.exit(0)
" <<<"$RAW_OUT"; then
    unset _E2E_AGENT_TYPE _E2E_AGENT_ID _E2E_SESSION_KEYS _E2E_EXPECT_HASH _E2E_STRICT_HASH _E2E_POLL_INDEX _E2E_PROGRESS_POLL
    echo "OK: predictions for session_keys=$MARKERS_CSV ($AGENT_TYPE / $AGENT_INSTANCE_ID)"
    echo "PASS: Cursor end-to-end inject verified"
    exit 0
  fi
  sleep "$POLL_INTERVAL"
done

unset _E2E_AGENT_TYPE _E2E_AGENT_ID _E2E_SESSION_KEYS _E2E_EXPECT_HASH _E2E_STRICT_HASH _E2E_POLL_INDEX _E2E_PROGRESS_POLL

echo "FAIL: timeout waiting for behavioral model predictions (${POLL_ATTEMPTS}x${POLL_INTERVAL}s)" >&2

export _E2E_DIAG_RAW="${LAST_RAW_OUT:-}"
export _E2E_DIAG_SUITE="cursor"
export _E2E_DIAG_AGENT_TYPE="$AGENT_TYPE"
export _E2E_DIAG_AGENT_ID="$AGENT_INSTANCE_ID"
export _E2E_DIAG_SESSION_KEYS="$MARKERS_CSV"
export _E2E_DIAG_EXPECT_HASH="$EXPECTED_HASH"
export _E2E_DIAG_STRICT="${E2E_STRICT_HASH:-0}"
export _E2E_DIAG_ATTEMPTS="$POLL_ATTEMPTS"
export _E2E_DIAG_INTERVAL="$POLL_INTERVAL"
DIAG_OUT="$(python3 <<'PY'
import json, os, re, sys

def behavioral_from_cli_output(text):
    text = (text or "").strip()
    if not text:
        return None, "empty_cli_output"
    m = re.match(r"Result:\s*(.+)", text, re.S)
    payload = m.group(1).strip() if m else text.strip()
    try:
        first = json.loads(payload)
    except json.JSONDecodeError as exc:
        return None, f"json_decode_outer:{exc}"
    if isinstance(first, str):
        try:
            return json.loads(first), None
        except json.JSONDecodeError as exc:
            return None, f"json_decode_inner:{exc}"
    return first, None

suite = os.environ.get("_E2E_DIAG_SUITE", "")
at = os.environ.get("_E2E_DIAG_AGENT_TYPE", "").strip()
aid = os.environ.get("_E2E_DIAG_AGENT_ID", "").strip()
keys = [k.strip() for k in os.environ.get("_E2E_DIAG_SESSION_KEYS", "").split(",") if k.strip()]
expect = os.environ.get("_E2E_DIAG_EXPECT_HASH", "").strip()
strict = os.environ.get("_E2E_DIAG_STRICT", "0").strip() == "1"
raw = os.environ.get("_E2E_DIAG_RAW", "")
attempts = int(os.environ.get("_E2E_DIAG_ATTEMPTS", "0"))
interval = int(os.environ.get("_E2E_DIAG_INTERVAL", "0"))

out = {
    "e2e_suite": suite,
    "failure": "poll_timeout",
    "agent_type": at,
    "agent_instance_id": aid,
    "expected_session_keys": keys,
    "poll_config": {"attempts": attempts, "interval_seconds": interval},
    "had_successful_cli_fetch": bool(raw),
}

m, err = behavioral_from_cli_output(raw)
if err:
    out["parse_error"] = err
    print(json.dumps(out, indent=2, ensure_ascii=False))
    raise SystemExit(0)
if m is None:
    out["parse_error"] = "no_model"
    print(json.dumps(out, indent=2, ensure_ascii=False))
    raise SystemExit(0)

if m == {"model": None} or (len(m) == 1 and m.get("model") is None):
    out["model_empty"] = True
    print(json.dumps(out, indent=2, ensure_ascii=False))
    raise SystemExit(0)

contribs = m.get("contributors") if isinstance(m.get("contributors"), list) else []
out["contributor_count"] = len(contribs)
out["contributor_keys"] = [
    {"agent_type": c.get("agent_type"), "agent_instance_id": c.get("agent_instance_id"), "hash_prefix": str(c.get("hash") or "")[:24]}
    for c in contribs[:24]
    if isinstance(c, dict)
]

found = None
for c in contribs:
    if c.get("agent_type") == at and c.get("agent_instance_id") == aid:
        found = c
        break
if not found and m.get("agent_type") == at and m.get("agent_instance_id") == aid:
    found = m
out["contributor_row_matched"] = bool(found)
if found:
    h = (found.get("hash") or "").strip()
    out["matched_contributor_hash_prefix"] = h[:32]
    out["strict_hash_check"] = {"enabled": strict, "expect_prefix": expect[:32], "match": (not strict or not expect or h == expect)}

preds = m.get("predictions") if isinstance(m.get("predictions"), list) else []
out["predictions_total"] = len(preds)
ours = [p for p in preds if isinstance(p, dict) and p.get("agent_type") == at and p.get("agent_instance_id") == aid]
out["predictions_for_agent"] = len(ours)
sk_have = []
for p in ours:
    sk = p.get("session_key")
    if sk and sk not in sk_have:
        sk_have.append(sk)
out["session_keys_present_for_agent"] = sk_have[:40]
missing = [sk for sk in keys if sk not in sk_have]
out["session_keys_missing"] = missing
out["cu_e2e_keys_present"] = [x for x in sk_have if isinstance(x, str) and x.startswith("cu_e2e_")]
out["hint"] = "If keys are missing after extrapolator success, LLM merge may have dropped sessions or contributor hash drifted under merge."
print(json.dumps(out, indent=2, ensure_ascii=False))
PY
)"
if [[ -n "${E2E_DIAGNOSTICS_FILE:-}" ]]; then
  printf '%s\n' "$DIAG_OUT" >"$E2E_DIAGNOSTICS_FILE"
  echo "Wrote diagnosis: $E2E_DIAGNOSTICS_FILE" >&2
else
  printf '%s\n' "$DIAG_OUT" >&2
fi
unset _E2E_DIAG_RAW _E2E_DIAG_SUITE _E2E_DIAG_AGENT_TYPE _E2E_DIAG_AGENT_ID _E2E_DIAG_SESSION_KEYS _E2E_DIAG_EXPECT_HASH _E2E_DIAG_STRICT _E2E_DIAG_ATTEMPTS _E2E_DIAG_INTERVAL

exit 1
