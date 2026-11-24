import { randomUUID } from "node:crypto"
import { basename } from "node:path"
import { NodeFileSystem } from "@effect/platform-node"
import { ByteSize, Cause, Effect, Exit, Fiber, FileSystem, Option, Schema, Scope, Stream } from "effect"
import { REX_TUNNEL_DIAL_FLAVOR, REX_TUNNEL_LISTEN_FLAVOR, type IRexSdk } from "rex-sdk"
import { makeRexToolOperation, type RexToolOperation, type TargetingEvidence } from "./vendor/rex-tool-operations.ts"
import { encodeRexToolResult } from "./vendor/rex-tool-schemas.ts"
import type { RexToolJson } from "./vendor/rex-tool-schemas.ts"

export interface RexResources {
  readonly operations: readonly RexToolOperation[]
  readonly hasRawStream: (blockId: string) => boolean
  readonly withShared: <A, E>(blockId: string, effect: Effect.Effect<A, E>) => Effect.Effect<A, E | Error>
}

/** The SDK surface used by the resource manager. */
export type RexResourceSdk = {
  ids: Pick<IRexSdk["ids"], "session" | "block">
  terminals: Pick<IRexSdk["terminals"], "stream" | "activity" | "watch" | "download" | "downloadToFile" | "pasteFiles">
  sessions: Pick<IRexSdk["sessions"], "watchView">
  events: Pick<IRexSdk["events"], "stream">
  tunnels: Pick<IRexSdk["tunnels"], "openStream" | "connections" | "forwardLocal" | "forwardRemote">
}

/** Wire-level resource states and kinds, including accepted tunnel streams. */
export const ResourceState = Schema.Literals(["running", "stopping", "ended", "failed", "stopped"])
export const ResourceKind = Schema.Literals([
  "terminals_stream", "terminals_activity", "terminals_watch", "sessions_watchView", "events_stream",
  "terminals_download", "terminals_downloadToFile", "terminals_pasteFileFromPath", "tunnels_openStream",
  "tunnels_connections", "tunnels_forwardLocal", "tunnels_forwardRemote", "tunnels_acceptedStream",
])
/** A possible queued byte-stream item; SDK event items may have other JSON shapes. */
export const ResourceByteItem = Schema.Struct({ base64: Schema.String, byteLength: Schema.Number })
/** A possible queued fragment of an oversized JSON event. */
export const ResourceFragment = Schema.Struct({
  fragment: Schema.String, index: Schema.Number, count: Schema.Number,
  encoding: Schema.Literal("json-utf8-base64"), base64: Schema.String,
})
export const ResourceSummary = Schema.Struct({
  handle: Schema.String, kind: ResourceKind, state: ResourceState, queued: Schema.Number,
})
const RemoteFile = Schema.Struct({
  path: Schema.String, name: Schema.String, size: Schema.Number, modifiedAt: Schema.String,
  version: Schema.NullOr(Schema.String),
})
const ResourceResult = Schema.Union([
  Schema.Struct({ _tag: Schema.Literals(["Download", "NotModified"]), file: RemoteFile }),
  Schema.Struct({ _tag: Schema.Literal("Downloaded"), file: RemoteFile, destination: Schema.String, bytesWritten: Schema.Number }),
  Schema.Struct({ sourcePath: Schema.String, name: Schema.String, size: Schema.Number }),
  Schema.Struct({ blockId: Schema.String, address: Schema.String }),
])
export const ResourceStatus = Schema.Struct({
  ...ResourceSummary.fields, error: Schema.optional(Schema.String), result: Schema.optional(ResourceResult),
})
/** Items can also be heterogeneous SDK event JSON. */
export const ResourcePage = Schema.Struct({ ...ResourceStatus.fields, items: Schema.Array(Schema.Json) })
export type ResourceStatus = typeof ResourceStatus.Type
export type ResourcePage = typeof ResourcePage.Type
export type ResourceSummary = typeof ResourceSummary.Type
type Download = Effect.Success<ReturnType<RexResourceSdk["terminals"]["download"]>>
type DownloadToFile = Effect.Success<ReturnType<RexResourceSdk["terminals"]["downloadToFile"]>>
type Forward = Effect.Success<ReturnType<RexResourceSdk["tunnels"]["forwardLocal"]>>
type ResourceMetadata =
  | { _tag: Download["_tag"]; file: Download["file"] }
  | DownloadToFile
  | { sourcePath: string; name: string; size: number }
  | Pick<Forward, "blockId" | "address">
