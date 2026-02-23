---
description: Sync a working document (plan, design, etc.) with the current state of the implementation
---

Review a working document and update it to reflect the current state of the
codebase. The goal is to keep planning and design artifacts accurate across
agent sessions so that context persists reliably and documents don't go stale.

## 1. Identify the Working Document

If a path was provided as an argument, use it directly. Otherwise, determine
which document to update based on your conversation history — you may already
know which document you've been working from in this session.

If you're unsure which document is the working document, **ask the user**. Don't
guess. There may be multiple markdown files in the project that look like
candidates (plans, designs, architecture docs, notes), and the user knows which
one matters right now.

When searching for candidates, look for `.md` files in common locations like the
project root, `docs/`, `.agents/`, `.opencode/`, or similar directories. The
document might or might not be version-controlled — don't assume either way.

## 2. Read the Document

Read the entire working document. Understand its structure and what it claims:

- What does it say is done, in-progress, or planned?
- What decisions does it record?
- What does it describe about the architecture, design, or approach?
- Are there open questions, risks, or unknowns it tracks?

Pay attention to anything that reads like a snapshot of project state — these are
the sections most likely to have drifted.

## 3. Assess the Current Implementation

Examine the actual codebase using your codebase-searcher skill to understand what
exists today. This means reading code, not just VCS metadata. Look at what's built,
what's wired up, what's partially implemented, and what's missing.

Don't make assumptions about commit conventions, branch strategies, or how
granular the project's change history is. The source of truth is the code on
disk, not the history around it.

Be thorough but proportional — focus your investigation on the areas the
document makes claims about. If the document describes a three-phase migration
plan, go check whether phases one and two are actually complete. If it lists
modules to be built, verify which ones exist and in what state.

## 4. Compare and Identify Drift

With both the document's claims and the implementation's reality in hand,
identify where they've diverged:

- **Stale completions**: things the document marks as planned or in-progress that
  are actually done.
- **Overstated progress**: things the document marks as done that are incomplete,
  missing, or were implemented differently than described.
- **Undocumented work**: implementation that exists but isn't reflected in the
  document at all — new modules, changed approaches, emergent patterns.
- **Obsolete sections**: decisions, risks, or open questions that have been
  resolved by the implementation but not updated in the document.
- **Structural drift**: cases where the implementation took a different approach
  than what the document describes, making the document's framing misleading
  even if the specifics aren't technically wrong.

## 5. Propose Updates

Present a clear summary of what needs to change in the document and why. For
each proposed update, explain what the document currently says, what the
implementation actually reflects, and what the document should say instead.

**Wait for the user's approval before making any edits.** The user may have
context about why certain discrepancies exist, or may want to adjust the
proposed updates before they're applied.

Once approved, make the edits. Preserve the document's existing structure and
voice — the goal is to update its content, not rewrite it.

$ARGUMENTS
