import assert from "node:assert/strict";
import { test } from "node:test";
import { Deferred, Effect, Exit, Fiber, Option, Schema, Scope } from "effect";
import { RexClientPerformRequestedEvent, type IRexSdk, type RexCallRequestHandler, type RexPerformRequestHandler } from "rex-sdk";
import { makeRequests, requestDefinitions } from "../requests.ts";
import { RexMarkStore } from "../vendor/rex-tool-marks.ts";

const fixture = () => {
  let call!: RexCallRequestHandler;
  let perform!: RexPerformRequestHandler;
  const rex = { clients: {
    serveCallRequests: (handler: RexCallRequestHandler) => { call = handler; return Effect.never; },
    servePerformRequests: (handler: RexPerformRequestHandler) => { perform = handler; return Effect.never; },
  } } as unknown as IRexSdk;
  return { rex, call: () => call, perform: () => perform };
};
const request = { callId: "secret-wire-id", server: "remote", method: "delete_everything", args: Option.some({ x: 1 }) };

const validated = (name: string, effect: Effect.Effect<unknown, unknown>) => effect.pipe(
  Effect.tap((result) => Effect.sync(() => {
    const definition = requestDefinitions.find((entry) => entry.name === name);
    assert.ok(definition, `missing definition for ${name}`);
    Schema.decodeUnknownSync(Schema.toType(definition.output))(result);
  })),
);

test("cancelled stop completes cleanup before a replacement server can start", { timeout: 5000 }, async () => {
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const entered = yield* Deferred.make<void>();
    const release = yield* Deferred.make<void>();
    let closed = false;
    const rex = { clients: {
      serveCallRequests: () => Effect.never.pipe(Effect.ensuring(Effect.gen(function* () {
        yield* Deferred.succeed(entered, undefined);
        yield* Deferred.await(release);
        closed = true;
      }))),
    } } as unknown as IRexSdk;
    const registry = yield* makeRequests(rex);
    const op = (name: string, params: Record<string, unknown> = {}) =>
      validated(name, registry.operations.find((entry) => entry.name === name)!.program(rex, params, {}, new RexMarkStore()));
    const server = (yield* op("clients_serveCallRequests")) as { handle: string };
    const stopping = yield* Effect.forkChild(op("requests_stop", { handle: server.handle }));
    yield* Deferred.await(entered);
    const cancellation = yield* Effect.forkChild(Fiber.interrupt(stopping));
    assert.equal((yield* Effect.exit(op("clients_serveCallRequests")))._tag, "Failure");
    assert.equal(closed, false);
    yield* Deferred.succeed(release, undefined);
    yield* Fiber.join(cancellation);
    assert.equal(closed, true);
    const status = yield* op("requests_status");
    assert.match(JSON.stringify(status), /"state":"stopped"/);
    yield* op("clients_serveCallRequests");
  })));
});

test("managed servers expose requests and submit exactly one owned reply", async () => {
  const f = fixture();
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const a = yield* makeRequests(f.rex);
    const b = yield* makeRequests(f.rex);
    const op = (name: string, params: Record<string, unknown> = {}) => validated(name, a.operations.find((x) => x.name === name)!.program(f.rex, params, {}, new RexMarkStore()));
    yield* op("clients_serveCallRequests");
    const handler = yield* Effect.forkChild(f.call()(request));
    yield* Effect.yieldNow;
    const list = (yield* op("requests_list")) as { requests: Array<{ handle: string }> };
    assert.equal(list.requests.length, 1);
    const handle = list.requests[0]!.handle;
    const read = (yield* op("requests_read", { handle })) as { request: Record<string, unknown> };
    assert.equal(read.request.method, "delete_everything");
    assert.equal("callId" in read.request, false);
    assert.equal("request" in list.requests[0]!, false);
    assert.equal((yield* Effect.exit(b.reply({ handle, result: 1 })))._tag, "Failure");
    assert.ok(Exit.isFailure(yield* Effect.exit(a.reply({ handle }))));
    assert.ok(Exit.isFailure(yield* Effect.exit(a.reply({ handle, result: 1, error: { code: "refused", message: "No" } }))));
    assert.deepEqual(yield* op("requests_reply", { handle, result: { ok: true } }), { status: "submitted" });
    assert.deepEqual(yield* Fiber.join(handler), { ok: true });
    assert.equal((yield* Effect.exit(a.reply({ handle, result: 1 })))._tag, "Failure");
  })));
});

test("stop and scope close cancel pending handlers", async () => {
  const f = fixture();
  await Effect.runPromise(Effect.gen(function* () {
    const scope = yield* Scope.make();
    const a = yield* Scope.provide(scope)(makeRequests(f.rex));
    const op = (name: string, params: Record<string, unknown> = {}) => validated(name, a.operations.find((x) => x.name === name)!.program(f.rex, params, {}, new RexMarkStore()));
    const server = (yield* op("clients_serveCallRequests")) as { handle: string };
    const one = yield* Effect.forkChild(f.call()(request));
    yield* Effect.yieldNow;
    yield* op("requests_stop", { handle: server.handle });
    assert.equal((yield* Fiber.await(one))._tag, "Failure");
    yield* op("clients_serveCallRequests");
    const two = yield* Effect.forkChild(f.call()(request));
    yield* Effect.yieldNow;
    yield* Scope.close(scope, Exit.void);
    assert.equal((yield* Fiber.await(two))._tag, "Failure");
  }));
});

test("perform requests accept documented failures and enforce capacity", async () => {
  const f = fixture();
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const a = yield* makeRequests(f.rex);
    const op = (name: string) => validated(name, a.operations.find((x) => x.name === name)!.program(f.rex, {}, {}, new RexMarkStore()));
    yield* op("clients_servePerformRequests");
    const event = yield* Schema.decodeUnknownEffect(RexClientPerformRequestedEvent)({
      call_id: "id", action: "do-not-run",
      requester: { client_id: "client:00000000-0000-4000-8000-000000000001", principal: { kind: "peer", transport: "unix", display: "test" } },
    });
    const fibers = [];
    for (let i = 0; i < 64; i++) fibers.push(yield* Effect.forkChild(f.perform()(event)));
    yield* Effect.yieldNow;
    assert.equal((yield* Effect.exit(f.perform()(event)))._tag, "Failure");
    const list = (yield* op("requests_list")) as { requests: Array<{ handle: string }> };
    assert.equal(list.requests.length, 64);
    yield* a.reply({ handle: list.requests[0]!.handle, error: { code: "refused", message: "No" } });
    assert.equal((yield* Fiber.await(fibers[0]!))._tag, "Failure");
  })));
});
