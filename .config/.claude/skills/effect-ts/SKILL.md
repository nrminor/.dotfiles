---
name: effect-ts
description: Write TypeScript with the Effect V4 library. Covers the core Effect type, generator syntax (Effect.gen/Effect.fn), typed errors, services and dependency injection via ServiceMap/Layer, resource management, streams, HTTP client/server, CLI, child processes, testing, observability, AI modules, and cluster. Use when writing or reviewing Effect code, migrating vanilla TypeScript to Effect, or when you need to understand Effect's service/layer/error model.
---

# Effect V4 for TypeScript

Effect is a TypeScript library that replaces ad-hoc patterns for error handling,
dependency injection, concurrency, resource management, and observability with a
single composable system. The core type `Effect<A, E, R>` tracks success (`A`),
typed errors (`E`), and required dependencies (`R`) at the type level.

This skill covers Effect V4, which introduces `ServiceMap.Service` (replacing
the older `Context.Tag` pattern), `Effect.fn` (replacing functions that return
`Effect.gen`), and several new modules under `effect/unstable/*`.

## Detailed references

For HTTP, streams, testing, and auxiliary modules:

- **HTTP**: See [references/http.md](references/http.md) — HttpClient, HttpApi server, generated typed client, middleware
- **Streams**: See [references/streams.md](references/streams.md) — creating, transforming, consuming, Ndjson/Msgpack encoding
- **Testing**: See [references/testing.md](references/testing.md) — @effect/vitest, shared layer tests, test clock, property tests
- **Auxiliary modules**: See [references/auxiliary-modules.md](references/auxiliary-modules.md) — CLI, child processes, schedules, PubSub, AI modules, cluster

## Why Effect over vanilla TypeScript

**Errors are untyped.** `throw` puts values into a black hole that
`catch(e: unknown)` can't inspect without runtime checks. Effect's `E` type
parameter makes the error channel visible to the compiler — errors compose
through generators automatically, and `catchTag`/`catchTags` give you
exhaustive pattern matching.

**Dependency injection is either heavy or manual.** Decorator-based DI
(inversify, tsyringe) requires runtime reflection. Manual constructor injection
gets tedious. Effect's `R` type parameter tracks dependencies at compile time —
`yield*` a service and the compiler adds it to `R`; `Layer.provide` removes it.

**Resource cleanup is fragile.** `try/finally` doesn't compose across async
boundaries or service boundaries. Effect's `Scope` system ties resource
lifetimes to layers — `acquireRelease` guarantees cleanup even under
interruption.

**Retry, timeout, concurrency are reimplemented everywhere.** Effect provides
composable `Schedule` primitives, `Effect.timeout`, and concurrency control on
every operator that needs it.

## Effect.gen — imperative-style Effect code

`Effect.gen` uses generator functions with `yield*` to unwrap effects, similar
to `async/await` for Promises but with typed errors and dependencies.

```ts
import { Effect, Schema } from "effect"

Effect.gen(function*() {
  yield* Effect.log("Starting...")
  const data = yield* loadData()

  // Always `return yield*` when raising an error — this tells TypeScript
  // the function won't continue past this point.
  if (!data.valid) {
    return yield* new ValidationError({ message: "bad data" })
  }

  return data.value
}).pipe(
  // Attach cross-cutting concerns with .pipe after the gen block
  Effect.catch((error) => Effect.succeed("fallback")),
  Effect.withSpan("processData")
)
```

## Effect.fn — named functions that return Effects

When writing a function that returns an Effect, use `Effect.fn` instead of a
function that returns `Effect.gen`. `Effect.fn` attaches a tracing span
automatically and improves stack traces.

```ts
// The name string should match the function name.
export const processOrder = Effect.fn("processOrder")(
  function*(orderId: string): Effect.fn.Return<Receipt, OrderError> {
    yield* Effect.logInfo("Processing order", orderId)
    const order = yield* fetchOrder(orderId)
    return yield* chargeCard(order)
  },
  // Trailing combinators are preferred — co-locates operational behavior
  // at the definition site. But .pipe() also works.
  Effect.retry(Schedule.exponential("200 millis")),
  Effect.annotateLogs({ module: "orders" })
)
```

## Creating effects from common sources

