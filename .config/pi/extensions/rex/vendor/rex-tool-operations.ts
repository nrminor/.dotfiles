/**
 * The Rex operations exposed to codemode, one tool per SDK operation.
 *
 * Tool names mirror the SDK path: `rex.terminals.writeLine` → `rex_terminals_writeLine`. Every
 * operation is deferred: none is listed in the codemode description, and scripts find them
 * through `rex_search`. {@link rexToolExclusions} names every SDK operation left out, and why.
 */
import { Array as Arr, Effect, Option, Schema } from "effect";
import type { ToolAnnotations } from "@earendil-works/pi-coding-agent";
import {
  AnchorId,
  BlockId,
  RexLayoutNode,
  RexRequestTimeout,
  SessionId,
  TunnelDialOptions,
  TunnelListenOptions,
  WindowId,
  rexBlockMethods,
  rexWireMethods,
  type IRexSdk,
  type RexBlockMethod,
  type RexBlockMethodArgs,
  type RexBlockMethodResult,
  type RexEvent,
  type RexMethodInput,
  type RexMethodResult,
  type RexOperationError,
  type RexRequestOptions,
  type RexWireMethod,
} from "rex-sdk";
import type { RexMarkStore } from "./rex-tool-marks.ts";

/** One SDK operation exposed as the codemode tool `rex_<name>`. */
export interface RexToolOperation {
  /** SDK path with `_` separators, such as `terminals_writeLine`. */
  readonly name: string;
  /** Model-facing description: what it does and returns, then the branch or next step. */
  readonly description: string;
  readonly annotations: ToolAnnotations;
  /** The server or block method the operation calls, when it calls exactly one. */
  readonly method: string | undefined;
  /** Named fields for SDK positional arguments; they win over input fields of the same name. */
  readonly fields: Schema.Struct.Fields;
  /** The SDK input object whose fields are top-level tool fields, or undefined for none. */
  readonly input: Schema.Top | undefined;
  /** Result schema, or `"void"` for operations that resolve to nothing. */
  readonly output: Schema.Top | "void";
  /** Decodes the flat tool parameters and runs the SDK operation. */
  readonly program: (
    rex: IRexSdk,
    params: { readonly [key: string]: unknown },
    options: RexRequestOptions,
    marks: RexMarkStore,
  ) => Effect.Effect<unknown, unknown>;
}

interface RexToolOperationBase {
  readonly name: string;
  readonly description: string;
  readonly method?: string;
  readonly readOnly?: boolean;
  readonly destructive?: boolean;
  readonly output: Schema.Top | "void";
}

function annotationsOf(spec: RexToolOperationBase): ToolAnnotations {
  return {
    readOnlyHint: spec.readOnly ?? false,
    ...(spec.readOnly === true ? {} : { destructiveHint: spec.destructive ?? false }),
    openWorldHint: false,
  };
}

function withoutUndefined(params: { readonly [key: string]: unknown }): {
  [key: string]: unknown;
} {
  return Object.fromEntries(Object.entries(params).filter(([, value]) => value !== undefined));
}

/** An operation whose parameters are all named fields. */
function operation<const Fields extends Schema.Struct.Fields>(
  spec: RexToolOperationBase & {
    readonly fields: Fields;
    readonly run: (
      rex: IRexSdk,
      fields: Schema.Struct<Fields>["Type"],
      options: RexRequestOptions,
      marks: RexMarkStore,
    ) => Effect.Effect<unknown, unknown>;
  },
): RexToolOperation {
  const decodeFields = Schema.decodeUnknownEffect(Schema.toType(Schema.Struct(spec.fields)));
  return {
    name: spec.name,
    description: spec.description,
    annotations: annotationsOf(spec),
    method: spec.method,
    fields: spec.fields,
    input: undefined,
    output: spec.output,
    program: (rex, params, options, marks) =>
      Effect.flatMap(decodeFields(params), (fields) => spec.run(rex, fields, options, marks)),
  };
}

/** An operation with named fields beside the fields of the SDK's input object. */
function inputOperation<const Fields extends Schema.Struct.Fields, Input extends Schema.Top>(
  spec: RexToolOperationBase & {
    readonly fields: Fields;
    readonly input: Input;
    readonly run: (
      rex: IRexSdk,
      fields: Schema.Struct<Fields>["Type"],
      input: Input["Type"],
      options: RexRequestOptions,
    ) => Effect.Effect<unknown, unknown>;
  },
): RexToolOperation {
  const decodeFields = Schema.decodeUnknownEffect(Schema.toType(Schema.Struct(spec.fields)));
  const decodeInput = Schema.decodeUnknownEffect(Schema.toType(spec.input));
  return {
    name: spec.name,
    description: spec.description,
    annotations: annotationsOf(spec),
    method: spec.method,
    fields: spec.fields,
    input: spec.input,
    output: spec.output,
    program: (rex, params, options) =>
      Effect.gen(function* () {
        const fields = yield* decodeFields(params);
        // The input ignores keys it doesn't declare. A field that overrides an input key, such as
        // a typed layout over the wire's untyped one, still satisfies the input's own schema.
        const input = yield* decodeInput(withoutUndefined(params));
        return yield* spec.run(rex, fields, input, options);
      }),
  };
}

/** A server method that takes its documented arguments as one input object. */
function method<Method extends RexWireMethod>(spec: {
  readonly name: string;
  readonly description: string;
  readonly method: Method;
  readonly readOnly?: boolean;
  readonly destructive?: boolean;
  readonly run: (
    rex: IRexSdk,
    input: RexMethodInput<Method>,
    options: RexRequestOptions,
  ) => Effect.Effect<RexMethodResult<Method>, RexOperationError>;
}): RexToolOperation {
  const schemas = rexWireMethods[spec.method];
  return inputOperation({
    ...spec,
    fields: {},
    input: schemas.input,
    output: schemas.result,
    run: (rex, _fields, input, options) => spec.run(rex, input, options),
  });
}

