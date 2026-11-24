import assert from "node:assert/strict";
import { test } from "node:test";
import { Deferred, Effect, Exit, Fiber, Option, Schema } from "effect";
import {
  RexSdk, rexWireMethods, REX_TUNNEL_DIAL_FLAVOR, REX_TUNNEL_LISTEN_FLAVOR,
  type IRexSdk, type RexLayoutNode,
} from "rex-sdk";
import { guardedProgram, type Approval, type Selection } from "../policy.ts";
import { RexMarkStore } from "../vendor/rex-tool-marks.ts";
import { makeRexToolOperation, rexToolOperations, type RexToolOperation, type TargetingEvidence } from "../vendor/rex-tool-operations.ts";

const selected: Selection = {
  server: "unix:///test", instanceId: "instance", sessionId: "session:selected",
  hostId: "host:a", blockId: "block:selected", owned: new Set(),
};
const terminalLayout: RexLayoutNode = { _tag: "Terminal" };

function catalog(name: string): RexToolOperation {
  const operation = rexToolOperations.find((candidate) => candidate.name === name);
  assert.ok(operation, `Missing catalog operation ${name}`);
  return operation;
}

// Resource operations are supplied by the resource manager, not the finite catalog.
// Their tiny stand-ins retain the real schemas and expose only the start boundary.
function resource<const Fields extends Schema.Struct.Fields>(
  name: string, fields: Fields, start: (params: Schema.Struct<Fields>["Type"]) => void,
  targeting: (params: Schema.Struct<Fields>["Type"]) => TargetingEvidence,
): RexToolOperation {
  return makeRexToolOperation({
    name, fields, targeting, description: "",
    output: Schema.Unknown,
    run: (_rex, params) => Effect.sync(() => { start({ ...params }); return "started"; }),
  });
}

