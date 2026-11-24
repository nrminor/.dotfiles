import assert from "node:assert/strict";
import { test } from "node:test";
import { Deferred, Effect, Exit, Fiber, Option, Schema } from "effect";
import { RexSdk, rexBlockMethods, rexWireMethods, type IRexSdk } from "rex-sdk";
import { guardedProgram, operationPolicy, type Approval, type Selection } from "../policy.ts";
import { makeRexToolOperation, rexToolOperations, type RexToolOperation, type TargetingEvidence } from "../vendor/rex-tool-operations.ts";
import { RexMarkStore } from "../vendor/rex-tool-marks.ts";

const selection = (): Selection => ({
  server: "unix:///test", instanceId: "instance", sessionId: "session:selected",
  hostId: "host:a", blockId: "block:one", owned: new Set(),
});

function fixture() {
  const listed = Schema.decodeUnknownSync(rexWireMethods["session.list_blocks"].result)({
    blocks: [
      { block_id: "block:one", label: "one", window_id: "window:one", host_id: "host:a",
        creator_name: "com.superlogical.terminal", placement: "placed" },
      { block_id: "block:two", label: "two", window_id: "window:one", host_id: "host:b",
        creator_name: "other", placement: "placed" },
    ],
  });
  const view = Schema.decodeUnknownSync(rexWireMethods["session.view"].result)({
    revision: 1, session_id: "session:selected", active_window_id: "window:one",
    windows: [{ window_id: "window:one", focused_block_id: "block:one", layers: [{
      layer_id: "layer:one", kind: "tiled", bounds: [0, 0, 1, 1],
      layout: {
        rect: [0, 0, 1, 1],
        split: {
          split_id: "split:one", direction: "horizontal", ratio: 0.5,
          before: { rect: [0, 0, 0.5, 1], block_id: "block:one" },
          after: { rect: [0.5, 0, 0.5, 1], block_id: "block:two" },
        },
      },
      blocks: [
        { block_id: "block:one", host_id: "host:a", creator_name: "com.superlogical.terminal" },
        { block_id: "block:two", host_id: "host:b", creator_name: "other" },
      ],
    }] }],
  });
  const status = Schema.decodeUnknownSync(rexWireMethods["server.status"].result)({
    pid: 1, instance_id: "instance", started_at: "2026-01-01T00:00:00Z",
    exit_empty: false, session_count: 1, config: { generation: 1, hash: "" },
  });
  const clients = Schema.decodeUnknownSync(rexWireMethods["client.list"].result)({ clients: [] });
  const creators = Schema.decodeUnknownSync(rexWireMethods["block_creator.list"].result)({
    creators: [{
      name: "com.superlogical.terminal", title: "Terminal", description: "Test creator", host_id: "host:a",
      flavors: [{ name: "shell", flavor: "remote.shell", title: "Shell", description: "Test flavor" }],
      api: {},
    }],
  });
  const rex = {
    server: { status: () => Effect.succeed(status) } satisfies Pick<IRexSdk["server"], "status">,
    sessions: {
      view: () => Effect.succeed(view),
      listBlocks: () => Effect.succeed(listed),
    } satisfies Pick<IRexSdk["sessions"], "view" | "listBlocks">,
    clients: { list: () => Effect.succeed(clients) } satisfies Pick<IRexSdk["clients"], "list">,
    creators: { list: () => Effect.succeed(creators) } satisfies Pick<IRexSdk["creators"], "list">,
  } as unknown as IRexSdk;
  return { rex, blocks: listed.blocks };
}

function fake<const Fields extends Schema.Struct.Fields>(
  name: string, fields: Fields, run: (params: Schema.Struct<Fields>["Type"]) => unknown,
  targeting: (params: Schema.Struct<Fields>["Type"]) => TargetingEvidence,
): RexToolOperation {
  return makeRexToolOperation({
    name, description: "", fields, targeting, output: "void",
    run: (_rex, params) => Effect.sync(() => run({ ...params })),
  });
}

