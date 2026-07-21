# EDAMAME for Cursor

> **ARCHIVED (EDAMAME 1.7.0):** Level-2 agent plugin distribution is retired. Host-side transcript observation is the default monitoring path; prevention is via **nono** / **srt** governance harnesses. The remaining release gate is [agent_security fleet monitoring](https://github.com/edamametechnologies/agent_security/blob/main/.github/workflows/agent_monitoring_e2e.yml).

**Runtime behavioral monitoring for Cursor on developer workstations.**

EDAMAME Security monitors Cursor **automatically**: its host-side observer runs
two-plane divergence detection against Cursor the moment Cursor is discovered on
disk, with **no plugin required**. This package is a cooperative enhancement — it
adds off-host coverage and turnkey MCP onboarding (see "Observer vs plugin" below),
and never provides, or can weaken, that guarantee.

This is a named Cursor integration for EDAMAME Security, not a separate
EDAMAME product surface.

## How It Works

1. Cursor produces session transcripts while you code.
2. EDAMAME's host-side observer reads those transcripts directly (no plugin required)
   and runs divergence detection. Where the host cannot read them (off-host / remote /
   container), this package forwards them via MCP instead.
3. EDAMAME evaluates behavioral intent against live system telemetry.
4. Divergence verdicts surface in EDAMAME (and, for convenience, through this package's
   control center or health checks).

## Observer vs plugin: what provides the security

EDAMAME's **host-side transcript observer is the security control of
record** -- it runs divergence detection against Cursor as soon as Cursor
is discovered on disk, with **zero plugin installed**, and a compromised
agent cannot pause or silence it. This package is a **cooperative
enhancement**: it adds **off-host coverage** (when Cursor runs where the
host observer cannot read its transcripts -- remote box, SSH, container,
CI, VM) and **turnkey onboarding/UX** (MCP discovery, pairing, in-agent
posture/verdict views, health checks). It never provides -- and can never
weaken -- the guarantee. See
[Observer vs plugin: the value boundary](docs/ARCHITECTURE.md#observer-vs-plugin-the-value-boundary).

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
bash setup/install.sh [/path/to/your/workspace]
```

The workspace argument is **optional**. It seeds `transcript_project_hints`
and `agent_instance_id`. When omitted, the plugin monitors transcripts from
all workspaces. The install is **global per-user** -- no need to reinstall
when switching projects.

2. **Restart Cursor**, then run `edamame_cursor_control_center` to pair
   with your local EDAMAME host.

The installer automatically registers the `edamame` MCP server entry in
Cursor's global configuration (`~/.cursor/mcp.json`). When installing via
the EDAMAME Security app or `edamame-posture install-agent-plugin cursor`, the same
automatic registration is performed by the provisioning engine. If Cursor's
global MCP config already contains other servers, they are preserved.

See [Setup Guide](docs/SETUP.md) for detailed config paths per platform.

### Pairing

- **macOS / Windows**: Start the EDAMAME Security app, enable MCP on port
  3000. Primary: click "Request pairing from app" in the control center and
  approve in the app. Fallback: generate a PSK and paste it into the control center.
- **Linux**: Run `edamame-posture mcp-generate-psk` then
  `edamame-posture mcp-start 3000 "<PSK>"`, and paste the PSK into the
  control center. Or run `edamame_cursor_control_center` and use
  "Generate, start, and pair automatically".

### Troubleshooting: `env: node: No such file or directory`

Cursor does not inherit your shell's `PATH`. If `node` is installed via
Homebrew or nvm, Cursor may not find it. The manual installer resolves this
automatically (it writes the absolute `node` path into the rendered MCP
snippet). If you see this error after a Marketplace install, edit
`~/.cursor/mcp.json` and replace `"command": "node"` with the full path
(e.g. `"/opt/homebrew/bin/node"` on macOS with Homebrew).

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
| `setup/` | Install, bundle, and health-check scripts plus config templates |
| `prompts/` | Prompt contract used by EDAMAME-side raw-session ingest |
| `docs/` | Architecture, setup, operator guidance, validation |
| `tests/` | Unit tests and [E2E intent injection](E2E_TESTS.md) |

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

## E2E Tests

Intent injection E2E test: see [E2E_TESTS.md](E2E_TESTS.md) for details.

```bash
bash tests/e2e_inject_intent.sh
```

The full cross-agent E2E harness (intent + CVE/divergence) lives in
[agent_security/tests/e2e/](https://github.com/edamametechnologies/agent_security/tree/main/tests/e2e).

## Related Repositories

| Repository | Purpose |
|------------|---------|
| [edamame_openclaw](https://github.com/edamametechnologies/edamame_openclaw) | EDAMAME OpenClaw integration |
| [edamame_claude_code](https://github.com/edamametechnologies/edamame_claude_code) | EDAMAME integration for Claude Code |
| [edamame_claude_desktop](https://github.com/edamametechnologies/edamame_claude_desktop) | EDAMAME integration for Claude Desktop |
| [edamame_codex](https://github.com/edamametechnologies/edamame_codex) | EDAMAME integration for Codex CLI |
| [agent_security](https://github.com/edamametechnologies/agent_security) | Research paper: two-plane runtime security (arXiv preprint) |
| [edamame_security](https://github.com/edamametechnologies/edamame_security) | EDAMAME Security desktop/mobile app |
| [edamame_posture](https://github.com/edamametechnologies/edamame_posture) | EDAMAME Posture CLI for CI/CD and servers |
| [edamame_core_api](https://github.com/edamametechnologies/edamame_core_api) | EDAMAME Core public API documentation |
| [threatmodels](https://github.com/edamametechnologies/threatmodels) | Public security benchmarks, policies, and threat models |

### Related Named Integrations

- **edamame_claude_code** (Claude Code): Easy install via Claude Code marketplace:
  ```shell
  /plugin marketplace add edamametechnologies/edamame_claude_code
  /plugin install edamame@edamame-security
  ```
- **edamame_openclaw** (OpenClaw): See [edamame_openclaw README](https://github.com/edamametechnologies/edamame_openclaw) for plugin bundle and Lima VM provisioning.

## License

Apache License 2.0 -- see [LICENSE](LICENSE).
