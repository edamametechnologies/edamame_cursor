# EDAMAME Security Demo Test Report

**Date**: 2026-03-15 21:36 -- 22:20 CET (44 minutes)
**Environment**: macOS (kralizec-4.local), EDAMAME Security App, Cursor IDE
**Confirmation tool**: `edamame_cli rpc` (RPC to running app)

---

## Test Plan

### Objective
Validate that EDAMAME's two detection planes -- the **divergence engine** (intent vs. telemetry) and the **vulnerability detector** (CVE/pattern-based) -- correctly detect simulated attacks launched from within a Cursor agent context.

### Demo Scripts Executed

| Script | Target Detection | CVE Reference | Duration |
|--------|-----------------|---------------|----------|
| `trigger_divergence.py` | Divergence: unexplained destinations | N/A | 1800s |
| `trigger_cve_token_exfil.py` | Vulnerability: token_exfiltration | CVE-2025-52882, CVE-2026-25253 | 1800s |
| `trigger_cve_sandbox_escape.py` | Vulnerability: sandbox_exploitation | CVE-2026-24763 | 1800s |
| `trigger_blacklist_comm.py` | Vulnerability: skill_supply_chain | VirusTotal Code Insight | 1800s |

### Monitoring Schedule
Baseline captured at T+0, then checks at T+3, T+5, T+10, T+15, T+20, T+25, T+30 minutes via `edamame_cli rpc`.

---

## Baseline State (T+0, 21:36 CET)

| Metric | Value |
|--------|-------|
| Divergence verdict | Divergence (pre-existing, AWS IPs) |
| Unexplained observations | 11 |
| Active evidence | 10 (all `correlation:unexplained`, Cursor Helper Plugin to AWS IPs) |
| Vulnerability findings | 0 |
| Contributors | 2 (cursor, openclaw) |
| Decision source | LlmConfirmed |

---

## Results

### Vulnerability Detector (CVE Detection)

#### DETECTED: token_exfiltration (CVE-2025-52882 / CVE-2026-25253)

| Field | Value |
|-------|-------|
| First detected | ~T+3 min |
| Severity | HIGH |
| Check | `token_exfiltration` |
| Description | Anomalous session with credential file access detected |
| Process | `python3` |
| Parent | `launchd` |
| Destination | `35.180.139.74:63169` (portquiz.net) |
| Open files | `~/.env_demo_cursor_exfil`, `~/.ssh/demo_cursor_exfil_token` |
| Persistence | Remained active through all 30 min checks and after cleanup |

**Detection path**: flodbadd iForest marked session as anomalous (long-lived high-port TCP flow) + L7 open_files scan detected credential file access -> `token_exfiltration` finding.

#### DETECTED: skill_supply_chain (VirusTotal Code Insight)

| Field | Value |
|-------|-------|
| First detected | ~T+3 min |
| Severity | HIGH |
| Check | `skill_supply_chain` |
| Description | C2 traffic with credential file access detected |
| Process | `python3` |
| Parent | `launchd` |
| Destination | `198.51.100.1:443` (sinkhole.cert.pl) |
| Open files | `~/.ssh/demo_cursor_blacklist_key` |
| Persistence | Remained active through all 30 min checks and after cleanup |

**Detection path**: flodbadd blacklist engine matched destination IP -> session marked blacklisted + L7 open_files detected credential file access -> `skill_supply_chain` finding.

#### NOT DETECTED: sandbox_exploitation (CVE-2026-24763)

| Field | Value |
|-------|-------|
| Expected detection | sandbox_exploitation |
| CVE | CVE-2026-24763 |
| Actual result | Not triggered |

**Root cause analysis**: The vulnerability detector checks `parent_process_path.starts_with("/tmp/")`. The `sandbox_probe` binary runs FROM `/tmp/edamame_cursor_demo/sandbox_probe` (its own **process_path** is under `/tmp/`), but its **parent_process_path** is `/opt/homebrew/.../python3` (the Python wrapper script). The check is looking for the session's L7 parent path starting with `/tmp/`, not the process path itself.

The sandbox probe IS visible in sessions (confirmed via `get_anomalous_sessions`) with `process_path=/tmp/edamame_cursor_demo/sandbox_probe`, but the detection heuristic only fires on `parent_process_path`, not `process_path`.

**Recommendation**: The `sandbox_exploitation` check should also fire when `process_path` itself starts with `/tmp/`, not just `parent_process_path`. A binary running from `/tmp/` is equally suspicious regardless of what spawned it.

### Divergence Engine (Intent vs. Telemetry)

#### Divergence Verdict History (Full 30-min window)

| Timestamp | Verdict | Unexplained | Active Evidence |
|-----------|---------|-------------|-----------------|
| 20:41:29 | Clean | 0 | 0 |
| 20:43:29 | **Divergence** | 7 | 7 |
| 20:45:31 | Clean | 2 | 2 |
| 20:47:28 | Clean | 0 | 0 |
| 20:49:40 | Clean | 0 | 0 |
| 20:51:29 | Clean | 1 | 1 |
| 20:53:28 | **Divergence** | 7 | 7 |
| 20:55:39 | Clean | 1 | 1 |
| 20:57:29 | Clean | 0 | 0 |
| 20:59:24 | Clean | 0 | 0 |
| 21:01:24 | Clean | 1 | 1 |
| 21:03:27 | Clean | 0 | 0 |
| 21:05:29 | Clean | 1 | 1 |
| 21:07:24 | Clean | 0 | 0 |
| 21:09:29 | Clean | 3 | 3 |
| 21:11:31 | **Divergence** | 20 | 10 |
| 21:13:27 | Clean | 0 | 0 |
| 21:15:26 | Clean | 5 | 5 |
| 21:17:22 | Clean | 0 | 0 |
| 21:19:26 | Clean | 0 | 0 |

