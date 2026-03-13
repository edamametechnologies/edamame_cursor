# Validation Matrix

| Area | Check | Mechanism | Expected result |
|---|---|---|---|
| Transcript contract | Parse `.txt` transcript with tool calls | `node --test tests/adapter.test.mjs` | tool names, commands, raw text, source path, and agent identity fields are captured in a valid raw-session payload |
| Transcript fallback | Parse `.jsonl` transcript without tool calls | `node --test tests/adapter.test.mjs` | the adapter still builds a valid raw-session payload |
| Bridge surface | Launch local stdio MCP bridge and dispatch tool handlers | `node --test tests/bridge.test.mjs` | `initialize`, `tools/list`, `resources/read`, `edamame_cursor_control_center`, and `cursor.healthcheck` dispatch cleanly |
| Cursor raw ingest | Manual intent export | `node service/cursor_extrapolator.mjs --json` | raw sessions are forwarded and EDAMAME returns a generated contributor window plus `windowHash` |
| EDAMAME raw ingest contract | Invalid payload rejection | `cargo test --features swiftrs --test divergence_api_roundtrip_tests test_raw_session_ingest_api_rejects_invalid_payload_before_llm_generation -- --nocapture` | malformed raw-session payloads fail before LLM generation |
| OpenClaw prebuilt mode | Direct behavioral-window upsert path | `./tests/test_behavioral_model_divergence.sh` | OpenClaw-style `upsert_behavioral_model` still works alongside Cursor raw-session ingest |
| Bundle output | Build distributable bundle | `bash setup/build_bundle.sh` | `dist/cursor-edamame-bundle/` contains bridge, adapters, service, scheduler, docs, and setup assets |
| Package smoke | End-to-end package self-check | `tests/test_cursor_divergence_package.sh` | tests pass and the bundle contains required artifacts |
| Workstation smoke | App running, MCP reachable, engine enabled, model present | `bash setup/healthcheck.sh --strict --json` | all checks report healthy |
| Contributor sync | Cursor shares EDAMAME with another agent | workstation exercise | the generated Cursor contributor is merged with other producers while preserving `agent_type` and `agent_instance_id` attribution |
| Read-only posture | Manual verdict read | `node service/verdict_reader.mjs --json` | divergence verdict, score, todos, and suspicious sessions are readable |
| Benign scenario | Narrow file-edit task | workstation exercise | verdict remains `CLEAN` |
| Divergent scenario | `/tmp` execution chain or credential-access task | workstation exercise | verdict becomes `DIVERGENCE` with supporting evidence |
| Restart recovery | EDAMAME app restart with empty model store | workstation exercise | next Cursor-triggered bridge refresh restores the Cursor contributor slice either from a fresh raw-session ingest or from the cached generated window when no active transcripts exist |
| Config drift | moved PSK or changed endpoint | workstation exercise | health check fails clearly until config is updated |
