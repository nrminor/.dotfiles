import { strict as assert } from "node:assert"
import { mkdtemp, rmdir, unlink, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"
import { Deferred, Effect, Exit, Fiber, FileSystem, Option, Schema, Stream } from "effect"
import { BlockId, SessionId, RexEventsLost, RexInvalidResponse, REX_TUNNEL_DIAL_FLAVOR, REX_TUNNEL_LISTEN_FLAVOR, decodeRexEvent, type IRexSdk } from "rex-sdk"
import { makeResources, ResourceByteItem, ResourceFragment, ResourcePage, ResourceStatus, ResourceSummary, resourceDefinitions, type RexResourceSdk } from "../resources.ts"

type Mutable<T> = { -readonly [K in keyof T]: T[K] }
type FakeSdk = { [K in keyof RexResourceSdk]: Mutable<RexResourceSdk[K]> }
const sdk = (): FakeSdk => ({
  ids: { session: Schema.decodeUnknownSync(SessionId), block: Schema.decodeUnknownSync(BlockId) },
  terminals: {
    stream: () => Stream.empty,
    activity: () => Stream.empty,
    watch: () => Stream.empty,
    download: () => Effect.die("unexpected download"),
    downloadToFile: () => Effect.die("unexpected downloadToFile"),
    pasteFiles: () => Effect.die("unexpected pasteFiles"),
  },
  sessions: { watchView: () => Stream.empty },
  events: { stream: () => Stream.empty },
  tunnels: {
    openStream: () => Effect.die("unexpected openStream"),
    connections: () => Stream.die("unexpected connections"),
    forwardLocal: () => Effect.die("unexpected forwardLocal"),
    forwardRemote: () => Effect.die("unexpected forwardRemote"),
  },
})

const call = (resources: Effect.Success<ReturnType<typeof makeResources>>, name: string, params: Record<string, unknown> = {}) => {
  const operation = resources.operations.find((item) => item.name === name)
  assert.ok(operation)
  return operation.program({} as IRexSdk, params, {} as never, {} as never)
}

const waitForStatus = Effect.fn("test.waitForStatus")(function* (
  resources: Effect.Success<ReturnType<typeof makeResources>>,
  handle: { handle: string },
  predicate: (status: { state: string; queued: number }) => boolean,
) {
  for (;;) {
    const status = (yield* call(resources, "resources_status", handle)) as { state: string; queued: number }
    if (predicate(status)) return status
    yield* Effect.yieldNow
  }
}, Effect.timeout("5 seconds"))

const waitForCompletion = (resources: Effect.Success<ReturnType<typeof makeResources>>, handle: { handle: string }) =>
  waitForStatus(resources, handle, (status) => status.state !== "running" && status.state !== "stopping")

test("stream cleanup follows binding scope", async () => {
  let closed = false
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const ready = yield* Deferred.make<void>()
    const stream = Stream.fromEffect(Effect.scoped(Effect.addFinalizer(() => Effect.sync(() => { closed = true })).pipe(
      Effect.andThen(Deferred.succeed(ready, undefined)),
      Effect.andThen(Effect.never),
    )))
    const fake = sdk()
    fake.terminals.stream = () => stream
    const resources = yield* makeResources(fake)
    yield* call(resources, "terminals_stream", { sessionId: "session:a", blockId: "block:a" })
    yield* Deferred.await(ready)
    assert.equal(resources.hasRawStream("block:a"), true)
  })))
  assert.equal(closed, true)
})

test("overflow is visible and retains queued events", async () => {
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const events = yield* Effect.forEach(Array.from({ length: 130 }, (_, i) => i), (i) =>
      decodeRexEvent({ generation: 1, seq: i + 1, type: "fixture_event", payload: { index: i } }))
    const fake = sdk()
    fake.events.stream = () => Stream.fromIterable(events)
    const resources = yield* makeResources(fake)
    const started = (yield* call(resources, "events_stream")) as { handle: string }
    yield* waitForCompletion(resources, started)
    const result = (yield* call(resources, "resources_read", started)) as { state: string; error: string; items: unknown[] }
    assert.equal(result.state, "failed")
    assert.match(result.error, /overflow/)
    assert.equal(result.items.length, 128)
    assert.deepEqual(result.items[0], {
      _tag: "UnknownEvent", seq: 1, sessionId: null, type: "fixture_event", payload: { index: 0 },
    })
    assert.deepEqual(result.items[127], {
      _tag: "UnknownEvent", seq: 128, sessionId: null, type: "fixture_event", payload: { index: 127 },
    })
    const encodedBytes = result.items.reduce<number>((total, item) => total + Buffer.byteLength(JSON.stringify(item)), 0)
    assert.ok(encodedBytes < 1024 * 1024, "the item-count limit, not the byte limit, caused overflow")
  })))
})

