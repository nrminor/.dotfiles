/**
 * Marks handed to codemode scripts by ID.
 *
 * A mark (`RexTerminalMark`) holds anchor lines a script has no use for, so tools return a short
 * `markId` and keep the mark here, per pi session. The newest 256 are kept.
 */
import { Effect } from "effect";
import type { RexBlockTarget, RexTerminalMark } from "rex-sdk";

/** How many marks a session keeps before forgetting the oldest. */
const MAX_MARKS = 256;

/** A markId the script passed is unknown, expired, or belongs to another block. */
export class RexUnknownMark extends Error {
  readonly _tag = "RexUnknownMark";

  constructor(markId: string, reason: string) {
    super(
      `mark ${markId} ${reason}; make a new one with rex_terminals_mark or rex_terminals_writeLine`,
    );
    this.name = "RexUnknownMark";
  }
}

interface StoredMark {
  readonly sessionId: string;
  readonly blockId: string;
  readonly mark: RexTerminalMark;
}

/** The marks of one pi session. */
export class RexMarkStore {
  readonly #marks = new Map<string, StoredMark>();
  #next = 1;

  /** Keeps `mark` for `target` and returns its ID. */
  put(target: RexBlockTarget, mark: RexTerminalMark): string {
    const markId = `mark-${this.#next++}`;
    this.#marks.set(markId, { sessionId: target.sessionId, blockId: target.blockId, mark });
    for (const oldest of this.#marks.keys()) {
      if (this.#marks.size <= MAX_MARKS) break;
      this.#marks.delete(oldest);
    }
    return markId;
  }

  /** The mark with `markId`, which must belong to `target`. */
  get(markId: string, target: RexBlockTarget): Effect.Effect<RexTerminalMark, RexUnknownMark> {
    const stored = this.#marks.get(markId);
    if (stored === undefined)
      return Effect.fail(new RexUnknownMark(markId, "is unknown or expired"));
    if (stored.sessionId !== target.sessionId || stored.blockId !== target.blockId) {
      return Effect.fail(new RexUnknownMark(markId, `belongs to block ${stored.blockId}`));
    }
    return Effect.succeed(stored.mark);
  }
}
