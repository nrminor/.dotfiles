import assert from "node:assert/strict";
import test from "node:test";
import type { ExtensionAPI, ExtensionCommandContext, ExtensionToolContext } from "@earendil-works/pi-coding-agent";
import rexExtension from "../index.ts";
import { operationPolicy } from "../policy.ts";
import { rexToolOperations } from "../vendor/rex-tool-operations.ts";

// Explicit safety specification: upstream additions or category changes need review.
const expectedCategories = {
  read: `
    sessions_view sessions_list sessions_listBlocks sessions_listClients sessions_help
    server_status server_version server_whoami server_help server_apple_privacyStatus
    blocks_describe terminals_waitForOutput terminals_mark terminals_waitForQuiet
    terminals_readTail terminals_waitForExit terminals_read terminals_format terminals_size
    terminals_title terminals_pwd terminals_process terminals_modes terminals_inputMode
    terminals_programStatus terminals_ports tunnels_info clients_list clients_inspect
    targets_resolve targets_complete hosts_list creators_list`,
  "sensitive read": "terminals_blobRead terminals_listDir terminals_clipboardRead terminals_readFile events_waitFor",
  "execution/input": `
    terminals_writeLine terminals_write terminals_pasteFiles blocks_sendEvent blocks_callMethod
    clients_setScript clients_action clients_key clients_perform clients_reply sessions_create
    windows_create blocks_splitBeside blocks_split blocks_create layers_create`,
  layout: `
    sessions_setLabel sessions_move windows_focus windows_focusNext windows_focusPrevious
    windows_move windows_setLabel blocks_move blocks_swap blocks_zoom blocks_detach blocks_float
    blocks_focus blocks_focusDirection blocks_focusNext blocks_focusPrevious blocks_resize
    blocks_setLabel blocks_own blocks_disown layers_raise layers_lower layers_resize layers_setState
    terminals_resize terminals_setTheme clients_setLabel clients_keymap`,
  "close/destroy": "sessions_destroy windows_close blocks_close layers_close terminals_clear terminals_reset",
  "server config/shutdown": "server_reloadConfig server_stop server_apple_grantFileAccess",
  "network/host config": `
    server_tailscale_enable server_tailscale_disable server_tailscale_login server_tailscale_logout
    server_tailscale_rename tunnels_createDial tunnels_createListen hosts_put hosts_remove`,
};
const words = (text: string) => text.trim().split(/\s+/);

test("every catalog operation has exactly the reviewed policy classification, with no stale entries", () => {
  const expected = Object.fromEntries(Object.entries(expectedCategories).flatMap(([category, names]) =>
    words(names).map((name) => [name, category])));
  assert.deepEqual(Object.fromEntries(Object.entries(operationPolicy).map(([name, policy]) => [name, policy.category])), expected);
  const catalog = rexToolOperations.map((operation) => operation.name);
  assert.equal(new Set(catalog).size, catalog.length, "No duplicate catalog names");
  assert.deepEqual(catalog.toSorted(), Object.keys(expected).toSorted());
});

test("only ambient focus and unclassified dynamic actions are deferred, not the terminal working loop", () => {
  assert.deepEqual(Object.entries(operationPolicy).filter(([, policy]) => policy.deferred).map(([name]) => name).toSorted(), [
    "windows_focusNext", "windows_focusPrevious", "blocks_focusDirection", "blocks_focusNext",
    "blocks_focusPrevious", "blocks_sendEvent", "clients_action", "clients_key", "clients_perform", "clients_reply",
  ].toSorted());
});

type RegisteredTool = Parameters<ExtensionAPI["registerTool"]>[0];
type RegisteredCommand = Parameters<ExtensionAPI["registerCommand"]>[1];

function register() {
  const tools: RegisteredTool[] = [];
  const commands = new Map<string, RegisteredCommand>();
  const events: string[] = [];
  rexExtension({
    registerTool: (tool: RegisteredTool) => { tools.push(tool); },
    registerCommand: (name: string, command: RegisteredCommand) => { commands.set(name, command); },
    on: (name: string) => { events.push(name); },
  } as unknown as ExtensionAPI);
  return { tools, commands, events };
}

test("search is the only eager tool; every operation is registered once in the Rex namespace", () => {
  const { tools, commands, events } = register();
  assert.equal(tools.length, rexToolOperations.length + 1);
  assert.deepEqual(tools.filter((tool) => tool.exposure !== "deferred").map((tool) => tool.name), ["rex_search"]);
  assert.deepEqual(tools.slice(1).map((tool) => tool.name).toSorted(),
    rexToolOperations.map((operation) => `rex_${operation.name}`).toSorted());
  for (const tool of tools) assert.equal(tool.namespace?.name, "rex");
  assert.deepEqual([...commands.keys()].toSorted(), ["rex-activity", "rex-clear", "rex-jump", "rex-target"]);
  assert.deepEqual(events, ["session_shutdown"]);
});

test("ambient Rex variables never bind search or permit tool execution", async (t) => {
  for (const [key, value] of Object.entries({
    REX_SERVER: "/must-not-connect/rex.sock", REX_SESSION: "session:ambient", REX_BLOCK: "block:ambient",
  })) {
    const old = process.env[key];
    process.env[key] = value;
    t.after(() => { if (old === undefined) delete process.env[key]; else process.env[key] = old; });
  }
  const { tools } = register();
  const ctx = {
    hasUI: false, sessionManager: { getSessionId: () => "pi:a" },
    ui: { confirm: () => assert.fail("Headless execution must not open dialogs") },
  } as unknown as ExtensionToolContext;
  const search = tools.find((tool) => tool.name === "rex_search");
  assert.ok(search);
  const result = await search.execute("search", {}, undefined, undefined, ctx);
  assert.deepEqual((result.structuredContent as { here: unknown }).here, { sessionId: null, blockId: null });
  const write = tools.find((tool) => tool.name === "rex_terminals_write");
  assert.ok(write);
  await assert.rejects(Promise.resolve().then(() => write.execute("write", {
    sessionId: "session:ambient", blockId: "block:ambient", data: "x",
  }, undefined, undefined, ctx)), /explicit target/);
  const found = await search.execute("search", { query: "blocks_sendEvent" }, undefined, undefined, ctx);
  assert.match(JSON.stringify(found.structuredContent), /Deferred:.*classification/);
});

test("headless target selection reports denial before confirmation or connecting", async () => {
  const { commands } = register();
  const notifications: Array<{ message: string; level: string }> = [];
  const command = commands.get("rex-target");
  assert.ok(command);
  await command.handler('{"server":"/must-not-connect","sessionId":"session:selected"}', {
    hasUI: false,
    waitForIdle: async () => undefined,
    ui: {
      confirm: () => assert.fail("Headless target selection must not request confirmation"),
      notify: (message: string, level: string) => { notifications.push({ message, level }); },
    },
  } as unknown as ExtensionCommandContext);
  assert.deepEqual(notifications, [{
    message: "Rex target selection requires dialog-capable UI.", level: "error",
  }]);
});