/** A server method without arguments. */
function noInputMethod<Method extends RexWireMethod>(spec: {
  readonly name: string;
  readonly description: string;
  readonly method: Method;
  readonly readOnly?: boolean;
  readonly destructive?: boolean;
  readonly run: (
    rex: IRexSdk,
    options: RexRequestOptions,
  ) => Effect.Effect<RexMethodResult<Method>, RexOperationError>;
}): RexToolOperation {
  return operation({
    ...spec,
    fields: {},
    output: rexWireMethods[spec.method].result,
    run: (rex, _fields, options) => spec.run(rex, options),
  });
}

/** The fields that name a block for a block method. */
const blockTarget = { sessionId: SessionId, blockId: BlockId };

/** A block method: `sessionId` and `blockId` beside the method's own arguments. */
function blockMethod<Method extends RexBlockMethod>(spec: {
  readonly name: string;
  readonly description: string;
  readonly method: Method;
  readonly readOnly?: boolean;
  readonly destructive?: boolean;
  readonly run: (
    rex: IRexSdk,
    target: Schema.Struct<typeof blockTarget>["Type"],
    args: RexBlockMethodArgs<Method>,
    options: RexRequestOptions,
  ) => Effect.Effect<RexBlockMethodResult<Method>, RexOperationError>;
}): RexToolOperation {
  const schemas = rexBlockMethods[spec.method];
  return inputOperation({
    ...spec,
    fields: blockTarget,
    input: schemas.args,
    output: schemas.result,
    run: (rex, target, args, options) => spec.run(rex, target, args, options),
  });
}

/** A block method without arguments of its own. */
function blockNoArgsMethod<Method extends RexBlockMethod>(spec: {
  readonly name: string;
  readonly description: string;
  readonly method: Method;
  readonly readOnly?: boolean;
  readonly destructive?: boolean;
  readonly run: (
    rex: IRexSdk,
    target: Schema.Struct<typeof blockTarget>["Type"],
    options: RexRequestOptions,
  ) => Effect.Effect<RexBlockMethodResult<Method>, RexOperationError>;
}): RexToolOperation {
  return operation({
    ...spec,
    fields: blockTarget,
    output: rexBlockMethods[spec.method].result,
    run: (rex, target, options) => spec.run(rex, target, options),
  });
}

/** Required `timeoutMs` of every wait tool. */
const waitTimeout = {
  timeoutMs: Schema.Finite.check(Schema.isGreaterThanOrEqualTo(0)).annotate({
    description: "How long to wait; the tool resolves to { timedOut: true } when it passes.",
  }),
};

/** `{ timedOut: true } | { timedOut: false, [key]: value }`, the result of every wait tool. */
function waitOutcomeSchema(key: string, value: Schema.Top): Schema.Top {
  return Schema.Union([
    Schema.Struct({ timedOut: Schema.Literal(true) }),
    Schema.Struct({ timedOut: Schema.Literal(false), [key]: value }),
  ]);
}

/**
 * Resolves a wait to `{ timedOut: true }` when its own deadline passes. Only the
 * `RexRequestTimeout` the wait raises for itself counts: a request inside the wait that times out
 * still rejects.
 */
function waitOutcome<A, E>(
  key: string,
  waitName: string,
  effect: Effect.Effect<A, E | RexRequestTimeout>,
): Effect.Effect<{ readonly [key: string]: unknown }, E | RexRequestTimeout> {
  return effect.pipe(
    Effect.map((value) => ({ timedOut: false, [key]: value })),
    Effect.catchIf(
      (error): error is RexRequestTimeout =>
        error instanceof RexRequestTimeout && error.method === waitName,
      () => Effect.succeed({ timedOut: true }),
    ),
  );
}

const TerminalExit = Schema.Struct({
  exitCode: Schema.Number,
  error: Schema.NullOr(Schema.String),
});

const OutputMatch = Schema.Struct({
  line: Schema.String,
  text: Schema.String,
  groups: Schema.Array(Schema.NullOr(Schema.String)),
  alignment: Schema.NullOr(Schema.Literals(["offset", "anchor", "unaligned"])).annotate({
    description:
      "How `since` was found: offset or anchor (exact), unaligned (the output was cleared or scrolled past the mark, so every line counted); null without `since`.",
  }),
});

const MarkResult = Schema.Struct({ markId: Schema.String });

/** The script's regex does not compile. */
class RexInvalidPattern extends Error {
  readonly _tag = "RexInvalidPattern";

  constructor(reason: string) {
    super(reason);
    this.name = "RexInvalidPattern";
  }
}

class RexReadLimit extends Schema.TaggedError<RexReadLimit>()(
  "RexReadLimit",
  { message: Schema.String },
) {}

const OutputPattern = Schema.Struct({
  type: Schema.Literals(["substring", "regex"]),
  value: Schema.String,
  flags: Schema.optionalKey(
    Schema.String.annotate({ description: 'Regex flags, such as "i"; "g" and "y" are ignored.' }),
  ),
});

const EventSource = Schema.Literals(["server", "session", "terminal", "block", "unknown"]);
const eventTags = {
  server: "ServerEvent",
  session: "SessionEvent",
  terminal: "TerminalEvent",
  block: "BlockEvent",
  unknown: "UnknownEvent",
} as const;

const AnyEvent = Schema.Struct({
  _tag: Schema.String,
  seq: Schema.Number,
}).annotate({ description: "The event, with its type or name, payload, and IDs." });

function fieldOf(value: unknown, key: string): unknown {
  return typeof value === "object" && value !== null && key in value
    ? Object.getOwnPropertyDescriptor(value, key)?.value
    : undefined;
}

