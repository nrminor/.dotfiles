import { ConfigProvider, Context, Effect, Exit, Layer, Option, Predicate, Schema, Scope } from "effect"
import { RexSdk, SessionId, rexSdkLayerFromOptions } from "rex-sdk"
import type { Selection } from "./policy.ts"
import { makeResources, type RexResources } from "./resources.ts"
import { makeRequests } from "./requests.ts"
import { RexMarkStore } from "./vendor/rex-tool-marks.ts"

/** Explicit connection and execution-host selection accepted by `/rex-target`. */
export const Target = Schema.Struct({
  server: Schema.String.check(Schema.isMinLength(1)),
  sessionId: SessionId,
  blockId: Schema.optionalKey(Schema.String.check(Schema.isMinLength(1))),
  hostId: Schema.String.check(Schema.isMinLength(1)),
})

/** A missing, invalid, superseded, or closed session binding. */
export class BindingError extends Schema.TaggedError<BindingError>()("Rex.BindingError", {
  message: Schema.String,
}) {}

type ManagedRequests = Effect.Success<ReturnType<typeof makeRequests>>

/** One OpenCode session's connection, terminal marks, and scoped resource managers. */
export interface Binding {
  readonly selection: Selection
  readonly scope: Scope.Closeable
  readonly sdk: RexSdk["Service"]
  readonly marks: RexMarkStore
  readonly resources: RexResources & Pick<ManagedRequests, "reply">
}

/** Connects to the explicit endpoint without taking a target from ambient configuration. */
export const sdkLayer = (server: string) => rexSdkLayerFromOptions({
  server,
  client: { kind: "agent", name: "opencode-rex", version: "0.1.0" },
}).pipe(Layer.provide(ConfigProvider.layer(ConfigProvider.fromUnknown({}))))

/** Connections and grants belong to an OpenCode session, never to its directory. */
export const makeBindings = Effect.fn("Rex.makeBindings")(function* <Failure>(
  layer: (server: string) => Layer.Layer<RexSdk, Failure>,
) {
  const root = yield* Effect.scope
  const bindings = new Map<string, Binding>()
  const generations = new Map<string, object>()
  let closed = false

  yield* Effect.addFinalizer(() => Effect.sync(() => {
    closed = true
    bindings.clear()
    generations.clear()
  }))

  const clear = Effect.fn("Rex.clearTarget")(function* (owner: string) {
    const generation = {}
    generations.set(owner, generation)
    const previous = bindings.get(owner)
    bindings.delete(owner)
    if (previous) yield* Scope.close(previous.scope, Exit.void)
    return generation
  })

  const select = Effect.fn("Rex.selectTarget")(function* (owner: string, target: typeof Target.Type) {
    if (closed) return yield* new BindingError({ message: "Rex plugin has been unloaded." })
    const generation = yield* clear(owner)
    if (closed || generations.get(owner) !== generation)
      return yield* new BindingError({ message: "Target selection was superseded." })
    const scope = yield* Scope.fork(root, "sequential")
    let committed = false
    return yield* Effect.gen(function* () {
      const context = yield* Layer.buildWithScope(layer(target.server), scope)
      const sdk = Context.get(context, RexSdk)
      const status = yield* sdk.server.status()
      const view = yield* sdk.sessions.view({ sessionId: target.sessionId })
      const listed = yield* sdk.sessions.listBlocks({ sessionId: target.sessionId })
      if (view.sessionId !== target.sessionId)
        return yield* new BindingError({ message: "Rex returned a different session." })
      const block = listed.blocks.find((item) => item.blockId === target.blockId)
      if (target.blockId && (!block || Option.getOrNull(block.hostId) !== target.hostId))
        return yield* new BindingError({ message: "The selected pane is absent or belongs to another execution host." })
      const hosts = new Set([Option.getOrNull(status.hostId), ...listed.blocks.map((item) => Option.getOrNull(item.hostId))])
      if (!hosts.has(target.hostId)) {
        const creators = yield* sdk.creators.list()
        if (!creators.creators.some((creator) => Option.getOrNull(creator.hostId) === target.hostId))
          return yield* new BindingError({ message: "The selected execution host is not advertised by this Rex server." })
      }
      const resources = yield* Scope.provide(scope)(makeResources(sdk))
      const requests = yield* Scope.provide(scope)(makeRequests(sdk))
      if (closed || generations.get(owner) !== generation)
        return yield* new BindingError({ message: "Target selection was superseded." })
      const binding: Binding = {
        scope, sdk,
        resources: {
          ...resources,
          operations: [...resources.operations, ...requests.operations],
          reply: requests.reply,
        },
        marks: new RexMarkStore(),
        selection: {
          server: target.server, sessionId: target.sessionId, hostId: target.hostId,
          blockId: target.blockId ?? null, instanceId: status.instanceId, owned: new Set(),
        },
      }
      bindings.set(owner, binding)
      committed = true
      return binding
    }).pipe(
      Effect.timeout("30 seconds"),
      Effect.ensuring(Effect.suspend(() => committed ? Effect.void : Scope.close(scope, Exit.void))),
    )
  })

  const get = (owner: string) => {
    const binding = bindings.get(owner)
    return !closed && binding
      ? Effect.succeed(binding)
      : Effect.fail(new BindingError({ message: "Select an explicit Rex target with /rex-target first." }))
  }
  const current = (owner: string, binding: Binding) =>
    !closed && bindings.get(owner) === binding && !Predicate.isTagged(binding.scope.state, "Closed")

  return { get, select, clear, current }
})
