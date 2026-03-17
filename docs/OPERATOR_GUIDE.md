# Operator Guide

## Day-One Workflow

1. Start your local EDAMAME host:
   - macOS / Windows: EDAMAME Security app with MCP enabled
   - Linux: `edamame_posture mcp-start 3000 "<PSK>"`
2. Run `edamame_cursor_control_center` from Cursor and pair: on macOS/Windows use "Request pairing from app" (or paste a PSK as fallback); on Linux save the local endpoint + PSK explicitly.
3. Run `bash setup/healthcheck.sh --strict --json`.
4. Trigger one manual model refresh:

```bash
node service/cursor_extrapolator.mjs --json
```

5. Inspect the current posture:

```bash
node service/verdict_reader.mjs --json
```

6. Open EDAMAME Security and inspect `AI` -> `Divergence`.

Use the Divergence subtab as the canonical operator surface for:

- the currently injected merged behavioral model and its contributing agents,
- behavioral-model injection history,
- the latest divergence verdict and verdict history,
- model-independent `Safety Floor / CVE` findings and detector history.

## Cursor-Driven Refresh

The portable package path is bridge-hosted and Cursor-driven:

- Cursor launches `bridge/cursor_edamame_mcp.mjs` through its MCP configuration.
- The bridge uses Cursor lifecycle events that are already part of the stdio MCP flow: `notifications/initialized`, `tools/list`, and `tools/call`.
- On those events it performs a throttled best-effort refresh of the behavioral model, so the Cursor contributor slice is updated when Cursor is actively interacting with the MCP server.

No `launchd`, `systemd`, or separate background daemon is required for the normal package path.

## When The App Restarts

The package expects the app-hosted MCP server and divergence engine to come back
after the app does. Once that happens, the next Cursor-triggered bridge refresh restores the
latest Cursor contributor slice. If there are active transcripts, it rebuilds
the raw transcript payload and calls `upsert_behavioral_model_from_raw_sessions`
again. If there are no active transcripts but the package has a cached generated
slice, it replays that slice through `upsert_behavioral_model` so the app can
recover without waiting for a fresh transcript update.

## Failure Modes

- Missing credential file: use `edamame_cursor_control_center` to pair. On macOS/Windows, "Request pairing from app" or paste a PSK; on Linux, paste and store a fresh local PSK.
- MCP unreachable: `cursor.healthcheck` and `setup/healthcheck.sh` report endpoint failure.
- Divergence engine disabled: health checks stay unhealthy until the operator re-enables the engine in the app path.
- No relevant transcripts and no cached slice: the extrapolator exits non-zero with `no_sessions`.
