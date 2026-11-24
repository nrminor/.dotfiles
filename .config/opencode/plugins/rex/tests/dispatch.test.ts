import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect, Option, Predicate, Schema } from "effect";
import { BlockId, SessionId, decodeRexEvent, type IRexSdk, type RexRequestOptions, RexRequestTimeout } from "rex-sdk";
import { RexToolFailure, rexToolOperations } from "../vendor/rex-tool-operations.ts";
import { RexMarkStore } from "../vendor/rex-tool-marks.ts";

// Acceptance seam: flat catalog arguments -> public SDK methods. These expectations
// are independent of the catalog's method/run metadata. Argument examples follow
// the pinned SDK's schema/rex-api.json and testing/rex-block-method-examples.ts.
// This spy deliberately does NOT claim to test SDK websocket encoding or host
// authorization (the host suite owns that boundary).
const sessionId = Schema.decodeUnknownSync(SessionId)("session:selected");
const blockId = Schema.decodeUnknownSync(BlockId)("block:existing");
const windowId = "window:editor";
const layerId = "layer:floating";
const target = { sessionId, blockId };
const session = { sessionId };
const window = { sessionId, windowId };
const layer = { sessionId, layerId };
const layout = { _tag: "Terminal", label: "logs" };
const options: RexRequestOptions = { timeout: "713 millis" };
const marker = { offset: 17, anchor: ["previous"], hasCursorLine: true };
const response = { fixture: "SDK response must survive dispatch unchanged" };

type Call = { path: string; args: readonly unknown[] };
type Case = {
  name: string;
  params: Record<string, unknown>;
  calls: readonly Call[];
  result?: unknown;
  expected?: unknown;
};

function input(path: string, params: Record<string, unknown>): Case {
  return {
    name: path.replaceAll(".", "_"),
    params,
    calls: [{ path, args: [params, options] }],
  };
}

function noInput(path: string): Case {
  return {
    name: path.replaceAll(".", "_"), params: {},
    calls: [{ path, args: [options] }],
  };
}

function block(path: string, args?: Record<string, unknown>): Case {
  return {
    name: path.replaceAll(".", "_"),
    params: { ...target, ...args },
    calls: [{ path, args: args === undefined ? [target, options] : [target, args, options] }],
  };
}

