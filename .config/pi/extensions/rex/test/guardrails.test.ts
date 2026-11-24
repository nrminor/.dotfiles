import assert from "node:assert/strict";
import test from "node:test";
import { Effect, Exit, Layer, Option, Schema } from "effect";
import { BlockId, RexSdk, SessionId, type IRexSdk, type RexTerminalMark } from "rex-sdk";
import { RexController } from "../controller.ts";
import { guardedProgram, type Selection } from "../policy.ts";
import { RexMarkStore } from "../vendor/rex-tool-marks.ts";
import { rexToolOperations } from "../vendor/rex-tool-operations.ts";
import { RexToolRuntime, toRexToolResult } from "../vendor/rex-tool-runtime.ts";

const sessionId = Schema.decodeUnknownSync(SessionId)("session:selected");
const blockId = Schema.decodeUnknownSync(BlockId)("block:existing");
const otherBlockId = Schema.decodeUnknownSync(BlockId)("block:second");
const target = { sessionId, blockId };
const terminalMark: RexTerminalMark = { offset: 0, anchor: [], hasCursorLine: false };
const approve = async () => true;
const deny = async () => false;
const operation = (name: string) => {
  const found = rexToolOperations.find((item) => item.name === name);
  assert.ok(found, `Catalog must contain ${name}`);
  return found;
};

function gate<A>() {
  let resolve!: (value: A) => void;
  const promise = new Promise<A>((done) => { resolve = done; });
  return { promise, resolve };
}

function fixture() {
  const calls: Array<{ name: string; input: unknown }> = [];
  const state = {
    instanceId: "instance:selected",
    sessionId: sessionId as string,
    blocks: [blockId, otherBlockId] as string[],
    blockHosts: new Map<string, Option.Option<string>>(),
    formatComplete: true,
    createsFail: false,
    sessionCreateResult: { sessionId: "session:created", initialWindows: [] } as unknown,
    acquired: 0,
    released: 0,
    pauseStatus: false,
    statusStarted: gate<void>(),
    resumeStatus: gate<void>(),
    waitStarted: gate<void>(),
    waitReleased: 0,
  };
  const record = (name: string, input: unknown, result: unknown = {}) =>
    Effect.sync(() => { calls.push({ name, input }); return result; });
  const sdk = {
    server: { status: () => Effect.gen(function* () {
      if (state.pauseStatus) {
        state.statusStarted.resolve();
        yield* Effect.promise(() => state.resumeStatus.promise);
      }
      return { instanceId: state.instanceId, hostId: Option.some("host:test") };
    }) },
    sessions: {
      create: (input: unknown) => Effect.suspend(() => record("create session", input, state.sessionCreateResult)),
      view: () => Effect.sync(() => ({
        sessionId: state.sessionId,
        windows: [{
          windowId: "window:selected",
          layers: [{ layerId: "layer:selected", blocks: state.blocks.map((id) => ({
            blockId: id, hostId: state.blockHosts.get(id) ?? Option.some("host:test"),
          })) }],
        }],
      })),
      listBlocks: () => Effect.sync(() => ({ blocks: state.blocks.map((id) => ({
        blockId: id, hostId: state.blockHosts.get(id) ?? Option.some("host:test"),
      })) })),
    },
    terminals: {
      format: (target: unknown, args: unknown) => Effect.suspend(() => record("format", { target, args }, {
        content: "READY",
        id: state.formatComplete ? Option.none() : Option.some(7),
        total: Option.some(state.formatComplete ? 5 : 100_000),
        eof: Option.some(state.formatComplete),
      })),
      read: () => record("unbounded read", undefined, "Must not use automatic paging"),
      blobRead: () => record("blobRead", undefined, { content: "Must not page automatically" }),
      mark: (target: unknown) => record("mark", target, terminalMark),
      writeLine: (target: unknown, text: string) => record("writeLine", { target, text }),
      waitForOutput: (target: unknown, query: unknown) => record("waitForOutput", { target, query }, {
        line: "READY", text: "READY", groups: [], alignment: "offset",
      }),
      readTail: (target: unknown, options: unknown) => record("readTail", { target, options }, {
        lines: ["READY"], truncated: false,
      }),
      waitForExit: (target: unknown) => record("waitForExit", target, { exitCode: 0, error: null }),
      write: (target: unknown, args: unknown) => record("write", { target, args }, { bytesWritten: 1 }),
      waitForQuiet: () => Effect.acquireUseRelease(
        Effect.sync(() => { state.waitStarted.resolve(); return undefined; }),
        () => Effect.never,
        () => Effect.sync(() => { state.waitReleased++; }),
      ),
    },
    blocks: {
      create: (input: unknown) => Effect.suspend(() => {
        calls.push({ name: "create", input });
        if (state.createsFail) return Effect.fail(new Error("transport lost after dispatch"));
        state.blocks.push("block:created");
        return Effect.succeed({ blockId: "block:created", revision: 1 });
      }),
      split: (input: unknown) => record("split", input, { blockIds: ["block:created"], revision: 1 }),
      close: (input: unknown) => record("close", input),
      swap: (input: unknown) => record("swap", input),
      callMethod: (input: unknown) => record("raw method", input),
    },
    windows: {
      close: (input: unknown) => record("close window", input),
      focus: (input: unknown) => record("focus window", input),
    },
    events: { waitFor: (predicate: unknown, options: unknown) => record("event wait", { predicate, options }, {}) },
    targets: {
      resolve: (input: unknown) => record("resolve", input, { results: [] }),
      complete: (input: unknown) => record("complete", input, { completions: [] }),
    },
  } as unknown as IRexSdk;
  // Acquisition and finalization are real Effect resources, not mocked promises.
  const layer = Layer.effect(RexSdk, Effect.acquireRelease(
    Effect.sync(() => { state.acquired++; return sdk; }),
    () => Effect.sync(() => { state.released++; }),
  ));
  const selection: Selection = {
    server: "/explicit/rex.sock", sessionId, blockId, instanceId: state.instanceId,
    hostId: "host:test", owned: new Set(),
  };
  const run = async (
    name: string, params: Record<string, unknown>,
    authorize: (title: string, message: string) => Promise<boolean> = approve, current = () => true,
  ) => {
    const exit = await Effect.runPromiseExit(guardedProgram(
      operation(name), params, selection, new RexMarkStore(), authorize, current,
    ).pipe(Effect.provide(layer)));
    return toRexToolResult(exit);
  };
  return { calls, state, layer, selection, run };
}