```ts
// Value you already have
Effect.succeed({ env: "prod" })

// Synchronous side effect (should not throw)
Effect.sync(() => Date.now())

// Synchronous code that may throw
Effect.try({
  try: () => JSON.parse(input),
  catch: (cause) => new ParseError({ input, cause })
})

// Promise-based API
Effect.tryPromise({
  try: () => fetch(url).then((r) => r.json()),
  catch: (cause) => new FetchError({ url, cause })
})

// Nullable/optional values
Effect.fromNullishOr(map.get("key")).pipe(
  Effect.mapError(() => new MissingKeyError())
)

// Callback-based API with cleanup
Effect.callback<number>((resume) => {
  const id = setTimeout(() => resume(Effect.succeed(42)), 100)
  return Effect.sync(() => clearTimeout(id))  // finalizer for interruption
})
```

## Errors

### Defining errors

All custom errors should use `Schema.TaggedErrorClass`. This gives you a
discriminated union with a `_tag` field and integration with `catchTag`.

```ts
export class ParseError extends Schema.TaggedErrorClass<ParseError>()(
  "ParseError",
  { input: Schema.String, message: Schema.String }
) {}

// For wrapping unknown thrown values
export class NetworkError extends Schema.TaggedErrorClass<NetworkError>()(
  "NetworkError",
  { statusCode: Schema.Number, cause: Schema.Defect }
) {}

// Non-tagged variant (when you don't need catchTag matching)
export class SmtpError extends Schema.ErrorClass<SmtpError>("SmtpError")({
  cause: Schema.Defect
}) {}

// With HTTP status code for HttpApi
export class UserNotFound extends Schema.TaggedErrorClass<UserNotFound>()(
  "UserNotFound", {}, { httpApiStatus: 404 }
) {}
```

### Catching errors

```ts
// Catch all errors
effect.pipe(Effect.catch((_) => Effect.succeed("fallback")))

// Catch by tag — single or multiple
effect.pipe(Effect.catchTag("ParseError", (e) => ...))
effect.pipe(Effect.catchTag(["ParseError", "NetworkError"], (e) => ...))

// Per-tag handlers (exhaustive)
effect.pipe(Effect.catchTags({
  ParseError: (e) => Effect.succeed(`parse: ${e.message}`),
  NetworkError: (e) => Effect.succeed(`network: ${e.statusCode}`)
}))
```

### Reason errors — nested error hierarchies

When a service wraps another service's errors, use a `reason` field:

```ts
export class AiError extends Schema.TaggedErrorClass<AiError>()("AiError", {
  reason: Schema.Union([RateLimitError, QuotaExceededError, SafetyBlockedError])
}) {}

// Handle one specific reason
effect.pipe(Effect.catchReason("AiError", "RateLimitError",
  (reason) => Effect.succeed(`retry after ${reason.retryAfter}s`),
  (reason) => Effect.succeed(`unhandled: ${reason._tag}`)  // optional catch-all
))

// Handle multiple reasons
effect.pipe(Effect.catchReasons("AiError", {
  RateLimitError: (r) => Effect.succeed(`retry after ${r.retryAfter}s`),
  QuotaExceededError: (r) => Effect.succeed(`quota: ${r.limit}`)
}))

// Flatten reasons into the error channel, then use normal catchTags
effect.pipe(
  Effect.unwrapReason("AiError"),
  Effect.catchTags({
    RateLimitError: ...,
    QuotaExceededError: ...,
    SafetyBlockedError: ...
  })
)
```

## Services and dependency injection

### ServiceMap.Service

The V4 way to define a service. Replaces the older `Context.Tag` pattern.

```ts
import { Effect, Layer, Schema, ServiceMap } from "effect"

export class Database extends ServiceMap.Service<Database, {
  query(sql: string): Effect.Effect<Array<unknown>, DatabaseError>
}>()(
  "myapp/db/Database"  // namespaced identifier
) {
  static readonly layer = Layer.effect(
    Database,
    Effect.gen(function*() {
      const query = Effect.fn("Database.query")(function*(sql: string) {
        yield* Effect.log("Executing:", sql)
        return [{ id: 1, name: "Alice" }]
      })
      return Database.of({ query })  // .of() enforces the interface
    })
  )
}
```