// Explicit SDK-path ledger: neither names nor expected calls are read from the
// production operation table. Distinct IDs expose swapped target arguments.
const direct: readonly Case[] = [
  input("sessions.view", session),
  input("blocks.splitBeside", { ...session, placement: "right", anchorId: blockId, layout, ratio: 0.4, focus: false }),
  noInput("server.status"),
  noInput("server.version"),
  noInput("server.whoami"),
  noInput("server.reloadConfig"),
  input("server.stop", { ifIdle: true }),
  noInput("server.help"),
  input("server.tailscale.enable", { hostname: "studio", allowTailnetMembers: false }),
  noInput("server.tailscale.disable"),
  noInput("server.tailscale.login"),
  noInput("server.tailscale.logout"),
  input("server.tailscale.rename", { hostname: "studio" }),
  input("server.apple.grantFileAccess", { files: [{ path: "/project/README.md", token: "grant" }] }),
  noInput("server.apple.privacyStatus"),
  noInput("sessions.list"),
  input("sessions.create", { label: "work", initialWindows: [{ windowLabel: "editor", layout }] }),
  input("sessions.destroy", session),
  input("sessions.setLabel", { ...session, label: "" }),
  input("sessions.move", { ...session, beforeSessionId: "session:other" }),
  input("sessions.listBlocks", session),
  input("sessions.listClients", session),
  input("sessions.help", session),
  input("windows.create", { ...session, windowLabel: "server", layout, focus: false }),
  input("windows.close", window),
  input("windows.focus", window),
  input("windows.focusNext", { ...session, wrap: true }),
  input("windows.focusPrevious", { ...session, wrap: false }),
  input("windows.move", { ...window, beforeWindowId: "window:other" }),
  input("windows.setLabel", { ...window, label: "" }),
  input("blocks.split", { ...session, anchorId: blockId, direction: "horizontal", side: "after", layout, focus: false }),
  input("blocks.create", { ...session, flavor: "com.superlogical.terminal.shell", label: "logs" }),
  input("blocks.move", { ...target, anchorBlockId: "block:other", direction: "vertical" }),
  input("blocks.swap", { ...target, otherBlockId: "block:other" }),
  input("blocks.zoom", { ...target, zoom: false }),
  input("blocks.detach", target),
  input("blocks.float", { ...target, bounds: [0.1, 0.2, 0.6, 0.5] }),
  input("blocks.focus", target),
  input("blocks.focusDirection", { ...session, direction: "right", wrap: false }),
  input("blocks.focusNext", { ...session, wrap: true }),
  input("blocks.focusPrevious", { ...session, wrap: false }),
  input("blocks.resize", { ...session, direction: "horizontal", beforeBlockId: blockId, afterBlockId: "block:other", ratio: 0.65 }),
  input("blocks.setLabel", { ...target, label: "" }),
  input("blocks.own", { ...session, blockIds: [blockId], mode: "request" }),
  input("blocks.disown", { ...session, blockIds: [blockId] }),
  input("blocks.describe", target),
  input("blocks.close", target),
  input("blocks.sendEvent", { ...target, event: { type: "paste", payload: { text: "echo hello\n" } } }),
  input("blocks.callMethod", { ...target, method: "write", args: { data: "echo hello\r" } }),
  input("layers.create", { ...session, layout, bounds: [0.1, 0.1, 0.8, 0.6], focus: false }),
  input("layers.close", layer),
  input("layers.raise", layer),
  input("layers.lower", layer),
  input("layers.resize", { ...layer, bounds: [0.2, 0.15, 0.5, 0.6] }),
  input("layers.setState", { ...layer, state: "minimized" }),
  block("terminals.write", { data: "ls\r" }),
  block("terminals.format", { trim: true, unwrap: true, maxBytes: 4096 }),
  block("terminals.blobRead", { id: 4, offset: 10 }),
  block("terminals.clear"),
  block("terminals.reset"),
  block("terminals.resize", { columns: 120, rows: 40 }),
  block("terminals.size"),
  block("terminals.setTheme", { foreground: "#ffffff", background: "#000000" }),
  block("terminals.title"),
  block("terminals.pwd"),
  block("terminals.process"),
  block("terminals.modes"),
  block("terminals.inputMode"),
  block("terminals.listDir", { path: "~", files: true }),
  block("terminals.clipboardRead", { id: 2 }),
  block("terminals.programStatus"),
  block("terminals.ports"),
  input("tunnels.createDial", { ...session, label: "db", options: { host: "127.0.0.1", port: 5432 } }),
  input("tunnels.createListen", { ...session, label: "web", options: { port: 8080 } }),
  block("tunnels.info"),
  input("clients.list", { kinds: ["app"] }),
  input("clients.inspect", { clientId: "client:app" }),
  input("clients.setLabel", { label: "studio" }),
  input("clients.setScript", { scripts: [{ name: "init.lua", source: "return true" }] }),
  input("clients.keymap", { actions: [{ name: "pane.split", kind: "client", title: "Split Pane" }] }),
  input("clients.action", { ...session, action: "com.superlogical.terminal.reset", origin: "key" }),
  input("clients.key", { ...session, key: { key: "key_g", mods: "ctrl", consumedMods: "", text: "", unshiftedCodepoint: 103, composing: false, action: "press" } }),
  input("clients.perform", { clientId: "client:app", action: "pane.split", args: { direction: "right" }, origin: "cli" }),
  input("clients.reply", { callId: "1", result: { revision: 7 } }),
  input("targets.resolve", { kinds: ["block"], queries: ["shell", "build"], scope: { session: "work" } }),
  input("targets.complete", { kinds: ["block", "window"], prefix: "s", context: session }),
  noInput("hosts.list"),
  input("hosts.put", { host: { id: "host:studio", label: "studio", endpoints: ["studio.tail1234.ts.net"], addedFrom: "laptop" } }),
  input("hosts.remove", { id: "host:studio" }),
  noInput("creators.list"),
];

