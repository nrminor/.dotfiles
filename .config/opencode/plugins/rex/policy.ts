import { isAbsolute, normalize } from "node:path";
import { Cause, Duration, Effect, Option, Schema } from "effect";
import { RexSdk, SessionId, rexBlockMethods, type IRexSdk, type RexRequestOptions, type RexOperationError, type ViewLayoutNode } from "rex-sdk";
import { RexPreparationError, RexToolFailure, rexToolOperations, type RexPreparedParameters, type RexToolOperation, type TargetingEvidence } from "./vendor/rex-tool-operations.ts";
import type { RexMarkStore } from "./vendor/rex-tool-marks.ts";
import type { RexToolJson } from "./vendor/rex-tool-schemas.ts";

export interface Selection {
  readonly server: string;
  readonly sessionId: string;
  readonly instanceId: string;
  readonly hostId: string | null;
  readonly blockId: string | null;
  readonly owned: Set<string>;
}

export interface Approval {
  readonly action: string;
  readonly resources: readonly string[];
  readonly message: string;
  readonly confirm: boolean;
}

export type Category = "read" | "sensitive read" | "execution/input" | "layout" |
  "close/destroy" | "server config/shutdown" | "network/host config" | "file transfer";
export interface OperationPolicy {
  readonly category: Category;
  readonly note?: string;
}

const groups: ReadonlyArray<readonly [Category, readonly string[]]> = [
  ["read", [
    "sessions_view", "sessions_list", "sessions_listBlocks", "sessions_listClients", "sessions_help",
    "server_status", "server_version", "server_whoami", "server_help", "server_apple_privacyStatus",
    "blocks_describe", "terminals_waitForOutput", "terminals_mark", "terminals_waitForQuiet",
    "terminals_readTail", "terminals_waitForExit", "terminals_read", "terminals_format",
    "terminals_size", "terminals_title", "terminals_pwd", "terminals_process", "terminals_modes",
    "terminals_inputMode", "terminals_programStatus", "terminals_ports", "tunnels_info",
    "clients_list", "clients_inspect", "targets_resolve", "targets_complete", "hosts_list",
     "creators_list", "clients_keymap", "resources_status", "resources_list", "requests_status",
  ]],
  ["sensitive read", [
    "events_waitFor", "events_stream", "terminals_blobRead", "terminals_listDir",
    "terminals_clipboardRead", "terminals_readFile", "terminals_stream", "terminals_activity",
    "terminals_watch", "terminals_download", "sessions_watchView",
    "resources_read", "requests_list", "requests_read",
  ]],
  ["execution/input", [
    "terminals_writeLine", "terminals_write", "terminals_pasteFiles", "terminals_pasteFileFromPath", "blocks_sendEvent",
    "blocks_callMethod", "clients_setScript", "clients_action", "clients_key", "clients_perform",
    "clients_reply", "sessions_create", "windows_create", "blocks_splitBeside", "blocks_split",
    "blocks_create", "layers_create", "clients_servePerformRequests", "clients_serveCallRequests",
    "resources_write", "resources_end", "resources_reply", "requests_reply",
  ]],
  ["layout", [
    "sessions_setLabel", "sessions_move", "windows_focus", "windows_focusNext",
    "windows_focusPrevious", "windows_move", "windows_setLabel", "blocks_move", "blocks_swap",
    "blocks_zoom", "blocks_detach", "blocks_float", "blocks_focus", "blocks_focusDirection",
    "blocks_focusNext", "blocks_focusPrevious", "blocks_resize", "blocks_setLabel", "blocks_own",
    "blocks_disown", "layers_raise", "layers_lower", "layers_resize", "layers_setState",
    "terminals_resize", "terminals_setTheme", "clients_setLabel",
  ]],
  ["close/destroy", [
    "sessions_destroy", "windows_close", "blocks_close", "layers_close", "terminals_clear",
    "terminals_reset", "resources_stop", "requests_stop",
  ]],
  ["server config/shutdown", ["server_reloadConfig", "server_stop", "server_apple_grantFileAccess"]],
  ["file transfer", ["terminals_downloadToFile"]],
  ["network/host config", [
    "server_tailscale_enable", "server_tailscale_disable", "server_tailscale_login",
    "server_tailscale_logout", "server_tailscale_rename", "tunnels_createDial",
    "tunnels_createListen", "hosts_put", "hosts_remove", "tunnels_openStream",
    "tunnels_connections", "tunnels_forwardLocal", "tunnels_forwardRemote", "resources_accept",
  ]],
];

