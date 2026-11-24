import { strict as assert } from "node:assert"
import { test } from "node:test"
import { Deferred, Effect, Exit, Fiber, Layer, Option, Schema, Scope } from "effect"
import { RexSdk, type IRexSdk } from "rex-sdk"
import { BindingError, makeBindings, Target } from "../bindings.ts"

const target = (server = "rex:a") => Schema.decodeUnknownSync(Target)({
  server, sessionId: "session:a", hostId: "host:a",
})
const owner = "opencode:a"
const options = { timeout: 5_000 }
const run = <A, E>(program: Effect.Effect<A, E, Scope.Scope>) =>
  Effect.runPromise(Effect.scoped(program.pipe(Effect.timeout("3 seconds"))))

interface Plan {
  readonly acquire?: Effect.Effect<void>
  readonly finalize?: Effect.Effect<void>
  readonly view?: Effect.Effect<{ sessionId: string }, Error>
}

// This layer exercises binding ownership, not SDK transport or wire decoding.
const fixture = (plans: Readonly<Record<string, Plan>> = {}) => {
  const counts = { acquired: 0, active: 0, finalized: 0 }
  const layer = (server: string) => Layer.effect(RexSdk, Effect.gen(function* () {
    const plan = plans[server]
    counts.acquired++
    counts.active++
    yield* Effect.addFinalizer(() => Effect.gen(function* () {
      yield* plan?.finalize ?? Effect.void
      counts.active--
      counts.finalized++
    }))
    yield* plan?.acquire ?? Effect.void
    return {
      server: { status: () => Effect.succeed({ hostId: Option.some("host:a"), instanceId: server }) },
      sessions: {
        view: () => plan?.view ?? Effect.succeed({ sessionId: "session:a" }),
        listBlocks: () => Effect.succeed({ blocks: [] }),
      },
      // Deliberately no creators: a matching server host must not require that call.
    } as unknown as IRexSdk
  }))
  return { counts, layer }
}

const assertBindingError = (error: unknown, message: string) => {
  assert.ok(error instanceof BindingError)
  assert.equal(error.message, message)
}

test("bindings are owner-local and clear invalidates and closes only the selected owner", options, async () => {
  const fake = fixture()
  await run(Effect.gen(function* () {
    const bindings = yield* makeBindings(fake.layer)
    assertBindingError(yield* Effect.flip(bindings.get(owner)), "Select an explicit Rex target with /rex-target first.")
    const first = yield* bindings.select(owner, target())
    const other = yield* bindings.select("opencode:b", target("rex:b"))
    assert.equal(yield* bindings.get(owner), first)
    assert.equal(bindings.current(owner, first), true)
    assert.equal(bindings.current("opencode:b", first), false)
    yield* bindings.clear(owner)
    assert.equal(first.scope.state._tag, "Closed")
    assert.equal(bindings.current(owner, first), false)
    assert.equal(yield* bindings.get("opencode:b"), other)
    assert.deepEqual(fake.counts, { acquired: 2, active: 1, finalized: 1 })
  }))
  assert.deepEqual(fake.counts, { acquired: 2, active: 0, finalized: 2 })
})

for (const successor of ["clear", "rebind"] as const) {
  test(`a ${successor} supersedes a rebind blocked closing the previous binding`, options, async () => {
    const closing = Deferred.makeUnsafe<void>()
    const release = Deferred.makeUnsafe<void>()
    const fake = fixture({
      "rex:old": { finalize: Deferred.succeed(closing, undefined).pipe(Effect.andThen(Deferred.await(release))) },
    })
    await run(Effect.gen(function* () {
      const bindings = yield* makeBindings(fake.layer)
      const old = yield* bindings.select(owner, target("rex:old"))
      yield* Effect.gen(function* () {
        const pending = yield* Effect.forkChild(bindings.select(owner, target("rex:stale")).pipe(Effect.flip))
        yield* Deferred.await(closing)
        assert.equal(bindings.current(owner, old), false)
        const newest = successor === "rebind"
          ? yield* bindings.select(owner, target("rex:new"))
          : (yield* bindings.clear(owner), undefined)
        yield* Deferred.succeed(release, undefined)
        assertBindingError(yield* Fiber.join(pending), "Target selection was superseded.")
        assert.equal(fake.counts.acquired, successor === "rebind" ? 2 : 1,
          "the superseded rebind must not acquire another SDK")
        if (newest) {
          assert.equal(yield* bindings.get(owner), newest)
          assert.equal(bindings.current(owner, newest), true)
        } else {
          assertBindingError(yield* Effect.flip(bindings.get(owner)), "Select an explicit Rex target with /rex-target first.")
        }
      }).pipe(Effect.ensuring(Deferred.succeed(release, undefined)))
    }))
    assert.equal(fake.counts.active, 0)
    assert.equal(fake.counts.finalized, fake.counts.acquired)
  })
}

