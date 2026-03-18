# Effect Auxiliary Modules

## CLI applications

Build typed command-line apps with `effect/unstable/cli`. Flags produce literal
union types, subcommands can access parent flags via `yield*`, and help text is
declarative.

```ts
import { Console, Effect } from "effect"
import { Argument, Command, Flag } from "effect/unstable/cli"
import { NodeRuntime, NodeServices } from "@effect/platform-node"

// Reusable flags
const workspace = Flag.string("workspace").pipe(
  Flag.withAlias("w"),
  Flag.withDescription("Workspace to operate on"),
  Flag.withDefault("personal")
)

// Root command with shared flags
const tasks = Command.make("tasks").pipe(
  Command.withSharedFlags({
    workspace,
    verbose: Flag.boolean("verbose").pipe(Flag.withAlias("v"))
  }),
  Command.withDescription("Track and manage tasks")
)

// Subcommand — handler is an Effect.fn
const create = Command.make(
  "create",
  {
    title: Argument.string("title").pipe(
      Argument.withDescription("Task title")
    ),
    // Flag.choice gives you a literal union type, not just string
    priority: Flag.choice("priority", ["low", "normal", "high"]).pipe(
      Flag.withDescription("Priority for the new task"),
      Flag.withDefault("normal")
    )
  },
  Effect.fn(function*({ title, priority }) {
    // Access parent command's parsed flags — fully typed
    const root = yield* tasks
    if (root.verbose) {
      yield* Console.log(`workspace=${root.workspace} action=create`)
    }
    yield* Console.log(`Created "${title}" in ${root.workspace} [${priority}]`)
  })
).pipe(
  Command.withDescription("Create a task"),
  Command.withExamples([{
    command: 'tasks create "Ship 4.0" --priority high',
    description: "Create a high-priority task"
  }])
)

const list = Command.make(
  "list",
  {
    status: Flag.choice("status", ["open", "done", "all"]).pipe(
      Flag.withDefault("open")
    ),
    json: Flag.boolean("json")
  },
  Effect.fn(function*({ status, json }) {
    const root = yield* tasks
    // ... handler logic
  })
).pipe(
  Command.withDescription("List tasks"),
  Command.withAlias("ls")
)

// Compose and run
tasks.pipe(
  Command.withSubcommands([create, list]),
  Command.run({ version: "1.0.0" }),
  Effect.provide(NodeServices.layer),
  NodeRuntime.runMain
)
```

## Child processes

Use `effect/unstable/process` for structured child process management with
typed errors, stream output, process pipelines, and scoped lifecycle.

```ts
import { Console, Effect, Stream } from "effect"
import { ChildProcess, ChildProcessSpawner } from "effect/unstable/process"
import { NodeServices } from "@effect/platform-node"

// ChildProcessSpawner comes from NodeServices.layer
const spawner = yield* ChildProcessSpawner.ChildProcessSpawner

// Collect entire output as a string
const version = yield* spawner.string(
  ChildProcess.make("node", ["--version"])
).pipe(Effect.map(String.trim))

// Collect as lines
const files = yield* spawner.lines(
  ChildProcess.make("git", ["diff", "--name-only", "main...HEAD"])
)

// Pipe processes together — like shell pipes
const subjects = yield* spawner.lines(
  ChildProcess.make("git", ["log", "--pretty=format:%s", "-n", "20"]).pipe(
    ChildProcess.pipeTo(ChildProcess.make("head", ["-n", "5"]))
  )
)

// Stream long-running output with lifecycle management
const handle = yield* spawner.spawn(
  ChildProcess.make("pnpm", ["lint-fix"], {
    env: { FORCE_COLOR: "1" },
    extendEnv: true
  })
)
yield* handle.all.pipe(          // interleaved stdout+stderr as Stream
  Stream.decodeText(),
  Stream.splitLines,
  Stream.runForEach((line) => Console.log(`[lint] ${line}`))
)
const exitCode = yield* handle.exitCode
// Use Effect.scoped to ensure the process is killed when the scope closes
```

`ChildProcess.pipeTo` composes processes like shell pipes — stdout of one
connects to stdin of the next, with error handling and cleanup on both.
`spawner.spawn` returns a scoped handle — wrap with `Effect.scoped` to
guarantee cleanup.