function fixture(creatorHost: string | undefined = "host:a", flavor = "com.superlogical.terminal.shell") {
  const calls: Array<{ method: string; input: unknown }> = [];
  const record = (method: string, input: unknown) => {
    calls.push({ method, input });
  };
  // Decode wire fixtures so IDs, Options and creator action metadata have SDK types.
  const blocks = Schema.decodeUnknownSync(rexWireMethods["session.list_blocks"].result)({
    blocks: ["selected", "focused"].map((name) => ({
      block_id: `block:${name}`, label: name, creator_name: "com.superlogical.terminal",
      host_id: "host:a", placement: "placed", window_id: `window:${name}`,
    })),
  });
  const view = Schema.decodeUnknownSync(rexWireMethods["session.view"].result)({
    revision: 1, session_id: selected.sessionId, active_window_id: "window:focused",
    windows: ["selected", "focused"].map((name) => ({
      window_id: `window:${name}`, focused_block_id: `block:${name}`,
      layers: [{
        layer_id: `layer:${name}`, kind: "tiled", bounds: [0, 0, 1, 1],
        layout: null, blocks: [{ block_id: `block:${name}`, host_id: "host:a" }],
      }],
    })),
  });
  const creators = Schema.decodeUnknownSync(rexWireMethods["block_creator.list"].result)({
    creators: [{
      name: "com.superlogical.terminal", title: "Terminal", description: "Test creator",
      ...(creatorHost === undefined ? {} : { host_id: creatorHost }),
      flavors: [{ name: "shell", flavor, title: "Shell", description: "Test flavor" }],
      api: { methods: { reset: { actions: [{ name: "reset", title: "Reset Terminal" }] } } },
    }],
  });
  const status = Schema.decodeUnknownSync(rexWireMethods["server.status"].result)({
    pid: 1, instance_id: "instance", started_at: "2026-01-01T00:00:00Z",
    exit_empty: false, session_count: 1, config: { generation: 1, hash: "" },
  });
  const sdk = {
    server: { status: () => Effect.succeed(status) } satisfies Partial<IRexSdk["server"]>,
    sessions: {
      view: () => Effect.succeed(view), listBlocks: () => Effect.succeed(blocks),
    } satisfies Partial<IRexSdk["sessions"]>,
    creators: { list: () => Effect.succeed(creators) } satisfies Partial<IRexSdk["creators"]>,
    targets: {
      resolve: (input) => Effect.sync(() => {
        record("targets.resolve", input);
        return Schema.decodeUnknownSync(rexWireMethods["target.resolve"].result)({ results: [] });
      }),
      complete: (input) => Effect.sync(() => {
        record("targets.complete", input);
        return Schema.decodeUnknownSync(rexWireMethods["target.complete"].result)({ completions: [] });
      }),
    } satisfies Pick<IRexSdk["targets"], "resolve" | "complete">,
    clients: {
      action: (input) => Effect.sync(() => {
        record("clients.action", input);
        return Schema.decodeUnknownSync(rexWireMethods["client.action"].result)({ client_actions: [] });
      }),
    } satisfies Partial<IRexSdk["clients"]>,
    terminals: {
      reset: (target) => Effect.sync(() => { record("terminals.reset", target); return {}; }),
    } satisfies Partial<IRexSdk["terminals"]>,
    windows: {
      create: (input) => Effect.sync(() => {
        record("windows.create", input);
        return Schema.decodeUnknownSync(rexWireMethods["session.new_window"].result)({
          window_id: "window:new", block_ids: [], revision: 2,
        });
      }),
      close: (input) => Effect.sync(() => { record("windows.close", input); return { revision: 2 }; }),
    } satisfies Partial<IRexSdk["windows"]>,
    blocks: {
      create: (input) => Effect.sync(() => {
        record("blocks.create", input);
        return Schema.decodeUnknownSync(rexWireMethods["session.new_block"].result)({
          block_id: "block:new", revision: 2,
        });
      }),
      move: (input) => Effect.sync(() => {
        record("blocks.move", input);
        return Schema.decodeUnknownSync(rexWireMethods["session.move_block"].result)({
          created_split_id: "split:new", revision: 2,
        });
      }),
      swap: (input) => Effect.sync(() => {
        record("blocks.swap", input);
        return Schema.decodeUnknownSync(rexWireMethods["session.swap_blocks"].result)({ revision: 2 });
      }),
      resize: (input) => Effect.sync(() => {
        record("blocks.resize", input);
        return Schema.decodeUnknownSync(rexWireMethods["session.resize_pane"].result)({ revision: 2 });
      }),
      split: (input) => Effect.sync(() => {
        record("blocks.split", input);
        return Schema.decodeUnknownSync(rexWireMethods["session.new_split"].result)({
          anchor_id: input.anchorId, block_ids: [], split_ids: ["split:new"], revision: 2,
        });
      }),
      splitBeside: (input) => Effect.sync(() => {
        record("blocks.splitBeside", input);
        return Schema.decodeUnknownSync(rexWireMethods["session.new_split"].result)({
          anchor_id: input.anchorId, block_ids: [], split_ids: ["split:new"], revision: 2,
        });
      }),
      close: (input) => Effect.sync(() => {
        record("blocks.close", input);
        return Schema.decodeUnknownSync(rexWireMethods["block.close"].result)({
          block_id: input.blockId, revision: 2,
        });
      }),
      zoom: (input) => Effect.sync(() => {
        record("blocks.zoom", input);
        return Schema.decodeUnknownSync(rexWireMethods["session.zoom_block"].result)({
          block_id: input.blockId, zoomed: true, revision: 2,
        });
      }),
    } satisfies Partial<IRexSdk["blocks"]>,
    layers: {
      create: (input) => Effect.sync(() => {
        record("layers.create", input);
        return Schema.decodeUnknownSync(rexWireMethods["session.new_layer"].result)({
          layer_id: "layer:new", block_ids: [], revision: 2,
        });
      }),
    } satisfies Partial<IRexSdk["layers"]>,
    tunnels: {
      createDial: (input) => Effect.sync(() => {
        record("tunnels.createDial", input);
        return Schema.decodeUnknownSync(rexWireMethods["session.new_block"].result)({ block_id: "block:new", revision: 2 });
      }),
      createListen: (input) => Effect.sync(() => {
        record("tunnels.createListen", input);
        return Schema.decodeUnknownSync(rexWireMethods["session.new_block"].result)({ block_id: "block:new", revision: 2 });
      }),
    } satisfies Partial<IRexSdk["tunnels"]>,
  };
  // Only the exercised SDK methods are provided; each stub above is type-checked.
  return { rex: sdk as unknown as IRexSdk, calls, creators, view, blocks };
}