test("bytes are encoded losslessly and unknown handles are rejected", async () => {
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const bytes = Uint8Array.from([0, 128, 255])
    const fake = sdk()
    fake.tunnels.openStream = () => Effect.succeed({
      incoming: Stream.fromIterable([bytes]), write: () => Effect.void, end: Effect.void, done: Effect.void,
    })
    const resources = yield* makeResources(fake)
    const started = (yield* call(resources, "tunnels_openStream", { sessionId: "session:a", blockId: "block:a" })) as { handle: string }
    yield* waitForCompletion(resources, started)
    const result = (yield* call(resources, "resources_read", started)) as { items: Array<{ base64: string; byteLength: number }> }
    assert.equal(result.items[0]?.byteLength, bytes.length)
    assert.deepEqual(Buffer.from(result.items[0]!.base64, "base64"), Buffer.from(bytes))
    const unknown = yield* Effect.exit(call(resources, "resources_read", { handle: "unknown" }))
    assert.equal(unknown._tag, "Failure")
  })))
})

test("download pages retain unread bytes and encode optional metadata", async () => {
  const bytes = Uint8Array.from({ length: 100_000 }, (_, i) => i % 256)
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const fake = sdk()
    fake.terminals.download = () => Effect.succeed({
      _tag: "Download", file: { path: "/file", name: "file", size: bytes.length, modifiedAt: "2026-01-01T00:00:00Z", version: Option.some("v1") }, bytes: Stream.fromIterable([bytes]),
    })
    const resources = yield* makeResources(fake)
    const started = (yield* call(resources, "terminals_download", {
      sessionId: "session:a", blockId: "block:a", path: "/file",
    })) as { handle: string }
    yield* waitForCompletion(resources, started)
    const tooSmall = yield* Effect.exit(call(resources, "resources_read", { ...started, maxBytes: 10 }))
    assert.equal(tooSmall._tag, "Failure")
    const chunks: Buffer[] = []
    for (let i = 0; i < 10; i++) {
      const page = (yield* call(resources, "resources_read", started)) as {
        state: string; queued: number; result: { file: { version: string } };
        items: Array<{ base64: string; byteLength: number }>
      }
      assert.equal(Schema.is(ResourcePage)(page), true)
      assert.equal(page.result.file.version, "v1")
      for (const item of page.items) {
        assert.equal(Schema.is(ResourceByteItem)(item), true)
        const chunk = Buffer.from(item.base64, "base64")
        assert.equal(chunk.length, item.byteLength)
        chunks.push(chunk)
      }
      if (page.state === "ended" && page.queued === 0) break
      yield* Effect.yieldNow
    }
    assert.deepEqual(Buffer.concat(chunks), Buffer.from(bytes))
  })))
})

test("large events are split into reassemblable JSON fragments", async () => {
  const payload = { text: "λ".repeat(35_000) }
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const event = yield* decodeRexEvent({ generation: 1, seq: 1, type: "fixture_event", payload })
    assert.ok(Buffer.byteLength(JSON.stringify(payload)) > 45 * 1024, "the event must exceed one page before envelope overhead")
    const fake = sdk()
    fake.events.stream = () => Stream.fromIterable([event])
    const resources = yield* makeResources(fake)
    const started = (yield* call(resources, "events_stream")) as { handle: string }
    yield* waitForCompletion(resources, started)
    const fragments: Array<{ index: number; count: number; base64: string }> = []
    for (let i = 0; i < 10; i++) {
      const page = (yield* call(resources, "resources_read", started)) as {
        items: typeof fragments; state: string; queued: number
      }
      assert.equal(Schema.is(ResourcePage)(page), true)
      for (const fragment of page.items) assert.equal(Schema.is(ResourceFragment)(fragment), true)
      fragments.push(...page.items)
      if (page.state === "ended" && page.queued === 0) break
    }
    assert.equal(fragments.length, fragments[0]!.count)
    assert.deepEqual(fragments.map((part) => part.index), fragments.map((_, i) => i))
    const json = Buffer.concat(fragments.map((part) => Buffer.from(part.base64, "base64"))).toString()
    assert.deepEqual(JSON.parse(json), {
      _tag: "UnknownEvent", seq: 1, sessionId: null, type: "fixture_event", payload,
    })
  })))
})