**3 Divergence events** detected during the test window.

#### Divergence Analysis

All three Divergence verdicts were caused by **Cursor Helper (Plugin)** connections to AWS EC2 IPs (e.g., `34.206.104.129:443`, `52.5.158.229:443`, `18.232.254.206:443`, `23.23.57.136:443`). These are Cursor's backend API servers, which rotate IPs frequently and are not all covered by the `asn:` or domain filters in the behavioral model.

**The demo scripts themselves did NOT trigger divergence**, because:
1. The demo Python processes have `parent_process_path` = `launchd`, not a Cursor path
2. The divergence engine's `scope_parent_paths` filter requires sessions to have a Cursor parent/grandparent to be evaluated
3. Demo processes spawned from `python3` in a Cursor terminal get reparented to `launchd` on macOS once the shell fork completes

This is by design: the divergence engine evaluates only sessions within the Cursor process tree. However, it limits the testability of divergence from demo scripts.

---

## Key Findings and Issues

### 1. Process Lineage Gap for Demo Scripts (IMPORTANT)

**Issue**: Python scripts launched from a Cursor terminal have `parent=launchd` in L7 attribution, not a Cursor path. This means:
- They pass the **vulnerability detector** checks (which scan all sessions regardless of scope)
- They do NOT pass the **divergence engine** scope filter (which requires Cursor parent lineage)

**Impact**: Demo scripts cannot reliably trigger divergence events. Only real Cursor Helper processes produce in-scope sessions for the divergence engine.

**Root cause**: On macOS, processes forked from a terminal session get reparented to `launchd` quickly. The L7 attribution polling cycle captures `launchd` as the parent rather than the Cursor terminal process.

### 2. Sandbox Detection Missing `process_path` Check

**Issue**: `sandbox_exploitation` only checks `parent_process_path.starts_with("/tmp/")`. A binary running from `/tmp/` with a normal parent (Python, bash) is not detected.

**Recommendation**: Add `process_path.starts_with("/tmp/")` as an additional trigger condition.

### 3. AWS IP Rotation Causes Spurious Divergence

**Issue**: Cursor Helper (Plugin) connections to rotating AWS EC2 IPs periodically exceed the `unexplained_observations > 5` threshold, causing transient Divergence verdicts unrelated to actual attacks.

**Impact**: 3 Divergence events during the 30-min window were all false positives from AWS IP rotation, not from the demo attacks.

**Current mitigation**: `asn:CLOUDFLARENET` covers Cloudflare, `amazonaws.com:443` covers most AWS. But EC2 IPs don't always resolve to `*.amazonaws.com` domains.

**Recommendation**: Consider adding `asn:AMAZON` or `asn:AMAZON-02` to `cursorLlmHosts` to cover all AWS infrastructure traffic.

### 4. Vulnerability Findings Persist Correctly

Both CVE findings persisted across all 30-minute checks and survived demo process cleanup. This confirms that findings are anchored to the session data in flodbadd, not to the live process state.

---

## Summary Table

| Detection Type | Script | CVE | Expected | Actual | Latency |
|---------------|--------|-----|----------|--------|---------|
| Vulnerability | trigger_cve_token_exfil.py | CVE-2025-52882/CVE-2026-25253 | DETECTED | DETECTED | ~3 min |
| Vulnerability | trigger_blacklist_comm.py | VirusTotal | DETECTED | DETECTED | ~3 min |
| Vulnerability | trigger_cve_sandbox_escape.py | CVE-2026-24763 | DETECTED | **NOT DETECTED** | N/A |
| Divergence | trigger_divergence.py | N/A | DIVERGENCE | **NOT IN SCOPE** | N/A |

**Vulnerability detector**: 2/3 checks passed (67%). Missing sandbox detection due to `process_path` vs `parent_process_path` gap.

**Divergence engine**: Functional (3 events detected from AWS rotation), but demo scripts are out of scope due to macOS process reparenting.

---

## Recommendations

1. **Extend sandbox check** to also inspect `process_path` (not just `parent_process_path`)
2. **Add AWS ASN** (`asn:AMAZON-02` or `asn:AMAZON`) to Cursor's `cursorLlmHosts` to reduce false-positive divergence from EC2 IP rotation
3. **Consider adding `process_path` to scope filter** as a fallback when parent attribution fails (macOS reparenting to `launchd`)
4. **Demo script improvement**: Create a demo mode that uses `Cursor Helper` process masquerading (e.g., symlink or rename) to test divergence engine scope matching from within demo scripts

---

## Verification Commands Used

```bash
edamame_cli rpc get_divergence_verdict
edamame_cli rpc get_divergence_engine_status
edamame_cli rpc get_divergence_history '[20]'
edamame_cli rpc get_vulnerability_findings
edamame_cli rpc get_vulnerability_detector_status
edamame_cli rpc get_anomalous_sessions
edamame_cli rpc get_blacklisted_sessions
```
