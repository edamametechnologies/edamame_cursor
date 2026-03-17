# Setup

## Prerequisites

- Node.js 18+ with `fetch` support.
- A local EDAMAME host on the same machine as Cursor:
  - macOS / Windows production default: the EDAMAME Security app
  - Linux production default: `edamame_posture`
  - macOS opt-in live automation: a locally built `edamame_posture` binary
    started on the host itself, not the Lima VM daemon

The supported pairing flow is explicit. The package no longer reads PSKs from
app preference files or other host internals.

## Install via Cursor Marketplace Plugin

The recommended install path. Search for **EDAMAME Security** in the Cursor
Marketplace panel and click **Install**. The plugin registers:

- the MCP server (stdio bridge to EDAMAME),
- persistent security-awareness rules,
- skills for posture assessment and divergence diagnosis,
- a security-monitor agent,
- healthcheck and export-intent commands.

After installation, run `edamame_cursor_control_center` from Cursor to pair
with your local EDAMAME host. The plugin uses the `.mcp.json` at the repo
root. Set the `CURSOR_EDAMAME_CONFIG` environment variable to point at your
rendered config file, or run `setup/install.sh` once to generate it and then
point the env var at the generated path.

## Install From Source (Traditional)

```bash
bash setup/install.sh /absolute/path/to/target/workspace
```

The installer:

- copies the package into a stable per-user install directory,
- renders a default package config,
- renders a Cursor MCP snippet,
- renders optional scheduler templates for operators that want out-of-band execution.

The portable package path does not depend on `launchd`, `systemd`, or another
OS-level scheduler. Once Cursor launches the MCP bridge, the bridge itself
refreshes the behavioral model on the configured cadence while the Cursor
session remains connected.

## Config Paths

Primary config file:

- macOS: `~/Library/Application Support/cursor-edamame/config.json`
- Windows: `%APPDATA%\\cursor-edamame\\config.json`
- Linux: `~/.config/cursor-edamame/config.json`

Default state directory:

- macOS: `~/Library/Application Support/cursor-edamame/state`
- Windows: `%LOCALAPPDATA%\\cursor-edamame\\state`
- Linux: `~/.local/state/cursor-edamame`

The default local credential file now lives inside the package state directory as
`edamame-mcp.psk`.

Key fields:

- `workspace_root` - workspace this package is expected to monitor.
- `cursor_projects_root` - Cursor project storage, typically `~/.cursor/projects`.
- `transcript_project_hints` - path substrings used to rank relevant transcript stores.
- `agent_type` - human-readable producer name attached to each behavioral-model slice. Default: `cursor`.
- `agent_instance_id` - stable unique producer instance identifier shown in the EDAMAME UI and used for merged-model contributor matching.
- `host_kind` - production default is `edamame_app` on macOS/Windows and `edamame_posture` on Linux. For host-side live automation you may also point macOS at a same-machine `edamame_posture`.
- `posture_cli_command` - optional override for the `edamame_posture` binary when it is not on `PATH`. This can point at a local macOS build for posture-backed live automation.
- `systemctl_command` - optional override for `systemctl` if it is not on `PATH`.
- `posture_daemon_wrapper_path` - Linux path expected for the packaged daemon wrapper. Default: `/usr/bin/edamame_posture_daemon.sh`.
- `posture_config_path` - Linux path expected for the packaged daemon config. Default: `/etc/edamame_posture.conf`.
- `edamame_mcp_endpoint` - local EDAMAME MCP endpoint, default `http://127.0.0.1:3000/mcp`.
- `edamame_mcp_psk_file` - package-local file where the credential (PSK or per-client token) is stored.

## Cursor MCP Registration

The installer renders a `cursor-mcp.json` snippet with fully resolved paths.
Merge it into your Cursor MCP configuration (`~/.cursor/mcp.json` or workspace
`.cursor/mcp.json`). The snippet location is printed at the end of the install.

The bridge process is the portable runtime entrypoint for both:

- on-demand tools such as `cursor.refresh_behavioral_model`
- automatic periodic behavioral-model refresh while Cursor is open
- the `edamame_cursor_control_center` MCP App used for pairing and status

On each refresh, the package reads recent transcripts, assembles a
`RawReasoningSessionPayload`, and sends it to EDAMAME through
`upsert_behavioral_model_from_raw_sessions`. EDAMAME then uses its configured
internal LLM provider to generate and store the contributor `BehavioralWindow`.