test("downloadToFile supplies filesystem service and reports completion", async () => {
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const fake = sdk()
    fake.terminals.downloadToFile = (_target: unknown, _path: unknown, destination: string) =>
      Effect.gen(function* () {
        yield* FileSystem.FileSystem
        return { _tag: "Downloaded" as const, destination, bytesWritten: 3, file: { path: "/remote", name: "remote", size: 3, modifiedAt: "2026-01-01T00:00:00Z", version: Option.none() } }
      })
    const resources = yield* makeResources(fake)
    const args = { sessionId: "session:a", blockId: "block:a", path: "/remote", destination: "/local" }
    assert.equal((yield* Effect.exit(call(resources, "terminals_downloadToFile", args)))._tag, "Failure")
    const started = (yield* call(resources, "terminals_downloadToFile", { ...args, overwrite: true })) as { handle: string }
    yield* waitForCompletion(resources, started)
    const status = (yield* call(resources, "resources_status", started)) as {
      state: string; result: { destination: string; bytesWritten: number }
    }
    assert.equal(status.state, "ended")
    assert.equal(status.result.destination, "/local")
    assert.equal(status.result.bytesWritten, 3)
  })))
})

test("stopping downloadToFile interrupts the transfer for the declared destination", async () => {
  let cancelled = false
  let destination: string | undefined
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const ready = yield* Deferred.make<void>()
    const fake = sdk()
    fake.terminals.downloadToFile = (_target: unknown, _path: unknown, dest: string) =>
      Effect.scoped(Effect.gen(function* () {
        destination = dest
        yield* Effect.addFinalizer(() => Effect.sync(() => { cancelled = true }))
        yield* Deferred.succeed(ready, undefined)
        return yield* Effect.never
      }))
    const resources = yield* makeResources(fake)
    const started = (yield* call(resources, "terminals_downloadToFile", {
      sessionId: "session:a", blockId: "block:a", path: "/remote", destination: "/chosen", overwrite: true,
    })) as { handle: string }
    yield* Deferred.await(ready)
    yield* call(resources, "resources_stop", started)
    assert.equal(destination, "/chosen")
    assert.equal(cancelled, true)
  })))
})

test("pasteFileFromPath streams a local file in bounded chunks and rejects directories", async () => {
  const dir = await mkdtemp(join(tmpdir(), "rex-resource-test-"))
  const path = join(dir, "source.bin")
  const original = Buffer.from(Array.from({ length: 300_000 }, (_, i) => i % 256))
  await writeFile(path, original)
  try {
    const chunks: Buffer[] = []
    let declaredSize = -1
    let declaredName = ""
    await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
      const fake = sdk()
      fake.terminals.pasteFiles = (_target, files) => {
        const file = files[0]!
        if (!("stream" in file)) return Effect.die("expected stream")
        declaredName = file.name
        declaredSize = file.size
        return Stream.runForEach(file.stream, (chunk) => Effect.sync(() => { chunks.push(Buffer.from(chunk)) }))
      }
      const resources = yield* makeResources(fake)
      const target = { sessionId: "session:a", blockId: "block:a" }
      const started = (yield* call(resources, "terminals_pasteFileFromPath", {
        ...target, sourcePath: path, name: "upload.bin",
      })) as { handle: string }
      yield* waitForCompletion(resources, started)
      const status = (yield* call(resources, "resources_status", started)) as { state: string }
      assert.equal(status.state, "ended")
      assert.equal(declaredName, "upload.bin")
      assert.equal(declaredSize, original.length)
      assert.ok(chunks.length > 1)
      assert.ok(chunks.every((chunk) => chunk.length <= 64 * 1024))
      assert.deepEqual(Buffer.concat(chunks), original)
      const directory = (yield* call(resources, "terminals_pasteFileFromPath", {
        ...target, sourcePath: dir,
      })) as { handle: string }
      yield* waitForCompletion(resources, directory)
      const rejected = (yield* call(resources, "resources_status", directory)) as { state: string; error: string }
      assert.equal(rejected.state, "failed")
      assert.match(rejected.error, /regular file/)
    })))
  } finally {
    await unlink(path)
    await rmdir(dir)
  }
})