const helpers: readonly Case[] = [
  {
    name: "terminals_writeLine", params: { ...target, text: "echo 雪" },
    calls: [
      { path: "terminals.mark", args: [target, options] },
      { path: "terminals.writeLine", args: [target, "echo 雪", options] },
    ],
    expected: "mark",
  },
  {
    name: "terminals_mark", params: target,
    calls: [{ path: "terminals.mark", args: [target, options] }],
    expected: "mark",
  },
  {
    name: "terminals_waitForOutput",
    params: { ...target, match: { type: "substring", value: "ready" }, lines: 31, timeoutMs: 213 },
    calls: [{ path: "terminals.waitForOutput", args: [target, { pattern: "ready", since: undefined, lines: 31 }, { timeout: "213 millis" }] }],
    result: { line: "ready!", text: "ready", groups: [], alignment: null },
    expected: { timedOut: false, match: { line: "ready!", text: "ready", groups: [], alignment: null } },
  },
  {
    name: "terminals_waitForQuiet", params: { ...target, quietForMs: 27, timeoutMs: 213 },
    calls: [{ path: "terminals.waitForQuiet", args: [target, { quietFor: "27 millis", timeout: "213 millis" }] }],
    expected: { timedOut: false, quiet: true },
  },
  {
    name: "terminals_waitForExit", params: { ...target, timeoutMs: 213 },
    calls: [{ path: "terminals.waitForExit", args: [target, { timeout: "213 millis" }] }],
    result: { exitCode: 7, error: null },
    expected: { timedOut: false, exit: { exitCode: 7, error: null } },
  },
  {
    name: "terminals_readTail", params: { ...target, maxBytes: 67 },
    calls: [{ path: "terminals.readTail", args: [target, { maxBytes: 67 }, options] }],
    result: { lines: ["α", "β"], truncated: true, privateMetadata: "not public" },
    expected: { lines: ["α", "β"], truncated: true },
  },
  {
    name: "terminals_read", params: { ...target, trim: true },
    calls: [{ path: "terminals.format", args: [target, { trim: true, maxBytes: 32768 }, options] }],
    result: { content: "α\nβ", id: Option.none() }, expected: "α\nβ",
  },
  {
    name: "terminals_readFile", params: { ...target, path: "report.txt" },
    calls: [{ path: "terminals.readFile", args: [target, "report.txt", { maxBytes: 1048576 }, options] }],
    result: { file: { path: "/report.txt", name: "report.txt", size: 3, modifiedAt: "2026-10-29T00:00:00Z", version: null }, bytes: Buffer.from("雪") },
    expected: { file: { path: "/report.txt", name: "report.txt", size: 3, modifiedAt: "2026-10-29T00:00:00Z", version: null }, encoding: "utf8", content: "雪" },
  },
  {
    name: "terminals_pasteFiles",
    params: { ...target, files: [{ name: "one.txt", text: "雪" }, { name: "two.bin", base64: "AP+A" }] },
    calls: [{ path: "terminals.pasteFiles", args: [target, [{ name: "one.txt", data: "雪" }, { name: "two.bin", data: Buffer.from([0, 255, 128]) }], options] }],
    result: undefined, expected: null,
  },
];

function operation(name: string) {
  const found = rexToolOperations.filter((item) => item.name === name);
  assert.equal(found.length, 1, `exactly one catalog operation named ${name}`);
  return found[0]!;
}

function fixture(result: unknown, failure?: Error) {
  const calls: Call[] = [];
  function namespace(path: string): unknown {
    return new Proxy(() => {}, {
      get: (_target, key) => namespace(path ? `${path}.${String(key)}` : String(key)),
      apply: (_target, _this, args) => {
        calls.push({ path, args });
        if (failure) return Effect.fail(failure);
        return Effect.succeed(path === "terminals.mark" ? marker : result);
      },
    });
  }
  return { sdk: namespace("") as IRexSdk, calls };
}