const notes: Readonly<Record<string, string>> = {
  server_stop: "Stops the server and all sessions, including unrelated work.",
  server_reloadConfig: "Reloads server-wide configuration and Lua behavior.",
  sessions_create: "Creates a separate session; it does not change the selected session.",
  windows_create: "Layouts can execute commands. Focus is false, but the first window can become active.",
  clients_keymap: "Supplying actions changes the stored client action list.",
  events_stream: "Server events may expose content from unrelated sessions and hosts.",
};

export const operationPolicy: Readonly<Record<string, OperationPolicy>> = Object.fromEntries(
  groups.flatMap(([category, names]) => names.map((name) => [name, { category, note: notes[name] }])),
);

export class RexPolicyError extends Schema.TaggedError<RexPolicyError>()(
  "RexPolicyError", { message: Schema.String },
) {}

const fail = (message: string) => Effect.fail(new RexPolicyError({ message }));
const creates = new Set(["windows_create", "blocks_split", "blocks_splitBeside", "blocks_create", "layers_create", "tunnels_createDial", "tunnels_createListen"]);
const parentCloses = new Set(["sessions_destroy", "windows_close", "layers_close"]);
const relativeFocus = new Set(["windows_focusNext", "windows_focusPrevious", "blocks_focusDirection", "blocks_focusNext", "blocks_focusPrevious"]);
const longRunning = new Set([
  "terminals_stream", "terminals_activity", "terminals_watch", "terminals_download",
  "terminals_downloadToFile", "sessions_watchView", "events_stream", "tunnels_openStream",
  "tunnels_connections", "tunnels_forwardLocal", "tunnels_forwardRemote",
  "clients_servePerformRequests", "clients_serveCallRequests",
]);

/** Only routing hints are needed before resolving defaults; final arguments decode in prepare. */
const RoutingHints = Schema.Struct({
  blockId: Schema.optionalKey(Schema.String),
  anchorId: Schema.optionalKey(Schema.String),
  windowId: Schema.optionalKey(Schema.String),
});

function layoutReferences(node: ViewLayoutNode): { blocks: string[]; splits: string[] } {
  const blocks = Option.isSome(node.blockId) ? [node.blockId.value] : [];
  if (Option.isNone(node.split)) return { blocks, splits: [] };
  const { splitId, before, after } = node.split.value;
  const left = layoutReferences(before);
  const right = layoutReferences(after);
  return { blocks: [...blocks, ...left.blocks, ...right.blocks], splits: [splitId, ...left.splits, ...right.splits] };
}

const observeSelection = Effect.fn("policy.observeSelection")(function* (
  rex: IRexSdk, selection: Selection, sessionId: typeof SessionId.Type,
  options: RexRequestOptions, isCurrent: () => boolean,
) {
  if (!isCurrent()) return yield* fail("Selection is no longer current.");
  const status = yield* rex.server.status(options);
  if (status.instanceId !== selection.instanceId) return yield* fail("Selected server instance changed.");
  const view = yield* rex.sessions.view({ sessionId }, options);
  if (view.sessionId !== selection.sessionId) return yield* fail("Selected session changed.");
  const listed = yield* rex.sessions.listBlocks({ sessionId }, options);
  return { view, listed };
});
type Observation = Effect.Success<ReturnType<typeof observeSelection>>;

