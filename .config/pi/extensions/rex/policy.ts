import { Duration, Effect, Option, Schema } from "effect";
import { RexSdk, SessionId, rexBlockMethods } from "rex-sdk";
import { rexToolOperations, type RexToolOperation } from "./vendor/rex-tool-operations.ts";
import type { RexMarkStore } from "./vendor/rex-tool-marks.ts";
import { encodeRexToolResult, type RexToolJson } from "./vendor/rex-tool-schemas.ts";

export interface Selection {
  readonly server: string;
  readonly sessionId: string;
  readonly instanceId: string;
  readonly hostId: string | null;
  readonly blockId: string | null;
  readonly owned: Set<string>;
}

type Category = "read" | "sensitive read" | "execution/input" | "layout" |
  "close/destroy" | "server config/shutdown" | "network/host config";
export interface OperationPolicy {
  readonly category: Category;
  readonly deferred?: string;
  readonly note?: string;
}

// This table is deliberately independent of the reference's advisory annotations.
// A new upstream operation fails closed until classified here.
const groups: ReadonlyArray<readonly [Category, readonly string[]]> = [
  ["read", [
    "sessions_view", "sessions_list", "sessions_listBlocks", "sessions_listClients", "sessions_help",
    "server_status", "server_version", "server_whoami", "server_help", "server_apple_privacyStatus",
    "blocks_describe", "terminals_waitForOutput", "terminals_mark", "terminals_waitForQuiet",
    "terminals_readTail", "terminals_waitForExit", "terminals_read", "terminals_format",
    "terminals_size", "terminals_title", "terminals_pwd",
    "terminals_process", "terminals_modes", "terminals_inputMode", "terminals_programStatus",
    "terminals_ports", "tunnels_info", "clients_list", "clients_inspect",
    "targets_resolve", "targets_complete", "hosts_list", "creators_list",
  ]],
  ["sensitive read", ["events_waitFor", "terminals_blobRead", "terminals_listDir", "terminals_clipboardRead", "terminals_readFile"]],
  ["execution/input", [
    "terminals_writeLine", "terminals_write", "terminals_pasteFiles", "blocks_sendEvent",
    "blocks_callMethod", "clients_setScript", "clients_action", "clients_key",
    "clients_perform", "clients_reply",
    "sessions_create", "windows_create", "blocks_splitBeside", "blocks_split",
    "blocks_create", "layers_create",
  ]],
  ["layout", [
    "sessions_setLabel", "sessions_move", "windows_focus",
    "windows_focusNext", "windows_focusPrevious", "windows_move", "windows_setLabel",
    "blocks_move", "blocks_swap",
    "blocks_zoom", "blocks_detach", "blocks_float", "blocks_focus", "blocks_focusDirection",
    "blocks_focusNext", "blocks_focusPrevious", "blocks_resize", "blocks_setLabel",
    "blocks_own", "blocks_disown", "layers_raise", "layers_lower",
    "layers_resize", "layers_setState", "terminals_resize", "terminals_setTheme", "clients_setLabel", "clients_keymap",
  ]],
  ["close/destroy", ["sessions_destroy", "windows_close", "blocks_close", "layers_close", "terminals_clear", "terminals_reset"]],
  ["server config/shutdown", ["server_reloadConfig", "server_stop", "server_apple_grantFileAccess"]],
  ["network/host config", [
    "server_tailscale_enable", "server_tailscale_disable", "server_tailscale_login",
    "server_tailscale_logout", "server_tailscale_rename", "tunnels_createDial",
    "tunnels_createListen", "hosts_put", "hosts_remove",
  ]],
];

const deferred: Readonly<Record<string, string>> = {
  windows_focusNext: "Depends on ambient focus.",
  windows_focusPrevious: "Depends on ambient focus.",
  blocks_focusDirection: "Depends on ambient focus.",
  blocks_focusNext: "Depends on ambient focus.",
  blocks_focusPrevious: "Depends on ambient focus.",
  blocks_sendEvent: "Event payloads require per-event classification.",
  clients_action: "Configured actions require per-action classification.",
  clients_key: "Key bindings require per-action classification.",
  clients_perform: "Remote client actions require per-action classification.",
  clients_reply: "Replies require an authorized request lifecycle.",
};