function run(
  operation: RexToolOperation, params: Record<string, unknown>, rex: IRexSdk,
  authorize: (approval: Approval) => Effect.Effect<void, unknown> = () => Effect.void,
  selection: Selection = selected,
) {
  return Effect.runPromiseExit(guardedProgram(operation, params, { ...selection, owned: new Set() },
    new RexMarkStore(), authorize, () => true).pipe(Effect.provideService(RexSdk, rex)));
}

for (const deniedBy of ["category", "operation"] as const) {
  test(`built-in reset action cannot bypass canonical ${deniedBy} denial`, async () => {
    const { rex, calls, creators } = fixture();
    const methods = Option.getOrThrow(creators.creators[0]!.api.methods);
    assert.deepEqual(methods.reset!.actions.map((action) => action.name), ["reset"]);
    const approvals: Approval[] = [];
    const exit = await run(catalog("clients_action"), { action: "com.superlogical.terminal.reset" }, rex,
      (approval) => {
        approvals.push(approval);
        const denied = deniedBy === "category" ? approval.action === "rex.close/destroy"
          : approval.resources.includes("operation:terminals_reset");
        return denied ? Effect.fail(new Error(`denied canonical ${deniedBy}`)) : Effect.void;
      });
    assert.ok(Exit.isFailure(exit));
    assert.match(String(exit), /denied canonical/);
    assert.equal(calls.length, 0, "denial must precede action dispatch");
    assert.equal(approvals.length, 1);
    assert.equal(approvals[0]!.action, "rex.close/destroy");
    assert.equal(approvals[0]!.confirm, true);
    assert.ok(approvals[0]!.resources.includes("operation:terminals_reset"));
    assert.ok(!approvals[0]!.resources.includes("operation:clients_action"));
  });
}

for (const [name, query, method] of [
  ["targets_resolve", { queries: ["shell"] }, "targets.resolve"],
  ["targets_complete", { prefix: "sh" }, "targets.complete"],
] as const) {
  for (const [scope, message] of [
    [{ session: "session:foreign", window: "window:selected" }, /Lookup scope must use the selected session/],
    [{ session: "session:selected", window: "window:foreign" }, /Lookup scope window is outside the selected session/],
  ] as const) {
    test(`${name} rejects foreign lookup scope ${JSON.stringify(scope)} before approval or dispatch`, async () => {
      const { rex, calls } = fixture();
      const approvals: Approval[] = [];
      const exit = await run(catalog(name), {
        kinds: ["block"], ...query, scope, context: { sessionId: "session:selected", blockId: "block:selected" },
      }, rex, (approval) => Effect.sync(() => { approvals.push(approval); }));
      assert.ok(Exit.isFailure(exit));
      assert.match(String(exit), message);
      assert.deepEqual(approvals, []);
      assert.deepEqual(calls, []);
    });
  }

  test(`${name} preserves allowed lookup scope and context in the exact SDK request`, async () => {
    const { rex, calls } = fixture();
    const approvals: Approval[] = [];
    const exit = await run(catalog(name), {
      kinds: ["block"], ...query,
      scope: { session: "session:selected", window: "window:selected" },
      context: { sessionId: "session:selected", blockId: "block:selected" },
    }, rex, (approval) => Effect.sync(() => { approvals.push(approval); }));
    assert.ok(Exit.isSuccess(exit), String(exit));
    assert.equal(approvals.length, 1);
    assert.equal(approvals[0]?.action, "rex.read");
    assert.deepEqual(calls, [{
      method, input: {
        kinds: ["block"], ...query,
        scope: { session: "session:selected", window: "window:selected" },
        context: { sessionId: "session:selected", blockId: "block:selected" },
      },
    }]);
  });
}

test("allowing a built-in action requires both canonical and original operation approval", async () => {
  const { rex, calls } = fixture();
  const approvals: Approval[] = [];
  const exit = await run(catalog("clients_action"), { action: "com.superlogical.terminal.reset" }, rex,
    (approval) => Effect.sync(() => { approvals.push(approval); }));
  assert.ok(Exit.isSuccess(exit), String(exit));
  assert.deepEqual(approvals.map((approval) => approval.action), ["rex.close/destroy", "rex.execution/input"]);
  assert.ok(approvals[1]!.resources.includes("operation:clients_action"));
  assert.deepEqual(calls.map((call) => call.method), ["clients.action"]);
});