test("selection verifies session and block membership and hides binding from another Pi session", async (t) => {
  const f = fixture();
  const controller = new RexController(() => f.layer);
  t.after(() => controller.dispose());
  assert.deepEqual(controller.here("pi:a"), { sessionId: null, blockId: null });
  await assert.rejects(controller.select("/explicit", sessionId, "block:foreign", "pi:a"), /does not belong/);
  f.state.sessionId = "session:other";
  await assert.rejects(controller.select("/explicit", sessionId, null, "pi:a"), /does not belong/);
  f.state.sessionId = sessionId;
  await controller.select("/explicit", sessionId, blockId, "pi:a");
  assert.deepEqual(controller.here("pi:a"), target);
  assert.deepEqual(controller.here("pi:b"), { sessionId: null, blockId: null });
  await assert.rejects(controller.call(operation("terminals_write"), { ...target, data: "x" }, "pi:b", approve), /explicit target/);
  assert.equal(f.calls.length, 0);
});

test("server instance changes are rejected before approval or dispatch", async () => {
  const f = fixture();
  f.state.instanceId = "instance:replacement";
  let approvals = 0;
  await assert.rejects(f.run("terminals_write", { ...target, data: "x" }, async () => {
    approvals++; return true;
  }), /instance changed/);
  assert.equal(approvals, 0);
  assert.deepEqual(f.calls, []);
});

test("server replacement during approval is rechecked before dispatch", async () => {
  const f = fixture();
  await assert.rejects(f.run("terminals_write", { ...target, data: "x" }, async () => {
    f.state.instanceId = "instance:replacement"; return true;
  }), /instance changed/);
  assert.deepEqual(f.calls, []);
});

test("false approval and a throwing approval both deny execution", async () => {
  const f = fixture();
  await assert.rejects(f.run("terminals_write", { ...target, data: "x" }, deny), /Authorization denied/);
  await assert.rejects(f.run("terminals_write", { ...target, data: "x" }, async () => {
    throw new Error("no dialog");
  }), /Authorization failed.*no dialog/);
  assert.deepEqual(f.calls, []);
});

