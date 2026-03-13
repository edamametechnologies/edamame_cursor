# Cursor EDAMAME Package

This package ports the OpenClaw two-plane divergence pattern to Cursor on a developer workstation:

- Cursor transcripts are the reasoning plane.
- EDAMAME Security is the system-plane observer and verdict authority.
- This package supplies the local bridge, transcript parser, raw-session adapter, extrapolator, and operator tooling around the existing EDAMAME MCP surface.
- Each extrapolator push carries explicit `agent_type` and `agent_instance_id` fields so EDAMAME can merge Cursor and OpenClaw intent into one canonical model.

## Layout

- `bridge/` - local stdio MCP bridge, MCP App resource, and approved forwarding surface for the app-hosted EDAMAME MCP endpoint.
- `adapters/` - Cursor transcript parsing and `RawReasoningSessionPayload` assembly.
- `service/` - control center, extrapolator, posture facade, verdict reader, and health checks.
- `scheduler/` - optional launchd and systemd user-job templates for operators who want out-of-band execution.
- `setup/` - install, bundle, and health-check scripts plus config templates.
- `prompts/` - prompt contract used by EDAMAME-side raw-session ingest.
- `docs/` - architecture, setup, operator guidance, worker-monitor pattern, and validation matrix.

## Behavioral Model Contract

- `service/cursor_extrapolator.mjs` forwards raw reasoning sessions to EDAMAME with `upsert_behavioral_model_from_raw_sessions`, not a standalone verdict.
- `agent_type` defaults to `cursor`.
- `agent_instance_id` is stable per workstation/workspace unless overridden in config.
- EDAMAME uses its configured internal LLM provider to convert the raw transcript payload into a contributor slice and then evaluates the merged model.
- The returned `window.hash` is the contributor-slice hash from EDAMAME; `get_behavioral_model` may return a merged model when multiple producers are active.

## Quick Start

```bash
cd cursor_package
bash setup/install.sh /path/to/workspace
```

Once the MCP snippet is wired into Cursor, refresh is driven by the Cursor MCP lifecycle itself. The bridge opportunistically refreshes on server initialization and before tool calls, so no `launchd` or other OS scheduler is required for the normal package path.

Then wire `setup/cursor-mcp.template.json` or the rendered `cursor-mcp.json` snippet into Cursor's MCP configuration and run `edamame_cursor_control_center`.

In the control center:

- `Refresh status` is read-only. It reads the current pairing, endpoint, engine, and intent/model state from EDAMAME.
- `Export intent now` reads recent Cursor transcripts, exports updated intent to EDAMAME, and then refreshes status.
- `Local EDAMAME host` means the local product exposing the MCP endpoint: the EDAMAME Security App on macOS/Windows, or `edamame_posture` on Linux.

- macOS / Windows: generate the PSK from the EDAMAME Security app, then paste it into the control center.
- Linux: either paste a PSK from `edamame_posture`, or use the control center's automatic posture pairing action to generate, start, and store it locally.

After pairing succeeds:

```bash
bash setup/healthcheck.sh --strict --json
```