const resolveDefaultTargets = Effect.fn("policy.resolveDefaultTargets")(function* (
  name: string, raw: Record<string, unknown>, hints: typeof RoutingHints.Type,
  selection: Selection, { view, listed }: Observation,
) {
  const blocks = new Map(listed.blocks.map((block): [string, typeof block] => [block.blockId, block]));
  const windows = new Map(view.windows.map((window): [string, typeof window] => [window.windowId, window]));
  const selectedBlock = selection.blockId ? blocks.get(selection.blockId) : undefined;
  const selectedWindow = selectedBlock ? Option.getOrNull(selectedBlock.windowId) : null;
  const activeWindow = Option.getOrNull(view.activeWindowId);
  const defaultWindow = selectedWindow ?? activeWindow;
  if (hints.windowId !== undefined && !windows.has(hints.windowId))
    return yield* fail("windowId is not in the selected session.");
  if (["windows_close", "layers_create"].includes(name) && hints.windowId === undefined && defaultWindow)
    raw.windowId = defaultWindow;
  if (["blocks_close", "blocks_zoom", "blocks_split", "blocks_splitBeside"].includes(name)) {
    const split = name === "blocks_split" || name === "blocks_splitBeside";
    const target = split ? hints.anchorId : hints.blockId;
    if (target === undefined) {
      const windowId = hints.windowId ?? defaultWindow;
      const window = windowId ? windows.get(windowId) : undefined;
      const blockId = hints.windowId === undefined && selection.blockId
        ? selection.blockId : window ? Option.getOrNull(window.focusedBlockId) : null;
      if (blockId) {
        if (split) raw.anchorId = blockId;
        else raw.blockId = blockId;
        delete raw.windowId;
      }
    }
  }
});