test("generic known block methods use named-operation authorization, never raw dispatch", async () => {
  const f = fixture();
  const params = { ...target, method: "write", args: { data: "x" } };
  await assert.rejects(f.run("blocks_callMethod", params, deny), /Authorization denied/);
  const approvals: string[] = [];
  await f.run("blocks_callMethod", params, async (title) => { approvals.push(title); return true; });
  assert.deepEqual(approvals, ["Rex: terminals_write"]);
  assert.deepEqual(f.calls, [{ name: "write", input: { target, args: { data: "x" } } }]);
});

test("unknown block methods and foreign outer targets fail closed even when args contain local IDs", async () => {
  const f = fixture();
  await assert.rejects(f.run("blocks_callMethod", { ...target, method: "future.unsafe", args: {} }), /Unknown or ambiguous/);
  await assert.rejects(f.run("blocks_callMethod", {
    ...target, blockId: "block:foreign", method: "write", args: { data: "x", blockId },
  }), /blockId is not in/);
  assert.deepEqual(f.calls, []);
});

test("cross-session, secondary block, and window references cannot reach mutation", async () => {
  const f = fixture();
  for (const [name, params, message] of [
    ["terminals_write", { ...target, sessionId: "session:other", data: "x" }, /different session/],
    ["blocks_swap", { sessionId, blockId, otherBlockId: "block:foreign" }, /otherBlockId is not in/],
    ["windows_focus", { sessionId, windowId: "window:foreign" }, /windowId is not in/],
  ] as const) {
    await assert.rejects(f.run(name, params), message);
  }
  assert.deepEqual(f.calls, []);
});

test("same-session blocks on another or unknown host cannot inherit selected-host authority", async () => {
  for (const hostId of [Option.some("host:remote"), Option.none<string>()]) {
    const f = fixture();
    f.state.blockHosts.set(blockId, hostId);
    let approvals = 0;
    await assert.rejects(f.run("terminals_write", { ...target, data: "x" }, async () => {
      approvals++; return true;
    }), /host/i);
    assert.equal(approvals, 0);
    assert.deepEqual(f.calls, []);
  }
});

test("closing a parent window cannot silently close panes on a different host", async () => {
  const f = fixture();
  f.state.blockHosts.set(otherBlockId, Option.some("host:remote"));
  let approvals = 0;
  await assert.rejects(f.run("windows_close", { sessionId, windowId: "window:selected" }, async () => {
    approvals++; return true;
  }), /host/i);
  assert.equal(approvals, 0);
  assert.deepEqual(f.calls, []);
});

test("clipboard and unfiltered block event streams both require sensitive-read approval", async () => {
  const f = fixture();
  const categories: string[] = [];
  for (const type of ["clipboard_read", undefined]) {
    await assert.rejects(f.run("events_waitFor", {
      ...target, source: "block", ...(type === undefined ? {} : { type }), timeoutMs: 500,
    }, async (_title, message) => {
      categories.push(JSON.parse(message).category); return false;
    }), /Authorization denied/);
  }
  assert.deepEqual(categories, ["sensitive read", "sensitive read"]);
  assert.deepEqual(f.calls, []);
});

test("terminal and block event sources require an explicit block before approval or subscription", async () => {
  const f = fixture();
  let approvals = 0;
  for (const source of ["terminal", "block"]) {
    await assert.rejects(f.run("events_waitFor", { sessionId, source, timeoutMs: 500 }, async () => {
      approvals++; return true;
    }), /explicit blockId/);
  }
  assert.equal(approvals, 0);
  assert.equal(f.calls.length, 0);
});

test("target discovery validates nested context and scope before dispatch", async () => {
  const f = fixture();
  for (const name of ["targets_resolve", "targets_complete"]) {
    const query = name === "targets_resolve" ? { queries: [""] } : { prefix: "" };
    for (const nested of [
      { context: { sessionId: "session:foreign" } },
      { context: { sessionId, blockId: "block:foreign" } },
      { scope: { session: "session:foreign" } },
      { scope: { session: sessionId, window: "window:foreign" } },
    ]) {
      await assert.rejects(f.run(name, { kinds: ["block"], ...query, ...nested }), /session|block|window/i);
    }
  }
  assert.equal(f.calls.length, 0);
  await f.run("targets_resolve", {
    kinds: ["block"], queries: [""], context: target,
    scope: { session: sessionId, window: "window:selected" },
  });
  assert.equal(f.calls.at(0)?.name, "resolve");
  assert.equal(f.selection.sessionId, sessionId);
  assert.equal(f.selection.blockId, blockId);
});