The class is never instantiated with `new`. It serves as a type, a tag, a
namespace for layers, and a factory via `.of()`. Consume it by yielding:

```ts
Effect.gen(function*() {
  const db = yield* Database
  const rows = yield* db.query("SELECT * FROM users")
})
```

### ServiceMap.Reference — config and feature flags

```ts
export const FeatureFlag = ServiceMap.Reference<boolean>("myapp/FeatureFlag", {
  defaultValue: () => false
})
```

### Layer composition

```ts
// Layer.provide — satisfy a dependency, hide it from consumers
static readonly layer = this.layerNoDeps.pipe(Layer.provide(Database.layer))
// Result: Layer<UserRepository>  (Database is hidden)

// Layer.provideMerge — satisfy and expose both
static readonly layerWithDb = this.layerNoDeps.pipe(
  Layer.provideMerge(Database.layer)
)
// Result: Layer<UserRepository | Database>

// Layer.mergeAll — combine independent layers
const AppLayer = Layer.mergeAll(HttpServerLayer, WorkerLayer, MetricsLayer)
```

The standard pattern for services with dependencies:

```ts
export class UserRepository extends ServiceMap.Service<UserRepository, {
  findById(id: string): Effect.Effect<Option.Option<User>, UserRepoError>
}>()(
  "myapp/UserRepository"
) {
  // Raw implementation — dependency on SqlClient visible in R
  static readonly layerNoDeps: Layer.Layer<
    UserRepository, never, SqlClient.SqlClient
  > = Layer.effect(UserRepository, Effect.gen(function*() {
    const sql = yield* SqlClient.SqlClient
    const findById = Effect.fn("UserRepository.findById")(function*(id) {
      const results = yield* sql`SELECT * FROM users WHERE id = '${id}'`
      return Array.head(results)
    })
    return UserRepository.of({ findById })
  }))

  // Wired — hides SqlClient
  static readonly layer = this.layerNoDeps.pipe(Layer.provide(SqlClientLayer))
}
```

### Layer.unwrap — dynamic layer selection

```ts
static readonly layer = Layer.unwrap(Effect.gen(function*() {
  const useInMemory = yield* Config.boolean("IN_MEMORY").pipe(
    Config.withDefault(false)
  )
  return useInMemory
    ? MessageStore.layerInMemory
    : MessageStore.layerRemote(yield* Config.url("STORE_URL"))
}))
```

## Resource management

### Effect.acquireRelease

```ts
const transporter = yield* Effect.acquireRelease(
  Effect.sync(() => createTransport(config)),   // acquire
  (t) => Effect.sync(() => t.close())           // release (guaranteed)
)
```

When used inside `Layer.effect`, the resource lives as long as the layer.

### Effect.addFinalizer

```ts
const pubsub = yield* PubSub.bounded<Event>({ capacity: 256 })
yield* Effect.addFinalizer(() => PubSub.shutdown(pubsub))
```

### Background tasks with forkScoped

```ts
const BackgroundWorker = Layer.effectDiscard(Effect.gen(function*() {
  yield* Effect.gen(function*() {
    while (true) {
      yield* Effect.sleep("5 seconds")
      yield* Effect.logInfo("tick")
    }
  }).pipe(
    Effect.onInterrupt(() => Effect.logInfo("worker stopped")),
    Effect.forkScoped  // fiber lifetime tied to layer scope
  )
}))
```

### LayerMap.Service — dynamic keyed resource pools

```ts
export class PoolMap extends LayerMap.Service<PoolMap>()("app/PoolMap", {
  lookup: (tenantId: string) => DatabasePool.layer(tenantId),
  idleTimeToLive: "1 minute"
}) {}

// Consumer doesn't know about multi-tenancy
const pool = yield* DatabasePool
yield* pool.query("SELECT * FROM users")

// Caller provides tenant context
yield* myEffect.pipe(Effect.provide(PoolMap.get("acme")))
yield* PoolMap.invalidate("acme")  // force rebuild on next access
```

## Running programs

```ts
import { NodeRuntime } from "@effect/platform-node"

// One-shot program
NodeRuntime.runMain(myEffect)

// Long-running service
Layer.launch(AppLayer).pipe(NodeRuntime.runMain)
```

