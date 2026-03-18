# Effect Streams

Effect Streams represent effectful, pull-based sequences of values over time.
They let you model finite or infinite data sources with typed errors,
backpressure, and concurrency control.

## Creating streams

```ts
import { Effect, Queue, Schedule, Schema, Stream } from "effect"
import { NodeStream } from "@effect/platform-node"
import * as Option from "effect/Option"
import { Readable } from "node:stream"

// From data you already have
Stream.fromIterable([1, 2, 3, 4, 5])

// Polling — repeat an effect on a schedule (metrics, health checks)
Stream.fromEffectSchedule(
  Effect.succeed(42),
  Schedule.spaced("30 seconds")
).pipe(Stream.take(100))

// Paginated APIs — returns [currentPageResults, nextCursor?]
Stream.paginate(
  0,  // initial cursor
  Effect.fn(function*(page) {
    yield* Effect.sleep("50 millis")
    const results = Array.from({ length: 100 }, (_, i) => `Item ${i + page * 100}`)
    const next = page < 10 ? Option.some(page + 1) : Option.none()
    return [results, next] as const
  })
)

// Async iterables
async function* letters() { yield "a"; yield "b"; yield "c" }
Stream.fromAsyncIterable(letters(), (cause) => new LetterError({ cause }))

// DOM events
Stream.fromEventListener<PointerEvent>(button, "click")

// Callback APIs with cleanup
Stream.callback<PointerEvent>(Effect.fn(function*(queue) {
  const handler = (e: PointerEvent) => Queue.offerUnsafe(queue, e)
  yield* Effect.acquireRelease(
    Effect.sync(() => button.addEventListener("click", handler)),
    () => Effect.sync(() => button.removeEventListener("click", handler))
  )
}))

// Node.js readable streams
NodeStream.fromReadable({
  evaluate: () => Readable.from(["Hello", " ", "world"]),
  onError: (cause) => new StreamError({ cause }),
  closeOnDone: true
})
```

## Transforming streams

```ts
// Pure per-element transform
stream.pipe(Stream.map((order) => ({ ...order, total: order.subtotal + order.shipping })))

// Filter
stream.pipe(Stream.filter((order) => order.status === "paid"))

// FlatMap — each element becomes a stream, results are flattened
Stream.make("US", "CA", "NZ").pipe(
  Stream.flatMap(
    (country) => Stream.range(1, 50).pipe(
      Stream.map((i) => ({ id: `${country}_${i}`, country }))
    ),
    { concurrency: 2 }  // process 2 countries concurrently
  )
)

// Effectful per-element transform with concurrency control
stream.pipe(
  Stream.mapEffect(enrichOrder, { concurrency: 4 })
)
```

## Consuming streams

Each `run*` method terminates a stream into an `Effect`:

```ts
// Collect all elements into an array
Stream.runCollect(stream)                    // → Effect<Array<A>>

// Run for side effects, discard output
Stream.runDrain(stream)                      // → Effect<void>

// Per-element effectful consumer
stream.pipe(
  Stream.runForEach((order) =>
    Effect.logInfo(`Order ${order.id} total=$${order.total}`)
  )
)                                            // → Effect<void>

// Reduce to a single value
stream.pipe(
  Stream.runFold(() => 0, (acc, order) => acc + order.total)
)                                            // → Effect<number>

// Custom sink
stream.pipe(
  Stream.map((order) => order.total),
  Stream.run(Sink.sum)
)                                            // → Effect<number>

// Edge elements
Stream.runHead(stream)                       // → Effect<Option<A>>
Stream.runLast(stream)                       // → Effect<Option<A>>
```

## Windowing

```ts
stream.pipe(Stream.take(10))                              // first 10
stream.pipe(Stream.drop(5))                               // skip first 5
stream.pipe(Stream.takeWhile((x) => x.status === "active"))  // until predicate fails
```

## Stream encoding — Ndjson and Msgpack

Use `Stream.pipeThroughChannel` with the `Ndjson` or `Msgpack` modules to
decode and encode streams of structured data.