test("canonical action approval does not bypass denial of the original operation", async () => {
  const { rex, calls } = fixture();
  const approvals: Approval[] = [];
  const exit = await run(catalog("clients_action"), { action: "com.superlogical.terminal.reset" }, rex,
    (approval) => {
      approvals.push(approval);
      return approval.resources.includes("operation:clients_action")
        ? Effect.fail(new Error("original action denied")) : Effect.void;
    });
  assert.ok(Exit.isFailure(exit));
  assert.match(String(exit), /original action denied/);
  assert.deepEqual(approvals.map(({ action }) => action), ["rex.close/destroy", "rex.execution/input"]);
  assert.deepEqual(calls, []);
});

for (const method of ["reset", "com.superlogical.terminal.reset"]) {
  test(`${method} uses canonical destructive policy and dispatches reset exactly once`, async () => {
    const { rex, calls } = fixture();
    const approvals: Approval[] = [];
    const params = { method };
    const denied = await run(catalog("blocks_callMethod"), params, rex, (approval) => {
      approvals.push(approval);
      return Effect.fail(new Error("canonical reset denied"));
    });
    assert.ok(Exit.isFailure(denied));
    assert.match(String(denied), /canonical reset denied/);
    assert.deepEqual(calls, []);
    const allowed = await run(catalog("blocks_callMethod"), params, rex,
      (approval) => Effect.sync(() => { approvals.push(approval); }));
    assert.ok(Exit.isSuccess(allowed), String(allowed));
    assert.equal(approvals.length, 2);
    for (const approval of approvals) {
      assert.equal(approval.action, "rex.close/destroy");
      assert.equal(approval.confirm, true);
      assert.ok(approval.resources.includes("operation:terminals_reset"));
      assert.equal(approval.resources.includes("operation:blocks_callMethod"), false);
    }
    assert.deepEqual(calls, [{
      method: "terminals.reset", input: { sessionId: "session:selected", blockId: "block:selected" },
    }]);
  });
}

for (const method of [
  "download_begin", "upload_begin",
  "com.superlogical.terminal.download_begin", "com.superlogical.terminal.upload_begin",
]) {
  test(`${method} cannot expose an unmanaged transfer ticket`, async () => {
    const { rex, calls } = fixture();
    const approvals: Approval[] = [];
    const exit = await run(catalog("blocks_callMethod"), { method }, rex,
      (approval) => Effect.sync(() => { approvals.push(approval); }));
    assert.ok(Exit.isFailure(exit));
    assert.match(String(exit), /Low-level transfer tickets are internal/);
    assert.deepEqual(approvals, []);
    assert.deepEqual(calls, []);
  });
}

test("named terminal reset authorization exposes operation:terminals_reset to native resource rules", async () => {
  const { rex, calls } = fixture();
  const approvals: Approval[] = [];
  const exit = await run(catalog("terminals_reset"), {}, rex, (approval) => {
    approvals.push(approval);
    return approval.resources.includes("operation:terminals_reset")
      ? Effect.fail(new Error("named reset denied")) : Effect.void;
  });
  assert.ok(Exit.isFailure(exit));
  assert.match(String(exit), /named reset denied/);
  assert.equal(approvals.length, 1);
  assert.equal(approvals[0]!.action, "rex.close/destroy");
  assert.deepEqual(calls, []);
});

test("typed Terminal layouts use the selected-host shell creator", async () => {
  const { rex, calls } = fixture();
  const exit = await run(catalog("windows_create"), { layout: terminalLayout }, rex);
  assert.ok(Exit.isSuccess(exit), String(exit));
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0], {
    method: "windows.create",
    input: { sessionId: selected.sessionId, layout: { _tag: "Terminal" }, focus: false },
  });
});