const validateObservation = Effect.fn("policy.validateObservation")(function* (
  rex: IRexSdk, options: RexRequestOptions, selection: Selection, name: string,
  facts: TargetingEvidence, { view, listed }: Observation,
) {
  const blocks = new Map(listed.blocks.map((block): [string, typeof block] => [block.blockId, block]));
  const windows = new Map(view.windows.map((window): [string, typeof window] => [window.windowId, window]));
  const layers = new Map(view.windows.flatMap((window) => window.layers.map((layer): [string, typeof layer] => [layer.layerId, layer])));
  const layerWindows = new Map(view.windows.flatMap((window) =>
    window.layers.map((layer): [string, string] => [layer.layerId, window.windowId])));
  const references = (layer: typeof view.windows[number]["layers"][number]) => {
    const layout = Option.isSome(layer.layout) ? layoutReferences(layer.layout.value) : { blocks: [], splits: [] };
    return { blocks: [...layer.blocks.map((block) => block.blockId), ...layout.blocks], splits: layout.splits };
  };
  const anchors = new Set<string>([...blocks.keys(), ...[...layers.values()].flatMap((layer) => references(layer).splits)]);
  for (const key of ["blockId", "otherBlockId", "anchorBlockId", "beforeBlockId", "afterBlockId"] as const) {
    const id = facts[key];
    if (id !== undefined && !blocks.has(id)) return yield* fail(`${key} is not in the selected session.`);
  }
  for (const key of ["windowId", "beforeWindowId"] as const) {
    const id = facts[key];
    if (id !== undefined && !windows.has(id)) return yield* fail(`${key} is not in the selected session.`);
  }
  for (const key of ["layerId", "relativeLayerId"] as const) {
    const id = facts[key];
    if (id !== undefined && !layers.has(id)) return yield* fail(`${key} is not in the selected session.`);
  }
  if (facts.layerId !== undefined && facts.relativeLayerId !== undefined &&
      layerWindows.get(facts.layerId) !== layerWindows.get(facts.relativeLayerId))
    return yield* fail("Layers must belong to the same window.");
  if (facts.beforeSessionId !== undefined) {
    const sessions = yield* rex.sessions.list(options);
    if (!sessions.sessions.some((session) => session.sessionId === facts.beforeSessionId))
      return yield* fail("beforeSessionId is not on the selected server.");
  }
  if (facts.anchorId !== undefined && !anchors.has(facts.anchorId))
    return yield* fail("anchorId is not in the selected session tree.");
  if (["blocks_split", "blocks_splitBeside"].includes(name) && facts.anchorId === undefined && facts.windowId === undefined)
    return yield* fail("A split requires an explicit anchorId or windowId.");
  if (["windows_close", "layers_create"].includes(name) && facts.windowId === undefined)
    return yield* fail("An explicit windowId is required.");
  if (["blocks_close", "blocks_zoom"].includes(name) && facts.blockId === undefined)
    return yield* fail("An explicit blockId is required.");
  if (facts.blockIds?.some((id) => !blocks.has(id)))
    return yield* fail("blockIds must belong to the selected session.");
  const context = facts.context;
  const scope = facts.scope;
  if ((context?.sessionId !== undefined && context.sessionId !== selection.sessionId) ||
      (scope?.session !== undefined && scope.session !== selection.sessionId))
    return yield* fail("Lookup scope must use the selected session.");
  if (context?.blockId !== undefined && !blocks.has(context.blockId))
    return yield* fail("Lookup context block is outside the selected session.");
  if (scope?.window !== undefined && !windows.has(scope.window))
    return yield* fail("Lookup scope window is outside the selected session.");
  if (facts.clientId !== undefined || context?.clientId !== undefined) {
    const clients = yield* rex.clients.list({}, options);
    for (const id of [facts.clientId, context?.clientId]) {
      if (id !== undefined && !clients.clients.some((client) => client.clientId === id))
        return yield* fail("clientId is not on the selected server.");
    }
  }
  const affected = new Set<string>();
  for (const key of ["blockId", "otherBlockId", "anchorBlockId", "beforeBlockId", "afterBlockId", "anchorId"] as const) {
    const id = facts[key];
    if (id !== undefined && blocks.has(id)) affected.add(id);
  }
  if (facts.blockIds) for (const id of facts.blockIds) affected.add(id);
  if (name === "sessions_destroy") for (const id of blocks.keys()) affected.add(id);
  if (name === "windows_close" && facts.windowId !== undefined) {
    const window = windows.get(facts.windowId);
    if (window) for (const layer of window.layers) for (const id of references(layer).blocks) affected.add(id);
  }
  if (name === "layers_close" && facts.layerId !== undefined) {
    const layer = layers.get(facts.layerId);
    if (layer) for (const id of references(layer).blocks) affected.add(id);
  }
  const targets = [...affected].sort().map((id) => ({
    blockId: id, hostId: Option.getOrNull(blocks.get(id)!.hostId),
    creator: Option.getOrNull(blocks.get(id)!.creatorName), owned: selection.owned.has(id),
  }));
  if (!parentCloses.has(name)) for (const target of targets) {
    if (!selection.hostId || !target.hostId || target.hostId !== selection.hostId)
      return yield* fail(`Block ${target.blockId} is not on the selected known execution host.`);
  }
  const creatorEvidence: Array<{ flavor: string; creator: string; host: string }> = [];
  if (facts.creatorFlavors !== undefined) {
    const explicitHosts = facts.creatorHostClaims ?? [];
    if (explicitHosts.some((host) => typeof host !== "string" || host !== selection.hostId))
      return yield* fail("Explicit creator host must be the selected execution host.");
    const flavors = facts.creatorFlavors.length === 0 ? ["com.superlogical.terminal.shell"] : facts.creatorFlavors;
    const creators = yield* rex.creators.list(options);
    for (const flavor of flavors) {
      const matches = creators.creators.filter((creator) => creator.flavors.some((item) => item.flavor === flavor));
      if (matches.length !== 1) return yield* fail(`Creator flavor ${String(flavor)} is unknown or ambiguous.`);
      const host = Option.getOrNull(matches[0]!.hostId);
      if (!host || !selection.hostId || host !== selection.hostId)
        return yield* fail(`Creator flavor ${String(flavor)} is not on the selected known host.`);
      creatorEvidence.push({ flavor, creator: matches[0]!.name, host });
    }
  }
  return { targets, creators: creatorEvidence };
});
type ValidatedEvidence = Effect.Success<ReturnType<typeof validateObservation>>;