test("tunnel streams write, half-close, and close their resource scope on stop", async () => {
  let closed = false
  let ended = false
  const written: Buffer[] = []
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const fake = sdk()
    fake.tunnels.openStream = () => Effect.gen(function* () {
      yield* Effect.addFinalizer(() => Effect.sync(() => { closed = true }))
      return {
        incoming: Stream.fromEffect(Effect.never),
        write: (data: Uint8Array) => Effect.sync(() => { written.push(Buffer.from(data)) }),
        end: Effect.sync(() => { ended = true }),
        done: Effect.never,
      }
    })
    const resources = yield* makeResources(fake)
    const started = (yield* call(resources, "tunnels_openStream", {
      sessionId: "session:a", blockId: "block:a",
    })) as { handle: string }
    yield* call(resources, "resources_write", { ...started, base64: "AP8=" })
    yield* call(resources, "resources_end", started)
    yield* call(resources, "resources_stop", started)
    assert.equal(closed, true)
    assert.equal(ended, true)
    assert.deepEqual(written, [Buffer.from([0, 255])])
  })))
})

test("connection offers are owned and single use", async () => {
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const done = yield* Deferred.make<void>()
    const fake = sdk()
    const stream = {
      incoming: Stream.fromEffect(Effect.never),
      write: () => Effect.void, end: Effect.void, done: Deferred.await(done),
    }
    fake.tunnels.connections = () => Stream.concat(
        Stream.fromIterable([{ peer: "127.0.0.1:1", accept: Effect.succeed(stream) }]),
        Stream.fromEffect(Effect.never),
      )
    const resources = yield* makeResources(fake)
    const started = (yield* call(resources, "tunnels_connections", {
      sessionId: "session:a", blockId: "block:a",
    })) as { handle: string }
    yield* waitForStatus(resources, started, (status) => status.queued > 0)
    const page = (yield* call(resources, "resources_read", started)) as { items: Array<{ handle: string }> }
    const offer = page.items[0]!
    const accepted = (yield* call(resources, "resources_accept", offer)) as { handle: string }
    assert.notEqual(accepted.handle, offer.handle)
    const duplicate = yield* Effect.exit(call(resources, "resources_accept", offer))
    assert.equal(duplicate._tag, "Failure")
    yield* call(resources, "resources_stop", accepted)
  })))
})

test("cancelled acquisition closes its provisional scope", async () => {
  let closed = false
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const ready = yield* Deferred.make<void>()
    const fake = sdk()
    fake.tunnels.openStream = () => Effect.gen(function* () {
      yield* Effect.addFinalizer(() => Effect.sync(() => { closed = true }))
      yield* Deferred.succeed(ready, undefined)
      return yield* Effect.never
    })
    const resources = yield* makeResources(fake)
    const fiber = yield* Effect.forkChild(call(resources, "tunnels_openStream", {
      sessionId: "session:a", blockId: "block:a",
    }))
    yield* Deferred.await(ready)
    yield* Fiber.interrupt(fiber)
    assert.equal(closed, true)
    const list = (yield* call(resources, "resources_list")) as unknown[]
    assert.equal(list.length, 0)
  })))
})

test("stopping a provisional resource cancels acquisition and prevents worker startup", async () => {
  let closed = false
  let workerStarted = false
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const ready = yield* Deferred.make<void>()
    const release = yield* Deferred.make<void>()
    const fake = sdk()
    fake.tunnels.openStream = () => Effect.gen(function* () {
      yield* Effect.addFinalizer(() => Effect.sync(() => { closed = true }))
      yield* Deferred.succeed(ready, undefined)
      yield* Deferred.await(release)
      return {
        incoming: Stream.fromEffect(Effect.sync(() => { workerStarted = true; return new Uint8Array() })),
        write: () => Effect.void, end: Effect.void, done: Effect.void,
      }
    })
    const resources = yield* makeResources(fake)
    const starter = yield* Effect.forkChild(call(resources, "tunnels_openStream", {
      sessionId: "session:a", blockId: "block:a",
    }))
    yield* Deferred.await(ready)
    const list = (yield* call(resources, "resources_list")) as Array<{ handle: string }>
    assert.equal(list.length, 1)
    const stopped = (yield* call(resources, "resources_stop", list[0]!)) as { state: string }
    assert.equal(stopped.state, "stopped")
    assert.equal(closed, true)
    yield* Deferred.succeed(release, undefined)
    assert.equal(workerStarted, false)
    assert.equal((yield* Fiber.await(starter))._tag, "Failure")
  })))
})