for (const [name, params, method, expected] of [
  ["blocks_swap", { blockId: "block:selected", otherBlockId: "block:focused" }, "blocks.swap", {
    blockId: "block:selected", otherBlockId: "block:focused",
  }],
  ["blocks_move", { blockId: "block:selected", anchorBlockId: "block:focused", direction: "horizontal" }, "blocks.move", {
    blockId: "block:selected", anchorBlockId: "block:focused", direction: "horizontal",
  }],
  ["blocks_resize", {
    beforeBlockId: "block:selected", afterBlockId: "block:focused", direction: "horizontal", ratio: 0.4,
  }, "blocks.resize", {
    beforeBlockId: "block:selected", afterBlockId: "block:focused", direction: "horizontal", ratio: 0.4,
  }],
  ["blocks_resize", {
    beforeBlockId: "block:focused", afterBlockId: "block:selected", direction: "horizontal", ratio: 0.4,
  }, "blocks.resize", {
    beforeBlockId: "block:focused", afterBlockId: "block:selected", direction: "horizontal", ratio: 0.4,
  }],
] as const) {
  test(`${name} rejects a foreign host in secondary references ${JSON.stringify(params)}`, async () => {
    const { rex, calls, blocks } = fixture();
    const secondary = blocks.blocks.find((block) => block.blockId === "block:focused");
    assert.ok(secondary);
    Object.assign(secondary, { hostId: Option.some("host:foreign") });
    const approvals: Approval[] = [];
    const denied = await run(catalog(name), params, rex,
      (approval) => Effect.sync(() => { approvals.push(approval); }));
    assert.ok(Exit.isFailure(denied));
    assert.match(String(denied), /Block block:focused is not on the selected known execution host/);
    assert.deepEqual(approvals, [], "all secondary hosts must be checked before authorization");
    assert.deepEqual(calls, []);
    Object.assign(secondary, { hostId: Option.some("host:a") });
    const allowed = await run(catalog(name), params, rex);
    assert.ok(Exit.isSuccess(allowed), String(allowed));
    assert.deepEqual(calls, [{ method, input: { sessionId: "session:selected", ...expected } }]);
  });
}

for (const key of ["hostId", "host_id"] as const) {
  test(`blocks_create checks nested opaque options ${key} claims before approval`, async () => {
    const { rex, calls } = fixture();
    const approvals: Approval[] = [];
    const denied = await run(catalog("blocks_create"), {
      flavor: "com.superlogical.terminal.shell",
      options: { transport: { routes: [{ [key]: "host:foreign" }] } },
    }, rex, (approval) => Effect.sync(() => { approvals.push(approval); }));
    assert.ok(Exit.isFailure(denied));
    assert.match(String(denied), /Explicit creator host must be the selected execution host/);
    assert.deepEqual(approvals, []);
    assert.deepEqual(calls, []);
    const allowed = await run(catalog("blocks_create"), {
      flavor: "com.superlogical.terminal.shell",
      options: { transport: { routes: [{ [key]: "host:a" }] } },
    }, rex);
    assert.ok(Exit.isSuccess(allowed), String(allowed));
    assert.deepEqual(calls, [{
      method: "blocks.create", input: {
        sessionId: "session:selected", flavor: "com.superlogical.terminal.shell",
        options: { transport: { routes: [{ [key]: "host:a" }] } },
      },
    }]);
  });
}

for (const host of ["host:foreign", undefined]) {
  test(`typed Terminal layouts reject ${host ?? "unknown"} creator hosts`, async () => {
    // Passing undefined to fixture would select its default, so remove host metadata explicitly.
    const { rex, calls, creators } = fixture(host ?? "host:a");
    if (host === undefined) Object.assign(creators.creators[0]!, { hostId: Option.none() });
    const exit = await run(catalog("windows_create"), { layout: terminalLayout }, rex);
    assert.ok(Exit.isFailure(exit));
    assert.match(String(exit), /not on the selected known host/);
    assert.deepEqual(calls, []);
  });
}

test("closing without a window uses the selected block's containing window", async () => {
  const { rex, calls } = fixture();
  const exit = await run(catalog("windows_close"), {}, rex);
  assert.ok(Exit.isSuccess(exit), String(exit));
  assert.deepEqual(calls, [{
    method: "windows.close", input: { sessionId: selected.sessionId, windowId: "window:selected" },
  }]);
});