## Pairing Through `edamame_cursor_control_center`

After Cursor sees the MCP snippet, run `edamame_cursor_control_center` from Cursor. The
control center shows:

- the configured endpoint and local credential file,
- the last intent export time and trigger,
- the current EDAMAME status when the MCP endpoint is reachable,
- Linux-only local host controller status for `edamame_posture`,
- Linux-only Debian `systemd` service readiness for `edamame_posture` when `systemctl` is available,
- platform-specific pairing instructions.

UI wording:

- `Refresh status`: read-only. Fetches the current pairing, endpoint, engine, and intent/model state.
- `Export intent now`: reads recent Cursor transcripts, exports updated intent to EDAMAME, then refreshes status.
- `Local EDAMAME host`: the local product exposing the MCP endpoint on this machine. On macOS/Windows this is usually the EDAMAME Security App. On Linux this is usually `edamame_posture`.

### macOS / Windows

Use `host_kind = edamame_app`.

1. Start the EDAMAME Security app.
2. Enable its local MCP server on port `3000`.
3. **Primary flow**: Click "Request pairing from app" in the control center, approve in the EDAMAME Security app. The credential is stored automatically.
4. **Fallback**: Generate a PSK from the app's MCP controls, paste it into `edamame_cursor_control_center` and save pairing.
5. Refresh status until the MCP endpoint, divergence engine, and behavioral model checks go healthy.

### Linux

Use `host_kind = edamame_posture`.

Preferred path from the MCP App:

1. Run `edamame_cursor_control_center`.
2. Use `Generate, start, and pair automatically`.
3. Refresh status until the MCP endpoint, divergence engine, and behavioral model checks go healthy.

Manual fallback:

1. Generate a PSK:

```bash
edamame_posture mcp-generate-psk
```

2. Start the local MCP endpoint with the same PSK:

```bash
edamame_posture mcp-start 3000 "<PSK>"
```

3. Paste that PSK into `edamame_cursor_control_center` and save pairing.
4. Refresh status until the MCP endpoint, divergence engine, and behavioral model checks go healthy.

### macOS posture automation for live tests

Production macOS pairing still defaults to `host_kind = edamame_app`. For the
host-side live suites under `cursor_package/tests_live/`, you can instead run a
same-machine `edamame_posture` on macOS for easier automation and debugging.

Important:

- This is a separate environment from the Lima VM posture daemon used by the
  OpenClaw runtime suites.
- The Cursor live runner does not open SSH tunnels into Lima.
- `host_kind = edamame_posture` on macOS therefore means "use a locally built
  posture binary and a host-local MCP endpoint".

Typical flow:

1. Build the local binaries:

```bash
cd ../edamame_core && cargo build --features standalone,swiftrs
cd ../edamame_posture && cargo build
```

2. Point your Cursor package config at the local posture binary and local PSK
   file:

```json
{
  "host_kind": "edamame_posture",
  "posture_cli_command": "/absolute/path/to/edamame_posture/target/debug/edamame_posture",
  "edamame_mcp_endpoint": "http://127.0.0.1:3000/mcp",
  "edamame_mcp_psk_file": "/absolute/path/to/edamame-mcp.psk"
}
```

3. Start the local posture daemon with admin privileges, then generate a PSK,
   start the local posture MCP server, and store the same PSK in the configured
   file:

```bash
POSTURE_BIN=/absolute/path/to/edamame_posture/target/debug/edamame_posture
sudo "$POSTURE_BIN" start
PSK="$($POSTURE_BIN mcp-generate-psk | awk 'NF && $1 !~ /^#/ { print; exit }')"
printf '%s\n' "$PSK" > /absolute/path/to/edamame-mcp.psk
"$POSTURE_BIN" mcp-start 3000 "$PSK"
```

`mcp-start` talks to the local posture daemon, so it will fail if that daemon
is not already running on the same machine.

4. Run the live suite against that same-machine endpoint:

```bash
node tests_live/run_cursor_live_suite.mjs --host-kind edamame_posture --config /absolute/path/to/config.json --json
```

## Health Check

```bash
bash setup/healthcheck.sh --strict --json
```

This validates:

- local config presence,
- credential file presence,
- Linux `edamame_posture` service readiness when the Debian `systemd` path is applicable,
- EDAMAME MCP reachability,
- divergence-engine running state,
- behavioral-model presence.
