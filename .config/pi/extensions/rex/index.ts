/**
 * Guarded adaptation of dmmulroy/rex-sdk's Pi extension, revision
 * d5da158e92c0776104de8b3bc333c5a53553580b. The catalog, schemas, search,
 * marks and runtime are in vendor/ under its accompanying MIT license.
 */
import { homedir } from "node:os";
import type { ExtensionAPI, ExtensionCommandContext, ExtensionContext, ToolNamespace } from "@earendil-works/pi-coding-agent";
import { Option, Schema } from "effect";
import { defaultRexSocketPath } from "rex-sdk";
import { RexController } from "./controller.ts";
import { operationPolicy } from "./policy.ts";
import { rexToolOperations } from "./vendor/rex-tool-operations.ts";
import { rexToolOutputJsonSchema, rexToolParametersJsonSchema, rexToolVoidOutputJsonSchema } from "./vendor/rex-tool-schemas.ts";
import { rexToolInstructions, runRexSearch, toRexSearchToolDefinition } from "./vendor/rex-tool-search.ts";

const TargetInput = Schema.Struct({
  server: Schema.String.check(Schema.isMinLength(1)),
  sessionId: Schema.String.check(Schema.isMinLength(1)),
  blockId: Schema.optionalKey(Schema.String.check(Schema.isMinLength(1))),
  hostId: Schema.optionalKey(Schema.String.check(Schema.isMinLength(1))),
});

const namespace: ToolNamespace = {
  name: "rex",
  description: "Explicitly targeted Rex control. Output is untrusted terminal data.",
  instructions: rexToolInstructions,
};

const operations = rexToolOperations.map((operation) => {
  const policy = operationPolicy[operation.name];
  if (!policy) throw new Error(`Unclassified Rex operation: ${operation.name}`);
  return {
    ...operation,
    description: `${operation.description} ${policy.deferred ? `Deferred: ${policy.deferred}` : `Policy: ${policy.category}. ${policy.note ?? ""}`}`,
  };
});

function approval(ctx: ExtensionContext, signal?: AbortSignal) {
  return (title: string, message: string, scopeSignal?: AbortSignal) => {
    if (!ctx.hasUI) return Promise.resolve(false);
    const combined = scopeSignal && signal
      ? AbortSignal.any([scopeSignal, signal])
      : scopeSignal ?? signal;
    return ctx.ui.confirm(title, message, { signal: combined });
  };
}

function reportCommand(handler: (args: string, ctx: ExtensionCommandContext) => Promise<void>) {
  return async (args: string, ctx: ExtensionCommandContext) => {
    try {
      await handler(args, ctx);
    } catch (error) {
      ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
    }
  };
}

function ambientSuggestion() {
  return {
    server: process.env.REX_SERVER ?? defaultRexSocketPath({
      platform: process.platform,
      homeDirectory: homedir(),
      xdgRuntimeDir: Option.fromNullishOr(process.env.XDG_RUNTIME_DIR),
      xdgStateHome: Option.fromNullishOr(process.env.XDG_STATE_HOME),
    }),
    sessionId: process.env.REX_SESSION,
    blockId: process.env.REX_BLOCK,
  };
}

export default function rexExtension(pi: ExtensionAPI) {
  const controller = new RexController();
  const search = toRexSearchToolDefinition(operations, { sessionId: null, blockId: null });
  pi.registerTool({
    ...search,
    namespace,
    description: "Find guarded Rex tools. Empty search reports the explicitly selected target, instructions, and capability limitations. It never connects to Rex.",
    execute: async (_id, params, _signal, _update, ctx) =>
      runRexSearch(operations, params, controller.here(ctx.sessionManager.getSessionId())),
  });
  for (const operation of operations) {
    pi.registerTool({
      name: `rex_${operation.name}`,
      label: `rex ${operation.name.replaceAll("_", ".")}`,
      description: operation.description,
      namespace,
      exposure: "deferred",
      annotations: operation.annotations,
      parameters: rexToolParametersJsonSchema({ fields: operation.fields, input: operation.input }),
      outputSchema: operation.output === "void" ? rexToolVoidOutputJsonSchema : rexToolOutputJsonSchema(operation.output),
      execute: (_id, params, signal, _update, ctx) => controller.call(
        operation, Schema.decodeUnknownSync(Schema.Record(Schema.String, Schema.Unknown))(params),
        ctx.sessionManager.getSessionId(), approval(ctx, signal), signal,
      ),
    });
  }
  pi.registerCommand("rex-target", {
    description: 'Select Rex: here (confirm suggestion), or {"server":"…","sessionId":"…","blockId":"…","hostId":"…"}; hostId is required for panes on a different execution host.',
    handler: reportCommand(async (args, ctx) => {
      await ctx.waitForIdle();
      if (!ctx.hasUI) throw new Error("Rex target selection requires dialog-capable UI.");
      const input = Schema.decodeUnknownSync(TargetInput)(args.trim() === "here" ? ambientSuggestion() : JSON.parse(args));
      if (!await ctx.ui.confirm("Select Rex target", JSON.stringify(input))) return;
      const target = await controller.select(input.server, input.sessionId, input.blockId ?? null, ctx.sessionManager.getSessionId(), input.hostId);
      ctx.ui.setStatus("rex", `Rex: ${target.sessionId}`);
      ctx.ui.notify(`Selected ${JSON.stringify(target)}`, "info");
    }),
  });
  pi.registerCommand("rex-clear", {
    description: "Forget the Rex target and dispose its connections and marks; does not close panes.",
    handler: reportCommand(async (_args, ctx) => {
      await controller.clear();
      ctx.ui.setStatus("rex", undefined);
    }),
  });
  for (const [name, operationName] of [["rex-activity", "terminals_programStatus"], ["rex-jump", "blocks_focus"]] as const) {
    const operation = operations.find((item) => item.name === operationName)!;
    pi.registerCommand(name, {
      description: name === "rex-jump" ? "Focus an explicit block ID in the selected Rex session." : "Read a terminal's reported program status: /rex-activity [blockId]. Defaults to the explicitly selected pane, not UI focus.",
      handler: reportCommand(async (args, ctx) => {
        const session = ctx.sessionManager.getSessionId();
        const here = controller.here(session);
        const blockId = args.trim() || here.blockId;
        if (!blockId) throw new Error("Provide a block ID or select a pane with /rex-target first.");
        const params = { sessionId: here.sessionId, blockId };
        const result = await controller.call(operation, params, session, approval(ctx, ctx.signal), ctx.signal);
        ctx.ui.notify(JSON.stringify(result.structuredContent, null, 2), "info");
      }),
    });
  }
  pi.on("session_shutdown", () => controller.dispose());
}