test("creating a layer without a window explicitly uses the selected block's window", async () => {
  const { rex, calls } = fixture();
  const exit = await run(catalog("layers_create"), { layout: terminalLayout, bounds: [0, 0, 1, 1] }, rex);
  assert.ok(Exit.isSuccess(exit), String(exit));
  assert.deepEqual(calls, [{
    method: "layers.create", input: {
      sessionId: selected.sessionId, windowId: "window:selected", layout: terminalLayout,
      bounds: [0, 0, 1, 1], focus: false,
    },
  }]);
});

for (const name of ["blocks_close", "blocks_zoom"]) {
  test(`${name} rejects an unknown explicit window instead of falling back to the selected block`, async () => {
    const { rex, calls } = fixture();
    let approvals = 0;
    const exit = await run(catalog(name), { windowId: "window:unknown" }, rex,
      () => Effect.sync(() => { approvals++; }));
    assert.ok(Exit.isFailure(exit));
    assert.match(String(exit), /windowId is not in the selected session/);
    assert.equal(approvals, 0);
    assert.deepEqual(calls, []);
  });

  test(`${name} resolves a supplied window's focused block without mixing alternative IDs`, async () => {
    const { rex, calls } = fixture();
    const exit = await run(catalog(name), { windowId: "window:focused" }, rex);
    assert.ok(Exit.isSuccess(exit), String(exit));
    assert.deepEqual(calls, [{
      method: name.replace("_", "."), input: { sessionId: selected.sessionId, blockId: "block:focused" },
    }]);
  });
}

for (const [name, params, method, expected] of [
  ["blocks_close", {}, "blocks.close", { blockId: "block:focused" }],
  ["blocks_zoom", {}, "blocks.zoom", { blockId: "block:focused" }],
  ["blocks_split", { direction: "horizontal", side: "after", layout: terminalLayout }, "blocks.split", {
    anchorId: "block:focused", direction: "horizontal", side: "after", layout: terminalLayout, focus: false,
  }],
  ["blocks_splitBeside", { placement: "right" }, "blocks.splitBeside", {
    anchorId: "block:focused", placement: "right", focus: false,
  }],
  ["windows_close", {}, "windows.close", { windowId: "window:focused" }],
  ["layers_create", { layout: terminalLayout, bounds: [0, 0, 1, 1] }, "layers.create", {
    windowId: "window:focused", layout: terminalLayout, bounds: [0, 0, 1, 1], focus: false,
  }],
] as const) {
  test(`${name} uses the active window's focus when no block is selected`, async () => {
    const { rex, calls } = fixture();
    const approvals: Approval[] = [];
    const exit = await run(catalog(name), params, rex,
      (approval) => Effect.sync(() => { approvals.push(approval); }), { ...selected, blockId: null });
    assert.ok(Exit.isSuccess(exit), String(exit));
    assert.deepEqual(calls, [{ method, input: { sessionId: selected.sessionId, ...expected } }]);
    assert.equal(approvals.length, 1);
    assert.ok(approvals[0]!.resources.includes(`operation:${name}`));
  });

  test(`${name} keeps its approved default when focus changes during authorization`, { timeout: 5000 }, async () => {
    const { rex, calls, view } = fixture();
    await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
      const entered = yield* Deferred.make<Approval>();
      const release = yield* Deferred.make<void>();
      const execution = yield* Effect.forkChild(guardedProgram(
        catalog(name), params, { ...selected, blockId: null, owned: new Set() }, new RexMarkStore(),
        (approval) => Deferred.succeed(entered, approval).pipe(Effect.andThen(Deferred.await(release))),
        () => true,
      ).pipe(Effect.provideService(RexSdk, rex)));
      const approval = yield* Deferred.await(entered);
      assert.deepEqual(JSON.parse(approval.message).params, { sessionId: "session:selected", ...expected });
      assert.deepEqual(calls, [], "authorization must finish before dispatch");
      // Both panes remain valid; only the default focus changes while the user decides.
      Object.assign(view, { activeWindowId: Option.some("window:selected") });
      for (const window of view.windows) Object.assign(window, { focusedBlockId: Option.some("block:selected") });
      yield* Deferred.succeed(release, undefined);
      const exit = yield* Fiber.await(execution);
      assert.ok(Exit.isSuccess(exit), String(exit));
      assert.deepEqual(calls, [{ method, input: { sessionId: "session:selected", ...expected } }]);
    })));
  });
}