test("a select superseded during SDK acquisition closes its provisional scope without replacing the winner", options, async () => {
  const acquiring = Deferred.makeUnsafe<void>()
  const release = Deferred.makeUnsafe<void>()
  const fake = fixture({
    "rex:stale": { acquire: Deferred.succeed(acquiring, undefined).pipe(Effect.andThen(Deferred.await(release))) },
  })
  await run(Effect.gen(function* () {
    const bindings = yield* makeBindings(fake.layer)
    yield* Effect.gen(function* () {
      const pending = yield* Effect.forkChild(bindings.select(owner, target("rex:stale")).pipe(Effect.flip))
      yield* Deferred.await(acquiring)
      const winner = yield* bindings.select(owner, target("rex:winner"))
      assert.deepEqual(fake.counts, { acquired: 2, active: 2, finalized: 0 })
      yield* Deferred.succeed(release, undefined)
      assertBindingError(yield* Fiber.join(pending), "Target selection was superseded.")
      assert.equal(yield* bindings.get(owner), winner)
      assert.equal(bindings.current(owner, winner), true)
      assert.deepEqual(fake.counts, { acquired: 2, active: 1, finalized: 1 })
    }).pipe(Effect.ensuring(Deferred.succeed(release, undefined)))
  }))
  assert.deepEqual(fake.counts, { acquired: 2, active: 0, finalized: 2 })
})

test("interrupting an acquiring select closes its scope and leaves no binding", options, async () => {
  const acquiring = Deferred.makeUnsafe<void>()
  const fake = fixture({
    "rex:a": { acquire: Deferred.succeed(acquiring, undefined).pipe(Effect.andThen(Effect.never)) },
  })
  await run(Effect.gen(function* () {
    const bindings = yield* makeBindings(fake.layer)
    const pending = yield* Effect.forkChild(bindings.select(owner, target()))
    yield* Deferred.await(acquiring)
    yield* Fiber.interrupt(pending)
    const exit = yield* Fiber.await(pending)
    assert.equal(Exit.isFailure(exit), true)
    assert.deepEqual(fake.counts, { acquired: 1, active: 0, finalized: 1 })
    assertBindingError(yield* Effect.flip(bindings.get(owner)), "Select an explicit Rex target with /rex-target first.")
    const retry = yield* bindings.select(owner, target("rex:retry"))
    assert.equal(bindings.current(owner, retry), true)
  }))
  assert.deepEqual(fake.counts, { acquired: 2, active: 0, finalized: 2 })
})

test("an SDK failure closes the provisional scope and propagates the original error", options, async () => {
  const failure = new Error("view unavailable")
  const fake = fixture({ "rex:bad": { view: Effect.fail(failure) } })
  await run(Effect.gen(function* () {
    const bindings = yield* makeBindings(fake.layer)
    const previous = yield* bindings.select(owner, target())
    assert.equal(yield* Effect.flip(bindings.select(owner, target("rex:bad"))), failure)
    assert.equal(bindings.current(owner, previous), false)
    assert.equal(previous.scope.state._tag, "Closed")
    assert.deepEqual(fake.counts, { acquired: 2, active: 0, finalized: 2 })
    assertBindingError(yield* Effect.flip(bindings.get(owner)), "Select an explicit Rex target with /rex-target first.")
  }))
  assert.deepEqual(fake.counts, { acquired: 2, active: 0, finalized: 2 })
})

test("unloading closes committed scopes and prevents later lookup or selection", options, async () => {
  const fake = fixture()
  const { bindings, binding } = await run(Effect.gen(function* () {
    const bindings = yield* makeBindings(fake.layer)
    const binding = yield* bindings.select(owner, target())
    return { bindings, binding }
  }))
  assert.equal(binding.scope.state._tag, "Closed")
  assert.equal(bindings.current(owner, binding), false)
  assert.deepEqual(fake.counts, { acquired: 1, active: 0, finalized: 1 })
  await run(Effect.gen(function* () {
    assertBindingError(yield* Effect.flip(bindings.get(owner)), "Select an explicit Rex target with /rex-target first.")
    assertBindingError(yield* Effect.flip(bindings.select(owner, target())), "Rex plugin has been unloaded.")
  }))
  assert.deepEqual(fake.counts, { acquired: 1, active: 0, finalized: 1 })
})
