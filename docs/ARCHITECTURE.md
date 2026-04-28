# Cursor Package Architecture

## Goal

Keep the OpenClaw split intact on a developer workstation:

- Cursor is the reasoning plane and only proposes intent.
- EDAMAME Security remains the system-plane authority for telemetry, behavioral-model storage, divergence-engine execution, and verdict history.

## Distribution Modes

This package supports two distribution paths:

- **Cursor Marketplace Plugin**: installed from the Marketplace, automatic discovery of MCP server, rules, skills, agents, and commands via `.cursor-plugin/plugin.json`.
- **Traditional MCP install**: manual `setup/install.sh` copies the package to a stable per-user directory and renders config templates. The user wires the MCP snippet into Cursor manually.

Both paths use the same runtime code. The plugin structure (`.cursor-plugin/`, `.mcp.json`, `rules/`, `skills/`, `agents/`, `commands/`) provides Cursor-native discovery; the traditional path provides the same MCP bridge plus rendered scheduler templates for operators.

## Plugin Structure

```text
.cursor-plugin/plugin.json  -- Cursor plugin manifest
.mcp.json                   -- MCP server definition (auto-discovered by Cursor)
rules/                      -- Persistent AI guidance (.mdc files)
  security-awareness.mdc    -- Safety-floor rules for monitored workstations
  edamame-integration.mdc   -- EDAMAME MCP tool usage patterns
skills/                     -- Agent skills
  security-posture/         -- Posture assessment skill
  divergence-monitor/       -- Divergence diagnosis skill
agents/                     -- Custom agent configurations
  security-monitor.md       -- Security-aware coding agent
commands/                   -- Agent-executable commands
  healthcheck.md            -- Run EDAMAME health check
  export-intent.md          -- Force behavioral model refresh
assets/                     -- Logo and static assets
```

## Producer Modes

EDAMAME supports three additive reasoning-plane producer contracts:

- OpenClaw skill mode: an LLM skill reads session history, builds a `BehavioralWindow`, and calls `upsert_behavioral_model`.
- Cursor workstation mode (this package): reads transcript artifacts, builds a `RawReasoningSessionPayload`, and calls `upsert_behavioral_model_from_raw_sessions` so EDAMAME can generate the `BehavioralWindow` internally with its configured LLM provider.
- EDAMAME-side external transcript observer (added in core 1.2.3): runs inside `edamame_core` and reads the same transcript directory directly, feeding the same ingest pipeline. The observer is purely additive and hash-skips when its payload matches the last push from this Node bridge -- so the install / MCP / pairing flow in this repo is unchanged. Operator UX (pause / resume / run-now) lives in the EDAMAME app's AI / Config tab. When the observer is paused while Cursor is still installed, EDAMAME's `unsecured_cursor` internal threat trips on the next score cycle. See `../../edamame_core/AGENTIC.md` and `../../edamame_core/INTERNAL.md` in the workspace.

## Component Mapping

| OpenClaw concept | Cursor package component | Responsibility |
|---|---|---|
| MCP bridge | `bridge/cursor_edamame_mcp.mjs` | Present a local stdio MCP server to Cursor, serve the control-center MCP App resource, and forward approved calls to the app-hosted EDAMAME MCP endpoint. |
| Pairing and status UI | `bridge/control_center_app.html` + `service/control_center.mjs` | Support two pairing modes: app-mediated pairing (macOS/Windows via POST /mcp/pair) and PSK paste (Linux/CLI). Persist credentials locally and show runtime status without reading secrets from host app internals. |
| Extrapolator skill | `service/cursor_extrapolator.mjs` + `adapters/session_prediction_adapter.mjs` | Read Cursor transcripts, assemble a `RawReasoningSessionPayload`, and forward it to EDAMAME raw-session ingest. |
| Posture facade | `service/posture_facade.mjs` + `service/verdict_reader.mjs` | Read divergence verdicts, history, score, suspicious sessions, and todos without owning verdict state. |
| Portable refresh loop | `bridge/cursor_edamame_mcp.mjs` | Keep a lightweight periodic extrapolator loop alive while Cursor keeps the MCP bridge connected. |

## Runtime Flow