async function run(name: string, params: Record<string, unknown>, sdk: IRexSdk, marks = new RexMarkStore()) {
  return Effect.runPromise(operation(name).program(sdk, params, options, marks).pipe(Effect.timeout("1 second")));
}

for (const entry of [...direct, ...helpers]) {
  test(`${entry.name} decodes flat arguments and dispatches the documented SDK call`, async () => {
    const value = "result" in entry ? entry.result : response;
    const { sdk, calls } = fixture(value);
    const marks = new RexMarkStore();
    const actual = await run(entry.name, { ...entry.params, undeclared: "must not reach SDK" }, sdk, marks);
    assert.deepEqual(calls, entry.calls);
    if (entry.expected === "mark") {
      assert.equal(typeof (actual as { markId: string }).markId, "string");
      assert.deepEqual(await Effect.runPromise(marks.get((actual as { markId: string }).markId, target)), marker);
    } else {
      assert.deepEqual(actual, "expected" in entry ? entry.expected : response);
    }
    // Helpers transform SDK values; unlike the direct passthrough sentinel, their
    // fixtures are actual public results and must satisfy the advertised schema.
    if ("expected" in entry && operation(entry.name).output !== "void") {
      Schema.decodeUnknownSync(Schema.toType(operation(entry.name).output as Schema.Top))(actual);
    }
  });
}

test("the independent dispatch ledger covers every finite operation exactly once", () => {
  const names = [...direct, ...helpers].map((entry) => entry.name).concat("events_waitFor");
  assert.equal(names.length, 100);
  assert.equal(new Set(names).size, 100);
  assert.deepEqual([...names].sort(), rexToolOperations.map((entry) => entry.name).sort());
});

test("events_waitFor passes a conjunctive predicate and session-scoped subscription", async () => {
  const event = await Effect.runPromise(decodeRexEvent({
    generation: 1, seq: 3, type: "session_event",
    payload: {
      session_id: sessionId,
      event: {
        type: "block_event",
        payload: {
          block_id: blockId, creator_name: "com.superlogical.terminal",
          name: "child_exited", payload: { exit_code: 0 },
        },
      },
    },
  }));
  const { sdk, calls } = fixture(event);
  assert.deepEqual(
    await run("events_waitFor", { ...target, source: "terminal", type: "child_exited", timeoutMs: 213 }, sdk),
    {
      timedOut: false,
      event: {
        _tag: "TerminalEvent", seq: 3, sessionId, blockId,
        name: "child_exited", payload: { exitCode: 0, error: null },
      },
    },
  );
  assert.equal(calls.length, 1);
  assert.equal(calls[0]!.path, "events.waitFor");
  const [predicate, subscription] = calls[0]!.args;
  assert.deepEqual(subscription, { timeout: "213 millis", sessionIds: [sessionId], server: "none" });
  const matches = predicate as (event: unknown) => boolean;
  assert.equal(matches(event), true);
  for (const change of [
    { _tag: "SessionEvent" }, { name: "output" }, { sessionId: "session:other" }, { blockId: "block:other" },
  ]) assert.equal(matches({ ...event, ...change }), false, JSON.stringify(change));
});

for (const entry of [...direct, ...helpers]) {
  test(`${entry.name} does not swallow SDK failures`, async () => {
    const error = new Error(`failed ${entry.name}`);
    const { sdk, calls } = fixture(undefined, error);
    await assert.rejects(run(entry.name, entry.params, sdk),
      (actual) => actual instanceof RexToolFailure && actual.phase === "execution" && actual.cause === error);
    assert.equal(error.message, `failed ${entry.name}`, "wrapping preserves the original SDK error");
    assert.deepEqual(calls, entry.calls.slice(0, 1), "failure stops further SDK calls");
  });
}

test("read refuses a continuation rather than fetching unbounded terminal output", async () => {
  const { sdk, calls } = fixture({ content: "partial", id: Option.some(4) });
  await assert.rejects(run("terminals_read", target, sdk), (error) =>
    error instanceof RexToolFailure && error.phase === "execution" && Predicate.isTagged(error.cause, "RexReadLimit"));
  assert.deepEqual(calls, [{ path: "terminals.format", args: [target, { maxBytes: 32768 }, options] }]);
});