const targetFields = { sessionId: Schema.String, blockId: Schema.String }
const handleFields = { handle: Schema.String }
const optionalNumber = Schema.optional(Schema.Number)
const optionalString = Schema.optional(Schema.String)
const downloadFields = {
  ...targetFields, path: Schema.String, ifNoneMatch: optionalString,
  stallTimeoutMs: optionalNumber, closeTimeoutMs: optionalNumber,
}
const address = Schema.Struct({ host: optionalString, port: Schema.Number })
const targetAddress = Schema.Struct({ host: Schema.String, port: Schema.Number })
const forwardFields = {
  sessionId: Schema.String, target: targetAddress,
  listen: Schema.optional(address), label: optionalString,
}
const define = <const F extends Schema.Struct.Fields>(name: string, fields: F, description: string, readOnly = false) => ({
  name, fields, description, annotations: { readOnlyHint: readOnly, destructiveHint: false, openWorldHint: false },
  method: undefined, input: undefined,
  output: name === "resources_list" ? Schema.Array(ResourceSummary) : name === "resources_read" ? ResourcePage : ResourceStatus,
})

/** Static descriptors: creating these never opens an SDK connection or requires a binding. */
const descriptors = {
  stream: define("terminals_stream", { ...targetFields, maxResumes: optionalNumber }, "Start a raw terminal output stream."),
  activity: define("terminals_activity", targetFields, "Start a shared terminal activity subscription."),
  watch: define("terminals_watch", { ...targetFields, tailBytes: optionalNumber, settleMs: optionalNumber }, "Watch terminal frames."),
  view: define("sessions_watchView", { sessionId: Schema.String }, "Watch a session view."),
  events: define("events_stream", { sessionIds: Schema.optional(Schema.Array(Schema.String)), server: Schema.optional(Schema.Literals(["none", "session", "all"])) }, "Stream selected Rex events."),
  download: define("terminals_download", downloadFields, "Download a remote terminal file as paged base64 bytes."),
  downloadFile: define("terminals_downloadToFile", { ...downloadFields, destination: Schema.String, overwrite: Schema.Literal(true) }, "Download to a path on the plugin host, replacing the destination after completion. Requires explicit overwrite acknowledgment."),
  paste: define("terminals_pasteFileFromPath", { ...targetFields, sourcePath: Schema.String, name: optionalString }, "Stream a regular file from the OpenCode server host to the terminal. Pasting types its uploaded path into the terminal."),
  open: define("tunnels_openStream", targetFields, "Open a bidirectional tunnel byte stream."),
  connections: define("tunnels_connections", targetFields, "Watch incoming tunnel connections; accept handles expire after 25 seconds."),
  forwardLocal: define("tunnels_forwardLocal", forwardFields, "Start an SDK-managed local TCP forward."),
  forwardRemote: define("tunnels_forwardRemote", forwardFields, "Start an SDK-managed remote TCP forward."),
  list: define("resources_list", {}, "List owned resources.", true),
  status: define("resources_status", handleFields, "Inspect an owned resource.", true),
  read: define("resources_read", { ...handleFields, maxItems: optionalNumber, maxBytes: optionalNumber }, "Read a bounded page. Byte-stream items have base64 and byteLength. Oversized JSON events are ordered fragments sharing a fragment ID; concatenate decoded base64 parts by index, then parse UTF-8 JSON."),
  stop: define("resources_stop", handleFields, "Stop and close an owned resource."),
  write: define("resources_write", { ...handleFields, base64: Schema.String }, "Write base64 bytes to an owned tunnel stream."),
  end: define("resources_end", handleFields, "Half-close the writable side of an owned tunnel stream."),
  accept: define("resources_accept", handleFields, "Accept one unexpired, owned tunnel connection handle."),
}
/** Static descriptors: creating these never opens an SDK connection or requires a binding. */
export const resourceDefinitions = Object.values(descriptors)
export const resourceOperationNames = resourceDefinitions.map((definition) => definition.name)