test("background split forces focus false in both approval and SDK input without changing caller parameters", async () => {
  const f = fixture();
  const params = {
    sessionId, anchorId: blockId, direction: "horizontal", side: "after",
    layout: { _tag: "Terminal" }, focus: true,
  };
  let approvedParams: unknown;
  await f.run("blocks_split", params, async (_title, message) => {
    approvedParams = JSON.parse(message).params; return true;
  });
  assert.equal((approvedParams as { focus: boolean }).focus, false);
  assert.equal((f.calls[0]?.input as { focus: boolean }).focus, false);
  assert.equal(params.focus, true);
  assert.deepEqual([...f.selection.owned], ["block:created"]);
});

test("task ownership is granted only on confirmed creation, never on ambiguous failure or denial", async () => {
  const f = fixture();
  const params = { sessionId, flavor: "com.superlogical.terminal.shell" };
  await assert.rejects(f.run("blocks_create", params, deny), /Authorization denied/);
  assert.deepEqual([...f.selection.owned], []);
  assert.deepEqual(f.calls, []);
  f.state.createsFail = true;
  await assert.rejects(f.run("blocks_create", params), /Outcome may be uncertain.*No automatic replay/);
  assert.deepEqual([...f.selection.owned], []);
  assert.equal(f.calls.length, 1);
  f.state.createsFail = false;
  await f.run("blocks_create", params);
  assert.deepEqual([...f.selection.owned], ["block:created"]);
  assert.equal(f.calls.length, 2);
});

for (const failure of ["oversized", "unencodable"] as const) {
  test(`successful session creation with an ${failure} result forbids repeating the completed mutation`, async () => {
    const f = fixture();
    const createdSessionId = `session:${"x".repeat(1_000)}`;
    f.state.sessionCreateResult = {
      sessionId: createdSessionId,
      initialWindows: failure === "oversized"
        ? Array.from({ length: 1_000 }, () => ({
          windowId: "window:created", blockIds: ["block:created"], revision: 1,
        }))
        : () => undefined,
    };
    let approvals = 0;
    await assert.rejects(f.run("sessions_create", { label: "new task" }, async () => {
      approvals++; return true;
    }), (error: unknown) => {
      assert.ok(error instanceof Error);
      assert.match(error.message, /^RexPolicyError: Operation completed/);
      assert.match(error.message, /Do not repeat the mutation/);
      assert.doesNotMatch(error.message, /narrower|retry|uncertain|Defect/i);
      const reportedId = /"sessionId":"([^"]+)"/.exec(error.message)?.[1];
      assert.equal(reportedId, createdSessionId.slice(0, 128));
      assert.ok(error.message.length < 1_024, "Recovery instructions and IDs must remain bounded");
      return true;
    });
    assert.equal(approvals, 1);
    assert.deepEqual(f.calls, [{ name: "create session", input: { label: "new task" } }]);
    assert.deepEqual([...f.selection.owned], [], "Creating a different session does not grant pane ownership");
  });
}

test("window close approval includes pre-existing panes as well as task-created panes", async () => {
  const f = fixture();
  f.selection.owned.add(otherBlockId);
  let affected: unknown;
  await f.run("windows_close", { sessionId, windowId: "window:selected" }, async (_title, message) => {
    affected = JSON.parse(message).affected; return true;
  });
  assert.deepEqual(affected, [
    { blockId: "block:existing", hostId: "host:test", status: "pre-existing" },
    { blockId: "block:second", hostId: "host:test", status: "task-created" },
  ]);
  assert.equal(f.calls[0]?.name, "close window");
});

test("window close refuses a changed set of affected panes after approval", async () => {
  const f = fixture();
  await assert.rejects(f.run("windows_close", { sessionId, windowId: "window:selected" }, async () => {
    f.state.blocks.push("block:arrived"); return true;
  }), /Affected blocks or execution hosts changed/);
  assert.deepEqual(f.calls, []);
});