test("caller nested mutations during approval cannot alter the approved SDK layout", { timeout: 5000 }, async () => {
  const { rex, calls } = fixture();
  const params = { layout: { _tag: "Terminal", label: "approved" }, bounds: [0, 0, 1, 1], focus: true };
  const expected = {
    sessionId: "session:selected", windowId: "window:selected",
    layout: { _tag: "Terminal", label: "approved" }, bounds: [0, 0, 1, 1], focus: false,
  };
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const entered = yield* Deferred.make<Approval>();
    const release = yield* Deferred.make<void>();
    const execution = yield* Effect.forkChild(guardedProgram(
      catalog("layers_create"), params, { ...selected, owned: new Set() }, new RexMarkStore(),
      (approval) => Deferred.succeed(entered, approval).pipe(Effect.andThen(Deferred.await(release))),
      () => true,
    ).pipe(Effect.provideService(RexSdk, rex)));
    const approval = yield* Deferred.await(entered);
    assert.deepEqual(JSON.parse(approval.message).params, expected);
    params.layout.label = "not approved";
    params.bounds[2] = 0.5;
    params.focus = true;
    yield* Deferred.succeed(release, undefined);
    const exit = yield* Fiber.await(execution);
    assert.ok(Exit.isSuccess(exit), String(exit));
    assert.deepEqual(JSON.parse(approval.message).params, expected);
    assert.deepEqual(calls, [{ method: "layers.create", input: expected }]);
  })));
});

test("a default target moved to another host during approval is not dispatched", { timeout: 5000 }, async () => {
  const { rex, calls, blocks } = fixture();
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const entered = yield* Deferred.make<Approval>();
    const release = yield* Deferred.make<void>();
    const execution = yield* Effect.forkChild(guardedProgram(
      catalog("blocks_zoom"), {}, { ...selected, blockId: null, owned: new Set() }, new RexMarkStore(),
      (approval) => Deferred.succeed(entered, approval).pipe(Effect.andThen(Deferred.await(release))),
      () => true,
    ).pipe(Effect.provideService(RexSdk, rex)));
    const approval = yield* Deferred.await(entered);
    assert.ok(approval.resources.includes("host:host:a/block:block:focused"));
    const block = blocks.blocks.find((item) => item.blockId === "block:focused");
    assert.ok(block);
    Object.assign(block, { hostId: Option.some("host:foreign") });
    yield* Deferred.succeed(release, undefined);
    const exit = yield* Fiber.await(execution);
    assert.ok(Exit.isFailure(exit));
    assert.match(String(exit), /not on the selected known execution host|Targets changed/);
    assert.deepEqual(calls, []);
  })));
});

test("foreign event sessionIds are rejected before authorization or stream start", async () => {
  const { rex } = fixture();
  let starts = 0;
  let approvals = 0;
  const operation = resource("events_stream", {
    sessionIds: Schema.optionalKey(Schema.Array(Schema.String)),
  }, () => { starts++; }, () => ({}));
  for (const sessionIds of [["session:foreign"], [selected.sessionId, "session:foreign"]]) {
    const exit = await run(operation, { sessionIds }, rex,
      () => Effect.sync(() => { approvals++; }));
    assert.ok(Exit.isFailure(exit));
    assert.match(String(exit), /Event sessionIds/);
  }
  assert.equal(approvals, 0);
  assert.equal(starts, 0);
  const exit = await run(resource("events_stream", {
    sessionIds: Schema.optionalKey(Schema.Array(Schema.String)),
  }, (params) => {
    starts++;
    assert.deepEqual(params.sessionIds, [selected.sessionId]);
  }, () => ({})), {}, rex);
  assert.ok(Exit.isSuccess(exit), String(exit));
  assert.equal(starts, 1);
});

