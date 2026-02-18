---
description: Describe the current commit with intent, or create a new one if needed — never a dummy message
---

Load the **jj** skill, then follow this process:

## 1. Read the Graph

Run `jj status` and `jj log -r '::@' --limit 10`. Understand:

- Is `@` an empty commit waiting to be described?
- Does `@` already have a description?
- Does `@` already have changes in the working copy?
- What do recent commit messages look like — what style, what conventions?

## 2. Decide What to Do

**If `@` is empty and undescribed:** This commit is waiting for intent. Proceed
to step 3.

**If `@` already has changes but no description:** The user has been working
without declaring intent. Proceed to step 3 — describe what's already there.

**If `@` already has a description but the code has diverged from it:** The
implementation may have evolved beyond the original intent — scope grew, the
approach changed, or the commit now does something different than described.
Compare the current diff (`jj diff`) against the existing description. If
they've drifted, update the description with `jj describe` to reflect what the
commit actually contains. Flag the discrepancy to the user.

**If `@` already has an accurate description:** The user may want to start a new
commit. Confirm with them before running `jj new`.

## 3. Plan Before Describing

Declaring intent for a commit is a planning opportunity. **Do not write a
throwaway or placeholder description.** If it's unclear what this commit should
contain, that means more discussion is needed — ask the user questions:

- What is the goal of this change?
- What files or modules will it touch?
- Is this a standalone unit, or part of a larger effort?
- Should this be one commit or should we plan to split it later?

A commit description is a contract. It should be specific enough that someone
reading the log can understand what the commit is for without looking at the
diff.

## 4. Describe

Match the commit message style from recent history. Run `jj describe -m "..."`
with a message that reflects the planned intent (or the work already done, if
changes are already in the working copy).

If the commit warrants a longer description body beyond the summary line, use
`jj describe` without `-m` to open the editor, or use a multi-line message.

$ARGUMENTS