test("completed SDK work is not replayed when its result cannot be encoded", async () => {
  const { sdk, calls } = fixture({ unsupported: () => "not JSON" });
  await assert.rejects(run("sessions_create", { label: "one attempt" }, sdk), (error) => {
    assert.ok(error instanceof RexToolFailure);
    assert.equal(error.operation, "sessions_create");
    assert.equal(error.phase, "encoding");
    assert.ok(error.cause instanceof Error);
    assert.match(error.cause.message, /unsupported function/);
    assert.match(error.message, /completed.*Do not repeat a mutation/);
    return true;
  });
  assert.deepEqual(calls, [{
    path: "sessions.create", args: [{ label: "one attempt" }, options],
  }]);
});

test("the JSON boundary unwraps SDK Options without changing the SDK response", async () => {
  const response = { title: Option.some("ready"), missing: Option.none(), omitted: undefined };
  const { sdk, calls } = fixture(response);
  assert.deepEqual(await run("terminals_title", target, sdk), { title: "ready", missing: null });
  assert.deepEqual(response, { title: Option.some("ready"), missing: Option.none(), omitted: undefined });
  assert.deepEqual(calls, [{ path: "terminals.title", args: [target, options] }]);
});

test("output waits compile regexes and resolve a mark only for its terminal", async () => {
  const marks = new RexMarkStore();
  const since = marks.put(target, marker);
  const { sdk, calls } = fixture(response);
  await run("terminals_waitForOutput", { ...target, since, match: { type: "regex", value: "(ready)", flags: "i" }, timeoutMs: 19 }, sdk, marks);
  assert.deepEqual(calls, [{ path: "terminals.waitForOutput", args: [target, { pattern: /(ready)/i, since: marker, lines: undefined }, { timeout: "19 millis" }] }]);
  calls.length = 0;
  await assert.rejects(run("terminals_waitForOutput", { ...target, blockId: "block:other", since, match: { type: "substring", value: "ready" }, timeoutMs: 19 }, sdk, marks),
    (error) => error instanceof RexToolFailure && error.phase === "execution" && Predicate.isTagged(error.cause, "RexUnknownMark"));
  assert.deepEqual(calls, []);
});

test("malformed regexes fail before SDK dispatch", async () => {
  const { sdk, calls } = fixture(response);
  await assert.rejects(run("terminals_waitForOutput", { ...target, match: { type: "regex", value: "[" }, timeoutMs: 19 }, sdk),
    (error) => error instanceof RexToolFailure && error.phase === "execution" && Predicate.isTagged(error.cause, "RexInvalidPattern"));
  assert.deepEqual(calls, []);
});

for (const [name, path, params, method] of [
  ["terminals_waitForOutput", "terminals.waitForOutput", { ...target, match: { type: "substring", value: "ok" }, timeoutMs: 0 }, "TerminalService.waitForOutput"],
  ["terminals_waitForQuiet", "terminals.waitForQuiet", { ...target, quietForMs: 1, timeoutMs: 0 }, "TerminalService.waitForQuiet"],
  ["terminals_waitForExit", "terminals.waitForExit", { ...target, timeoutMs: 0 }, "TerminalService.waitForExit"],
  ["events_waitFor", "events.waitFor", { timeoutMs: 0 }, "EventService.waitFor"],
] as const) {
  test(`${name} converts only its own deadline into timedOut`, async () => {
    const deadline = new RexRequestTimeout(method, "wait:fixture", 0);
    const own = fixture(undefined, deadline);
    assert.deepEqual(await run(name, params, own.sdk), { timedOut: true });
    assert.equal(own.calls[0]!.path, path);
    const inner = new RexRequestTimeout("block.method", "request:fixture", 0);
    await assert.rejects(run(name, params, fixture(undefined, inner).sdk),
      (actual) => actual instanceof RexToolFailure && actual.phase === "execution" && actual.cause === inner);
  });
}