type State = typeof ResourceState.Type
type Kind = typeof ResourceKind.Type
type ByteStream = Effect.Success<ReturnType<RexResourceSdk["tunnels"]["openStream"]>>
type ResourceError = Error | Cause.UnknownError
  | Stream.Error<ReturnType<RexResourceSdk["terminals"]["stream" | "activity" | "watch"]>>
  | Stream.Error<ReturnType<RexResourceSdk["sessions"]["watchView"]>>
  | Stream.Error<ReturnType<RexResourceSdk["events"]["stream"]>>
  | Stream.Error<ReturnType<RexResourceSdk["tunnels"]["connections"]>>
  | Effect.Error<ReturnType<RexResourceSdk["terminals"]["download" | "downloadToFile" | "pasteFiles"]>>
  | Effect.Error<ReturnType<RexResourceSdk["tunnels"]["openStream" | "forwardLocal" | "forwardRemote"]>>
  | Stream.Error<ByteStream["incoming"]>
type Entry = {
  id: string
  kind: Kind
  blockId?: string
  state: State
  error?: string
  items: { value: RexToolJson; size: number }[]
  bytes: number
  created: number
  finished?: number
  scope: Scope.Closeable
  starter?: Fiber.Fiber<unknown, ResourceError>
  fiber?: Fiber.Fiber<void, never>
  stream?: ByteStream
  result?: typeof ResourceResult.Type
}
type Offer = { owner: string; expires: number; accept: ReturnType<RexResourceSdk["tunnels"]["openStream"]> }
const isStopping = (entry: Entry) => entry.state === "stopping" || entry.state === "stopped"

const MAX_RESOURCES = 32
const MAX_ITEMS = 128
const MAX_BYTES = 1024 * 1024
// This includes a conservative allowance for the response envelope.
const PAGE_BYTES = 45 * 1024
const BYTE_CHUNK = 16 * 1024
const LIFETIME_MS = 15 * 60_000
const RETENTION_MS = 5 * 60_000