```ts
import { DateTime, Schema, Stream } from "effect"
import { Ndjson, Msgpack } from "effect/unstable/encoding"

class LogEntry extends Schema.Class<LogEntry>("LogEntry")({
  timestamp: Schema.DateTimeUtcFromString,
  level: Schema.Literals(["info", "warn", "error"]),
  message: Schema.String
}) {}
```

### Decoding

```ts
// Raw JSON parse (untyped)
stream.pipe(
  Stream.pipeThroughChannel(Ndjson.decodeString()),
  Stream.runCollect
)

// Schema-validated decode (typed)
stream.pipe(
  Stream.pipeThroughChannel(Ndjson.decodeSchemaString(LogEntry)()),
  Stream.runCollect
)

// Binary (Uint8Array) input
binaryStream.pipe(
  Stream.pipeThroughChannel(Ndjson.decode()),
  Stream.runCollect
)

// Handle empty lines
stream.pipe(
  Stream.pipeThroughChannel(Ndjson.decodeString({ ignoreEmptyLines: true }))
)
```

### Encoding

```ts
// Untyped encode
stream.pipe(
  Stream.pipeThroughChannel(Ndjson.encodeString()),
  Stream.runCollect
)

// Schema-validated encode (applies transformations like date formatting)
stream.pipe(
  Stream.pipeThroughChannel(Ndjson.encodeSchemaString(LogEntry)()),
  Stream.runCollect
)

// Binary output
stream.pipe(
  Stream.pipeThroughChannel(Ndjson.encode()),
  Stream.runCollect
)
```

### Full pipeline: decode → transform → re-encode

```ts
Stream.make(ndjsonInput).pipe(
  Stream.pipeThroughChannel(Ndjson.decodeSchemaString(LogEntry)()),
  Stream.filter((entry) => entry.level === "error"),
  Stream.pipeThroughChannel(Ndjson.encodeSchemaString(LogEntry)()),
  Stream.runCollect
)
```

### Error handling

```ts
stream.pipe(
  Stream.pipeThroughChannel(Ndjson.decodeString()),
  Stream.catchTag("NdjsonError", (err) =>
    // err.kind is "Pack" (encoding) or "Unpack" (decoding)
    Stream.succeed({ recovered: true, kind: err.kind })
  ),
  Stream.runCollect
)
```

Replace `Ndjson` with `Msgpack` for binary serialization — the API shape is
identical.

## PubSub — in-process event bus with Stream subscribers

`PubSub` pairs naturally with streams. Publishers push events; subscribers
receive them as a `Stream` with all the usual operators.

```ts
import { Effect, Layer, PubSub, ServiceMap, Stream } from "effect"

type OrderEvent =
  | { readonly _tag: "OrderPlaced"; readonly orderId: string }
  | { readonly _tag: "PaymentCaptured"; readonly orderId: string }

export class OrderEvents extends ServiceMap.Service<OrderEvents, {
  publish(event: OrderEvent): Effect.Effect<void>
  publishAll(events: ReadonlyArray<OrderEvent>): Effect.Effect<void>
  readonly subscribe: Stream.Stream<OrderEvent>
}>()(
  "acme/OrderEvents"
) {
  static readonly layer = Layer.effect(
    OrderEvents,
    Effect.gen(function*() {
      const pubsub = yield* PubSub.bounded<OrderEvent>({
        capacity: 256,
        replay: 50  // late subscribers get last 50 events
      })
      yield* Effect.addFinalizer(() => PubSub.shutdown(pubsub))

      return OrderEvents.of({
        publish: Effect.fn("OrderEvents.publish")(function*(event) {
          yield* PubSub.publish(pubsub, event)
        }),
        publishAll: Effect.fn("OrderEvents.publishAll")(function*(events) {
          yield* PubSub.publishAll(pubsub, events)
        }),
        subscribe: Stream.fromPubSub(pubsub)
      })
    })
  )
}
```

Backpressure is built in via `bounded`. Use `PubSub.unbounded` if you don't
need it. The `replay` option lets late subscribers catch up on recent events.
