# EDAMAME for Cursor

**Runtime behavioral monitoring for Cursor on developer workstations.**

This package bridges Cursor transcripts (reasoning plane) to the
[EDAMAME Security](https://edamame.tech) system-plane observer, enabling
two-plane divergence detection on developer machines.

## How It Works

1. Cursor produces session transcripts while you code.
2. This package parses transcripts and forwards them to EDAMAME via MCP.
3. EDAMAME evaluates behavioral intent against live system telemetry.
4. Divergence verdicts surface through the control center or health checks.

## Prerequisites

- **Node.js 18+**
- **EDAMAME Security** running on the same machine:
  - macOS / Windows: [EDAMAME Security app](https://edamame.tech)
  - Linux: [edamame_posture](https://github.com/edamametechnologies/edamame_posture) CLI

## Quick Start

```bash
# Install the package for your workspace
bash setup/install.sh /path/to/workspace
```

Wire `setup/cursor-mcp.template.json` (or the rendered `cursor-mcp.json`)
into Cursor's MCP configuration, then run `edamame_cursor_control_center`
from Cursor to pair with EDAMAME.

### Pairing

- **macOS / Windows**: Start the EDAMAME Security app, enable MCP on port
  3000, generate a PSK, paste it into the control center.
- **Linux**: Run `edamame_cursor_control_center` and use
  "Generate, start, and pair automatically", or manually start
  `edamame_posture mcp-start 3000 "<PSK>"` and paste the PSK.

### Health Check

```bash
bash setup/healthcheck.sh --strict --json
```

## Layout

| Directory | Purpose |
|-----------|---------|
| `bridge/` | Local stdio MCP bridge, control center MCP App, forwarding surface |
| `adapters/` | Cursor transcript parsing and `RawReasoningSessionPayload` assembly |
| `service/` | Control center, extrapolator, posture facade, verdict reader, health checks |
| `scheduler/` | Optional launchd and systemd user-job templates |
| `setup/` | Install, bundle, and health-check scripts plus config templates |
| `prompts/` | Prompt contract used by EDAMAME-side raw-session ingest |
| `docs/` | Architecture, setup, operator guidance, validation |
| `tests/` | Unit tests |

## Documentation

- [Setup Guide](docs/SETUP.md) -- install, config paths, pairing, health checks
- [Architecture](docs/ARCHITECTURE.md) -- component mapping and runtime flow
- [Operator Guide](docs/OPERATOR_GUIDE.md) -- day-to-day operations
- [Worker-Monitor Pattern](docs/WORKER_MONITOR_PATTERN.md) -- behavioral model lifecycle
- [Validation](docs/VALIDATION.md) -- test coverage and validation matrix

## Behavioral Model Contract

- `service/cursor_extrapolator.mjs` forwards raw reasoning sessions to
  EDAMAME via `upsert_behavioral_model_from_raw_sessions`.
- `agent_type` defaults to `cursor`.
- `agent_instance_id` is stable per workstation/workspace unless overridden.
- EDAMAME uses its configured LLM provider to convert raw transcripts into
  a contributor slice, then evaluates the merged model.
- Refresh is driven by the Cursor MCP lifecycle; no OS scheduler required.

## Running Tests

```bash
node --test tests/*.test.mjs
```

## Related Repositories

| Repository | Purpose |
|------------|---------|
| [edamame_openclaw](https://github.com/edamametechnologies/edamame_openclaw) | EDAMAME integration for OpenClaw agents |
| [agent_security](https://github.com/edamametechnologies/agent_security) | Research paper: two-plane runtime security (arXiv preprint) |
| [edamame_security](https://github.com/edamametechnologies/edamame_security) | EDAMAME Security desktop/mobile app |
| [edamame_posture](https://github.com/edamametechnologies/edamame_posture) | EDAMAME Posture CLI for CI/CD and servers |
| [edamame_core_api](https://github.com/edamametechnologies/edamame_core_api) | EDAMAME Core public API documentation |
| [threatmodels](https://github.com/edamametechnologies/threatmodels) | Public security benchmarks, policies, and threat models |

## License

Apache License 2.0 -- see [LICENSE](LICENSE).