export const makeResources = (rex: RexResourceSdk): Effect.Effect<RexResources, never, Scope.Scope> =>
  Effect.gen(function* () {
    const bindingScope = yield* Effect.scope
    const entries = new Map<string, Entry>()
    const offers = new Map<string, Offer>()
    const shared = new Map<string, number>()
    const rawReservations = new Set<string>()
    const hasRawStream = (blockId: string) => rawReservations.has(blockId) || [...entries.values()].some(
      (entry) => entry.blockId === blockId && entry.kind === "terminals_stream" &&
        (entry.state === "running" || entry.state === "stopping"),
    )
    const withShared = <A, E>(blockId: string, effect: Effect.Effect<A, E>): Effect.Effect<A, E | Error> =>
      Effect.acquireUseRelease(
        Effect.try(() => {
          if (hasRawStream(blockId)) throw new Error("Raw terminal stream conflicts with shared terminal operations")
          shared.set(blockId, (shared.get(blockId) ?? 0) + 1)
        }),
        () => effect,
        () => Effect.sync(() => {
          const count = shared.get(blockId) ?? 0
          if (count <= 1) shared.delete(blockId)
          else shared.set(blockId, count - 1)
        }),
      )

    const finish = (entry: Entry, state: "ended" | "failed", error?: string) => {
      if (entry.state !== "running") return
      entry.state = state
      entry.finished = Date.now()
      entry.error = error?.slice(0, 2048)
    }
    const get = (id: string) => {
      const entry = entries.get(id)
      if (!entry) throw new Error("Unknown or expired resource handle")
      return entry
    }
    const info = (entry: Entry) => ({
      handle: entry.id, kind: entry.kind, state: entry.state,
      queued: entry.items.length, error: entry.error, result: entry.result,
    })
    const summary = (entry: Entry) => ({
      handle: entry.id, kind: entry.kind, state: entry.state, queued: entry.items.length,
    })
    const stop = Effect.fn("resources.stop")(function* (entry: Entry) {
      if (entry.state === "running") entry.state = "stopping"
      for (const [id, offer] of offers) if (offer.owner === entry.id) offers.delete(id)
      if (entry.starter) yield* Fiber.interrupt(entry.starter)
      if (entry.fiber) yield* Fiber.interrupt(entry.fiber)
      yield* Scope.close(entry.scope, Exit.void)
      if (entry.state === "stopping") {
        entry.state = "stopped"
        entry.finished = Date.now()
      }
      return info(entry)
    }, Effect.uninterruptible)
    yield* Effect.forkIn(Effect.forever(Effect.gen(function* () {
      yield* Effect.sleep("1 second")
      const now = Date.now()
      for (const [id, offer] of offers) if (now >= offer.expires) offers.delete(id)
      for (const entry of entries.values()) {
        if (entry.state === "running" && now - entry.created >= LIFETIME_MS) yield* stop(entry)
        else if (entry.finished && now - entry.finished >= RETENTION_MS) entries.delete(entry.id)
      }
    })), bindingScope)

    const setResult = (entry: Entry, item: ResourceMetadata) => {
      const value = encodeRexToolResult(item)
      if (Buffer.byteLength(JSON.stringify(value)) > 8192) throw new Error("Resource metadata exceeds 8192 bytes")
      if (!Schema.is(ResourceResult)(value)) throw new Error("Invalid resource metadata")
      entry.result = value
    }
    const enqueue = Effect.fn("resources.enqueue")(function* (entry: Entry, item: unknown, backpressure = false) {
        const value = yield* Effect.try(() => encodeRexToolResult(item))
        const size = Buffer.byteLength(JSON.stringify(value))
        if (size > PAGE_BYTES - 256) {
          const data = Buffer.from(JSON.stringify(value))
          const count = Math.ceil(data.length / BYTE_CHUNK)
          const id = randomUUID()
          const parts = Array.from({ length: count }, (_, index) => ({
            fragment: id, index, count, encoding: "json-utf8-base64",
            base64: data.subarray(index * BYTE_CHUNK, (index + 1) * BYTE_CHUNK).toString("base64"),
          })).map((part) => ({ value: part, size: Buffer.byteLength(JSON.stringify(part)) }))
          const total = parts.reduce((sum, part) => sum + part.size, 0)
          if (count > MAX_ITEMS || total > MAX_BYTES || entry.items.length + count > MAX_ITEMS || entry.bytes + total > MAX_BYTES) {
            return yield* Effect.fail(new Error("Resource buffer overflow; oversized event lost and stream stopped"))
          }
          entry.items.push(...parts)
          entry.bytes += total
          return
        }
        while (entry.items.length >= MAX_ITEMS || entry.bytes + size > MAX_BYTES) {
          if (!backpressure) return yield* Effect.fail(new Error("Resource buffer overflow; triggering event lost and stream stopped"))
          yield* Effect.sleep("20 millis")
        }
        entry.items.push({ value, size })
        entry.bytes += size
      })

    const consumeBytes = (entry: Entry, bytes: Stream.Stream<Uint8Array, ResourceError>) =>
      Stream.runForEach(bytes, (chunk) => Effect.gen(function* () {
        for (let offset = 0; offset < chunk.length; offset += BYTE_CHUNK) {
          const slice = chunk.subarray(offset, offset + BYTE_CHUNK)
          yield* enqueue(entry, { base64: Buffer.from(slice).toString("base64"), byteLength: slice.length }, true)
        }
      }))

    // Acquisition is interruptible; a failed or cancelled start always closes the provisional
    // child scope. The committed worker is attached to the binding, not the calling tool fiber.
    const start = <A>(
      kind: Kind,
      acquire: Effect.Effect<A, ResourceError, Scope.Scope>,
      run: (entry: Entry, value: A) => Effect.Effect<void, ResourceError>,
      blockId?: string,
      prepare?: (entry: Entry, value: A) => void,
    ) => Effect.uninterruptibleMask((restore) => Effect.gen(function* () {
      if (entries.size >= MAX_RESOURCES) return yield* Effect.fail(new Error("Resource limit reached"))
      if (blockId && ["terminals_stream", "terminals_activity", "terminals_watch"].includes(kind)) {
        if (kind === "terminals_stream" && (shared.get(blockId) ?? 0) > 0) {
          return yield* Effect.fail(new Error("Raw terminal stream conflicts with active shared terminal operations"))
        }
        if (rawReservations.has(blockId)) {
          return yield* Effect.fail(new Error("Raw terminal stream is starting for this block"))
        }
        for (const entry of entries.values()) {
          if ((entry.state === "running" || entry.state === "stopping") && entry.blockId === blockId &&
              (kind === "terminals_stream"
                ? ["terminals_stream", "terminals_activity", "terminals_watch"].includes(entry.kind)
                : entry.kind === "terminals_stream")) {
            return yield* Effect.fail(new Error("Raw terminal stream conflicts with active terminal subscriptions"))
          }
        }
      }
      if (blockId && kind === "terminals_stream") rawReservations.add(blockId)
      const child = yield* Scope.fork(bindingScope)
      const starter = yield* Effect.fiber
      const entry: Entry = { id: randomUUID(), kind, blockId, state: "running", items: [], bytes: 0, created: Date.now(), scope: child, starter }
      // Reserve the slot and lease before acquisition, including while acquisition is suspended.
      entries.set(entry.id, entry)
      if (blockId && kind === "terminals_stream") rawReservations.delete(blockId)
      const acquired = yield* Effect.exit(restore(Scope.provide(child)(acquire)))
      if (Exit.isFailure(acquired)) {
        yield* Scope.close(child, acquired)
        if (entry.state === "running") entries.delete(entry.id)
        entry.starter = undefined
        return yield* Effect.failCause(acquired.cause)
      }
      if (entry.state !== "running") {
        yield* Scope.close(child, Exit.void)
        entry.starter = undefined
        return yield* Effect.fail(new Error("Resource stopped during acquisition"))
      }
      if (prepare) {
        const prepared = yield* Effect.exit(Effect.try(() => prepare(entry, acquired.value)))
        if (Exit.isFailure(prepared)) {
          yield* Scope.close(child, prepared)
          entries.delete(entry.id)
          entry.starter = undefined
          return yield* Effect.failCause(prepared.cause)
        }
      }
      const work = run(entry, acquired.value).pipe(
        Effect.ensuring(Scope.close(child, Exit.void)),
        Effect.matchCauseEffect({
          onFailure: (cause) => Effect.sync(() => finish(entry, "failed", String(cause))),
          onSuccess: () => Effect.sync(() => finish(entry, "ended")),
        }),
      )
      entry.fiber = yield* Effect.forkIn(work, bindingScope, { startImmediately: true })
      if (isStopping(entry)) {
        yield* Fiber.interrupt(entry.fiber)
        yield* Scope.close(child, Exit.void)
        entry.starter = undefined
        return yield* Effect.fail(new Error("Resource stopped during startup"))
      }
      entry.starter = undefined
      return info(entry)
    }))

    const streamStart = <A, E extends ResourceError>(kind: Kind, stream: Stream.Stream<A, E>, blockId?: string) =>
      start(kind, Effect.succeed(stream), (entry, value) =>
        Stream.runForEach(value, (item) => enqueue(entry, item)), blockId)
    const target = (p: Schema.Struct<typeof targetFields>["Type"]) => ({
      sessionId: rex.ids.session(p.sessionId), blockId: rex.ids.block(p.blockId),
    })
    const downloadOptions = (p: Schema.Struct<typeof downloadFields>["Type"]) => ({
      ifNoneMatch: p.ifNoneMatch,
      stallTimeout: p.stallTimeoutMs,
      closeTimeout: p.closeTimeoutMs,
    })
    const forwardInput = (p: Schema.Struct<typeof forwardFields>["Type"]) => ({
      sessionId: rex.ids.session(p.sessionId),
      target: p.target,
      listen: p.listen,
      label: p.label,
    })
    const byteStart = (kind: Kind, acquire: Effect.Effect<ByteStream, ResourceError, Scope.Scope>) =>
      start(kind, acquire, (entry, stream) => Effect.gen(function* () {
        yield* consumeBytes(entry, stream.incoming)
        yield* stream.done
      }), undefined, (entry, stream) => { entry.stream = stream })

    type RequestOptions = Parameters<RexToolOperation["program"]>[2]
    const pasteFile = (entry: Entry, p: Schema.Struct<typeof descriptors.paste.fields>["Type"], options: RequestOptions) =>
      Effect.scoped(Effect.gen(function* () {
        const fs = yield* FileSystem.FileSystem
        const sourcePath = p.sourcePath
        const name = p.name === undefined ? basename(sourcePath) : p.name
        if (!sourcePath || !name) return yield* Effect.fail(new Error("A source path and file name are required"))
        // Check before opening so a directory or FIFO cannot block an open; stat the
        // opened descriptor again so the size belongs to the file actually streamed.
        const before = yield* fs.stat(sourcePath)
        if (before.type !== "File") return yield* Effect.fail(new Error("Source must be a regular file"))
        const file = yield* fs.open(sourcePath, { flag: "r" })
        const stat = yield* file.stat
        if (stat.type !== "File") return yield* Effect.fail(new Error("Source must be a regular file"))
        const sizeOption = ByteSize.toNumber(stat.size)
        if (Option.isNone(sizeOption) || !Number.isSafeInteger(sizeOption.value)) {
          return yield* Effect.fail(new Error("Source file is too large to represent its exact size"))
        }
        const size = sizeOption.value
        const stream = Stream.unfold(0, () => file.readAlloc(64 * 1024).pipe(
          Effect.map((chunk) => Option.isSome(chunk) ? [chunk.value, 0] as const : undefined),
        ))
        yield* rex.terminals.pasteFiles(target(p), [{ name, size, stream }], options)
        yield* Effect.try(() => setResult(entry, { sourcePath, name, size }))
      })).pipe(Effect.provide(NodeFileSystem.layer))
    const enqueueOffer = Effect.fn("resources.enqueueOffer")(function* (
      entry: Entry, connection: Stream.Success<ReturnType<RexResourceSdk["tunnels"]["connections"]>>,
    ) {
      if (offers.size >= MAX_ITEMS) return yield* Effect.fail(new Error("Connection offer limit reached; incoming connection lost"))
      const handle = randomUUID()
      offers.set(handle, { owner: entry.id, expires: Date.now() + 25_000, accept: connection.accept })
      yield* enqueue(entry, { handle, peer: connection.peer }).pipe(Effect.onError(() => Effect.sync(() => { offers.delete(handle) })))
    })
    const readPage = (p: Schema.Struct<typeof descriptors.read.fields>["Type"]) => Effect.try(() => {
      const entry = get(p.handle)
      const limit = Math.min(PAGE_BYTES, Math.max(1, Math.floor(p.maxBytes ?? PAGE_BYTES)))
      const count = Math.min(MAX_ITEMS, Math.max(1, Math.floor(p.maxItems ?? MAX_ITEMS)))
      if (!Number.isFinite(limit) || !Number.isFinite(count)) throw new Error("Invalid page limit")
      const items: RexToolJson[] = []
      let bytes = 2
      while (entry.items.length && items.length < count) {
        const next = entry.items[0]!
        if (bytes + next.size + 1 > limit) {
          if (!items.length) throw new Error(`Next item requires at least ${next.size + 3} bytes; increase maxBytes`)
          break
        }
        entry.items.shift()
        entry.bytes -= next.size
        bytes += next.size + 1
        items.push(next.value)
      }
      return { ...info(entry), items }
    })
    function operation<F extends Schema.Struct.Fields, A, E>(
      descriptor: { name: string; description: string; fields: F; output: Schema.Top; annotations: { readOnlyHint: boolean; destructiveHint: boolean } },
      targeting: (p: Schema.Struct<F>["Type"]) => TargetingEvidence,
      run: (p: Schema.Struct<F>["Type"], options: RequestOptions) => Effect.Effect<A, E>,
    ) {
      return makeRexToolOperation({
        name: descriptor.name, description: descriptor.description, fields: descriptor.fields,
        output: descriptor.output, readOnly: descriptor.annotations.readOnlyHint,
        destructive: descriptor.annotations.destructiveHint,
        targeting,
        run: (_sdk, params, options) => run(params, options),
      })
    }
    const operations: RexToolOperation[] = [
      operation(descriptors.stream, (p) => ({ blockId: p.blockId }), (p) => streamStart("terminals_stream", rex.terminals.stream(target(p), { maxResumes: p.maxResumes }), p.blockId)),
      operation(descriptors.activity, (p) => ({ blockId: p.blockId }), (p) => streamStart("terminals_activity", rex.terminals.activity(target(p)), p.blockId)),
      operation(descriptors.watch, (p) => ({ blockId: p.blockId }), (p) => streamStart("terminals_watch", rex.terminals.watch(target(p), { tailBytes: p.tailBytes, settle: p.settleMs }), p.blockId)),
      operation(descriptors.view, () => ({}), (p) => streamStart("sessions_watchView", rex.sessions.watchView(rex.ids.session(p.sessionId)))),
      operation(descriptors.events, (p) => p.server === undefined ? {} : { server: p.server }, (p) => streamStart("events_stream", rex.events.stream({
        sessionIds: p.sessionIds?.map(rex.ids.session),
        server: p.server,
      }))),
      operation(descriptors.download, (p) => ({ blockId: p.blockId }), (p, options) => start("terminals_download", rex.terminals.download(target(p), p.path, downloadOptions(p), options), (entry, download) => Effect.gen(function* () {
        if (download._tag === "Download") yield* consumeBytes(entry, download.bytes)
      }), undefined, (entry, download) => setResult(entry, { _tag: download._tag, file: download.file }))),
      operation(descriptors.downloadFile, (p) => ({ blockId: p.blockId, destination: p.destination }), (p, options) => {
        if (p.overwrite !== true) return Effect.fail(new Error("Explicit overwrite acknowledgment required"))
        return start("terminals_downloadToFile", Effect.succeed(undefined), (entry) =>
          rex.terminals.downloadToFile(target(p), p.path, p.destination, downloadOptions(p), options).pipe(
            Effect.provide(NodeFileSystem.layer),
            Effect.tap((result) => Effect.try(() => setResult(entry, result))),
            Effect.asVoid,
          ))
      }),
      operation(descriptors.paste, (p) => ({ blockId: p.blockId, sourcePath: p.sourcePath }), (p, options) => start("terminals_pasteFileFromPath", Effect.succeed(undefined), (entry) => pasteFile(entry, p, options))),
      operation(descriptors.open, (p) => ({ blockId: p.blockId }), (p, options) => byteStart("tunnels_openStream", rex.tunnels.openStream(target(p), options))),
      operation(descriptors.connections, (p) => ({ blockId: p.blockId }), (p) => start("tunnels_connections", Effect.succeed(rex.tunnels.connections(target(p))), (entry, stream) =>
        Stream.runForEach(stream, (connection) => enqueueOffer(entry, connection)))),
      operation(descriptors.forwardLocal, () => ({ creatorFlavors: [REX_TUNNEL_DIAL_FLAVOR] }), (p) => start("tunnels_forwardLocal", rex.tunnels.forwardLocal(forwardInput(p)),
        (_entry, forward) => forward.stopped, undefined,
        (entry, forward) => setResult(entry, { blockId: forward.blockId, address: forward.address }))),
      operation(descriptors.forwardRemote, () => ({ creatorFlavors: [REX_TUNNEL_LISTEN_FLAVOR] }), (p) => start("tunnels_forwardRemote", rex.tunnels.forwardRemote(forwardInput(p)),
        (_entry, forward) => forward.stopped, undefined,
        (entry, forward) => setResult(entry, { blockId: forward.blockId, address: forward.address }))),
      operation(descriptors.list, () => ({}), () => Effect.sync(() => [...entries.values()].map(summary))),
      operation(descriptors.status, (p) => ({ handle: p.handle }), (p) => Effect.try(() => info(get(p.handle)))),
      operation(descriptors.read, (p) => p.maxBytes === undefined ? { handle: p.handle } : { handle: p.handle, maxBytes: p.maxBytes }, readPage),
      operation(descriptors.stop, (p) => ({ handle: p.handle }), (p) => Effect.try(() => get(p.handle)).pipe(Effect.flatMap(stop))),
      operation(descriptors.write, (p) => ({ handle: p.handle }), (p) => Effect.gen(function* () {
        const entry = yield* Effect.try(() => get(p.handle))
        if (entry.state !== "running" || !entry.stream) return yield* Effect.fail(new Error("Not an active writable tunnel stream"))
        const text = p.base64
        if (text.length > 64 * 1024 || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(text)) {
          return yield* Effect.fail(new Error("Invalid or oversized base64 data"))
        }
        yield* entry.stream.write(Buffer.from(text, "base64"))
        return info(entry)
      })),
      operation(descriptors.end, (p) => ({ handle: p.handle }), (p) => Effect.gen(function* () {
        const entry = yield* Effect.try(() => get(p.handle))
        if (entry.state !== "running" || !entry.stream) return yield* Effect.fail(new Error("Not an active writable tunnel stream"))
        yield* entry.stream.end
        return info(entry)
      })),
      operation(descriptors.accept, (p) => ({ handle: p.handle }), (p) => Effect.suspend(() => {
        const handle = p.handle
        const offer = offers.get(handle)
        offers.delete(handle)
        if (!offer || Date.now() >= offer.expires || entries.get(offer.owner)?.state !== "running") {
          return Effect.fail(new Error("Unknown, expired, or already accepted connection handle"))
        }
        return byteStart("tunnels_acceptedStream", offer.accept)
      })),
    ]
    return {
      operations,
      hasRawStream,
      withShared,
    }
  })