function idOf(event: RexEvent, key: "sessionId" | "blockId"): string | undefined {
  const direct = fieldOf(event, key);
  if (typeof direct === "string") return direct;
  // Unknown events carry their session as an Option; server events name it in the payload.
  const some = fieldOf(direct, "value");
  if (fieldOf(direct, "_tag") === "Some" && typeof some === "string") return some;
  const payload = fieldOf(event, "payload");
  const fromPayload = fieldOf(payload, key);
  if (typeof fromPayload === "string") return fromPayload;
  // `session_created` nests its session: { session: { sessionId, label } }.
  const nested = fieldOf(fieldOf(payload, "session"), key);
  return typeof nested === "string" ? nested : undefined;
}

function nameOf(event: RexEvent): unknown {
  return "type" in event ? event.type : event.name;
}

const ReadFileResult = Schema.Struct({
  file: Schema.Struct({
    path: Schema.String,
    name: Schema.String,
    size: Schema.Number,
    modifiedAt: Schema.String,
    version: Schema.NullOr(Schema.String),
  }),
  encoding: Schema.Literals(["utf8", "base64"]),
  content: Schema.String,
});

const PasteFile = Schema.Union([
  Schema.Struct({ name: Schema.String, text: Schema.String }),
  Schema.Struct({ name: Schema.String, base64: Schema.String }),
]);

const sessionCreateWindow = Schema.Struct({
  windowLabel: Schema.optionalKey(Schema.String),
  layout: Schema.optionalKey(RexLayoutNode),
});

const layoutDescription =
  'Layout tree: { _tag: "Terminal", label?, options?: { command?, cwd?, shell?, ... } }, { _tag: "Block", flavor, label?, options? }, or { _tag: "Split", direction: "horizontal" | "vertical", before, after, ratio? }.';
const layoutField = RexLayoutNode.annotateKey({ description: layoutDescription });
const optionalLayoutField = Schema.optionalKey(RexLayoutNode).annotateKey({
  description: layoutDescription,
});