const notes: Readonly<Record<string, string>> = {
  server_stop: "Stops the selected server and ALL its sessions and panes, including unrelated pre-existing work.",
  server_reloadConfig: "Reloads server-wide configuration and configured Lua behavior, not only the selected session.",
  sessions_create: "Creates a separate session on the selected server; it does not change the selection or task ownership. Initial layouts can execute commands.",
  windows_create: "Layouts can execute commands. Focus is forced false, but an empty session activates its first window.",
  blocks_split: "Layouts can execute commands; focus is forced false.",
  blocks_splitBeside: "Layouts can execute commands; focus is forced false.",
  layers_create: "Layouts can execute commands; focus is forced false.",
  blocks_create: "Block creator options can execute commands.",
  targets_resolve: "Server-wide metadata lookup; returned IDs are not authority and never change the selected binding. Supplied context and scope must use selected-session IDs.",
  targets_complete: "Server-wide metadata lookup; returned IDs are not authority and never change the selected binding. Supplied context and scope must use selected-session IDs.",
  clients_setLabel: "Changes the calling SDK client's label.",
  clients_setScript: "Loads and runs Lua scripts for the calling SDK client.",
  clients_keymap: "Uses the calling SDK client; supplying actions can update the server's stored client action list.",
  blocks_callMethod: "Only known uniquely mapped block methods are available.",
  events_waitFor: "Requires a session, terminal, or block source and is restricted to the selected session. Payloads can include sensitive content from any host in that session.",
  terminals_readFile: "Default maximum file bytes is 32768; larger explicit limits may exceed the encoded result cap, especially for base64.",
  terminals_read: "Bounded whole-output read; if the output exceeds maxBytes, use format and blobRead for pages.",
  terminals_readTail: "Returned bytes are bounded. SDK fallback paging on older servers can transfer more before trimming.",
};

export const operationPolicy: Readonly<Record<string, OperationPolicy>> = Object.fromEntries(
  groups.flatMap(([category, names]) => names.map((name) => [name, {
    category,
    ...(deferred[name] ? { deferred: deferred[name] } : {}),
    ...(notes[name] ? { note: notes[name] } : {}),
  }])),
);

export class RexPolicyError extends Schema.TaggedError<RexPolicyError>()(
  "RexPolicyError", { message: Schema.String },
) {}

const fail = (message: string) => Effect.fail(new RexPolicyError({ message }));
const object = (value: unknown): Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown> : {};
const creates = new Set([
  "windows_create", "blocks_split", "blocks_splitBeside", "blocks_create", "layers_create",
  "tunnels_createDial", "tunnels_createListen",
]);
const serverCreates = new Set([...creates, "sessions_create"]);

function explicitHostIds(value: unknown): unknown[] {
  if (Array.isArray(value)) return value.flatMap(explicitHostIds);
  if (typeof value !== "object" || value === null) return [];
  return Object.entries(value).flatMap(([key, entry]) =>
    key === "hostId" || key === "host_id" ? [entry] : explicitHostIds(entry));
}