## Schedules — composable retry and repeat policies

```ts
import { Duration, Effect, Schedule } from "effect"

// Primitives
Schedule.recurs(5)                    // max 5 attempts
Schedule.spaced("30 seconds")        // fixed delay
Schedule.exponential("200 millis")   // exponential backoff

// Composition
Schedule.both(a, b)    // intersection — both must continue
Schedule.either(a, b)  // union — either continues

// Production retry: capped exponential with jitter, conditional on error
const retryPolicy = Schedule.exponential("250 millis").pipe(
  Schedule.either(Schedule.spaced("10 seconds")),  // cap delay at 10s
  Schedule.jittered,                                 // add randomness
  Schedule.setInputType<HttpError>(),
  Schedule.while(({ input }) => input.retryable)     // conditional on error
)

fetchUser("123").pipe(Effect.retry(retryPolicy))

// Builder form — infers error type automatically
fetchUser("123").pipe(
  Effect.retry(($) =>
    $(Schedule.spaced("1 second")).pipe(
      Schedule.while(({ input }) => input.retryable)
    )
  )
)

// Side effects on retry
schedule.pipe(
  Schedule.tapInput((error) => Effect.logDebug(`retrying: ${error.message}`)),
  Schedule.tapOutput((delay) => Effect.logDebug(`next in ${Duration.toMillis(delay)}ms`))
)
```

## Request batching

Automatic N+1 elimination with typed errors, tracing, and caching:

```ts
import { Effect, Exit, Request, RequestResolver } from "effect"

// Define a request type
class GetUserById extends Request.Class<
  { readonly id: number },
  User,           // success type
  UserNotFound,   // error type
  never           // requirements
> {}

// Build a resolver that handles batches
const resolver = yield* RequestResolver.make<GetUserById>(
  Effect.fn(function*(entries) {
    for (const entry of entries) {
      const user = db.get(entry.request.id)
      entry.completeUnsafe(user
        ? Exit.succeed(user)
        : Exit.fail(new UserNotFound({ id: entry.request.id })))
    }
  })
).pipe(
  RequestResolver.setDelay("10 millis"),         // batching window
  RequestResolver.withSpan("getUserById"),        // automatic tracing
  RequestResolver.withCache({ capacity: 1024 })   // built-in LRU
)

// Caller doesn't know batching exists
const getUserById = (id: number) =>
  Effect.request(new GetUserById({ id }), resolver)

// Concurrent calls are batched automatically
yield* Effect.forEach([1, 2, 1, 3], getUserById, { concurrency: "unbounded" })
// → one resolver call with unique IDs [1, 2, 3]
```

## AI modules

Provider-agnostic language model interface with text generation, structured
object generation, streaming, tools, and stateful chat sessions.

### Provider setup

```ts
import { AnthropicClient, AnthropicLanguageModel } from "@effect/ai-anthropic"
import { OpenAiClient, OpenAiLanguageModel } from "@effect/ai-openai"
import { Config, Effect, ExecutionPlan, Layer } from "effect"
import { AiError, LanguageModel } from "effect/unstable/ai"
import { FetchHttpClient } from "effect/unstable/http"

const AnthropicClientLayer = AnthropicClient.layerConfig({
  apiKey: Config.redacted("ANTHROPIC_API_KEY")
}).pipe(Layer.provide(FetchHttpClient.layer))

const OpenAiClientLayer = OpenAiClient.layerConfig({
  apiKey: Config.redacted("OPENAI_API_KEY")
}).pipe(Layer.provide(FetchHttpClient.layer))
```

### Text and object generation

```ts
// Text generation
const model = yield* OpenAiLanguageModel.model("gpt-5.2")
const response = yield* LanguageModel.generateText({
  prompt: "Write a summary"
}).pipe(Effect.provide(model))

response.text           // string
response.usage          // { outputTokens: { total: number }, ... }
response.finishReason   // "stop" | "length" | ...

// Schema-validated object generation
const plan = yield* LanguageModel.generateObject({
  objectName: "launch_plan",
  prompt: "Convert these notes...",
  schema: LaunchPlan  // Schema.Class — validated at runtime
}).pipe(Effect.provide(model))

plan.value  // LaunchPlan (typed)
```