for (const action of ["clear", "dispose"] as const) {
  test(`${action} interrupts an unfinished selection and ignores its late server response`, { timeout: 3_000 }, async (t) => {
    const f = fixture();
    f.state.pauseStatus = true;
    const controller = new RexController(() => f.layer);
    t.after(() => controller.dispose());
    const pending = controller.select("/explicit", sessionId, blockId, "pi:a");
    const rejected = assert.rejects(pending, /Interrupted|superseded/);
    await f.state.statusStarted.promise;
    await controller[action]();
    f.state.resumeStatus.resolve();
    await rejected;
    assert.deepEqual(controller.here("pi:a"), { sessionId: null, blockId: null });
    assert.equal(f.state.released, 1);
  });

  test(`${action} while approval is pending cannot resurrect the binding or dispatch late input`, { timeout: 3_000 }, async (t) => {
    const f = fixture();
    const controller = new RexController(() => f.layer);
    t.after(() => controller.dispose());
    await controller.select("/explicit", sessionId, blockId, "pi:a");
    const started = gate<void>();
    const approval = gate<boolean>();
    let dialogSignal: AbortSignal | undefined;
    const pending = controller.call(operation("terminals_write"), { ...target, data: "x" }, "pi:a", (_title, _message, signal) => {
      dialogSignal = signal;
      started.resolve(); return approval.promise;
    });
    const rejected = assert.rejects(pending, /Interrupted|no longer current/);
    await started.promise;
    assert.ok(dialogSignal, "Approval must receive its Effect cancellation signal");
    assert.equal(dialogSignal.aborted, false);
    await controller[action]();
    assert.equal(dialogSignal.aborted, true, "Clearing the selection must dismiss its pending dialog");
    approval.resolve(true);
    await rejected;
    assert.deepEqual(controller.here("pi:a"), { sessionId: null, blockId: null });
    assert.deepEqual(f.calls, []);
    assert.equal(f.state.released, 1);
    if (action === "dispose")
      await assert.rejects(controller.select("/explicit", sessionId, blockId, "pi:a"), /disposed/);
  });
}

test("aborting a wait interrupts its resource, never replays, and disposing finalizes SDK once", { timeout: 3_000 }, async (t) => {
  const f = fixture();
  const controller = new RexController(() => f.layer);
  t.after(() => controller.dispose());
  await controller.select("/explicit", sessionId, blockId, "pi:a");
  const abort = new AbortController();
  const pending = controller.call(operation("terminals_waitForQuiet"), {
    ...target, quietForMs: 5, timeoutMs: 500,
  }, "pi:a", approve, abort.signal);
  const rejected = assert.rejects(pending, /Interrupted.*Cancellation is not rollback/);
  await f.state.waitStarted.promise;
  abort.abort();
  await rejected;
  assert.equal(f.state.waitReleased, 1);
  assert.equal(f.state.acquired, 1);
  assert.equal(f.state.released, 0);
  await controller.dispose();
  await controller.dispose();
  assert.equal(f.state.released, 1);
});

test("already-aborted calls never ask approval or dispatch", async (t) => {
  const f = fixture();
  const controller = new RexController(() => f.layer);
  t.after(() => controller.dispose());
  await controller.select("/explicit", sessionId, blockId, "pi:a");
  const abort = new AbortController();
  abort.abort();
  await assert.rejects(controller.call(operation("terminals_write"), { ...target, data: "x" }, "pi:a", async () => {
    assert.fail("Cancelled operation must not ask approval");
  }, abort.signal), /cancelled before dispatch/);
  assert.deepEqual(f.calls, []);
});

test("oversized parameters, output search bounds, and unbounded request timeouts fail before input dispatch", async () => {
  const f = fixture();
  for (const requestTimeoutMs of [0, -1, 30_001, Infinity, NaN]) {
    await assert.rejects(f.run("terminals_write", {
      ...target, data: "x", requestTimeoutMs,
    }), /requestTimeoutMs/);
  }
  await assert.rejects(f.run("terminals_write", {
    ...target, data: "é".repeat(33_000),
  }), /parameters exceed/);
  await assert.rejects(f.run("terminals_waitForOutput", {
    ...target, match: { type: "substring", value: "READY" }, lines: 2_001, timeoutMs: 500,
  }), /lines/);
  await assert.rejects(f.run("terminals_waitForQuiet", {
    ...target, quietForMs: 30_001, timeoutMs: 500,
  }), /quietForMs/);
  assert.deepEqual(f.calls, []);
});

test("read returns one complete bounded format response, never the SDK auto-paging read", async () => {
  const f = fixture();
  const result = await f.run("terminals_read", target);
  assert.equal(result.structuredContent, "READY");
  assert.deepEqual(f.calls.map((call) => call.name), ["format"]);
  const input = f.calls[0]?.input as { args: { maxBytes: number } };
  assert.ok(input.args.maxBytes > 0 && input.args.maxBytes <= 65_536);
});