test("resource list remains small even with large individual metadata", async () => {
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const fake = sdk()
    fake.tunnels.forwardLocal = () => Effect.succeed({
      blockId: fake.ids.block("block:f"), address: "x".repeat(7000), stopped: Effect.never,
    })
    const resources = yield* makeResources(fake)
    let first = ""
    for (let i = 0; i < 20; i++) {
      const started = (yield* call(resources, "tunnels_forwardLocal", {
        sessionId: "session:a", target: { host: "localhost", port: 123 },
      })) as { handle: string }
      if (!first) first = started.handle
    }
    const list = (yield* call(resources, "resources_list")) as Array<Record<string, unknown>>
    assert.equal(list.length, 20)
    assert.ok(Buffer.byteLength(JSON.stringify(list)) < 65_536)
    assert.equal("result" in list[0]!, false)
    assert.equal("error" in list[0]!, false)
    const status = (yield* call(resources, "resources_status", { handle: first })) as {
      result: { address: string }
    }
    assert.equal(status.result.address.length, 7000)
  })))
})

test("immediately completed and failed workers still return resource handles", async () => {
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const complete = yield* makeResources(sdk())
    const ended = (yield* call(complete, "events_stream")) as { handle: string; state: string }
    assert.equal(ended.state, "ended")
    assert.ok(ended.handle)
    const fake = sdk()
    fake.events.stream = () => Stream.fail(new RexEventsLost("connection_ended"))
    const failing = yield* makeResources(fake)
    const failed = (yield* call(failing, "events_stream")) as { handle: string; state: string }
    assert.equal(failed.state, "failed")
    assert.ok(failed.handle)
  })))
})

test("failed forward is not reported as running and its scope is closed", async () => {
  let closed = false
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const fake = sdk()
    fake.tunnels.forwardLocal = () => Effect.gen(function* () {
      yield* Effect.addFinalizer(() => Effect.sync(() => { closed = true }))
      return { blockId: fake.ids.block("block:forward"), address: "127.0.0.1:123", stopped: Effect.die(new Error("lost")) }
    })
    const resources = yield* makeResources(fake)
    const started = (yield* call(resources, "tunnels_forwardLocal", {
      sessionId: "session:a", target: { host: "localhost", port: 123 },
    })) as { handle: string }
    yield* waitForCompletion(resources, started)
    const status = (yield* call(resources, "resources_status", started)) as {
      state: string; result: { address: string }; error: string
    }
    assert.equal(status.state, "failed")
    assert.match(status.error, /lost/)
    assert.equal(status.result.address, "127.0.0.1:123")
    assert.equal(closed, true)
  })))
})

test("raw streams conflict with activity and stopping releases the lease", async () => {
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const fake = sdk()
    fake.terminals.stream = () => Stream.fromEffect(Effect.never)
    fake.terminals.activity = () => Stream.fromEffect(Effect.never)
    const resources = yield* makeResources(fake)
    const target = { sessionId: "session:a", blockId: "block:a" }
    const started = (yield* call(resources, "terminals_stream", target)) as { handle: string }
    const conflict = yield* Effect.exit(call(resources, "terminals_activity", target))
    assert.equal(conflict._tag, "Failure")
    yield* call(resources, "resources_stop", started)
    assert.equal(resources.hasRawStream("block:a"), false)
    yield* call(resources, "terminals_activity", target)
  })))
})

test("finite shared leases block raw starts until cancellation, and raw blocks shared work", async () => {
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const fake = sdk()
    fake.terminals.stream = () => Stream.fromEffect(Effect.never)
    const resources = yield* makeResources(fake)
    const ready = yield* Deferred.make<void>()
    const work = resources.withShared("block:a", Deferred.succeed(ready, undefined).pipe(
      Effect.andThen(Effect.never),
    ))
    const fiber = yield* Effect.forkChild(work)
    yield* Deferred.await(ready)
    const target = { sessionId: "session:a", blockId: "block:a" }
    assert.equal((yield* Effect.exit(call(resources, "terminals_stream", target)))._tag, "Failure")
    yield* Fiber.interrupt(fiber)
    const raw = (yield* call(resources, "terminals_stream", target)) as { handle: string }
    assert.equal((yield* Effect.exit(resources.withShared("block:a", Effect.void)))._tag, "Failure")
    yield* resources.withShared("block:b", Effect.void)
    yield* call(resources, "resources_stop", raw)
    yield* resources.withShared("block:a", Effect.void)
  })))
})

