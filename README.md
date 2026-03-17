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

## Installation

### Option A: Cursor Marketplace Plugin (Recommended)

Install from the [Cursor Marketplace](https://cursor.com/marketplace):

1. Open the marketplace panel in Cursor.
2. Search for **EDAMAME Security**.
3. Click **Install**.

The plugin automatically registers the MCP server, rules, skills, agents, and
commands. After installation, run `edamame_cursor_control_center` from Cursor
to pair with your local EDAMAME host.

### Option B: Manual Install (From Source)

For environments where the marketplace is not available, or when you want
full control over the installation:

1. **Clone the repo and run the installer:**

```bash
git clone https://github.com/edamametechnologies/edamame_cursor.git
cd edamame_cursor
bash setup/install.sh /path/to/your/workspace
```

2. **Register the MCP server in Cursor.** The installer renders a
   `cursor-mcp.json` snippet with fully resolved paths. Merge it into your
   Cursor MCP settings (`~/.cursor/mcp.json` or workspace `.cursor/mcp.json`).
   The snippet path is printed at the end of the install.

3. **Restart Cursor**, then run `edamame_cursor_control_center` to pair
   with your local EDAMAME host.

See [Setup Guide](docs/SETUP.md) for detailed config paths per platform.

### Pairing

- **macOS / Windows**: Start the EDAMAME Security app, enable MCP on port
  3000. Primary: click "Request pairing from app" in the control center and
  approve in the app. Fallback: generate a PSK and paste it into the control center.
- **Linux**: Run `edamame_cursor_control_center` and use
  "Generate, start, and pair automatically", or manually start
  `edamame_posture mcp-start 3000 "<PSK>"` and paste the PSK.

### Health Check

```bash
bash setup/healthcheck.sh --strict --json
```

## What the Plugin Provides

| Component | Contents |
|-----------|---------|
| **MCP Server** | stdio bridge forwarding EDAMAME tools (posture, divergence, sessions, remediation) to Cursor |
| **Rules** | Security-awareness guidance, EDAMAME integration patterns |
| **Skills** | Security posture assessment, divergence monitoring and diagnosis |
| **Agents** | Security-monitor agent for safety-aware coding |
| **Commands** | Health check, behavioral model export |

## Layout

| Directory | Purpose |
|-----------|---------|
| `.cursor-plugin/` | Cursor plugin manifest |
| `.mcp.json` | Plugin MCP server definition |
| `rules/` | Cursor rules (.mdc) for security-aware AI guidance |
| `skills/` | Agent skills (security-posture, divergence-monitor) |
| `agents/` | Custom agent definitions (security-monitor) |
| `commands/` | Agent-executable commands (healthcheck, export-intent) |
| `assets/` | Plugin logo and static assets |
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
