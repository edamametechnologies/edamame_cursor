# Cursor Package Architecture

## Goal

Keep the OpenClaw split intact on a developer workstation:

- Cursor is the reasoning plane and only proposes intent.
- EDAMAME Security remains the system-plane authority for telemetry, behavioral-model storage, divergence-engine execution, and verdict history.

## Producer Modes

EDAMAME supports two additive reasoning-plane producer contracts:

- OpenClaw skill mode: an LLM skill reads session history, builds a `BehavioralWindow`, and calls `upsert_behavioral_model`.
- Cursor workstation mode: this package reads transcript artifacts, builds a `RawReasoningSessionPayload`, and calls `upsert_behavioral_model_from_raw_sessions` so EDAMAME can generate the `BehavioralWindow` internally with its configured LLM provider.

## Component Mapping

| OpenClaw concept | Cursor package component | Responsibility |
|---|---|---|
| MCP bridge | `bridge/cursor_edamame_mcp.mjs` | Present a local stdio MCP server to Cursor, serve the control-center MCP App resource, and forward approved calls to the app-hosted EDAMAME MCP endpoint. |
| Pairing and status UI | `bridge/control_center_app.html` + `service/control_center.mjs` | Collect explicit PSK/endpoint pairing input, persist it locally, and show runtime status without reading secrets from host app internals. |
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

## Why The App Path Works

- The app already hosts the same MCP and RPC divergence surface as `edamame_posture`.
- The package treats app availability as an operational dependency and validates it through `service/health.mjs`.
- Raw-session repush is built into the extrapolator so app restarts do not require model persistence in the package itself.
- Pairing is explicit: the control center stores the PSK in the package state directory instead of scraping secrets from app preferences.