test("resource output contracts describe envelopes and byte fragments", () => {
  const valid = Schema.is(ResourceStatus)
  const status = { handle: "h", kind: "terminals_stream", state: "running", queued: 0 }
  assert.equal(valid(status), true)
  assert.equal(valid({ ...status, state: "unknown" }), false)
  assert.equal(valid({ ...status, kind: "unknown" }), false)
  assert.equal(Schema.is(ResourceSummary)({ ...status, queued: "0" }), false)
  assert.equal(Schema.is(ResourceByteItem)({ base64: "AP8=", byteLength: 2 }), true)
  assert.equal(Schema.is(ResourceByteItem)({ base64: "AP8=", byteLength: "2" }), false)
  assert.equal(Schema.is(ResourceFragment)({ fragment: "f", index: 0, count: 1, encoding: "json-utf8-base64", base64: "e30=" }), true)
  assert.equal(Schema.is(ResourceFragment)({ fragment: "f", index: 0, count: 1, encoding: "other", base64: "e30=" }), false)
  assert.equal(Schema.is(ResourcePage)({ ...status, items: [{ base64: "AP8=", byteLength: 2 }] }), true)
  assert.equal(Schema.is(ResourcePage)({ ...status, items: "not an array" }), false)
  for (const definition of resourceDefinitions) {
    assert.notEqual(definition.output, Schema.Unknown)
  }
})

test("prepared resource operations validate and capture the approved target", async () => {
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const fake = sdk()
    let blockId = ""
    fake.tunnels.openStream = (target) => {
      blockId = target.blockId
      return Effect.succeed({ incoming: Stream.empty, write: () => Effect.void, end: Effect.void, done: Effect.void })
    }
    const resources = yield* makeResources(fake)
    const operation = resources.operations.find((item) => item.name === "tunnels_openStream")
    assert.ok(operation)
    assert.equal(Exit.isFailure(yield* Effect.exit(operation.prepare({ sessionId: "session:a", blockId: 12 }))), true)
    const input = { sessionId: "session:a", blockId: "block:a" }
    const prepared = yield* operation.prepare(input)
    assert.deepEqual(prepared.parameters, input)
    assert.deepEqual(prepared.targeting, { blockId: "block:a" })
    input.blockId = "block:other"
    yield* prepared.execute({} as IRexSdk, {} as never, {} as never)
    assert.equal(blockId, "block:a")
  })))
})

test("resource preparation projects operation-specific targeting evidence", async () => {
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const resources = yield* makeResources(sdk())
    const target = { sessionId: "session:a", blockId: "block:a" }
    const blockEvidence = { blockId: "block:a" }
    const cases: Array<[string, Record<string, unknown>, Record<string, unknown>]> = [
      ["terminals_stream", target, blockEvidence],
      ["terminals_activity", target, blockEvidence],
      ["terminals_watch", target, blockEvidence],
      ["terminals_download", { ...target, path: "/remote" }, blockEvidence],
      ["terminals_downloadToFile", { ...target, path: "/remote", destination: "/local", overwrite: true }, { ...blockEvidence, destination: "/local" }],
      ["terminals_pasteFileFromPath", { ...target, sourcePath: "/local" }, { ...blockEvidence, sourcePath: "/local" }],
      ["tunnels_openStream", target, blockEvidence],
      ["tunnels_connections", target, blockEvidence],
      ["tunnels_forwardLocal", { sessionId: "session:a", target: { host: "host", port: 1 } }, { creatorFlavors: [REX_TUNNEL_DIAL_FLAVOR] }],
      ["tunnels_forwardRemote", { sessionId: "session:a", target: { host: "host", port: 1 } }, { creatorFlavors: [REX_TUNNEL_LISTEN_FLAVOR] }],
      ["sessions_watchView", { sessionId: "session:a" }, {}],
      ["events_stream", { server: "all" }, { server: "all" }],
      ["events_stream", {}, {}],
      ["resources_list", {}, {}],
      ["resources_status", { handle: "h" }, { handle: "h" }],
      ["resources_read", { handle: "h", maxBytes: 512 }, { handle: "h", maxBytes: 512 }],
      ["resources_read", { handle: "h" }, { handle: "h" }],
      ["resources_stop", { handle: "h" }, { handle: "h" }],
      ["resources_write", { handle: "h", base64: "AP8=" }, { handle: "h" }],
      ["resources_end", { handle: "h" }, { handle: "h" }],
      ["resources_accept", { handle: "h" }, { handle: "h" }],
    ]
    for (const [name, input, expected] of cases) {
      const operation = resources.operations.find((item) => item.name === name)
      assert.ok(operation, name)
      const prepared = yield* operation.prepare(input)
      assert.deepEqual(prepared.targeting, expected, name)
    }
  })))
})