function execute(
  op: RexToolOperation,
  params: Record<string, unknown>,
  approve: (approval: Approval) => Effect.Effect<void, unknown> = () => Effect.void,
) {
  const { rex } = fixture();
  return Effect.runPromiseExit(guardedProgram(op, params, selection(), new RexMarkStore(), approve, () => true)
    .pipe(Effect.provideService(RexSdk, rex)));
}

test("every finite catalog operation has an explicit policy", () => {
  assert.deepEqual(rexToolOperations.filter((op) => !operationPolicy[op.name]).map((op) => op.name), []);
});

test("read and formerly deferred relative focus call native authorization", async () => {
  const approvals: Approval[] = [];
  const op = fake("blocks_focusNext", { sessionId: Schema.String }, (params) => params.sessionId, () => ({}));
  const exit = await execute(op, {}, (approval) => Effect.sync(() => { approvals.push(approval); }));
  assert.ok(Exit.isSuccess(exit));
  assert.equal(exit.value, "session:selected");
  assert.equal(approvals[0]?.action, "rex.layout");
  assert.match(approvals[0]!.message, /current focus/);
});

test("session mismatch is rejected before dispatch", async () => {
  let dispatched = false;
  const op = fake("sessions_view", { sessionId: Schema.String }, () => { dispatched = true; }, () => ({}));
  assert.ok(Exit.isFailure(await execute(op, { sessionId: "session:other" })));
  assert.equal(dispatched, false);
});

test("parent close discloses every descendant host and requires confirmation", async () => {
  const approvals: Approval[] = [];
  const op = fake("windows_close", { sessionId: Schema.String, windowId: Schema.String }, () => "closed",
    ({ windowId }) => ({ windowId }));
  const exit = await execute(op, { windowId: "window:one" }, (approval) =>
    Effect.sync(() => { approvals.push(approval); }));
  assert.ok(Exit.isSuccess(exit));
  assert.ok(approvals[0]!.confirm);
  assert.ok(approvals[0]!.resources.includes("host:host:a/block:block:one"));
  assert.ok(approvals[0]!.resources.includes("host:host:b/block:block:two"));
});

test("remote creator matching the selected host is allowed", async () => {
  const op = fake("blocks_create", { sessionId: Schema.String, flavor: Schema.String }, () => ({ blockId: "block:new" }),
    ({ flavor }) => ({ creatorFlavors: [flavor] }));
  assert.ok(Exit.isSuccess(await execute(op, { flavor: "remote.shell" })));
});

test("opaque action requires exact approved execution", async () => {
  const approvals: Approval[] = [];
  const op = fake("clients_action", { sessionId: Schema.String, action: Schema.String }, () => "done",
    ({ action }) => ({ action }));
  const exit = await execute(op, { action: "custom.danger" }, (approval) =>
    Effect.sync(() => { approvals.push(approval); }));
  assert.ok(Exit.isSuccess(exit));
  assert.equal(approvals[0]!.action, "rex.execution/input");
  assert.ok(approvals[0]!.confirm);
  assert.match(approvals[0]!.message, /custom.danger/);
});

test("keymap actions are classified as execution, not a read", async () => {
  const approvals: Approval[] = [];
  const op = fake("clients_keymap", { actions: Schema.optionalKey(Schema.Array(Schema.String)) }, () => "done",
    ({ actions }) => ({ keymapActionsPresent: actions !== undefined }));
  assert.ok(Exit.isSuccess(await execute(op, { actions: ["custom"] }, (approval) =>
    Effect.sync(() => { approvals.push(approval); }))));
  assert.equal(approvals[0]!.action, "rex.execution/input");
  assert.ok(approvals[0]!.confirm);
});