export const rexToolOperations: readonly RexToolOperation[] = [
  // The working loop first: find a terminal, run something, wait, read.
  method({
    name: "sessions_view",
    method: "session.view",
    readOnly: true,
    description:
      "One session's windows, layouts, and blocks with their IDs. Start here with the sessionId from rex_search({}).here.",
    run: (rex, input, options) => rex.sessions.view(input, options),
  }),
  inputOperation({
    name: "blocks_splitBeside",
    description:
      "Open new blocks beside a block (anchorId) or a window's focused block, at placement right, left, above, or below; defaults to a terminal running the user's shell. Returns the new blockIds.",
    fields: {
      placement: Schema.Literals(["right", "left", "above", "below"]),
      anchorId: Schema.optionalKey(AnchorId),
      layout: optionalLayoutField,
    },
    input: Schema.Struct({
      sessionId: SessionId,
      windowId: Schema.optionalKey(WindowId),
      ratio: Schema.optionalKey(Schema.Number),
      focus: Schema.optionalKey(Schema.Boolean),
    }),
    output: rexWireMethods["session.new_split"].result,
    run: (rex, fields, input, options) => rex.blocks.splitBeside({ ...input, ...fields }, options),
  }),
  operation({
    name: "terminals_writeLine",
    description:
      "Type a line of text into a terminal and press Return, such as a shell command. Returns a markId taken just before typing: pass it as `since` to rex_terminals_waitForOutput to match only what the command prints.",
    fields: { ...blockTarget, text: Schema.String },
    output: MarkResult,
    run: (rex, { text, ...target }, options, marks) =>
      Effect.gen(function* () {
        const mark = yield* rex.terminals.mark(target, options);
        yield* rex.terminals.writeLine(target, text, options);
        return { markId: marks.put(target, mark) };
      }),
  }),
  operation({
    name: "terminals_waitForOutput",
    description:
      "Wait until a line of a terminal's output matches a substring or regex; `match` has the line, the matched text, capture groups, and how `since` was found. With `since` (a markId from rex_terminals_writeLine or rex_terminals_mark) only output printed after it counts; without it, output already on screen matches at once. Rejects with RexTerminalExited if the program exits first.",
    fields: {
      ...blockTarget,
      match: OutputPattern,
      since: Schema.optionalKey(
        Schema.String.annotate({
          description: "A markId; only lines printed after the mark count.",
        }),
      ),
      lines: Schema.optionalKey(
        Schema.Int.check(Schema.isGreaterThan(0)).annotate({
          description: "Search only the last `lines` lines (after `since`, when given).",
        }),
      ),
      ...waitTimeout,
    },
    output: waitOutcomeSchema("match", OutputMatch),
    run: (rex, { match, since, lines, timeoutMs, ...target }, _options, marks) =>
      waitOutcome(
        "match",
        "TerminalService.waitForOutput",
        Effect.gen(function* () {
          const pattern = yield* Effect.try({
            try: () =>
              match.type === "substring" ? match.value : new RegExp(match.value, match.flags ?? ""),
            catch: (cause) => new RexInvalidPattern(String(cause)),
          });
          const mark = since === undefined ? undefined : yield* marks.get(since, target);
          return yield* rex.terminals.waitForOutput(
            target,
            { pattern, since: mark, lines },
            { timeout: `${timeoutMs} millis` },
          );
        }),
      ),
  }),
  operation({
    name: "terminals_mark",
    readOnly: true,
    description:
      "Mark the current end of a terminal's output and return its markId, for `since` in rex_terminals_waitForOutput. rex_terminals_writeLine makes one for you.",
    fields: blockTarget,
    output: MarkResult,
    run: (rex, target, options, marks) =>
      Effect.map(rex.terminals.mark(target, options), (mark) => ({
        markId: marks.put(target, mark),
      })),
  }),
  operation({
    name: "terminals_waitForQuiet",
    readOnly: true,
    description:
      "Wait until a terminal's program has printed nothing for quietForMs, or has exited: for output with no line to match, such as a full-screen program settling.",
    fields: {
      ...blockTarget,
      quietForMs: Schema.Finite.check(Schema.isGreaterThan(0)),
      ...waitTimeout,
    },
    output: waitOutcomeSchema("quiet", Schema.Literal(true)),
    run: (rex, { quietForMs, timeoutMs, ...target }) =>
      waitOutcome(
        "quiet",
        "TerminalService.waitForQuiet",
        Effect.as(
          rex.terminals.waitForQuiet(target, {
            quietFor: `${quietForMs} millis`,
            timeout: `${timeoutMs} millis`,
          }),
          true,
        ),
      ),
  }),
  operation({
    name: "terminals_readTail",
    readOnly: true,
    description:
      "Read the last lines of a terminal's output, cheaply even when the scrollback is long; maxBytes (default 65536) bounds how much.",
    fields: {
      ...blockTarget,
      maxBytes: Schema.optionalKey(Schema.Int.check(Schema.isGreaterThan(0))),
    },
    output: Schema.Struct({ lines: Schema.Array(Schema.String), truncated: Schema.Boolean }),
    run: (rex, { maxBytes, ...target }, options) =>
      Effect.map(rex.terminals.readTail(target, { maxBytes }, options), ({ lines, truncated }) => ({
        lines,
        truncated,
      })),
  }),
  operation({
    name: "terminals_waitForExit",
    description:
      "Wait for the terminal's program to exit, such as a block created with layout options.command; `exit` has exitCode and error. Returns at once if it already exited.",
    fields: { ...blockTarget, ...waitTimeout },
    output: waitOutcomeSchema("exit", TerminalExit),
    run: (rex, { timeoutMs, ...target }) =>
      waitOutcome(
        "exit",
        "TerminalService.waitForExit",
        rex.terminals.waitForExit(target, { timeout: `${timeoutMs} millis` }),
      ),
  }),
  inputOperation({
    name: "terminals_read",
    readOnly: true,
    description:
      "Read a terminal's screen and scrollback as text (default), html, or vt within a byte budget (default 32768, maximum 65536). Rejects rather than silently truncating larger output; use format/blobRead for explicit pages. Pass trim and unwrap for clean text.",
    fields: blockTarget,
    input: rexBlockMethods["com.superlogical.terminal.format"].args,
    output: Schema.String,
    // The SDK read helper accumulates every page; retain the string contract without
    // downloading unbounded scrollback before checking the result size.
    run: (rex, target, args, options) =>
      Effect.flatMap(rex.terminals.format(target, { ...args, maxBytes: args.maxBytes ?? 32_768 }, options), (page) =>
        Option.isNone(page.id)
          ? Effect.succeed(page.content)
          : Effect.fail(new RexReadLimit({ message: "Output exceeds this read's byte budget. Use terminals_format and terminals_blobRead for explicit bounded pages." }))),
  }),

  // server
  noInputMethod({
    name: "server_status",
    method: "server.status",
    readOnly: true,
    description: "The server's identity, session count, configuration, and Tailscale status.",
    run: (rex, options) => rex.server.status(options),
  }),
  noInputMethod({
    name: "server_version",
    method: "server.version",
    readOnly: true,
    description: "The Rex version the server runs and how it was built.",
    run: (rex, options) => rex.server.version(options),
  }),
  noInputMethod({
    name: "server_whoami",
    method: "server.whoami",
    readOnly: true,
    description: "How the server identified this client, and the account it runs as.",
    run: (rex, options) => rex.server.whoami(options),
  }),
  noInputMethod({
    name: "server_reloadConfig",
    method: "server.config_reload",
    description: "Reload the Rex configuration file and tell clients to refetch keymaps.",
    run: (rex, options) => rex.server.reloadConfig(options),
  }),
  method({
    name: "server_stop",
    method: "server.stop",
    destructive: true,
    description:
      "Shut the Rex server down, ending every session; with ifIdle, only when nothing uses it.",
    run: (rex, input, options) => rex.server.stop(input, options),
  }),
  noInputMethod({
    name: "server_help",
    method: "help.all",
    readOnly: true,
    description: "Every method the server provides, with JSON Schemas, as raw JSON. Large.",
    run: (rex, options) => rex.server.help(options),
  }),
  method({
    name: "server_tailscale_enable",
    method: "server.tailscale.enable",
    description: "Turn built-in Tailscale on, so devices on the tailnet can reach the server.",
    run: (rex, input, options) => rex.server.tailscale.enable(input, options),
  }),
  noInputMethod({
    name: "server_tailscale_disable",
    method: "server.tailscale.disable",
    destructive: true,
    description: "Turn built-in Tailscale off, keeping its sign-in.",
    run: (rex, options) => rex.server.tailscale.disable(options),
  }),
  noInputMethod({
    name: "server_tailscale_login",
    method: "server.tailscale.login",
    description: "Ask Tailscale for a sign-in link.",
    run: (rex, options) => rex.server.tailscale.login(options),
  }),
  noInputMethod({
    name: "server_tailscale_logout",
    method: "server.tailscale.logout",
    destructive: true,
    description: "Sign the server out of Tailscale and turn Tailscale off.",
    run: (rex, options) => rex.server.tailscale.logout(options),
  }),
  method({
    name: "server_tailscale_rename",
    method: "server.tailscale.rename",
    description: "Change the server's Tailscale device name without signing in again.",
    run: (rex, input, options) => rex.server.tailscale.rename(input, options),
  }),
  method({
    name: "server_apple_grantFileAccess",
    method: "server.apple.grant_file_access",
    description: "Let the server read files a Mac app was given access to.",
    run: (rex, input, options) => rex.server.apple.grantFileAccess(input, options),
  }),
  noInputMethod({
    name: "server_apple_privacyStatus",
    method: "server.apple.privacy_status",
    readOnly: true,
    description: "The macOS privacy permissions the server has.",
    run: (rex, options) => rex.server.apple.privacyStatus(options),
  }),

  // sessions
  noInputMethod({
    name: "sessions_list",
    method: "session.list",
    readOnly: true,
    description: "The sessions on the server, in order, with IDs and labels.",
    run: (rex, options) => rex.sessions.list(options),
  }),
  inputOperation({
    name: "sessions_create",
    description:
      "Create a session (a workspace), optionally with first windows and their layouts. Returns the sessionId and each window's windowId and blockIds.",
    fields: {
      initialWindows: Schema.optionalKey(Schema.Array(sessionCreateWindow)),
    },
    input: rexWireMethods["session.create"].input,
    output: rexWireMethods["session.create"].result,
    run: (rex, fields, { initialWindows: _wire, ...input }, options) =>
      rex.sessions.create({ ...input, ...fields }, options),
  }),
  method({
    name: "sessions_destroy",
    method: "session.destroy",
    destructive: true,
    description: "Destroy a session and close every block in it.",
    run: (rex, input, options) => rex.sessions.destroy(input, options),
  }),
  method({
    name: "sessions_setLabel",
    method: "session.set_label",
    description: "Set a session's label; an empty label restores the default.",
    run: (rex, input, options) => rex.sessions.setLabel(input, options),
  }),
  method({
    name: "sessions_move",
    method: "session.move",
    description: "Move a session in the order rex_sessions_list returns.",
    run: (rex, input, options) => rex.sessions.move(input, options),
  }),
  method({
    name: "sessions_listBlocks",
    method: "session.list_blocks",
    readOnly: true,
    description: "Every block in a session, including detached blocks.",
    run: (rex, input, options) => rex.sessions.listBlocks(input, options),
  }),
  method({
    name: "sessions_listClients",
    method: "session.list_clients",
    readOnly: true,
    description: "The clients attached to a session.",
    run: (rex, input, options) => rex.sessions.listClients(input, options),
  }),
  method({
    name: "sessions_help",
    method: "session.help",
    readOnly: true,
    description:
      "The methods a session accepts and its blocks provide, as raw JSON. Large; prefer rex_blocks_describe for one block.",
    run: (rex, input, options) => rex.sessions.help(input, options),
  }),

  // windows
  inputOperation({
    name: "windows_create",
    description:
      "Create a window (a tab) with a layout of blocks; it becomes active unless focus is false. Returns windowId and blockIds.",
    fields: { layout: optionalLayoutField },
    input: rexWireMethods["session.new_window"].input,
    output: rexWireMethods["session.new_window"].result,
    run: (rex, fields, { layout: _wire, ...input }, options) =>
      rex.windows.create({ ...input, ...fields }, options),
  }),
  method({
    name: "windows_close",
    method: "session.close_window",
    destructive: true,
    description: "Close a window, or the active one, and every block in it.",
    run: (rex, input, options) => rex.windows.close(input, options),
  }),
  method({
    name: "windows_focus",
    method: "session.focus_window",
    description: "Make a window active; focus returns to the block it last had focused.",
    run: (rex, input, options) => rex.windows.focus(input, options),
  }),
  method({
    name: "windows_focusNext",
    method: "session.focus_next_window",
    description: "Make the next window active.",
    run: (rex, input, options) => rex.windows.focusNext(input, options),
  }),
  method({
    name: "windows_focusPrevious",
    method: "session.focus_previous_window",
    description: "Make the previous window active.",
    run: (rex, input, options) => rex.windows.focusPrevious(input, options),
  }),
  method({
    name: "windows_move",
    method: "session.move_window",
    description: "Move a window in the session's window order.",
    run: (rex, input, options) => rex.windows.move(input, options),
  }),
  method({
    name: "windows_setLabel",
    method: "session.set_window_label",
    description: "Set a window's label; an empty label restores the default.",
    run: (rex, input, options) => rex.windows.setLabel(input, options),
  }),

  // blocks
  inputOperation({
    name: "blocks_split",
    description:
      "Create blocks in a new split beside a block, a split, or a window's focused block, by direction and side. rex_blocks_splitBeside is simpler.",
    fields: { layout: layoutField },
    input: rexWireMethods["session.new_split"].input,
    output: rexWireMethods["session.new_split"].result,
    run: (rex, fields, { layout: _wire, ...input }, options) =>
      rex.blocks.split({ ...input, ...fields }, options),
  }),
  method({
    name: "blocks_create",
    method: "session.new_block",
    description: "Create a detached block from a flavor, to place later with rex_blocks_move.",
    run: (rex, input, options) => rex.blocks.create(input, options),
  }),
  method({
    name: "blocks_move",
    method: "session.move_block",
    description: "Move a block, or place a detached one, in a new split beside another block.",
    run: (rex, input, options) => rex.blocks.move(input, options),
  }),
  method({
    name: "blocks_swap",
    method: "session.swap_blocks",
    description: "Swap the places of two blocks.",
    run: (rex, input, options) => rex.blocks.swap(input, options),
  }),
  method({
    name: "blocks_zoom",
    method: "session.zoom_block",
    description: "Zoom a block to fill its window, or undo the zoom.",
    run: (rex, input, options) => rex.blocks.zoom(input, options),
  }),
  method({
    name: "blocks_detach",
    method: "session.detach_block",
    description: "Take a block out of its window without closing it.",
    run: (rex, input, options) => rex.blocks.detach(input, options),
  }),
  method({
    name: "blocks_float",
    method: "session.float_block",
    description: "Move a block out of its window's layout into a new floating layer.",
    run: (rex, input, options) => rex.blocks.float(input, options),
  }),
  method({
    name: "blocks_focus",
    method: "session.focus_block",
    description: "Focus a block and make its window active.",
    run: (rex, input, options) => rex.blocks.focus(input, options),
  }),
  method({
    name: "blocks_focusDirection",
    method: "session.focus_direction",
    description: "Move focus to the nearest block in a direction.",
    run: (rex, input, options) => rex.blocks.focusDirection(input, options),
  }),
  method({
    name: "blocks_focusNext",
    method: "session.focus_next_pane",
    description: "Move focus to the next block in the active window.",
    run: (rex, input, options) => rex.blocks.focusNext(input, options),
  }),
  method({
    name: "blocks_focusPrevious",
    method: "session.focus_previous_pane",
    description: "Move focus to the previous block in the active window.",
    run: (rex, input, options) => rex.blocks.focusPrevious(input, options),
  }),
  method({
    name: "blocks_resize",
    method: "session.resize_pane",
    description: "Move the border between two blocks to change their sizes.",
    run: (rex, input, options) => rex.blocks.resize(input, options),
  }),
  method({
    name: "blocks_setLabel",
    method: "session.set_block_label",
    description: "Set a block's label, shown on its pane; an empty label restores the default.",
    run: (rex, input, options) => rex.blocks.setLabel(input, options),
  }),
  method({
    name: "blocks_own",
    method: "session.own_block",
    description: "Claim blocks for this client; an owner sets a terminal's size and colors.",
    run: (rex, input, options) => rex.blocks.own(input, options),
  }),
  method({
    name: "blocks_disown",
    method: "session.disown_block",
    description: "Give up this client's claim on blocks.",
    run: (rex, input, options) => rex.blocks.disown(input, options),
  }),
  method({
    name: "blocks_describe",
    method: "session.describe_block",
    readOnly: true,
    description: "A block's details and the methods, events, and actions it provides.",
    run: (rex, input, options) => rex.blocks.describe(input, options),
  }),
  method({
    name: "blocks_close",
    method: "block.close",
    destructive: true,
    description: "Close a block, or a window's focused block, ending its program.",
    run: (rex, input, options) => rex.blocks.close(input, options),
  }),
  method({
    name: "blocks_sendEvent",
    method: "block.event",
    description:
      "Send an input event, such as a key press or a paste, to a block. To type text into a terminal, use rex_terminals_write.",
    run: (rex, input, options) => rex.blocks.sendEvent(input, options),
  }),
  method({
    name: "blocks_callMethod",
    method: "block.method",
    description:
      "Call a method of any block by name and return its raw result; rex_blocks_describe lists them.",
    run: (rex, input, options) => rex.blocks.callMethod(input, options),
  }),

  // layers
  inputOperation({
    name: "layers_create",
    description:
      "Create blocks in a new floating layer at the front of a window; bounds are fractions of the window.",
    fields: { layout: layoutField },
    input: rexWireMethods["session.new_layer"].input,
    output: rexWireMethods["session.new_layer"].result,
    run: (rex, fields, { layout: _wire, ...input }, options) =>
      rex.layers.create({ ...input, ...fields }, options),
  }),
  method({
    name: "layers_close",
    method: "session.close_layer",
    destructive: true,
    description: "Close a floating layer and every block in it.",
    run: (rex, input, options) => rex.layers.close(input, options),
  }),
  method({
    name: "layers_raise",
    method: "session.raise_layer",
    description: "Move a floating layer to the front, or just above another.",
    run: (rex, input, options) => rex.layers.raise(input, options),
  }),
  method({
    name: "layers_lower",
    method: "session.lower_layer",
    description: "Move a floating layer to the back, or just below another.",
    run: (rex, input, options) => rex.layers.lower(input, options),
  }),
  method({
    name: "layers_resize",
    method: "session.resize_layer",
    description: "Move or resize a floating layer; bounds are fractions of the window.",
    run: (rex, input, options) => rex.layers.resize(input, options),
  }),
  method({
    name: "layers_setState",
    method: "session.set_layer_state",
    description: "Minimize or restore a floating layer.",
    run: (rex, input, options) => rex.layers.setState(input, options),
  }),

  // terminals
  blockMethod({
    name: "terminals_write",
    method: "com.superlogical.terminal.write",
    description:
      "Type text into a terminal as if the user typed it, escape sequences included (\\r is Return, \\u0003 is Ctrl+C); returns once queued.",
    run: (rex, target, args, options) => rex.terminals.write(target, args, options),
  }),
  blockMethod({
    name: "terminals_format",
    method: "com.superlogical.terminal.format",
    readOnly: true,
    description:
      "The screen and scrollback as text, html, or vt, possibly only the first part. rex_terminals_read pages through the rest for you.",
    run: (rex, target, args, options) => rex.terminals.format(target, args, options),
  }),
  blockMethod({
    name: "terminals_blobRead",
    method: "com.superlogical.terminal.blob_read",
    readOnly: true,
    description:
      "Read part of a result too large for one reply, such as a long format or ports result.",
    run: (rex, target, args, options) => rex.terminals.blobRead(target, args, options),
  }),
  blockNoArgsMethod({
    name: "terminals_clear",
    method: "com.superlogical.terminal.clear",
    destructive: true,
    description: "Clear a terminal's screen and scrollback, keeping the current line.",
    run: (rex, target, options) => rex.terminals.clear(target, options),
  }),
  blockNoArgsMethod({
    name: "terminals_reset",
    method: "com.superlogical.terminal.reset",
    destructive: true,
    description: "Reset a terminal to its starting state; the program keeps running.",
    run: (rex, target, options) => rex.terminals.reset(target, options),
  }),
  blockMethod({
    name: "terminals_resize",
    method: "com.superlogical.terminal.resize",
    description:
      "Request a terminal size in columns and rows; it applies when this client owns the block or nobody does.",
    run: (rex, target, args, options) => rex.terminals.resize(target, args, options),
  }),
  blockNoArgsMethod({
    name: "terminals_size",
    method: "com.superlogical.terminal.size",
    readOnly: true,
    description: "A terminal's size, its owner, and the size each client requested.",
    run: (rex, target, options) => rex.terminals.size(target, options),
  }),
  blockMethod({
    name: "terminals_setTheme",
    method: "com.superlogical.terminal.set_theme",
    description: "Replace a terminal's default colors.",
    run: (rex, target, args, options) => rex.terminals.setTheme(target, args, options),
  }),
  blockNoArgsMethod({
    name: "terminals_title",
    method: "com.superlogical.terminal.title",
    readOnly: true,
    description: "A terminal's title and the process that set it.",
    run: (rex, target, options) => rex.terminals.title(target, options),
  }),
  blockNoArgsMethod({
    name: "terminals_pwd",
    method: "com.superlogical.terminal.pwd",
    readOnly: true,
    description: "The working directory a program in the terminal last reported.",
    run: (rex, target, options) => rex.terminals.pwd(target, options),
  }),
  blockNoArgsMethod({
    name: "terminals_process",
    method: "com.superlogical.terminal.process",
    readOnly: true,
    description:
      "The processes running in a terminal (the shell and its foreground job) and how its program exited.",
    run: (rex, target, options) => rex.terminals.process(target, options),
  }),
  blockNoArgsMethod({
    name: "terminals_modes",
    method: "com.superlogical.terminal.modes",
    readOnly: true,
    description: "The terminal modes programs turned on, such as the alternate screen.",
    run: (rex, target, options) => rex.terminals.modes(target, options),
  }),
  blockNoArgsMethod({
    name: "terminals_inputMode",
    method: "com.superlogical.terminal.input_mode",
    readOnly: true,
    description:
      "How the terminal handles typed input, such as whether it is echoed (off while a program reads a password).",
    run: (rex, target, options) => rex.terminals.inputMode(target, options),
  }),
  blockMethod({
    name: "terminals_listDir",
    method: "com.superlogical.terminal.list_dir",
    readOnly: true,
    description:
      "Subdirectories, and optionally files, of a directory as the terminal resolves it.",
    run: (rex, target, args, options) => rex.terminals.listDir(target, args, options),
  }),
  blockMethod({
    name: "terminals_clipboardRead",
    method: "com.superlogical.terminal.clipboard_read",
    readOnly: true,
    description: "Text a program in the terminal copied to the clipboard.",
    run: (rex, target, args, options) => rex.terminals.clipboardRead(target, args, options),
  }),
  blockNoArgsMethod({
    name: "terminals_programStatus",
    method: "com.superlogical.terminal.program_status",
    readOnly: true,
    description: "Statuses programs reported with OSC 7501, such as working or blocked.",
    run: (rex, target, options) => rex.terminals.programStatus(target, options),
  }),
  blockNoArgsMethod({
    name: "terminals_ports",
    method: "com.superlogical.terminal.ports",
    readOnly: true,
    description:
      "The TCP ports programs in the terminal listen on, and the processes holding them.",
    run: (rex, target, options) => rex.terminals.ports(target, options),
  }),
  operation({
    name: "terminals_readFile",
    readOnly: true,
    description:
      'Read a file from the terminal\'s machine (a path relative to its working directory works). `content` is UTF-8 text, or base64 with encoding: "base64".',
    fields: {
      ...blockTarget,
      path: Schema.String,
      encoding: Schema.optionalKey(Schema.Literals(["utf8", "base64"])),
      maxBytes: Schema.optionalKey(
        Schema.Int.check(Schema.isGreaterThan(0)).annotate({
          description: "Fail with RexTransferTooLarge past this size; default 1048576.",
        }),
      ),
    },
    output: ReadFileResult,
    run: (rex, { path, encoding = "utf8", maxBytes = 1_048_576, ...target }, options) =>
      rex.terminals.readFile(target, path, { maxBytes }, options).pipe(
        Effect.map(({ file, bytes }) => ({
          file,
          encoding,
          content: Buffer.from(bytes).toString(encoding),
        })),
      ),
  }),
  operation({
    name: "terminals_pasteFiles",
    description:
      "Paste files into a terminal as a program sees a drag and drop: each file is uploaded, then its path is typed. Give each file as { name, text } or { name, base64 }.",
    fields: { ...blockTarget, files: Schema.NonEmptyArray(PasteFile) },
    output: "void",
    run: (rex, { files, ...target }, options) =>
      rex.terminals.pasteFiles(
        target,
        Arr.map(files, (file) => ({
          name: file.name,
          data: "text" in file ? file.text : Buffer.from(file.base64, "base64"),
        })),
        options,
      ),
  }),

  // tunnels
  operation({
    name: "tunnels_createDial",
    description:
      "Create a detached tunnel block that connects to a fixed host and port; place it with rex_blocks_move.",
    fields: {
      sessionId: SessionId,
      label: Schema.optionalKey(Schema.String),
      options: TunnelDialOptions,
    },
    output: rexWireMethods["session.new_block"].result,
    run: (rex, fields, options) => rex.tunnels.createDial(fields, options),
  }),
  operation({
    name: "tunnels_createListen",
    description:
      "Create a detached tunnel block that accepts connections on an address and port; place it with rex_blocks_move.",
    fields: {
      sessionId: SessionId,
      label: Schema.optionalKey(Schema.String),
      options: TunnelListenOptions,
    },
    output: rexWireMethods["session.new_block"].result,
    run: (rex, fields, options) => rex.tunnels.createListen(fields, options),
  }),
  blockNoArgsMethod({
    name: "tunnels_info",
    method: "com.superlogical.tunnel.info",
    readOnly: true,
    description: "What a tunnel forwards and how many connections it relays.",
    run: (rex, target, options) => rex.tunnels.info(target, options),
  }),

  // clients
  method({
    name: "clients_list",
    method: "client.list",
    readOnly: true,
    description: "The clients (Rex apps, CLIs, agents) connected to the server.",
    run: (rex, input, options) => rex.clients.list(input, options),
  }),
  method({
    name: "clients_inspect",
    method: "client.inspect",
    readOnly: true,
    description: "One client's details, including the actions it offers.",
    run: (rex, input, options) => rex.clients.inspect(input, options),
  }),
  method({
    name: "clients_setLabel",
    method: "client.set_label",
    description: "Set or remove this client's label.",
    run: (rex, input, options) => rex.clients.setLabel(input, options),
  }),
  method({
    name: "clients_setScript",
    method: "client.set_script",
    description: "Load Lua scripts for this client, replacing any loaded before.",
    run: (rex, input, options) => rex.clients.setScript(input, options),
  }),
  method({
    name: "clients_keymap",
    method: "client.keymap",
    readOnly: true,
    description: "What each key does for this client.",
    run: (rex, input, options) => rex.clients.keymap(input, options),
  }),
  method({
    name: "clients_action",
    method: "client.action",
    description: "Perform a configuration-file or block action as this client.",
    run: (rex, input, options) => rex.clients.action(input, options),
  }),
  method({
    name: "clients_key",
    method: "client.key",
    description: "Send a key to a block, giving Lua key bindings the first chance at it.",
    run: (rex, input, options) => rex.clients.key(input, options),
  }),
  method({
    name: "clients_perform",
    method: "client.perform",
    description:
      "Ask another client, such as Rex.app, to perform one of its actions and wait for its answer.",
    run: (rex, input, options) => rex.clients.perform(input, options),
  }),
  method({
    name: "clients_reply",
    method: "client.reply",
    description: "Answer a client_call_requested or client_perform_requested event.",
    run: (rex, input, options) => rex.clients.reply(input, options),
  }),

  // events
  operation({
    name: "events_waitFor",
    readOnly: true,
    description:
      "Wait for the next event matching every given filter: type (an event type such as session_created or block_closed, or a block event name such as child_exited), source, sessionId, blockId. `event` has its payload.",
    fields: {
      type: Schema.optionalKey(Schema.String),
      source: Schema.optionalKey(EventSource),
      sessionId: Schema.optionalKey(SessionId),
      blockId: Schema.optionalKey(BlockId),
      ...waitTimeout,
    },
    output: waitOutcomeSchema("event", AnyEvent),
    run: (rex, { type, source, sessionId, blockId, timeoutMs }) => {
      const sessionScoped = source === "session" || source === "terminal" || source === "block";
      const matches = (event: RexEvent): event is RexEvent =>
        (type === undefined || nameOf(event) === type) &&
        (source === undefined || event._tag === eventTags[source]) &&
        (sessionId === undefined || idOf(event, "sessionId") === sessionId) &&
        (blockId === undefined || idOf(event, "blockId") === blockId);
      return waitOutcome(
        "event",
        "EventService.waitFor",
        rex.events.waitFor(matches, {
          timeout: `${timeoutMs} millis`,
          ...(sessionId !== undefined && sessionScoped
            ? { sessionIds: [sessionId], server: "none" }
            : {}),
        }),
      );
    },
  }),

  // targets, hosts, creators
  method({
    name: "targets_resolve",
    method: "target.resolve",
    readOnly: true,
    description:
      "Resolve queries such as labels, window positions, or short IDs into IDs; each result says whether it matched one thing, nothing, or several.",
    run: (rex, input, options) => rex.targets.resolve(input, options),
  }),
  method({
    name: "targets_complete",
    method: "target.complete",
    readOnly: true,
    description: "Labels, window positions, and short IDs that start with a prefix.",
    run: (rex, input, options) => rex.targets.complete(input, options),
  }),
  noInputMethod({
    name: "hosts_list",
    method: "hosts.list",
    readOnly: true,
    description:
      "The server's saved hosts (other Rex servers), with a hash that identifies the list.",
    run: (rex, options) => rex.hosts.list(options),
  }),
  method({
    name: "hosts_put",
    method: "hosts.put",
    description: "Add a host, or replace the host with the same ID.",
    run: (rex, input, options) => rex.hosts.put(input, options),
  }),
  method({
    name: "hosts_remove",
    method: "hosts.remove",
    destructive: true,
    description: "Remove a saved host; removing one that isn't listed changes nothing.",
    run: (rex, input, options) => rex.hosts.remove(input, options),
  }),
  noInputMethod({
    name: "creators_list",
    method: "block_creator.list",
    readOnly: true,
    description:
      "Every block creator the server can make blocks with, their flavors, and their options schemas.",
    run: (rex, options) => rex.creators.list(options),
  }),
];