const classifyAction = Effect.fn("policy.classifyAction")(function* (
  rex: IRexSdk, options: RexRequestOptions, name: string, facts: TargetingEvidence,
) {
  if (name !== "clients_action" || facts.action === undefined) return [];
  const creators = yield* rex.creators.list(options);
  const matches: Array<{ creator: string; method: string; name: string; category: Category }> = [];
  for (const creator of creators.creators) {
    for (const [method, descriptor] of Object.entries(Option.getOrElse(creator.api.methods, () => ({})))) {
      if (!descriptor.actions.some((action) => `${creator.name}.${action.name}` === facts.action)) continue;
      const named = rexToolOperations.find((candidate) => candidate.method === `${creator.name}.${method}`);
      if (named) matches.push({ creator: creator.name, method, name: named.name, category: operationPolicy[named.name]!.category });
    }
  }
  return matches.sort((a, b) => `${a.creator}.${a.method}`.localeCompare(`${b.creator}.${b.method}`));
});
type ActionClassification = Effect.Success<ReturnType<typeof classifyAction>>;

const approveRequest = Effect.fn("policy.approveRequest")(function* <E>(
  name: string, policy: OperationPolicy, selection: Selection, facts: TargetingEvidence,
  decoded: RexPreparedParameters, evidence: ValidatedEvidence, actionClassification: ActionClassification,
  authorize: (approval: Approval) => Effect.Effect<void, E>,
) {
  const affected = evidence.targets;
  const category = name === "clients_keymap" && facts.keymapActionsPresent ? "execution/input" : policy.category;
  const resources = [
    `operation:${name}`, `server:${selection.server}`, `instance:${selection.instanceId}`, `session:${selection.sessionId}`,
    ...affected.map((target) => `host:${target.hostId ?? "unknown"}/block:${target.blockId}`),
  ];
  if (selection.hostId) resources.push(`host:${selection.hostId}`);
  if (facts.handle !== undefined) resources.push(`handle:${facts.handle}`);
  if (facts.clientId !== undefined) resources.push(`client:${facts.clientId}`);
  if (name === "terminals_downloadToFile") {
    const destination = facts.destination;
    if (destination === undefined) return yield* fail("destination is required.");
    resources.push(`server-file:${destination}`);
    yield* authorize({
      action: "edit", resources: [destination], confirm: false,
      message: `Download to this path on the OpenCode server: ${destination}`,
    });
  }
  if (name === "terminals_pasteFileFromPath") {
    const source = facts.sourcePath;
    if (source === undefined) return yield* fail("sourcePath is required.");
    resources.push(`server-file:${source}`);
    yield* authorize({
      action: "read", resources: [source], confirm: false,
      message: `Read this path on the OpenCode server and send it to Rex: ${source}`,
    });
  }
  const confirm = (name === "events_stream" && facts.server === "all") ||
    category === "close/destroy" || category === "server config/shutdown" || category === "file transfer" ||
    category === "network/host config" || (category === "execution/input" &&
     (affected.some((target) => !target.owned) || !creates.has(name)));
  for (const canonical of actionClassification) {
    yield* authorize({
      action: `rex.${canonical.category}`,
      resources: [...resources.filter((resource) => !resource.startsWith("operation:")), `operation:${canonical.name}`],
      message: JSON.stringify({ operation: name, canonicalOperation: canonical.name, params: decoded, affected }),
      confirm: canonical.category === "close/destroy",
    });
  }
  yield* authorize({
    action: `rex.${category}`, resources,
    message: JSON.stringify({ operation: name, params: decoded, affected, note: policy.note,
      scope: relativeFocus.has(name) ? "Selected session's current focus; no pane anchor is guaranteed." :
        "Exact request; server, client and custom actions may have collateral effects." }),
    confirm,
  });
});