### Multi-provider fallback

```ts
const DraftPlan = ExecutionPlan.make(
  { provide: OpenAiLanguageModel.model("gpt-5.2"), attempts: 3 },
  { provide: AnthropicLanguageModel.model("claude-opus-4-6"), attempts: 2 }
)

const draftsModel = yield* DraftPlan.withRequirements
// Use with Effect.withExecutionPlan(draftsModel)
```

### Tools and toolkits

```ts
import { Schema } from "effect"
import { Tool, Toolkit } from "effect/unstable/ai"

const SearchProducts = Tool.make("SearchProducts", {
  description: "Search the product catalog",
  parameters: Schema.Struct({
    query: Schema.String.annotate({ description: "Search query" }),
    maxResults: Schema.Number.pipe(Schema.withDecodingDefault(() => 10))
  }),
  success: Schema.Array(Product)
})

const toolkit = Toolkit.make(SearchProducts, GetInventory)

// Implement handlers as a Layer
const toolkitLayer = toolkit.toLayer(Effect.gen(function*() {
  return toolkit.of({
    SearchProducts: Effect.fn("SearchProducts")(function*({ query, maxResults }) {
      return [/* ... */]
    }),
    GetInventory: Effect.fn("GetInventory")(function*({ productId }) {
      return { productId, available: 42 }
    })
  })
}))

// Use with generateText
const response = yield* LanguageModel.generateText({
  prompt: "Find wireless headphones",
  toolkit,
  toolChoice: "required"  // force tool use; default is "auto"
})
response.toolCalls    // what the model called
response.toolResults  // resolved results
```

### Stateful chat sessions

```ts
import { Chat, Prompt } from "effect/unstable/ai"

// Create a session with system prompt
const session = yield* Chat.fromPrompt(Prompt.empty.pipe(
  Prompt.setSystem("You are a helpful assistant.")
))

// Multi-turn conversation — history maintained automatically
const r1 = yield* session.generateText({ prompt: "Hello" }).pipe(
  Effect.provide(modelLayer)
)
const r2 = yield* session.generateText({ prompt: "Tell me more" }).pipe(
  Effect.provide(modelLayer)
)

// Inspect history
const history = yield* Ref.get(session.history)

// Export/restore sessions
const json = yield* session.exportJson
const restored = yield* Chat.fromJson(json)

// Agentic loop with tools
while (true) {
  const response = yield* session.generateText({
    prompt: [],
    toolkit: tools
  }).pipe(Effect.provide(modelLayer))
  if (response.toolCalls.length === 0) {
    return response.text  // final answer
  }
  // Tool results are added to history automatically; loop continues
}
```

## Cluster — distributed entities

For stateful services distributed across machines:

```ts
import { Schema } from "effect"
import { Entity, Rpc } from "effect/unstable/cluster"

// Define RPCs with typed payloads and responses
const Increment = Rpc.make("Increment", {
  payload: { amount: Schema.Number },
  success: Schema.Number
})

const GetCount = Rpc.make("GetCount", { success: Schema.Number })
  .annotate(ClusterSchema.Persisted, true)  // persist messages

// Create an entity from RPCs
const Counter = Entity.make("Counter", [Increment, GetCount])

// Implement with in-memory state
const CounterLayer = Counter.toLayer(
  Effect.gen(function*() {
    const count = yield* Ref.make(0)
    return Counter.of({
      Increment: ({ payload }) =>
        Ref.updateAndGet(count, (n) => n + payload.amount),
      GetCount: () => Ref.get(count).pipe(Rpc.fork)  // concurrent reads
    })
  }),
  { maxIdleTime: "5 minutes" }  // passivation
)

// Client usage — looks like a local call
const clientFor = yield* Counter.client
const counter = clientFor("counter-123")
yield* counter.Increment({ amount: 1 })
yield* counter.GetCount()

// Production: NodeClusterSocket.layer with SqlClient
// Testing: TestRunner.layer (single-process, in-memory)
```