1. Cursor produces transcript artifacts under `~/.cursor/projects/.../agent-transcripts/`.
2. `service/cursor_extrapolator.mjs` reads recent transcript files, prefers `.txt` transcripts when available, and falls back to `.jsonl`.
3. `adapters/session_prediction_adapter.mjs` converts those transcripts into a `RawReasoningSessionPayload` carrying source identity, transcript text, tool names, commands, source path, and window bounds.
4. The bridge-hosted refresh loop periodically forwards that payload with `upsert_behavioral_model_from_raw_sessions` while Cursor remains connected.
5. EDAMAME validates the payload, uses its configured internal LLM provider to generate the contributor `BehavioralWindow`, stores it, and merges it with other active contributors.
6. `service/verdict_reader.mjs`, `service/control_center.mjs`, and the MCP bridge expose the read-only posture surface back to Cursor and operators.

## State Ownership

- Authoritative security state lives in EDAMAME Security only.
- Package-local state under `state/` stores operational metadata such as the last raw payload hash, the last contributor-slice hash returned by EDAMAME, and the last seen verdict key.
- The package never stores security verdict state in workspace files.
- Multi-agent merge ownership lives in EDAMAME Security. Cursor never tries to compute the merged model locally.

## Scope Filters (Cross-Platform)

The Cursor package uses `scope_parent_paths` to tell the EDAMAME divergence engine which sessions belong to Cursor. A session is in scope when its parent process matches any of these patterns:

| Platform | Filter pattern | Matches |
|---|---|---|
| macOS | `*/Cursor.app/Contents/MacOS/Cursor` | Main Cursor binary |
| macOS | `*/Cursor Helper*` | Renderer, Plugin, GPU helper processes |
| Windows | `*/Cursor/Cursor.exe` | Main binary under `AppData\Local\Programs\Cursor\` |
| Windows | `*/Cursor/Cursor Helper*.exe` | All helper variants (.exe) |
| Linux AppImage | `/tmp/.mount_cursor*` | FUSE-mounted AppImage processes |
| Linux installed | `*/cursor/cursor`, `/opt/cursor*` | Extracted or system-installed binary |
| All | `*/cursor_edamame_mcp.mjs` | MCP bridge script spawned by this package |

These defaults are defined in `service/config.mjs` under `scopeParentPaths` and can be overridden in the user config file. Additional scope levels (`scopeProcessPaths`, `scopeGrandparentPaths`, `scopeAnyLineagePaths`) are available but empty by default for Cursor.

## Infrastructure Traffic Patterns

The `cursorLlmHosts` config key lists entries that Cursor is expected to
connect to. These are injected both as LLM hints (via `derived_expected_traffic`
in the raw-session payload) and directly into heartbeat windows.

Two matching modes are supported:
- **Domain-suffix matching** (`host:port`): `amazonaws.com:443` matches any `*.amazonaws.com:443` destination.
- **ASN-based matching** (`asn:OWNER`): `asn:CLOUDFLARENET` matches any destination IP whose ASN owner contains "cloudflarenet" (case-insensitive substring). This is preferred for CDN providers whose IPs don't map to predictable domain suffixes.

| Entry | Covers |
|---|---|
| `cursor.sh:443` | Cursor API endpoints (`api2.cursor.sh`, etc.) |
| `api.openai.com:443` | OpenAI API calls |
| `api.anthropic.com:443` | Anthropic/Claude API calls |
| `amazonaws.com:443` | AWS EC2 backend hosts used by Cursor |
| `asn:CLOUDFLARENET` | Cloudflare CDN, analytics, edge workers (AS13335) |

These can be extended via the `cursorLlmHosts` key in the user config file.

## Why The App Path Works

- The app already hosts the same MCP and RPC divergence surface as `edamame_posture`.
- The package treats app availability as an operational dependency and validates it through `service/health.mjs`.
- Raw-session repush is built into the extrapolator so app restarts do not require model persistence in the package itself.
- Pairing is explicit: the control center stores the credential in the package state directory. On macOS/Windows, app-mediated pairing (POST /mcp/pair) obtains a per-client token; on Linux/CLI, a shared PSK is pasted. The credential file holds either type.