test("generic known methods decode wire arguments and use the named permission", async () => {
  const op = rexToolOperations.find((item) => item.name === "blocks_callMethod")!;
  const { rex } = fixture();
  let calls = 0;
  let actual: unknown;
  const terminals = { format: (_target, args) => {
    calls++;
    actual = args;
    return Effect.succeed(Schema.decodeUnknownSync(rexBlockMethods["com.superlogical.terminal.format"].result)({
      content: "output",
    }));
  } } satisfies Pick<IRexSdk["terminals"], "format">;
  Object.assign(rex, { terminals });
  const approvals: Approval[] = [];
  const run = (authorize: (approval: Approval) => Effect.Effect<void, unknown>) =>
    Effect.runPromiseExit(guardedProgram(op, {
      sessionId: "session:selected", blockId: "block:one", method: "format",
      args: { max_bytes: 123, extra_cursor: true },
    }, selection(), new RexMarkStore(), authorize, () => true).pipe(Effect.provideService(RexSdk, rex)));
  assert.ok(Exit.isFailure(await run(() => Effect.fail("denied"))));
  assert.equal(calls, 0);
  const result = await run((approval) => Effect.sync(() => { approvals.push(approval); }));
  assert.ok(Exit.isSuccess(result));
  assert.equal(calls, 1);
  assert.deepEqual(actual, { maxBytes: 123, extraCursor: true });
  assert.equal(approvals[0]!.action, "rex.read");
  assert.match(approvals[0]!.message, /terminals_format/);
});

test("authorization denial and binding changes prevent dispatch", async () => {
  let dispatched = false;
  const op = fake("sessions_view", { sessionId: Schema.String }, () => { dispatched = true; }, () => ({}));
  assert.ok(Exit.isFailure(await execute(op, {}, () => Effect.fail("denied"))));
  assert.equal(dispatched, false);
  let current = true;
  const { rex } = fixture();
  const exit = await Effect.runPromiseExit(guardedProgram(op, {}, selection(), new RexMarkStore(),
    () => Effect.sync(() => { current = false; }), () => current).pipe(Effect.provideService(RexSdk, rex)));
  assert.ok(Exit.isFailure(exit));
  assert.equal(dispatched, false);
});

test("the approved read budget and selected target reach the SDK unchanged", { timeout: 5000 }, async () => {
  const { rex } = fixture();
  const calls: Array<{ target: unknown; args: unknown }> = [];
  const terminals = {
    format: (target, args) => Effect.sync(() => {
      calls.push({ target, args });
      return { content: "output", id: Option.none(), total: Option.none(), eof: Option.none() };
    }),
  } satisfies Pick<IRexSdk["terminals"], "format">;
  Object.assign(rex, { terminals });
  const operation = rexToolOperations.find((item) => item.name === "terminals_format");
  assert.ok(operation);
  const params: Record<string, unknown> = { trim: true };
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const entered = yield* Deferred.make<Approval>();
    const release = yield* Deferred.make<void>();
    const execution = yield* Effect.forkChild(guardedProgram(
      operation, params, selection(), new RexMarkStore(),
      (approval) => Deferred.succeed(entered, approval).pipe(Effect.andThen(Deferred.await(release))),
      () => true,
    ).pipe(Effect.provideService(RexSdk, rex)));
    const approval = yield* Deferred.await(entered);
    assert.deepEqual(JSON.parse(approval.message).params, {
      sessionId: "session:selected", blockId: "block:one", trim: true, maxBytes: 49_152,
    });
    assert.deepEqual(calls, []);
    params.maxBytes = 1;
    params.blockId = "block:two";
    yield* Deferred.succeed(release, undefined);
    const exit = yield* Fiber.await(execution);
    assert.ok(Exit.isSuccess(exit), String(exit));
    assert.deepEqual(calls, [{
      target: { sessionId: "session:selected", blockId: "block:one" },
      args: { trim: true, maxBytes: 49_152 },
    }]);
  })));
});