/**
 * SDK operations without a tool, by SDK path. They hold a connection or stream open for a
 * caller-owned scope, manage the connection itself, or are covered by a tool above.
 */
export const rexToolExclusions: Readonly<Record<string, string>> = {
  "sessions.attach": "the SDK attaches automatically for every session-scoped call",
  "sessions.detach": "the SDK manages this connection's attachments",
  "sessions.attachAll": "the SDK manages this connection's attachments; use rex_events_waitFor",
  "sessions.bootstrap": "starts a client connection, which only app clients need",
  "sessions.watchView": "a stream; read rex_sessions_view again instead",
  "terminals.stream": "a stream; use rex_terminals_waitForOutput and rex_terminals_read",
  "terminals.activity": "a stream; use rex_terminals_waitForOutput or rex_terminals_waitForQuiet",
  "terminals.watch": "a stream; use rex_terminals_waitForOutput",
  "terminals.download": "a scoped byte stream; use rex_terminals_readFile",
  "terminals.downloadToFile": "needs a local file system service; use rex_terminals_readFile",
  "tunnels.openStream": "a scoped byte stream",
  "tunnels.connections": "a stream",
  "tunnels.forwardLocal": "a forward lives only as long as its scope",
  "tunnels.forwardRemote": "a forward lives only as long as its scope",
  "clients.servePerformRequests": "serves requests until interrupted",
  "clients.serveCallRequests": "serves requests until interrupted",
  "events.stream": "a stream; use rex_events_waitFor",
};