test("read refuses an incomplete bounded response instead of silently truncating or following its blob", async () => {
  const f = fixture();
  f.state.formatComplete = false;
  await assert.rejects(f.run("terminals_read", target), /format.*blobRead/i);
  assert.deepEqual(f.calls.map((call) => call.name), ["format"]);
});

test("marks are scoped to store, session, and block, and disposing a runtime erases marks", async () => {
  const mark = terminalMark;
  const marks = new RexMarkStore();
  const id = marks.put(target, mark);
  assert.equal(await Effect.runPromise(marks.get(id, target)), mark);
  for (const [store, reference] of [
    [new RexMarkStore(), target],
    [marks, { ...target, blockId: otherBlockId }],
    [marks, { ...target, sessionId: Schema.decodeUnknownSync(SessionId)("session:other") }],
  ] as const) {
    assert.equal(Exit.isFailure(await Effect.runPromiseExit(store.get(id, reference))), true);
  }
  const f = fixture();
  const runtime = new RexToolRuntime(() => f.layer);
  const runtimeMark = runtime.marks.put(target, mark);
  await runtime.run(Effect.as(RexSdk, undefined), undefined);
  await runtime.dispose();
  assert.equal(Exit.isFailure(await Effect.runPromiseExit(runtime.marks.get(runtimeMark, target))), true);
  assert.equal(f.state.released, 1);
});

test("working loop creates a task pane and preserves its pre-input mark through wait, read, exit, and close", async (t) => {
  const f = fixture();
  const controller = new RexController(() => f.layer);
  t.after(() => controller.dispose());
  await controller.select("/explicit", sessionId, blockId, "pi:a");
  const approvals: string[] = [];
  const authorize = async (title: string) => { approvals.push(title); return true; };
  const created = await controller.call(operation("blocks_create"), {
    sessionId, flavor: "com.superlogical.terminal.shell",
  }, "pi:a", authorize);
  assert.deepEqual(created.structuredContent, { blockId: "block:created", revision: 1 });
  const taskTarget = { sessionId, blockId: "block:created" };
  const written = await controller.call(operation("terminals_writeLine"), {
    ...taskTarget, text: "printf READY",
  }, "pi:a", authorize);
  assert.deepEqual(written.structuredContent, { markId: "mark-1" });
  const output = await controller.call(operation("terminals_waitForOutput"), {
    ...taskTarget, match: { type: "substring", value: "READY" }, since: "mark-1", lines: 20, timeoutMs: 500,
  }, "pi:a", authorize);
  assert.deepEqual(output.structuredContent, {
    timedOut: false, match: { line: "READY", text: "READY", groups: [], alignment: "offset" },
  });
  const tail = await controller.call(operation("terminals_readTail"), {
    ...taskTarget, maxBytes: 1_024,
  }, "pi:a", authorize);
  assert.deepEqual(tail.structuredContent, { lines: ["READY"], truncated: false });
  const exit = await controller.call(operation("terminals_waitForExit"), {
    ...taskTarget, timeoutMs: 500,
  }, "pi:a", authorize);
  assert.deepEqual(exit.structuredContent, { timedOut: false, exit: { exitCode: 0, error: null } });
  await controller.call(operation("blocks_close"), taskTarget, "pi:a", authorize);
  assert.deepEqual(approvals, ["Rex: blocks_create", "Rex: terminals_writeLine", "Rex: blocks_close"]);
  assert.deepEqual(f.calls.map((call) => call.name), [
    "create", "mark", "writeLine", "waitForOutput", "readTail", "waitForExit", "close",
  ]);
  assert.deepEqual(f.calls[3]?.input, {
    target: taskTarget, query: { pattern: "READY", since: terminalMark, lines: 20 },
  });
  await controller.clear();
  await controller.select("/explicit", sessionId, blockId, "pi:a");
  await assert.rejects(controller.call(operation("terminals_waitForOutput"), {
    ...taskTarget, match: { type: "substring", value: "READY" }, since: "mark-1", timeoutMs: 500,
  }, "pi:a", authorize), /RexUnknownMark/);
  assert.equal(f.calls.filter((call) => call.name === "waitForOutput").length, 1);
});
