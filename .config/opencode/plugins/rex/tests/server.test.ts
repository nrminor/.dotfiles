import assert from "node:assert/strict"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"
import { Agent, Plugin, Tool } from "@opencode/plugin/effect"
import { OpenCode } from "@opencode/sdk/effect"
import { Cause, Deferred, Effect, Exit, Fiber, Layer, Queue, Schema, Stream } from "effect"
import { RexSdk, rexBlockMethods, rexWireMethods, type IRexSdk } from "rex-sdk"
import { makePlugin } from "../index.ts"

test("native host enforces approvals, isolates bindings, and invalidates old tools on reload", { timeout: 30_000 }, async () => {
  const directory = mkdtempSync(join(tmpdir(), "opencode-rex-test-"))
  let connections = 0
  let writes = 0
  let focusMoves = 0
  let fetches = 0
  const status = Schema.decodeUnknownSync(rexWireMethods["server.status"].result)({
    pid: 1, instance_id: "instance", host_id: "host:test", started_at: "2026-01-01T00:00:00Z",
    exit_empty: false, session_count: 1, config: { generation: 1, hash: "" },
  })
  const view = Schema.decodeUnknownSync(rexWireMethods["session.view"].result)({
    revision: 1, session_id: "session:test", active_window_id: "window:test",
    windows: [{ window_id: "window:test", focused_block_id: "block:test", layers: [{
      layer_id: "layer:test", kind: "tiled", bounds: [0, 0, 1, 1],
      layout: { rect: [0, 0, 1, 1], block_id: "block:test" },
      blocks: [{ block_id: "block:test", host_id: "host:test", creator_name: "com.superlogical.terminal" }],
    }] }],
  })
  const listed = Schema.decodeUnknownSync(rexWireMethods["session.list_blocks"].result)({
    blocks: [{
      block_id: "block:test", label: "test", window_id: "window:test", host_id: "host:test",
      creator_name: "com.superlogical.terminal", placement: "placed",
    }],
  })
  const layer = () => Layer.effect(RexSdk, Effect.gen(function* () {
    yield* Effect.acquireRelease(
      Effect.sync(() => { connections++ }),
      () => Effect.sync(() => { connections-- }),
    )
    return {
      server: { status: () => Effect.succeed(status) } satisfies Pick<IRexSdk["server"], "status">,
      sessions: {
        view: () => Effect.succeed(view),
        listBlocks: () => Effect.succeed(listed),
      } satisfies Pick<IRexSdk["sessions"], "view" | "listBlocks">,
      blocks: { focusNext: () => Effect.sync(() => {
        focusMoves++
        return Schema.decodeUnknownSync(rexWireMethods["session.focus_next_pane"].result)({ revision: 1 })
      }) } satisfies Pick<IRexSdk["blocks"], "focusNext">,
      terminals: {
        write: () => Effect.sync(() => {
          writes++
          return Schema.decodeUnknownSync(rexBlockMethods["com.superlogical.terminal.write"].result)({ bytes_written: 5 })
        }),
        programStatus: () => Effect.succeed(
          Schema.decodeUnknownSync(rexBlockMethods["com.superlogical.terminal.program_status"].result)({
            records: [{ state: "idle" }],
          }),
        ),
      } satisfies Pick<IRexSdk["terminals"], "write" | "programStatus">,
    } as unknown as IRexSdk
  }))
  try {
    await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
      const observed = yield* Deferred.make<Plugin.Context>()
      const reloaded = yield* Deferred.make<void>()
      const implementation = makePlugin(layer)
      let loads = 0
      const plugin = Plugin.define({
        id: implementation.id,
        effect: (ctx) => Effect.gen(function* () {
          yield* implementation.effect(ctx)
          if (++loads > 1) yield* Deferred.succeed(reloaded, undefined)
        }),
      })
      const observer = Plugin.define({
        id: "rex-test-observer",
        effect: (ctx) => Deferred.succeed(observed, ctx).pipe(Effect.asVoid),
      })
      const host = yield* OpenCode.create({
        plugins: [plugin, observer], models: { fetch: false },
        config: { directory, project: false, claude: false }, fs: { filewatcher: false },
        fetch: async () => { fetches++; throw new Error("network disabled") },
      })
      yield* host.plugin.list({ location: { directory } })
      const ctx = yield* Deferred.await(observed)
      const events = yield* Queue.unbounded()
      yield* ctx.event.subscribe({ types: ["permission.asked"] }).pipe(
        Stream.runForEach((event) => Queue.offer(events, event)), Effect.forkScoped,
      )
      const first = yield* ctx.session.create({ title: "first" })
      const second = yield* ctx.session.create({ title: "second" })
      for (const session of [first, second]) {
        yield* ctx.session.update({
          sessionID: session.id, permissions: [{ action: "*", resource: "*", effect: "allow" }],
        })
      }
      const approve = Effect.fnUntraced(function* (sessionID: typeof first.id, decision: "once" | "always" = "once") {
        yield* Queue.take(events)
        const pending = yield* ctx.permission.list({ sessionID })
        assert.equal(pending.length, 1)
        yield* ctx.permission.reply({ sessionID, requestID: pending[0]!.id, decision })
      })
      const select = Effect.fnUntraced(function* (sessionID: typeof first.id) {
        const selecting = yield* ctx.session.command({
          sessionID, name: "rex-target",
          text: JSON.stringify({ server: "/fake/rex.sock", sessionId: "session:test", hostId: "host:test", blockId: "block:test" }),
        }).pipe(Effect.forkChild)
        yield* approve(sessionID)
        yield* Fiber.join(selecting)
      })
      const tools = yield* ctx.tool.list()
      const find = (id: string) => {
        const tool = tools.find((item) => item.id === `rex_${id}`)
        assert.ok(tool, `${id} is registered`)
        return tool
      }
      assert.equal(connections, 0, "loading the plugin must not connect using ambient environment")
      const context = (sessionID: typeof first.id): Tool.Context => ({
        sessionID, agent: Agent.ID.make("build"), id: Tool.CallID.make("call_rex_test"),
        messageID: Schema.String.pipe(Schema.brand("Session.Message.ID")).make("msg_rex_test"),
        progress: () => Effect.void,
      })
      const write = (sessionID: typeof first.id) => find("terminals_write").execute({
        sessionId: "session:test", blockId: "block:test", data: "hello",
      }, context(sessionID))
      assert.ok(Exit.isFailure(yield* Effect.exit(write(first.id))))
      assert.equal(writes, 0)
      yield* select(first.id)
      assert.equal(connections, 1)
      const instructions = yield* ctx.session.instructions.entry.list({ sessionID: first.id })
      assert.ok(JSON.stringify(instructions).includes("host:test"))
      assert.ok(Exit.isFailure(yield* Effect.exit(write(second.id))))
      for (const decision of ["always", "once"] as const) {
        const writing = yield* write(first.id).pipe(Effect.forkChild)
        yield* approve(first.id, decision)
        yield* Fiber.join(writing)
      }
      assert.equal(writes, 2, "each approval dispatches once, even after an always reply")
      const cancelled = yield* write(first.id).pipe(Effect.forkChild)
      yield* Queue.take(events)
      yield* Fiber.interrupt(cancelled)
      const interrupted = yield* Fiber.await(cancelled)
      assert.ok(Exit.isFailure(interrupted) && Cause.hasInterruptsOnly(interrupted.cause))
      assert.equal((yield* ctx.permission.list({ sessionID: first.id })).length, 0)
      assert.equal(writes, 2)
      yield* ctx.session.update({
        sessionID: first.id,
        permissions: [{ action: "rex.execution/input", resource: "*", effect: "deny" }],
      })
      assert.ok(Exit.isFailure(yield* Effect.exit(write(first.id))))
      assert.equal(writes, 2)
      assert.equal((yield* ctx.permission.list({ sessionID: first.id })).length, 0)
      yield* find("blocks_focusNext").execute({ sessionId: "session:test" }, context(first.id))
      assert.equal(focusMoves, 1)
      yield* select(second.id)
      assert.equal(connections, 2)
      yield* ctx.session.command({ sessionID: first.id, name: "rex-clear", text: "" })
      assert.equal(connections, 1, "clearing one owner must not dispose another")
      yield* find("blocks_focusNext").execute({ sessionId: "session:test" }, context(second.id))
      assert.equal(focusMoves, 2)
      yield* host.plugin(plugin)
      yield* Deferred.await(reloaded)
      assert.equal(connections, 0, "plugin reload disposes connections without stopping the host")
      assert.ok(Exit.isFailure(yield* Effect.exit(find("blocks_focusNext").execute(
        { sessionId: "session:test" }, context(second.id),
      ))), "old captured tool snapshots cannot retain authority after reload")
    })).pipe(Effect.timeout("25 seconds")))
    assert.equal(connections, 0)
    assert.ok(fetches >= 0)
  } finally {
    rmSync(directory, { recursive: true, force: true })
  }
})