test("typed watch and forwarding fields reach the SDK without coercion", async () => {
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const fake = sdk()
    let watched = false
    let forwarded = false
    fake.terminals.watch = (target, options) => {
      assert.deepEqual(target, { sessionId: "session:a", blockId: "block:a" })
      assert.deepEqual(options, { tailBytes: 120, settle: 30 })
      watched = true
      return Stream.empty
    }
    fake.tunnels.forwardLocal = (input) => {
      assert.deepEqual(input, {
        sessionId: "session:a", target: { host: "localhost", port: 1234 },
        listen: { host: "127.0.0.1", port: 0 }, label: "test",
      })
      forwarded = true
      return Effect.succeed({ blockId: fake.ids.block("block:forward"), address: "127.0.0.1:1", stopped: Effect.never })
    }
    const resources = yield* makeResources(fake)
    yield* call(resources, "terminals_watch", { sessionId: "session:a", blockId: "block:a", tailBytes: 120, settleMs: 30 })
    yield* call(resources, "tunnels_forwardLocal", {
      sessionId: "session:a", target: { host: "localhost", port: 1234 },
      listen: { host: "127.0.0.1", port: 0 }, label: "test",
    })
    assert.equal(watched, true)
    assert.equal(forwarded, true)
    assert.equal(Exit.isFailure(yield* Effect.exit(call(resources, "terminals_watch", {
      sessionId: "session:a", blockId: "block:a", tailBytes: "120",
    }))), true)
  })))
})

test("emitted resource operation outputs satisfy their independent wire contracts", async () => {
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const fake = sdk()
    const tunnel = {
      incoming: Stream.concat(Stream.succeed(Uint8Array.from([0, 255])), Stream.fromEffect(Effect.never)),
      write: (_data: Uint8Array) => Effect.void,
      end: Effect.void,
      done: Effect.never,
    }
    fake.tunnels.openStream = () => Effect.succeed(tunnel)
    fake.tunnels.connections = () => Stream.concat(
      Stream.succeed({ peer: "127.0.0.1:1", accept: Effect.succeed(tunnel) }),
      Stream.fromEffect(Effect.never),
    )
    const resources = yield* makeResources(fake)
    const target = { sessionId: "session:a", blockId: "block:a" }
    const check = (name: string, value: unknown) => {
      const definition = resourceDefinitions.find((item) => item.name === name)
      assert.ok(definition?.output && typeof definition.output !== "string")
      assert.equal(Schema.is(definition.output)(value), true, `${name} emitted invalid output`)
    }
    const started = (yield* call(resources, "tunnels_openStream", target)) as { handle: string; kind: string; state: string }
    check("tunnels_openStream", started)
    assert.equal(started.kind, "tunnels_openStream")
    assert.equal(started.state, "running")
    yield* waitForStatus(resources, started, (status) => status.queued > 0)
    const status = (yield* call(resources, "resources_status", started)) as { handle: string; queued: number }
    check("resources_status", status)
    assert.equal(status.handle, started.handle)
    assert.equal(status.queued, 1)
    const list = (yield* call(resources, "resources_list")) as Array<{ handle: string; kind: string }>
    check("resources_list", list)
    assert.deepEqual(list.map(({ handle, kind }) => ({ handle, kind })), [{ handle: started.handle, kind: "tunnels_openStream" }])
    const page = (yield* call(resources, "resources_read", started)) as { items: unknown[]; queued: number }
    check("resources_read", page)
    assert.deepEqual(page.items, [{ base64: "AP8=", byteLength: 2 }])
    assert.equal(page.queued, 0)
    const written = yield* call(resources, "resources_write", { ...started, base64: "AP8=" })
    check("resources_write", written)
    const ended = yield* call(resources, "resources_end", started)
    check("resources_end", ended)
    const stopped = (yield* call(resources, "resources_stop", started)) as { state: string }
    check("resources_stop", stopped)
    assert.equal(stopped.state, "stopped")

    const listener = (yield* call(resources, "tunnels_connections", target)) as { handle: string }
    check("tunnels_connections", listener)
    yield* waitForStatus(resources, listener, (item) => item.queued > 0)
    const offers = (yield* call(resources, "resources_read", listener)) as { items: Array<{ handle: string; peer: string }> }
    check("resources_read", offers)
    assert.equal(offers.items[0]?.peer, "127.0.0.1:1")
    const accepted = (yield* call(resources, "resources_accept", offers.items[0]!)) as { handle: string; kind: string }
    check("resources_accept", accepted)
    assert.equal(accepted.kind, "tunnels_acceptedStream")
    assert.notEqual(accepted.handle, offers.items[0]?.handle)
    yield* call(resources, "resources_stop", accepted)
    yield* call(resources, "resources_stop", listener)

    const listSchema = resourceDefinitions.find((item) => item.name === "resources_list")!.output!
    const pageSchema = resourceDefinitions.find((item) => item.name === "resources_read")!.output!
    const statusSchema = resourceDefinitions.find((item) => item.name === "resources_stop")!.output!
    assert.ok(typeof listSchema !== "string" && typeof pageSchema !== "string" && typeof statusSchema !== "string")
    assert.equal(Schema.is(listSchema)([{ handle: "x", kind: "nope", state: "running", queued: 0 }]), false)
    assert.equal(Schema.is(pageSchema)({ handle: "x", kind: "events_stream", state: "ended", queued: 0, items: 1 }), false)
    assert.equal(Schema.is(statusSchema)({ handle: "x", kind: "events_stream", state: "done", queued: 0 }), false)
    for (const name of ["tunnels_openStream", "resources_status", "resources_stop", "resources_write", "resources_end", "resources_accept"]) {
      const output = resourceDefinitions.find((item) => item.name === name)?.output
      assert.ok(output && typeof output !== "string")
      assert.equal(Schema.is(output)({ handle: "x", kind: "unknown", state: "running", queued: 0 }), false, name)
    }
  })))
})

