import assert from "node:assert/strict"
import { mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"
import { test } from "node:test"
import { Plugin } from "@opencode/plugin/effect"
import { OpenCode } from "@opencode/sdk/effect"
import { Deferred, Effect } from "effect"
import { resourceDefinitions } from "../resources.ts"
import { requestDefinitions } from "../requests.ts"
import { operationPolicy } from "../policy.ts"

test("every resource workflow has a unique name and an operation policy", () => {
  const definitions = [...resourceDefinitions, ...requestDefinitions]
  assert.equal(new Set(definitions.map((entry) => entry.name)).size, definitions.length)
  for (const entry of definitions) assert.ok(operationPolicy[entry.name], entry.name)
})

test("configuration loads the packaged plugin and discovers tools without a Rex connection", { timeout: 20_000 }, async () => {
  const directory = mkdtempSync(join(tmpdir(), "rex-discovery-"))
  writeFileSync(join(directory, "opencode.json"), JSON.stringify({
    plugins: [resolve(import.meta.dirname, "..")],
  }))
  try {
    await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
      const ready = yield* Deferred.make<Plugin.Context>()
      const observer = Plugin.define({
        id: "rex-discovery-observer",
        effect: (ctx) => Deferred.succeed(ready, ctx).pipe(Effect.asVoid),
      })
      const host = yield* OpenCode.create({
        plugins: [observer], models: { fetch: false },
        config: { directory, project: true, claude: false }, fs: { filewatcher: false },
        fetch: async () => { throw new Error("network disabled") },
      })
      yield* host.plugin.list({ location: { directory } })
      const ctx = yield* Deferred.await(ready)
      yield* ctx.session.create({ title: "discovery" })
      const tools = yield* ctx.tool.list()
      const names = tools.filter((tool) => tool.id.startsWith("rex_")).map((tool) => tool.id)
      for (const name of [
        "rex_search", "rex_blocks_splitBeside", "rex_clients_reply",
        ...resourceDefinitions.map((definition) => `rex_${definition.name}`),
        ...requestDefinitions.map((definition) => `rex_${definition.name}`),
      ]) assert.ok(names.includes(name), `${name} is discoverable through the real plugin loader`)
      assert.equal(new Set(names).size, names.length)
      const commands = yield* ctx.command.list()
      for (const name of ["rex-target", "rex-clear", "rex-activity", "rex-jump"])
        assert.ok(JSON.stringify(commands).includes(name), name)
    })).pipe(Effect.timeout("15 seconds")))
  } finally {
    rmSync(directory, { recursive: true, force: true })
  }
})