/** Authorizes the exact request and dispatches it once against the selected instance. */
export function guardedProgram<AuthorizationError>(
  operation: RexToolOperation,
  params: Readonly<Record<string, unknown>>,
  selection: Selection,
  marks: RexMarkStore,
  authorize: (approval: Approval) => Effect.Effect<void, AuthorizationError>,
  isCurrent: () => boolean,
): Effect.Effect<RexToolJson, AuthorizationError | RexPolicyError | RexOperationError | RexPreparationError | RexToolFailure | Schema.SchemaError | Cause.TimeoutError, RexSdk> {
  return Effect.gen(function* () {
    const policy = operationPolicy[operation.name];
    if (!policy) return yield* fail(`Unclassified operation: ${operation.name}`);
    if (!isCurrent()) return yield* fail("Selection is no longer current.");
    const timeout = params.requestTimeoutMs ?? 30_000;
    if (typeof timeout !== "number" || !Number.isFinite(timeout) || timeout <= 0 || timeout > 30_000)
      return yield* fail("requestTimeoutMs must be greater than zero and at most 30000.");
    const raw = yield* Effect.try({
      try: () => structuredClone({ ...params }),
      catch: () => new RexPolicyError({ message: "Parameters cannot be copied." }),
    });
    delete raw.requestTimeoutMs;
    const localPath = operation.name === "terminals_downloadToFile" ? "destination"
      : operation.name === "terminals_pasteFileFromPath" ? "sourcePath" : undefined;
    if (localPath) {
      const path = raw[localPath];
      if (typeof path !== "string" || !isAbsolute(path))
        return yield* fail(`${localPath} must be an absolute path on the OpenCode server.`);
      raw[localPath] = normalize(path);
    }
    const serialized = yield* Effect.try({
      try: () => JSON.stringify(raw),
      catch: () => new RexPolicyError({ message: "Parameters must be JSON-serializable." }),
    });
    if (Buffer.byteLength(serialized, "utf8") > 65_536) return yield* fail("Parameters exceed 65536 bytes.");
    if (raw.sessionId !== undefined && raw.sessionId !== selection.sessionId)
      return yield* fail("Operation targets a different session.");
    if (operation.name !== "sessions_create") raw.sessionId ??= selection.sessionId;
    if (operation.name === "events_stream") {
      raw.sessionIds ??= [selection.sessionId];
      if (!Array.isArray(raw.sessionIds) || raw.sessionIds.some((id) => id !== selection.sessionId))
        return yield* fail("Event sessionIds must use the explicitly selected session.");
    }
    if ((operation.name.startsWith("terminals_") || operation.name.startsWith("blocks_")) &&
        !relativeFocus.has(operation.name) && raw.blockId === undefined && raw.windowId === undefined && selection.blockId !== null &&
        ("blockId" in operation.fields || ["blocks_close", "blocks_zoom", "blocks_callMethod",
          "blocks_sendEvent", "blocks_describe", "blocks_focus", "blocks_detach", "blocks_float",
          "blocks_resize", "blocks_setLabel"].includes(operation.name)))
      raw.blockId = selection.blockId;
    if (["windows_create", "blocks_split", "blocks_splitBeside", "layers_create"].includes(operation.name))
      raw.focus = false;
    if (["terminals_readFile", "terminals_readTail", "terminals_format", "terminals_blobRead", "terminals_clipboardRead"].includes(operation.name))
      raw.maxBytes ??= operation.name === "terminals_readFile" ? 32_768 : 49_152;
    const hints = yield* Schema.decodeUnknownEffect(RoutingHints)(raw);
    const options = { timeout: Duration.millis(timeout) };
    const rex = yield* RexSdk;
    const sessionId = yield* Schema.decodeUnknownEffect(Schema.toType(SessionId))(selection.sessionId);

    const initial = yield* observeSelection(rex, selection, sessionId, options, isCurrent);
    yield* resolveDefaultTargets(operation.name, raw, hints, selection, initial);
    const prepared = yield* operation.prepare(raw);
    const decoded = prepared.parameters;
    const facts = prepared.targeting;
    for (const [key, limit] of [["maxBytes", 65_536], ["timeoutMs", 30_000], ["quietForMs", 30_000], ["lines", 2000]] as const) {
      if (longRunning.has(operation.name) && key === "timeoutMs") continue;
      const value = facts[key];
      if (value !== undefined && (!Number.isFinite(value) || value < 0 || value > limit))
        return yield* fail(`${key} exceeds its bound (${limit}).`);
    }
    if (["terminals_format", "terminals_read"].includes(operation.name) && facts.maxBytes === 0)
      return yield* fail("A positive maxBytes is required.");
    const evidence = yield* validateObservation(rex, options, selection, operation.name, facts, initial);

    if (operation.name === "blocks_callMethod" && facts.method !== undefined) {
      const listed = yield* rex.sessions.listBlocks({ sessionId }, options);
      const block = listed.blocks.find((item) => item.blockId === facts.blockId);
      const creator = block ? Option.getOrNull(block.creatorName) : null;
      if (!creator && Object.keys(rexBlockMethods).some((key) =>
        key === facts.method || key.endsWith(`.${facts.method}`)))
        return yield* fail("The block creator is unknown; a known method cannot be classified safely.");
      const keys = Object.keys(rexBlockMethods).filter((key) => key === facts.method ||
        (creator !== null && key === `${creator}.${facts.method}`));
      if (keys.length === 1) {
        if (!creator || keys[0] !== `${creator}.${facts.method.replace(`${creator}.`, "")}`)
          return yield* fail("Block method does not match the target creator.");
        const named = rexToolOperations.find((candidate) => candidate.method === keys[0]);
        if (named) {
          const codec = rexBlockMethods[keys[0] as keyof typeof rexBlockMethods].args;
          const args = yield* Schema.decodeUnknownEffect(codec)(facts.methodArgs ?? {});
          return yield* guardedProgram(named, {
            ...args, sessionId: selection.sessionId, blockId: facts.blockId, requestTimeoutMs: timeout,
          }, selection, marks, authorize, isCurrent);
        }
        if (keys[0]!.endsWith(".download_begin") || keys[0]!.endsWith(".upload_begin"))
          return yield* fail("Low-level transfer tickets are internal; use the managed download or upload workflow.");
      }
    }
    const executePrepared = () => prepared.execute(rex, options, marks);
    const actionClassification = yield* classifyAction(rex, options, operation.name, facts);
    yield* approveRequest(operation.name, policy, selection, facts, decoded, evidence, actionClassification, authorize);
    const recheck = Effect.gen(function* () {
      const observation = yield* observeSelection(rex, selection, sessionId, options, isCurrent);
      const after = yield* validateObservation(rex, options, selection, operation.name, facts, observation);
      if (JSON.stringify(evidence) !== JSON.stringify(after))
        return yield* fail("Targets or creators changed during authorization.");
      if (operation.name === "clients_action" &&
          JSON.stringify(actionClassification) !== JSON.stringify(yield* classifyAction(rex, options, operation.name, facts)))
        return yield* fail("Action classification changed during authorization.");
    });
    yield* recheck;
    const result = yield* executePrepared().pipe(Effect.timeout("35 seconds"));
    if (creates.has(operation.name)) {
      const created = Schema.decodeUnknownOption(Schema.Struct({
        blockId: Schema.optionalKey(Schema.String),
        blockIds: Schema.optionalKey(Schema.Array(Schema.String)),
      }))(result);
      if (Option.isSome(created)) {
        if (created.value.blockId !== undefined) selection.owned.add(created.value.blockId);
        if (created.value.blockIds) for (const id of created.value.blockIds) selection.owned.add(id);
      }
    }
    return result;
  });
}