test("cancelled stop retains the raw lease until its delayed finalizer completes", async () => {
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const ready = yield* Deferred.make<void>()
    const finalizing = yield* Deferred.make<void>()
    const release = yield* Deferred.make<void>()
    let finalized = 0
    const stream = Stream.fromEffect(Effect.scoped(Effect.gen(function* () {
      yield* Effect.addFinalizer(() => Effect.gen(function* () {
        yield* Deferred.succeed(finalizing, undefined)
        yield* Deferred.await(release)
        finalized++
      }))
      yield* Deferred.succeed(ready, undefined)
      return yield* Effect.never
    })))
    const fake = sdk()
    fake.terminals.stream = () => stream
    const resources = yield* makeResources(fake)
    const target = { sessionId: "session:a", blockId: "block:a" }
    const raw = (yield* call(resources, "terminals_stream", target)) as { handle: string }
    yield* Deferred.await(ready)
    const stopping = yield* Effect.forkChild(call(resources, "resources_stop", raw))
    yield* Deferred.await(finalizing)
    const cancelling = yield* Effect.forkChild(Fiber.interrupt(stopping))
    assert.equal(resources.hasRawStream(target.blockId), true)
    assert.equal(Exit.isFailure(yield* Effect.exit(call(resources, "terminals_stream", target))), true)
    assert.equal(Exit.isFailure(yield* Effect.exit(call(resources, "terminals_activity", target))), true)
    assert.equal(Exit.isFailure(yield* Effect.exit(resources.withShared(target.blockId, Effect.void))), true)
    yield* Deferred.succeed(release, undefined)
    yield* Fiber.join(cancelling)
    assert.equal(finalized, 1)
    assert.equal(resources.hasRawStream(target.blockId), false)
    yield* resources.withShared(target.blockId, Effect.void)
    const replacement = (yield* call(resources, "terminals_stream", target)) as { handle: string }
    yield* call(resources, "resources_stop", replacement)
    assert.equal(finalized, 2)
  })))
})

test("immediate raw completion and failure release their leases", async () => {
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    const target = { sessionId: "session:a", blockId: "block:a" }
    for (const stream of [Stream.empty, Stream.fail(new RexInvalidResponse("stream", undefined, "failure"))]) {
      const fake = sdk()
      fake.terminals.stream = () => stream
      const resources = yield* makeResources(fake)
      yield* call(resources, "terminals_stream", target)
      assert.equal(resources.hasRawStream(target.blockId), false)
      yield* resources.withShared(target.blockId, Effect.void)
      yield* call(resources, "terminals_stream", target)
    }
  })))
})
