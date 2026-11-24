import { ConfigProvider, Effect, Exit, Layer, Option, Schema } from "effect";
import { RexSdk, SessionId, rexSdkLayerFromOptions } from "rex-sdk";
import { guardedProgram, type Selection } from "./policy.ts";
import { RexToolError, RexToolRuntime, toRexToolResult } from "./vendor/rex-tool-runtime.ts";
import type { RexToolOperation } from "./vendor/rex-tool-operations.ts";

const makeSdkLayer = (server: string) => rexSdkLayerFromOptions({
  server,
  client: { kind: "agent", name: "pi-rex", version: "0.1.0" },
}).pipe(Layer.provide(ConfigProvider.layer(ConfigProvider.fromUnknown({}))));

/** One explicit binding per Pi session; no ambient target or persisted grant. */
export class RexController {
  #runtime: RexToolRuntime | undefined;
  #selection: Selection | undefined;
  #piSession: string | undefined;
  #generation = 0;
  #closed = false;
  readonly #makeLayer: (server: string) => Layer.Layer<RexSdk, unknown>;

  constructor(makeLayer: (server: string) => Layer.Layer<RexSdk, unknown> = makeSdkLayer) {
    this.#makeLayer = makeLayer;
  }

  here(piSession: string) {
    return this.#piSession === piSession && this.#selection
      ? { sessionId: this.#selection.sessionId, blockId: this.#selection.blockId }
      : { sessionId: null, blockId: null };
  }

  async clear() {
    ++this.#generation;
    this.#selection = undefined;
    this.#piSession = undefined;
    const runtime = this.#runtime;
    this.#runtime = undefined;
    await runtime?.dispose();
  }

  async dispose() {
    this.#closed = true;
    await this.clear();
  }

  async select(server: string, session: string, blockId: string | null, piSession: string, hostId?: string) {
    if (this.#closed) throw new RexToolError("RexPolicyError", "Extension is disposed.");
    const sessionId = Schema.decodeUnknownSync(SessionId)(session);
    const cleared = this.clear();
    const generation = this.#generation;
    await cleared;
    if (this.#closed || generation !== this.#generation)
      throw new RexToolError("RexPolicyError", "Target selection was superseded.");
    const runtime = new RexToolRuntime(() => this.#makeLayer(server));
    this.#runtime = runtime;
    try {
      const exit = await runtime.run(Effect.gen(function* () {
        const rex = yield* RexSdk;
        const status = yield* rex.server.status();
        const view = yield* rex.sessions.view({ sessionId });
        const listed = yield* rex.sessions.listBlocks({ sessionId });
        if (view.sessionId !== sessionId || (blockId !== null && !listed.blocks.some((block) => block.blockId === blockId)))
          return yield* Effect.fail(new RexToolError("RexPolicyError", "Target does not belong to the selected session."));
        const selectedHost = hostId ?? Option.getOrNull(status.hostId);
        const block = listed.blocks.find((item) => item.blockId === blockId);
        if (block && (selectedHost === null || Option.getOrNull(block.hostId) !== selectedHost))
          return yield* Effect.fail(new RexToolError("RexPolicyError", "Block is on another or unknown host. Select its explicit hostId."));
        return { instanceId: status.instanceId, hostId: selectedHost };
      }), undefined);
      if (Exit.isFailure(exit)) {
        toRexToolResult(exit);
        throw new Error("Unreachable failed selection");
      }
      if (this.#closed || generation !== this.#generation)
        throw new RexToolError("RexPolicyError", "Target selection was superseded.");
      this.#selection = { server, sessionId, blockId, ...exit.value, owned: new Set() };
      this.#piSession = piSession;
      return { server, sessionId, blockId, ...exit.value };
    } catch (error) {
      if (generation === this.#generation) await this.clear();
      else await runtime.dispose();
      throw error;
    }
  }

  async call(
    operation: RexToolOperation,
    params: Readonly<Record<string, unknown>>,
    piSession: string,
    authorize: (title: string, message: string, signal?: AbortSignal) => Promise<boolean>,
    signal?: AbortSignal,
  ) {
    const selection = this.#selection;
    const runtime = this.#runtime;
    const generation = this.#generation;
    if (this.#closed || !selection || !runtime || this.#piSession !== piSession)
      throw new RexToolError("RexPolicyError", "Select an explicit target with /rex-target first.");
    if (signal?.aborted)
      throw new RexToolError("Interrupted", "The Rex call was cancelled before dispatch.");
    const exit = await runtime.run(guardedProgram(
      operation, params, selection, runtime.marks, authorize,
      () => !this.#closed && generation === this.#generation && this.#selection === selection,
    ), signal);
    try {
      return toRexToolResult(exit);
    } catch (error) {
      if (error instanceof RexToolError && error.tag === "Interrupted")
        error.message += " Cancellation is not rollback; inspect the explicit target before retrying.";
      throw error;
    }
  }
}