/** All dispatch, including generic block methods, must pass through this boundary. */
export function guardedProgram(
  operation: RexToolOperation,
  params: Readonly<Record<string, unknown>>,
  selection: Selection,
  marks: RexMarkStore,
  authorize: (title: string, message: string, signal?: AbortSignal) => Promise<boolean>,
  isCurrent: () => boolean,
): Effect.Effect<RexToolJson, unknown, RexSdk> {
  return Effect.gen(function* () {
    const policy = operationPolicy[operation.name];
    if (!policy) return yield* fail(`Unclassified operation: ${operation.name}`);
    if (policy.deferred) return yield* fail(`${operation.name} deferred: ${policy.deferred}`);
    if (!isCurrent()) return yield* fail("Selection is no longer current.");

    const timeout = params.requestTimeoutMs ?? 30_000;
    if (typeof timeout !== "number" || !Number.isFinite(timeout) || timeout <= 0 || timeout > 30_000)
      return yield* fail("requestTimeoutMs must be greater than zero and at most 30000.");
    const options = { timeout: Duration.millis(timeout) };
    const raw = yield* Effect.try({
      try: () => structuredClone({ ...params }),
      catch: () => new RexPolicyError({ message: "Parameters cannot be safely copied." }),
    });
    const serialized = yield* Effect.try({
      try: () => JSON.stringify(raw),
      catch: () => new RexPolicyError({ message: "Parameters must be JSON-serializable." }),
    });
    if (Buffer.byteLength(serialized, "utf8") > 65_536)
      return yield* fail("Encoded parameters exceed 65536 bytes.");
    delete raw.requestTimeoutMs;
    if (creates.has(operation.name) && ["windows_create", "blocks_split", "blocks_splitBeside", "layers_create"].includes(operation.name))
      raw.focus = false;
    if (["terminals_readFile", "terminals_readTail", "terminals_format", "terminals_blobRead", "terminals_clipboardRead"].includes(operation.name))
      raw.maxBytes ??= operation.name === "terminals_readFile" ? 32_768 : 49_152;
    if (operation.name === "events_waitFor") {
      if (raw.sessionId !== undefined && raw.sessionId !== selection.sessionId)
        return yield* fail("Operation targets a different session.");
      if (!["session", "terminal", "block"].includes(String(raw.source)))
        return yield* fail("events_waitFor requires source session, terminal, or block.");
      if (raw.source !== "session" && typeof raw.blockId !== "string")
        return yield* fail("Terminal and block event waits require an explicit blockId to validate its execution host.");
      raw.sessionId = selection.sessionId;
    }

    // Decode precisely the same schemas that the upstream operation will dispatch.
    const fields = yield* Schema.decodeUnknownEffect(Schema.toType(Schema.Struct(operation.fields)))(raw);
    const input = operation.input
      ? yield* Schema.decodeUnknownEffect(Schema.toType(operation.input))(raw)
      : {};
    const decoded = { ...object(input), ...object(fields) };
    for (const [key, limit] of [["maxBytes", 65_536], ["timeoutMs", 30_000], ["quietForMs", 30_000], ["lines", 2000]] as const) {
      const value = decoded[key];
      if (value !== undefined && (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > limit))
        return yield* fail(`${key} exceeds its policy bound (${limit}).`);
    }
    if (["terminals_format", "terminals_read"].includes(operation.name) && decoded.maxBytes === 0)
      return yield* fail(`${operation.name} requires a positive maxBytes; zero requests the whole output.`);
    if (decoded.sessionId !== undefined && decoded.sessionId !== selection.sessionId)
      return yield* fail("Operation targets a different session.");
    if (operation.name === "blocks_callMethod") {
      const method = decoded.method;
      if (typeof method !== "string") return yield* fail("Missing block method.");
      const matches = Object.keys(rexBlockMethods).filter((key) => key === method || key.endsWith(`.${method}`));
      if (matches.length !== 1) return yield* fail("Unknown or ambiguous block method; classification needed.");
      const named = rexToolOperations.find((candidate) => candidate.method === matches[0]);
      if (!named) return yield* fail("Block method has no classified named operation.");
      const args = decoded.args === undefined ? {} : object(decoded.args);
      if (decoded.args !== undefined && (decoded.args === null || Array.isArray(decoded.args) || typeof decoded.args !== "object"))
        return yield* fail("Block method arguments must be an object.");
      return yield* guardedProgram(named, {
        ...args, sessionId: decoded.sessionId, blockId: decoded.blockId, requestTimeoutMs: timeout,
      }, selection, marks, authorize, isCurrent);
    }

    const rex = yield* RexSdk;
    const sessionId = yield* Schema.decodeUnknownEffect(Schema.toType(SessionId))(selection.sessionId);
    const check = Effect.gen(function* () {
      if (!isCurrent()) return yield* fail("Selection is no longer current.");
      const status = yield* rex.server.status(options);
      if (status.instanceId !== selection.instanceId) return yield* fail("Selected server instance changed.");
      if (serverCreates.has(operation.name)) {
        const serverHost = Option.getOrNull(status.hostId);
        if (selection.hostId === null || serverHost === null || selection.hostId !== serverHost)
          return yield* fail("Creation defaults to the control server's execution host, which is unknown or differs from the selected host. Select that execution host explicitly; remote creator routing is not verified.");
        if (explicitHostIds(decoded).some((id) => typeof id !== "string" || id !== selection.hostId))
          return yield* fail("A creator hostId differs from the selected execution host. Select the intended host explicitly.");
      }
      const view = yield* rex.sessions.view({ sessionId }, options);
      if (view.sessionId !== selection.sessionId) return yield* fail("Selected session changed.");
      const listed = yield* rex.sessions.listBlocks({ sessionId }, options);
      if (decoded.beforeSessionId !== undefined) {
        const sessions = yield* rex.sessions.list(options);
        if (!sessions.sessions.some((session) => session.sessionId === decoded.beforeSessionId))
          return yield* fail("beforeSessionId is not on the selected server.");
      }
      if (decoded.clientId !== undefined) {
        const clients = yield* rex.clients.list({}, options);
        if (!clients.clients.some((client) => client.clientId === decoded.clientId))
          return yield* fail("clientId is not on the selected server.");
      }
      const blocks = new Set(listed.blocks.map((block) => block.blockId as string));
      const blockHosts = new Map(listed.blocks.map((block) =>
        [block.blockId as string, Option.getOrNull(block.hostId)] as const));
      const placed = new Set<string>();
      const windows = new Set<string>();
      const layers = new Map<string, string>();
      const windowBlocks = new Map<string, string[]>();
      const layerBlocks = new Map<string, string[]>();
      for (const window of view.windows) {
        windows.add(window.windowId);
        windowBlocks.set(window.windowId, window.layers.flatMap((layer) => layer.blocks.map((block) => block.blockId)));
        for (const layer of window.layers) {
          layers.set(layer.layerId, window.windowId);
          layerBlocks.set(layer.layerId, layer.blocks.map((block) => block.blockId));
        }
      }
      for (const blockIds of layerBlocks.values())
        for (const id of blockIds) placed.add(id);
      if (operation.name === "targets_resolve" || operation.name === "targets_complete") {
        const context = object(decoded.context);
        const scope = object(decoded.scope);
        if (context.sessionId !== undefined && context.sessionId !== selection.sessionId)
          return yield* fail("Lookup context.sessionId must be the selected session.");
        if (context.blockId !== undefined && (typeof context.blockId !== "string" || !blocks.has(context.blockId)))
          return yield* fail("Lookup context.blockId must belong to the selected session.");
        if (scope.session !== undefined && scope.session !== selection.sessionId)
          return yield* fail("Lookup scope.session must be the full selected session ID.");
        if (scope.window !== undefined && (typeof scope.window !== "string" || !windows.has(scope.window)))
          return yield* fail("Lookup scope.window must be a full window ID in the selected session.");
        if (context.clientId !== undefined) {
          const clients = yield* rex.clients.list({}, options);
          if (!clients.clients.some((client) => client.clientId === context.clientId))
            return yield* fail("Lookup context.clientId is not on the selected server.");
        }
      }
      for (const key of ["blockId", "otherBlockId", "anchorBlockId", "beforeBlockId", "afterBlockId"]) {
        const id = decoded[key];
        if (id !== undefined && (typeof id !== "string" || !blocks.has(id)))
          return yield* fail(`${key} is not in the selected session.`);
      }
      for (const key of ["windowId", "beforeWindowId"]) {
        const id = decoded[key];
        if (id !== undefined && (typeof id !== "string" || !windows.has(id)))
          return yield* fail(`${key} is not in the selected session.`);
      }
      for (const key of ["layerId", "relativeLayerId"]) {
        const id = decoded[key];
        if (id !== undefined && (typeof id !== "string" || !layers.has(id)))
          return yield* fail(`${key} is not in the selected session.`);
      }
      if (typeof decoded.relativeLayerId === "string" && typeof decoded.layerId === "string" &&
          layers.get(decoded.relativeLayerId) !== layers.get(decoded.layerId))
        return yield* fail("Layers must belong to the same window.");
      if (["blocks_split", "blocks_splitBeside"].includes(operation.name) &&
          (typeof decoded.anchorId !== "string" || !placed.has(decoded.anchorId) || decoded.windowId !== undefined))
        return yield* fail("Split requires an explicit placed block anchor; split IDs and focused anchors are not supported.");
      if (typeof decoded.anchorBlockId === "string" && !placed.has(decoded.anchorBlockId))
        return yield* fail("The anchor block must be placed.");
      if (["windows_close", "layers_create"].includes(operation.name) && typeof decoded.windowId !== "string")
        return yield* fail("An explicit windowId is required.");
      if (["blocks_close", "blocks_zoom"].includes(operation.name) &&
          (typeof decoded.blockId !== "string" || decoded.windowId !== undefined))
        return yield* fail("An explicit blockId is required; focused targets are not allowed.");
      if (["blocks_own", "blocks_disown"].includes(operation.name)) {
        if (!Array.isArray(decoded.blockIds) || decoded.blockIds.length === 0 ||
            decoded.blockIds.some((id) => typeof id !== "string" || !blocks.has(id)))
          return yield* fail("An explicit nonempty list of selected-session blockIds is required.");
      }
      const affected = new Set<string>();
      for (const key of ["blockId", "otherBlockId", "anchorBlockId", "beforeBlockId", "afterBlockId", "anchorId"]) {
        if (typeof decoded[key] === "string") affected.add(decoded[key] as string);
      }
      if (Array.isArray(decoded.blockIds))
        for (const id of decoded.blockIds) if (typeof id === "string") affected.add(id);
      if (operation.name === "sessions_destroy") for (const id of blocks) affected.add(id);
      if (policy.category !== "read" && policy.category !== "sensitive read") {
        for (const key of ["windowId", "beforeWindowId"])
          if (typeof decoded[key] === "string")
            for (const id of windowBlocks.get(decoded[key] as string) ?? []) affected.add(id);
        for (const key of ["layerId", "relativeLayerId"])
          if (typeof decoded[key] === "string")
            for (const id of layerBlocks.get(decoded[key] as string) ?? []) affected.add(id);
      }
      const targets = [...affected].sort().map((id) => ({ id, hostId: blockHosts.get(id) ?? null }));
      if (["sessions_destroy", "windows_close", "layers_close"].includes(operation.name) &&
          new Set(targets.map((target) => target.hostId)).size > 1)
        return yield* fail("This parent close affects blocks on multiple or unknown execution hosts; select and close individual host-scoped blocks instead.");
      for (const target of targets) {
        if (selection.hostId === null || target.hostId === null || target.hostId !== selection.hostId)
          return yield* fail(`Block ${target.id} has execution host ${target.hostId ?? "unknown"}, not selected host ${selection.hostId ?? "unknown"}. Select its execution host explicitly with /rex-target; unknown hosts cannot be verified.`);
      }
      return targets;
    });
    const affected = yield* check;
    if (policy.category !== "read") {
      const details = affected.map(({ id, hostId }) => ({
        blockId: id, hostId, status: selection.owned.has(id) ? "task-created" : "pre-existing",
      }));
      const message = JSON.stringify({
        server: selection.server, instanceId: selection.instanceId, sessionId: selection.sessionId,
        selectedHostId: selection.hostId,
        category: policy.category, operation: operation.name, params: decoded, affected: details,
        note: policy.note,
        scope: policy.category === "server config/shutdown" || policy.category === "network/host config" && !operation.name.startsWith("tunnels_")
          ? "Server-wide: this can affect hosts, network access, sessions, or clients beyond the selected session and execution host."
          : operation.name === "sessions_create" || operation.name === "sessions_move"
            ? "Server-wide session creation or ordering; effects are not limited to the selected session."
            : undefined,
      });
      const approved = yield* Effect.tryPromise({
        try: (signal) => authorize(`Rex: ${operation.name}`, message, signal),
        catch: (cause) => new RexPolicyError({ message: `Authorization failed: ${String(cause)}` }),
      });
      if (!approved) return yield* fail("Authorization denied.");
      const after = yield* check;
      if (JSON.stringify(affected) !== JSON.stringify(after))
        return yield* fail("Affected blocks or execution hosts changed during authorization; request approval again.");
    }
    if (!isCurrent()) return yield* fail("Selection is no longer current.");
    const result = yield* operation.program(rex, raw, options, marks).pipe(
      Effect.timeout("35 seconds"),
      Effect.catch((error) => {
        if (policy.category !== "read" && policy.category !== "sensitive read" && error instanceof Error) {
          error.message += " Outcome may be uncertain; inspect state before retrying. No automatic replay.";
        }
        return Effect.fail(error);
      }),
    );
    if (creates.has(operation.name)) {
      const value = object(result);
      if (typeof value.blockId === "string") selection.owned.add(value.blockId);
      if (Array.isArray(value.blockIds)) for (const id of value.blockIds)
        if (typeof id === "string") selection.owned.add(id);
    }
    const mutation = policy.category !== "read" && policy.category !== "sensitive read";
    const identifiers = Object.fromEntries(
      ["sessionId", "windowId", "layerId", "blockId"].flatMap((key) => {
        const value = object(result)[key];
        return typeof value === "string" ? [[key, value.slice(0, 128)]] : [];
      }),
    );
    const resultFailure = mutation
      ? `Operation completed, but its result could not be delivered within the output contract. Do not repeat the mutation. Inspect state using ${JSON.stringify(identifiers)}.`
      : "Result could not be delivered within the output contract; use a narrower read.";
    const encoded = yield* Effect.try({
      try: () => encodeRexToolResult(result),
      catch: () => new RexPolicyError({ message: resultFailure }),
    });
    if (Buffer.byteLength(JSON.stringify(encoded), "utf8") > 65_536)
      return yield* fail(`${resultFailure} Encoded result exceeds 65536 bytes.`);
    return encoded;
  });
}
