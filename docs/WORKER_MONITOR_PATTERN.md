# Cursor Worker Monitor Pattern

## Intent Source

The Cursor package treats recent transcripts as the reasoning-plane source of truth. It does not rely on hidden chain-of-thought. Inputs come from:

- user requests,
- assistant planning text,
- tool-call traces in `.txt` transcripts,
- file paths, commands, URLs, ports, and repo references explicitly named in the session.

## Raw Session Payload

`adapters/session_prediction_adapter.mjs` does not build a local
`BehavioralWindow`. It assembles a `RawReasoningSessionPayload` containing:

- `agent_type`, `agent_instance_id`, `source_kind`, `window_start`, and `window_end`
- one entry per transcript session with:
  - `session_key`
  - `title`
  - `user_text`
  - `assistant_text`
  - `raw_text`
  - `tool_names`
  - `commands`
  - `source_path`
  - `started_at`
  - `modified_at`

The adapter extracts `tool_names` from `[Tool call]` lines plus tool-name and
recipient arguments, and it extracts `commands` from transcript command fields.
All higher-level expected and forbidden behavior is inferred later by EDAMAME.

## EDAMAME-Owned Model Generation

The Cursor package does not derive:

- `expected_traffic`
- `expected_sensitive_files`
- `expected_open_files`
- `expected_process_paths`
- `not_expected_*`

Instead, `service/cursor_extrapolator.mjs` sends the raw-session payload to
`upsert_behavioral_model_from_raw_sessions`, and EDAMAME:

- validates the raw payload,
- uses its configured internal LLM provider to generate the contributor
  `BehavioralWindow`,
- rejects malformed LLM output as a hard failure, which the Cursor bridge
  retries briefly before recording as a failed refresh attempt,
- merges the Cursor contributor with any other active producers.

EDAMAME's runtime `Safety Floor / CVE` detector remains model-independent. It
can still raise critical findings even when no behavioral model is present, the
model is stale, or the Cursor package has not refreshed yet.

## Repush Strategy

Behavioral models are not assumed to survive app restarts.
`service/cursor_extrapolator.mjs` therefore:

1. reads the latest local transcripts,
2. rebuilds the `RawReasoningSessionPayload`,
3. calls `upsert_behavioral_model_from_raw_sessions`,
4. stores `lastPayloadHash` and the returned contributor `windowHash` for
   operator diagnostics.

`bridge/cursor_edamame_mcp.mjs` runs this refresh path on a portable interval while
Cursor keeps the MCP bridge connected, so regular model injection does not depend
on `launchd`, `systemd`, or another workstation-specific scheduler.

This keeps recovery logic in the package while leaving verdict ownership inside EDAMAME Security.
