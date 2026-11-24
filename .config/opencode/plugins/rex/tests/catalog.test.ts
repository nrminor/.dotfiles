import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect, Exit, Schema } from "effect";
import { BlockId, SessionId, type RexTerminalMark } from "rex-sdk";
import { RexMarkStore } from "../vendor/rex-tool-marks.ts";

const sessionId = Schema.decodeUnknownSync(SessionId)("session:selected");
const blockId = Schema.decodeUnknownSync(BlockId)("block:existing");
const target = { sessionId, blockId };
const mark: RexTerminalMark = { offset: 0, anchor: [], hasCursorLine: false };

test("marks are scoped to their store, session, and block", async () => {
  const marks = new RexMarkStore();
  const id = marks.put(target, mark);
  assert.equal(await Effect.runPromise(marks.get(id, target)), mark);
  const otherSession = Schema.decodeUnknownSync(SessionId)("session:other");
  const otherBlock = Schema.decodeUnknownSync(BlockId)("block:other");
  for (const [store, reference] of [
    [new RexMarkStore(), target],
    [marks, { ...target, sessionId: otherSession }],
    [marks, { ...target, blockId: otherBlock }],
  ] as const) {
    assert.ok(Exit.isFailure(await Effect.runPromiseExit(store.get(id, reference))));
  }
});

test("marks evict the oldest after 256 entries", async () => {
  const marks = new RexMarkStore();
  const first = marks.put(target, mark);
  let newest = first;
  for (let i = 0; i < 256; i++) newest = marks.put(target, mark);
  assert.ok(Exit.isFailure(await Effect.runPromiseExit(marks.get(first, target))));
  assert.equal(await Effect.runPromise(marks.get(newest, target)), mark);
});

test("mark IDs cannot alias another binding after reload", async () => {
  const first = new RexMarkStore();
  const second = new RexMarkStore();
  const old = first.put(target, mark);
  const fresh = second.put(target, mark);
  assert.notEqual(old, fresh);
  assert.ok(Exit.isFailure(await Effect.runPromiseExit(second.get(old, target))));
});