`runMain` installs SIGINT/SIGTERM handlers and interrupts fibers for graceful
shutdown. Every `acquireRelease`, `forkScoped`, and `addFinalizer` runs.

### ManagedRuntime — bridging into existing frameworks

```ts
const runtime = ManagedRuntime.make(TodoRepo.layer, {
  memoMap: Layer.makeMemoMapUnsafe()
})

app.get("/todos", async (c) => {
  const todos = await runtime.runPromise(
    TodoRepo.use((repo) => repo.getAll)
  )
  return c.json(todos)
})

process.once("SIGINT", () => void runtime.dispose())
```

## Observability

### Logging

```ts
import { Config, Effect, Layer, Logger, References } from "effect"

Logger.layer([Logger.consoleJson])                          // JSON logger
Layer.succeed(References.MinimumLogLevel, "Warn")           // log level
Logger.layer([Logger.toFile(Logger.formatSimple, "app.log")])  // file logger

// Environment-based selection
Layer.unwrap(Effect.gen(function*() {
  const env = yield* Config.string("NODE_ENV").pipe(Config.withDefault("dev"))
  return env === "production"
    ? Logger.layer([appLogger])
    : Logger.layer([Logger.defaultLogger])
}))

// Structured metadata
myEffect.pipe(
  Effect.annotateLogs({ service: "checkout" }),
  Effect.withLogSpan("checkout")
)
```

### Tracing

```ts
import { OtlpTracer, OtlpLogger, OtlpSerialization } from "effect/unstable/observability"

const ObservabilityLayer = Layer.merge(
  OtlpTracer.layer({ url: "http://localhost:4318/v1/traces", resource: { ... } }),
  OtlpLogger.layer({ url: "http://localhost:4318/v1/logs", resource: { ... } })
).pipe(
  Layer.provide(OtlpSerialization.layerJson),
  Layer.provide(FetchHttpClient.layer)
)

// Provide at outermost layer — everything inside gets traced
const Main = AppLayer.pipe(Layer.provide(ObservabilityLayer))
```

Spans are added automatically by `Effect.fn("name")`. Add more with
`Effect.withSpan`, `Effect.annotateSpans`, and `Layer.withSpan`.

## Schema quick reference

```ts
import { Schema } from "effect"

// Domain classes
class User extends Schema.Class<User>("User")({
  id: Schema.Number, name: Schema.String
}) {}

// Branded types
const UserId = Schema.Int.pipe(Schema.brand("UserId"))
type UserId = typeof UserId.Type

// Literals
Schema.Literals(["info", "warn", "error"])

// Transformations
Schema.FiniteFromString.pipe(Schema.decodeTo(UserId))
Schema.DateTimeUtcFromString

// Decoding
Schema.decodeUnknownSync(User)({ id: 1, name: "Alice" })

// Annotations (AI tools, OpenAPI)
Schema.String.annotate({ description: "The search query" })
```

## Import paths

```ts
// Core — most modules live here
import { Effect, Layer, Schema, ServiceMap, Stream, PubSub, ... } from "effect"

// Unstable modules (newer APIs, may change)
import { FetchHttpClient, HttpClient, HttpRouter } from "effect/unstable/http"
import { HttpApiBuilder, HttpApiClient } from "effect/unstable/httpapi"
import { Ndjson, Msgpack } from "effect/unstable/encoding"
import { OtlpTracer, OtlpLogger } from "effect/unstable/observability"
import { ChildProcess, ChildProcessSpawner } from "effect/unstable/process"
import { Argument, Command, Flag } from "effect/unstable/cli"
import { LanguageModel, Tool, Toolkit, Chat } from "effect/unstable/ai"
import { SqlClient } from "effect/unstable/sql"
import { Entity, Rpc } from "effect/unstable/cluster"

// Platform-specific
import { NodeRuntime, NodeHttpServer, NodeServices } from "@effect/platform-node"
import { BunRuntime } from "@effect/platform-bun"

// AI providers
import { AnthropicClient, AnthropicLanguageModel } from "@effect/ai-anthropic"
import { OpenAiClient, OpenAiLanguageModel } from "@effect/ai-openai"
```
