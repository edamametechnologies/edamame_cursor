import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import {
  buildRawSessionIngestPayload,
  collectTranscriptSessions,
} from "../adapters/session_prediction_adapter.mjs";

async function makeCursorTranscriptFixture() {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "cursor-e2e-"));
  const workspaceRoot = path.join(root, "my_project");
  const cursorProjectsRoot = path.join(root, "cursor-projects");
  const transcriptDir = path.join(
    cursorProjectsRoot,
    "e2e-workspace",
    "agent-transcripts",
  );

  await fs.mkdir(path.join(workspaceRoot, "src"), { recursive: true });
  await fs.mkdir(transcriptDir, { recursive: true });

  const transcriptPath = path.join(transcriptDir, "e2e-session.txt");
  await fs.writeFile(
    transcriptPath,
    `user:
<user_query>
refactor the authentication module and run the test suite
</user_query>

assistant:
[Tool call] ReadFile
  path: ${workspaceRoot}/src/auth.rs
[Tool call] Shell
  command: cargo test --features standalone
[Tool call] StrReplace
  path: ${workspaceRoot}/src/auth.rs
[Tool call] Shell
  command: git diff HEAD
assistant:
I updated the authentication module. The changes touch ${workspaceRoot}/src/auth.rs
and ${workspaceRoot}/src/lib.rs. Do not modify ~/.ssh/id_rsa or ~/.aws/credentials.
The service connects to https://api.edamame.tech/v1/health for verification.
`,
    "utf8",
  );

  return {
    root,
    workspaceRoot,
    cursorProjectsRoot,
    transcriptDir,
    transcriptPath,
  };
}

test("adapter parses a sample Cursor transcript into sessions", async () => {
  const fixture = await makeCursorTranscriptFixture();
  const sessions = await collectTranscriptSessions({
    workspaceRoot: fixture.workspaceRoot,
    cursorProjectsRoot: fixture.cursorProjectsRoot,
    transcriptProjectHints: ["e2e-workspace"],
    transcriptLimit: 4,
    transcriptRecencyHours: 48,
    transcriptActiveWindowMinutes: 5,
    agentType: "cursor",
    agentInstanceId: "e2e-test",
    cursorLlmHosts: [],
  });

  assert.equal(sessions.length, 1, "should find exactly one session");
  const session = sessions[0];
  assert.equal(session.sessionId, "e2e-session");
  assert.ok(session.toolNames.includes("ReadFile"), `toolNames should include ReadFile: ${session.toolNames}`);
  assert.ok(session.toolNames.includes("Shell"), `toolNames should include Shell: ${session.toolNames}`);
  assert.ok(session.toolNames.includes("StrReplace"), `toolNames should include StrReplace: ${session.toolNames}`);
  assert.ok(
    session.commands.some((cmd) => cmd.includes("cargo test")),
    `commands should include cargo test: ${JSON.stringify(session.commands)}`,
  );
  assert.ok(
    session.commands.some((cmd) => cmd.includes("git diff")),
    `commands should include git diff: ${JSON.stringify(session.commands)}`,
  );
});

test("adapter builds a raw payload matching the core ingest schema", async () => {
  const fixture = await makeCursorTranscriptFixture();
  const result = await buildRawSessionIngestPayload({
    workspaceRoot: fixture.workspaceRoot,
    cursorProjectsRoot: fixture.cursorProjectsRoot,
    transcriptProjectHints: ["e2e-workspace"],
    transcriptLimit: 4,
    transcriptRecencyHours: 48,
    transcriptActiveWindowMinutes: 5,
    agentType: "cursor",
    agentInstanceId: "e2e-test",
    cursorLlmHosts: ["api2.cursor.sh:443"],
    scopeProcessPaths: ["*/Cursor Helper*"],
    scopeParentPaths: ["*/Cursor Helper*"],
    scopeGrandparentPaths: [],
    scopeAnyLineagePaths: [],
  });

  const raw = result.rawSessions;

  // Schema-level assertions: required top-level fields.
  assert.equal(raw.agent_type, "cursor");
  assert.equal(raw.agent_instance_id, "e2e-test");
  assert.equal(raw.source_kind, "cursor");
  assert.ok(typeof raw.window_start === "string" && raw.window_start.length > 0);
  assert.ok(typeof raw.window_end === "string" && raw.window_end.length > 0);
  assert.ok(Array.isArray(raw.sessions));
  assert.equal(raw.sessions.length, 1);

  const session = raw.sessions[0];
  assert.equal(session.session_key, "e2e-session");
  assert.ok(typeof session.title === "string" && session.title.length > 0);
  assert.ok(typeof session.user_text === "string");
  assert.ok(typeof session.assistant_text === "string");
  assert.ok(typeof session.raw_text === "string");

  // Array fields expected by the core ingest endpoint.
  for (const field of [
    "tool_names",
    "commands",
    "derived_expected_traffic",
    "derived_expected_local_open_ports",
    "derived_expected_process_paths",
    "derived_expected_parent_paths",
    "derived_expected_grandparent_paths",
    "derived_scope_process_paths",
    "derived_scope_parent_paths",
    "derived_scope_grandparent_paths",
    "derived_scope_any_lineage_paths",
    "derived_expected_open_files",
  ]) {
    assert.ok(Array.isArray(session[field]), `session.${field} should be an array`);
  }

  // Derived behavioral signals.
  assert.ok(
    session.derived_expected_traffic.includes("api2.cursor.sh:443"),
    `traffic should include LLM host: ${session.derived_expected_traffic}`,
  );
  assert.ok(
    session.derived_expected_traffic.some((t) => t.includes("api.edamame.tech")),
    `traffic should include mentioned endpoint: ${session.derived_expected_traffic}`,
  );
  assert.ok(
    session.derived_expected_traffic.includes("crates.io:443"),
    `traffic should include crates.io from cargo command: ${session.derived_expected_traffic}`,
  );

  assert.ok(
    session.derived_expected_process_paths.includes("*/cargo"),
    `process paths should include cargo: ${session.derived_expected_process_paths}`,
  );

  assert.deepEqual(session.derived_scope_process_paths, ["*/Cursor Helper*"]);
  assert.deepEqual(session.derived_scope_parent_paths, ["*/Cursor Helper*"]);

  // Payload hash for dedup.
  assert.ok(typeof result.rawPayloadHash === "string" && result.rawPayloadHash.length > 10);
});
