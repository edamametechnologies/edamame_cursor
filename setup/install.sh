#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash setup/install.sh [workspace_root]

Installs the Cursor EDAMAME package for the target workspace.
Behavioral-model refresh is driven by Cursor's stdio MCP lifecycle itself:
the bridge refreshes opportunistically on initialization and tool calls, so no
launchd or external scheduler is required for the normal package path.
EOF
}

WORKSPACE_ROOT=""

while (($# > 0)); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "$WORKSPACE_ROOT" ]]; then
        echo "Unexpected extra argument: $1" >&2
        usage >&2
        exit 1
      fi
      WORKSPACE_ROOT="$1"
      ;;
  esac
  shift
done

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$PWD}"

if [[ "$(uname -s)" == "Darwin" ]]; then
  CONFIG_HOME="$HOME/Library/Application Support/cursor-edamame"
  STATE_HOME="$CONFIG_HOME/state"
  DATA_HOME="$HOME/Library/Application Support/cursor-edamame"
else
  CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/cursor-edamame"
  STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}/cursor-edamame"
  DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/cursor-edamame"
fi

INSTALL_ROOT="$DATA_HOME/current"
RENDERED_DIR="$CONFIG_HOME/rendered"
CONFIG_PATH="$CONFIG_HOME/config.json"
CURSOR_MCP_PATH="$CONFIG_HOME/cursor-mcp.json"
NODE_BIN="$(command -v node)"

mkdir -p "$CONFIG_HOME" "$STATE_HOME" "$DATA_HOME" "$RENDERED_DIR"
rm -rf "$INSTALL_ROOT"
mkdir -p "$INSTALL_ROOT"

cp -R "$SOURCE_ROOT/bridge" "$INSTALL_ROOT/"
cp -R "$SOURCE_ROOT/adapters" "$INSTALL_ROOT/"
cp -R "$SOURCE_ROOT/prompts" "$INSTALL_ROOT/"
cp -R "$SOURCE_ROOT/scheduler" "$INSTALL_ROOT/"
cp -R "$SOURCE_ROOT/service" "$INSTALL_ROOT/"
cp -R "$SOURCE_ROOT/docs" "$INSTALL_ROOT/"
cp -R "$SOURCE_ROOT/tests" "$INSTALL_ROOT/"
cp -R "$SOURCE_ROOT/setup" "$INSTALL_ROOT/"
cp "$SOURCE_ROOT/package.json" "$INSTALL_ROOT/"
cp "$SOURCE_ROOT/README.md" "$INSTALL_ROOT/"

# Cursor plugin artifacts (for reference; plugin install uses the repo directly)
cp -R "$SOURCE_ROOT/.cursor-plugin" "$INSTALL_ROOT/"
cp "$SOURCE_ROOT/.mcp.json" "$INSTALL_ROOT/"
cp -R "$SOURCE_ROOT/rules" "$INSTALL_ROOT/"
cp -R "$SOURCE_ROOT/skills" "$INSTALL_ROOT/"
cp -R "$SOURCE_ROOT/agents" "$INSTALL_ROOT/"
cp -R "$SOURCE_ROOT/commands" "$INSTALL_ROOT/"
cp -R "$SOURCE_ROOT/assets" "$INSTALL_ROOT/"

chmod +x "$INSTALL_ROOT/bridge/"*.mjs
chmod +x "$INSTALL_ROOT/service/"*.mjs
chmod +x "$INSTALL_ROOT/setup/"*.sh

export INSTALL_ROOT CONFIG_PATH CURSOR_MCP_PATH WORKSPACE_ROOT STATE_HOME NODE_BIN RENDERED_DIR
python3 - <<'PY'
import hashlib
import os
import socket
import sys
from pathlib import Path

install_root = Path(os.environ["INSTALL_ROOT"])
config_path = Path(os.environ["CONFIG_PATH"])
cursor_mcp_path = Path(os.environ["CURSOR_MCP_PATH"])
workspace_root = Path(os.environ["WORKSPACE_ROOT"]).resolve()
state_home = Path(os.environ["STATE_HOME"])
node_bin = os.environ["NODE_BIN"]
rendered_dir = Path(os.environ["RENDERED_DIR"])
default_agent_instance_id = (
    f"{socket.gethostname()}-"
    f"{hashlib.sha256(str(workspace_root).encode('utf-8')).hexdigest()[:12]}"
)
default_host_kind = "edamame_posture" if sys.platform.startswith("linux") else "edamame_app"
default_posture_cli_command = "edamame_posture" if sys.platform.startswith("linux") else ""
default_psk_path = state_home / "edamame-mcp.psk"
edamame_mcp_psk_file = str(default_psk_path)

def render_template(src: Path, dst: Path) -> None:
    content = src.read_text(encoding="utf-8")
    content = (
        content.replace("__PACKAGE_ROOT__", str(install_root))
        .replace("__CONFIG_PATH__", str(config_path))
        .replace("__WORKSPACE_ROOT__", str(workspace_root))
        .replace("__WORKSPACE_BASENAME__", workspace_root.name)
        .replace("__DEFAULT_AGENT_INSTANCE_ID__", default_agent_instance_id)
        .replace("__DEFAULT_HOST_KIND__", default_host_kind)
        .replace("__DEFAULT_POSTURE_CLI_COMMAND__", default_posture_cli_command)
        .replace("__STATE_DIR__", str(state_home))
        .replace("__EDAMAME_MCP_PSK_FILE__", edamame_mcp_psk_file)
        .replace("__NODE_BIN__", node_bin)
    )
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(content, encoding="utf-8")

if not config_path.exists():
    render_template(
        install_root / "setup" / "cursor-edamame-config.template.json",
        config_path,
    )

render_template(
    install_root / "setup" / "cursor-mcp.template.json",
    cursor_mcp_path,
)

render_template(
    install_root / "scheduler" / "launchd" / "com.edamame.cursor.extrapolator.plist",
    rendered_dir / "launchd" / "com.edamame.cursor.extrapolator.plist",
)
render_template(
    install_root / "scheduler" / "launchd" / "com.edamame.cursor.verdict-reader.plist",
    rendered_dir / "launchd" / "com.edamame.cursor.verdict-reader.plist",
)
for name in [
    "cursor-edamame-extrapolator.service",
    "cursor-edamame-extrapolator.timer",
    "cursor-edamame-verdict-reader.service",
    "cursor-edamame-verdict-reader.timer",
]:
    render_template(
        install_root / "scheduler" / "systemd" / "user" / name,
        rendered_dir / "systemd" / "user" / name,
    )
PY

cat <<EOF
Installed Cursor EDAMAME package to:
  $INSTALL_ROOT

Primary config:
  $CONFIG_PATH

Cursor MCP snippet:
  $CURSOR_MCP_PATH

Rendered scheduler templates:
  $RENDERED_DIR

Next steps:
1. Copy the MCP snippet into your Cursor MCP configuration.
2. Launch Cursor and run the edamame_cursor_control_center tool.
3. macOS/Windows: click 'Request pairing from app' in the control center, or paste a PSK manually.
   Linux: use the auto-pair action or paste a PSK generated with edamame_posture mcp-generate-psk.
4. Run: "$INSTALL_ROOT/setup/healthcheck.sh" --strict --json
EOF
