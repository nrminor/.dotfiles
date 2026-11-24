/**
 * Runs Rex tool operations on one lazily built SDK runtime and converts their exits into pi tool
 * results: success → `structuredContent` JSON, typed failure → rejection whose message starts with
 * the SDK error tag, interruption (tool abort) → rejection.
 */
import { Cause, Duration, Effect, Exit, Layer, ManagedRuntime, Option } from "effect";
import type { AgentToolResult } from "@earendil-works/pi-coding-agent";
import { RexSdk } from "rex-sdk";
import { RexMarkStore } from "./rex-tool-marks.ts";
import type { RexToolOperation } from "./rex-tool-operations.ts";
import {
  encodeRexToolResult,
  REX_REQUEST_TIMEOUT_FIELD,
  type RexToolJson,
} from "./rex-tool-schemas.ts";

/** Owns one SDK runtime for a pi session; rebuilt after `dispose()` or a configuration failure. */
export class RexToolRuntime {
  #runtime: ManagedRuntime.ManagedRuntime<RexSdk, unknown> | undefined;
  /** Marks handed out in this pi session, by markId. */
  marks = new RexMarkStore();
  readonly #makeLayer: () => Layer.Layer<RexSdk, unknown>;

  constructor(makeLayer: () => Layer.Layer<RexSdk, unknown>) {
    this.#makeLayer = makeLayer;
  }

  async run<A>(effect: Effect.Effect<A, unknown, RexSdk>, signal: AbortSignal | undefined) {
    this.#runtime ??= ManagedRuntime.make(this.#makeLayer());
    return this.#runtime.runPromiseExit(effect, signal === undefined ? undefined : { signal });
  }

  async dispose(): Promise<void> {
    const runtime = this.#runtime;
    this.#runtime = undefined;
    this.marks = new RexMarkStore();
    await runtime?.dispose();
  }
}

/** Error carrying the SDK error tag, so scripts can branch on `error.message.startsWith(tag)`. */
export class RexToolError extends Error {
  readonly tag: string;

  constructor(tag: string, message: string) {
    super(`${tag}: ${message}`);
    this.name = "RexToolError";
    this.tag = tag;
  }
}

function describeFailure(error: unknown): RexToolError {
  if (typeof error === "object" && error !== null) {
    const tag =
      "_tag" in error && typeof error._tag === "string"
        ? error._tag
        : error instanceof Error
          ? error.name
          : "Error";
    const message =
      "message" in error && typeof error.message === "string"
        ? error.message
        : JSON.stringify(error);
    return new RexToolError(tag || "Error", message);
  }
  return new RexToolError("Error", String(error));
}

/** Decodes flat tool parameters and runs one operation, resolving to the JSON a script receives. */
export function makeRexToolProgram(
  operation: RexToolOperation,
  params: { readonly [key: string]: unknown },
  marks: RexMarkStore,
): Effect.Effect<RexToolJson, unknown, RexSdk> {
  return Effect.gen(function* () {
    const { [REX_REQUEST_TIMEOUT_FIELD]: requestTimeoutMs, ...rest } = params;
    const options =
      typeof requestTimeoutMs === "number" ? { timeout: Duration.millis(requestTimeoutMs) } : {};
    const rex = yield* RexSdk;
    const result = yield* operation.program(rex, rest, options, marks);
    return encodeRexToolResult(result);
  });
}

/** Converts an operation exit into a pi tool result, throwing for every failure. */
export function toRexToolResult(exit: Exit.Exit<RexToolJson, unknown>): AgentToolResult<undefined> {
  if (Exit.isSuccess(exit)) {
    return {
      content: [{ type: "text", text: JSON.stringify(exit.value) }],
      structuredContent: exit.value,
      details: undefined,
    };
  }
  const error = Cause.findErrorOption(exit.cause);
  if (Option.isSome(error)) throw describeFailure(error.value);
  if (Cause.hasInterruptsOnly(exit.cause))
    throw new RexToolError("Interrupted", "the Rex call was aborted");
  throw new RexToolError("Defect", Cause.pretty(exit.cause));
}
