# Testing Effect Programs

Effect provides `@effect/vitest` for writing tests that run Effect code
directly, with support for shared service layers, virtual time, parameterized
tests, and property-based testing with Schema arbitraries.

## Basics — it.effect

```ts
import { assert, describe, it } from "@effect/vitest"
import { Effect, Fiber, Schema } from "effect"
import { TestClock } from "effect/testing"

describe("@effect/vitest basics", () => {
  // Run Effect code in a test
  it.effect("runs Effect code with assert helpers", () =>
    Effect.gen(function*() {
      const upper = ["ada", "lin"].map((name) => name.toUpperCase())
      assert.deepStrictEqual(upper, ["ADA", "LIN"])
      assert.strictEqual(upper.length, 2)
      assert.isTrue(upper.includes("ADA"))
    }))

  // Parameterized tests
  it.effect.each([
    { input: " Ada ", expected: "ada" },
    { input: " Lin ", expected: "lin" },
    { input: " Nia ", expected: "nia" }
  ])("parameterized normalization %#", ({ input, expected }) =>
    Effect.gen(function*() {
      assert.strictEqual(input.trim().toLowerCase(), expected)
    }))

  // Virtual time — control the clock for testing timeouts, delays, etc.
  it.effect("controls time with TestClock", () =>
    Effect.gen(function*() {
      const fiber = yield* Effect.forkChild(
        Effect.sleep(60_000).pipe(Effect.as("done" as const))
      )
      // Advance virtual time — sleeping fibers complete immediately
      yield* TestClock.adjust(60_000)
      const value = yield* Fiber.join(fiber)
      assert.strictEqual(value, "done")
    }))

  // Real time — bypass the test clock
  it.live("uses real runtime services", () =>
    Effect.gen(function*() {
      const startedAt = Date.now()
      yield* Effect.sleep(1)
      assert.isTrue(Date.now() >= startedAt)
    }))

  // Property-based testing with Schema arbitraries
  it.effect.prop("reversing twice is identity", [Schema.String], ([value]) =>
    Effect.gen(function*() {
      const reversedTwice = value.split("").reverse().reverse().join("")
      assert.strictEqual(reversedTwice, value)
    }))
})
```

## Shared layers — layer()

The `layer()` function builds a service layer once in `beforeAll`, tears it
down in `afterAll`, and makes the services available to every `it.effect`
inside the block. State persists across tests within the block.

```ts
import { assert, it, layer } from "@effect/vitest"
import { Array, Effect, Layer, Ref, ServiceMap } from "effect"

// Test implementation backed by a Ref (not mocks)
class TodoRepoTestRef
  extends ServiceMap.Service<TodoRepoTestRef, Ref.Ref<Array<Todo>>>()(
    "app/TodoRepoTestRef"
  )
{
  static readonly layer = Layer.effect(TodoRepoTestRef, Ref.make(Array.empty()))
}

class TodoRepo extends ServiceMap.Service<TodoRepo, {
  create(title: string): Effect.Effect<Todo>
  readonly list: Effect.Effect<ReadonlyArray<Todo>>
}>()(
  "app/TodoRepo"
) {
  static readonly layerTest = Layer.effect(
    TodoRepo,
    Effect.gen(function*() {
      const store = yield* TodoRepoTestRef

      const create = Effect.fn("TodoRepo.create")(function*(title: string) {
        const todos = yield* Ref.get(store)
        const todo = { id: todos.length + 1, title }
        yield* Ref.set(store, [...todos, todo])
        return todo
      })

      return TodoRepo.of({ create, list: Ref.get(store) })
    })
  ).pipe(
    // provideMerge so tests can also access the Ref directly
    Layer.provideMerge(TodoRepoTestRef.layer)
  )
}

// Shared layer — built once, torn down after all tests
layer(TodoRepo.layerTest)("TodoRepo", (it) => {
  it.effect("creates a todo", () =>
    Effect.gen(function*() {
      const repo = yield* TodoRepo
      yield* repo.create("Write docs")
      const todos = yield* repo.list
      assert.strictEqual(todos.length, 1)
    }))

  it.effect("state persists across tests", () =>
    Effect.gen(function*() {
      const repo = yield* TodoRepo
      const todos = yield* repo.list
      // The todo from the previous test is still here
      assert.strictEqual(todos.length, 1)
    }))
})
```

## Testing higher-level services

When testing a service that depends on other services, compose the test layers
and provide them inline or via `layer()`:

```ts
class TodoService extends ServiceMap.Service<TodoService, {
  addAndCount(title: string): Effect.Effect<number>
  readonly titles: Effect.Effect<ReadonlyArray<string>>
}>()(
  "app/TodoService"
) {
  static readonly layerNoDeps = Layer.effect(
    TodoService,
    Effect.gen(function*() {
      const repo = yield* TodoRepo
      const addAndCount = Effect.fn("TodoService.addAndCount")(function*(title) {
        yield* repo.create(title)
        const todos = yield* repo.list
        return todos.length
      })
      const titles = repo.list.pipe(
        Effect.map((todos) => todos.map((t) => t.title))
      )
      return TodoService.of({ addAndCount, titles })
    })
  )

  static readonly layerTest = this.layerNoDeps.pipe(
    // provideMerge exposes TodoRepo and TodoRepoTestRef too
    Layer.provideMerge(TodoRepo.layerTest)
  )
}

describe("TodoService", () => {
  it.effect("tests higher-level logic", () =>
    Effect.gen(function*() {
      const ref = yield* TodoRepoTestRef  // access underlying test state
      const service = yield* TodoService
      const count = yield* service.addAndCount("Review docs")
      assert.isTrue(count >= 1)

      // Assert against the raw Ref for deeper inspection
      const todos = yield* Ref.get(ref)
      assert.isTrue(todos.length >= 1)
    }).pipe(Effect.provide(TodoService.layerTest)))
})
```

## Layer naming convention

- **`layerNoDeps`** — raw implementation, dependencies visible in `R`
- **`layer`** — wired with production dependencies via `Layer.provide`
- **`layerTest`** — wired with test implementations (Ref-backed stores, in-memory doubles)

Test implementations are real implementations with controlled state, not mocks.
Use `Layer.provideMerge` on test layers so tests can access both the service
and its underlying test state for assertions.