for (const [name, flavor, options] of [
  ["tunnels_createDial", REX_TUNNEL_DIAL_FLAVOR, { host: "localhost", port: 8080 }],
  ["tunnels_createListen", REX_TUNNEL_LISTEN_FLAVOR, { port: 8080 }],
] as const) {
  test(`${name} checks the tunnel creator host instead of the default terminal creator`, async () => {
    for (const host of ["host:foreign", "host:a"]) {
      const { rex, calls } = fixture(host, flavor);
      const exit = await run(catalog(name), { options }, rex);
      if (host === "host:foreign") {
        assert.ok(Exit.isFailure(exit));
        assert.match(String(exit), /not on the selected known host/);
        assert.deepEqual(calls, []);
      } else {
        assert.ok(Exit.isSuccess(exit), String(exit));
        assert.equal(calls.length, 1);
        assert.equal(calls[0]!.method, name.replace("_", "."));
      }
    }
  });
}

for (const [name, flavor] of [
  ["tunnels_forwardLocal", REX_TUNNEL_DIAL_FLAVOR],
  ["tunnels_forwardRemote", REX_TUNNEL_LISTEN_FLAVOR],
] as const) {
  test(`${name} routes creator authorization through ${flavor}`, async () => {
    let starts = 0;
    const operation = resource(name, {
      sessionId: Schema.String, target: Schema.Struct({ host: Schema.String, port: Schema.Number }),
    }, () => { starts++; }, () => ({ creatorFlavors: [flavor] }));
    const params = { target: { host: "localhost", port: 8080 } };
    const foreign = await run(operation, params, fixture("host:foreign", flavor).rex);
    assert.ok(Exit.isFailure(foreign));
    assert.match(String(foreign), /not on the selected known host/);
    assert.equal(starts, 0);
    const allowed = await run(operation, params, fixture("host:a", flavor).rex);
    assert.ok(Exit.isSuccess(allowed), String(allowed));
    assert.equal(starts, 1);
  });
}

for (const [name, pathKey, nativeAction] of [
  ["terminals_downloadToFile", "destination", "edit"],
  ["terminals_pasteFileFromPath", "sourcePath", "read"],
] as const) {
  test(`${name} requires native ${nativeAction} permission before starting`, async () => {
    const { rex } = fixture();
    const starts: Record<string, unknown>[] = [];
    const approvals: Approval[] = [];
    const operation = resource(name, {
      sessionId: Schema.String, blockId: Schema.String, [pathKey]: Schema.String,
    }, (params) => { starts.push(params); }, (params) => ({
      blockId: params.blockId,
      ...(pathKey === "destination" ? { destination: params.destination } : { sourcePath: params.sourcePath }),
    }));
    const params = { [pathKey]: "/test/files/../payload" };
    const denied = await run(operation, params, rex, (approval) => {
      approvals.push(approval);
      return approval.action === nativeAction ? Effect.fail(new Error("native file denied")) : Effect.void;
    });
    assert.ok(Exit.isFailure(denied));
    assert.match(String(denied), /native file denied/);
    assert.deepEqual(starts, []);
    assert.deepEqual(approvals.map(({ action, resources }) => ({ action, resources })), [
      { action: nativeAction, resources: ["/test/payload"] },
    ]);
    approvals.length = 0;
    const allowed = await run(operation, params, rex,
      (approval) => Effect.sync(() => { approvals.push(approval); }));
    assert.ok(Exit.isSuccess(allowed), String(allowed));
    assert.equal(starts.length, 1);
    assert.equal(starts[0]![pathKey], "/test/payload");
    assert.equal(approvals[0]!.action, nativeAction);
    assert.ok(approvals[1]!.resources.includes(`operation:${name}`));
    assert.ok(approvals[1]!.resources.includes("server-file:/test/payload"));
  });

  test(`${name} rejects relative server paths before authorization or start`, async () => {
    const { rex } = fixture();
    let starts = 0;
    let approvals = 0;
    const operation = resource(name, {
      sessionId: Schema.String, blockId: Schema.String, [pathKey]: Schema.String,
    }, () => { starts++; }, (params) => ({
      blockId: params.blockId,
      ...(pathKey === "destination" ? { destination: params.destination } : { sourcePath: params.sourcePath }),
    }));
    for (const path of ["relative/payload", "../payload", ""]) {
      const exit = await run(operation, { [pathKey]: path }, rex,
        () => Effect.sync(() => { approvals++; }));
      assert.ok(Exit.isFailure(exit));
      assert.match(String(exit), /must be an absolute path/);
    }
    assert.equal(approvals, 0);
    assert.equal(starts, 0);
  });
}