test("readFile honors explicit binary encoding and byte budget", async () => {
  const file = { path: "/binary", name: "binary", size: 3, modifiedAt: "2026-10-29T00:00:00Z", version: null };
  const { sdk, calls } = fixture({ file, bytes: Uint8Array.from([0, 255, 128]) });
  const result = await run("terminals_readFile", { ...target, path: "/binary", encoding: "base64", maxBytes: 3 }, sdk);
  assert.deepEqual(result, { file, encoding: "base64", content: "AP+A" });
  assert.deepEqual(calls, [{ path: "terminals.readFile", args: [target, "/binary", { maxBytes: 3 }, options] }]);
  Schema.decodeUnknownSync(Schema.toType(operation("terminals_readFile").output as Schema.Top))(result);
});

for (const [name, params] of [
  ["sessions_view", {}],
  ["blocks_splitBeside", { ...session, placement: "diagonal" }],
  ["blocks_split", { ...session, layout: { _tag: "Unknown" } }],
  ["terminals_write", { ...target, data: 42 }],
  ["terminals_resize", { ...target, columns: "120", rows: 40 }],
  ["terminals_waitForOutput", { ...target, match: { type: "substring", value: "ok" } }],
  ["terminals_waitForOutput", { ...target, match: { type: "substring", value: "ok" }, timeoutMs: -1 }],
  ["terminals_waitForQuiet", { ...target, quietForMs: 0, timeoutMs: 10 }],
  ["terminals_waitForExit", { ...target, timeoutMs: Infinity }],
  ["terminals_readTail", { ...target, maxBytes: 0 }],
  ["terminals_readFile", { ...target, path: "x", maxBytes: 0 }],
  ["terminals_readFile", { ...target, path: "x", encoding: "hex" }],
  ["terminals_pasteFiles", { ...target, files: [] }],
  ["terminals_pasteFiles", { ...target, files: [{ name: "x" }] }],
  ["events_waitFor", { timeoutMs: NaN }],
  ["tunnels_createDial", { ...session, options: { port: 5432 } }],
] as const) {
  test(`${name} rejects invalid input before any SDK call: ${JSON.stringify(params)}`, async () => {
    const { sdk, calls } = fixture(response);
    await assert.rejects(run(name, params, sdk), (error) => {
      assert.equal((error as { _tag: string })._tag, "SchemaError");
      return true;
    });
    assert.deepEqual(calls, []);
  });
}

test("read honors an explicit format and budget without calling the unbounded SDK read helper", async () => {
  const { sdk, calls } = fixture({ content: "<pre>雪</pre>", id: Option.none() });
  const result = await run("terminals_read", { ...target, format: "html", maxBytes: 513, trim: false }, sdk);
  assert.equal(result, "<pre>雪</pre>");
  assert.deepEqual(calls, [{ path: "terminals.format", args: [target, { format: "html", maxBytes: 513, trim: false }, options] }]);
});

for (const [source, event, other] of [
    [
      "server",
      { _tag: "ServerEvent", seq: 1, type: "session_created", payload: { session: { sessionId } } },
      { _tag: "ServerEvent", seq: 2, type: "session_created", payload: { session: { sessionId: "session:other" } } },
    ],
    [
      "unknown",
      { _tag: "UnknownEvent", seq: 1, name: "future_event", sessionId: Option.some(sessionId) },
      { _tag: "UnknownEvent", seq: 2, name: "future_event", sessionId: Option.none() },
    ],
  ] as const) {
  test(`${source} event filters find the session identity without narrowing to session events`, async () => {
    const { sdk, calls } = fixture(event);
    await run("events_waitFor", { sessionId, source, timeoutMs: 17 }, sdk);
    assert.equal(calls.length, 1);
    const [predicate, subscription] = calls[0]!.args;
    assert.deepEqual(subscription, { timeout: "17 millis" });
    assert.equal((predicate as (event: unknown) => boolean)(event), true, `${source} event with the selected session must match`);
    assert.equal((predicate as (event: unknown) => boolean)(other), false, `${source} event without the selected session must not match`);
  });
}
