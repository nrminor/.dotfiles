---
name: jj-preemptive-conflict-resolution
description: 'Conflict microscope for Jujutsu repos: use when preemptively resolving future rebase conflicts, moving a commit under an active stack, making a later rebase clean, or deciding how to jj absorb/squash conflict resolutions into semantic owners without rebasing the whole stack.'
---

# JJ Preemptive Conflict Resolution

Use a **conflict microscope**: a temporary jj merge commit that previews how two lines of history combine without moving the real stack. Resolve only enough to learn where the semantic mismatch lives, then move the smallest owned change into the commit that should have contained it all along.

The goal is not to finish a rebase. The goal is to make the eventual rebase boring.

```text
actual graph stays mostly still:

base ── target-change
   ╲
    downstream stack ── active tips

temporary microscope:

base ── target-change ─╮
                       ├─ microscope merge  # disposable
downstream stack ──────╯
```

## Start with the graph

Run these before every mutation:

```sh
jj status
jj log -r 'conflicts()|divergent()' --limit 80
jj workspace list
jj log -r '@|@-|parents(@-)' --limit 80
```

Completion criterion: you can name the working-copy commit, the target commit being improved, every active workspace tip that could be affected, and whether conflicts or divergences already exist.

If `divergent()` is non-empty, stop and recover before doing design work. If other workspaces are active on nearby descendants, prefer the conflict microscope over broad `jj rebase`.

## Build the conflict microscope

Create a disposable merge between the commit you want underneath the stack and the downstream tip you want to preview.

```sh
jj new <target-change> <downstream-tip>
```

This is a microscope, not a solution. Its job is to expose the conflict surface.

Inspect it:

```sh
jj status
jj diff --stat
jj log -r 'conflicts()|divergent()|@|@-' --limit 80
```

Completion criterion: every conflicted path is classified as one of:

- downstream deleted or replaced this seam;
- downstream added shape that the target change must mirror;
- both sides edited a stable seam;
- the target change touched a file it should not own.

## Classify by semantic owner

Do not ask “how do I make the merge compile?” first. Ask “which commit should have owned this behavior if history had been written in the right order?”

Common classifications:

```text
downstream deleted/replaced an old seam
  -> remove the target-change edit from that old seam, or move behavior below it

downstream added tuple/API shape
  -> mirror the addition in the target-change only if the target truly owns that stable seam

stable implementation can compute locally
  -> move mode decisions down into the stable implementation instead of threading state upward

test file was removed downstream
  -> don't resurrect it just to preserve a tripwire; move only essential assertions to a surviving test home

temporary merge has a resolution hunk with a clear later owner
  -> absorb or squash into that later owner, not into the microscope
```

The best resolution often reduces the target change's footprint. A smaller target commit is easier to rebase over than a clever merge resolution.

## Prefer shrinking over threading

When a conflict exists because the target change threaded state through a soon-to-change seam, look for a lower stable home.

Bad shape:

```text
source computes derived value -> public API seam -> replacement layer -> stable implementation
```

Better shape:

```text
stable implementation derives the value locally from stable inputs
```

This is especially powerful when downstream deletes or replaces the middle seam. The target commit stops fighting a future deletion, while the behavior survives in the stable implementation.

Completion criterion: no new public output, tuple slot, parameter, method argument, event field, or channel exists merely to carry a value that can be derived locally from stable inputs.

## Move changes with narrow jj operations

For a change that belongs in the target commit, make a child of the target, edit only that child, verify the diff, then squash it into the target.

```sh
jj new <target-change>
# edit narrowly
jj diff --stat
jj diff --git
jj squash --into <target-change>
```

For a resolution hunk that belongs in an existing downstream commit, use targeted absorb only after inspecting the owning commit.

```sh
jj show --stat <owner>
jj diff -r <owner> --git -- <paths>
jj absorb -f <microscope> -t <owner> <paths>
```

Avoid broad targets like `mutable()` during conflict preemption. They make it too easy to move a hunk into the nearest textual match instead of the semantic owner.

Completion criterion: after each squash or absorb, `jj log -r 'conflicts()|divergent()'` is empty or contains only the disposable microscope conflict you intentionally recreated.

## Recreate the microscope after each semantic move

After amending a semantic owner, discard or leave behind no useful state in the old microscope. Recreate it from the updated commits:

```sh
jj new <target-change> <downstream-tip>
jj status
jj diff --stat
jj log -r 'conflicts()|divergent()|@|@-' --limit 80
```

Interpret the new surface:

- fewer conflicts means the semantic move worked;
- the same conflict means the move hit the wrong owner or was too shallow;
- new conflicts mean the move changed a public shape and needs reconsideration.

Completion criterion: the microscope merge is conflict-free and has either an empty diff or only intentional, well-owned integration changes.

## Verify on the microscope, then discard it

When the microscope is conflict-free, it represents the future rebased shape. Run the cheapest relevant checks there. Prefer the repository's canonical entrypoint if it has one (`just`, `make`, package scripts, CI-local wrapper); otherwise run focused checks for the files and APIs touched by the semantic move.

Then check leakage and graph health:

```sh
jj status
jj log -r 'conflicts()|divergent()' --limit 80
jj diff --stat
```

If the microscope is empty and only served as a preview, move the workspace back to the real target and let jj hide the disposable merge:

```sh
jj new <target-change>
```

Only abandon by explicit, current revision id after inspection. Stale change ids disappear from the visible graph, and abandoning the wrong active tip is worse than leaving a hidden empty microscope.

Completion criterion: the working copy is clean, there are no conflicts or divergences, and the target commit's diff contains only files it semantically owns.

## Escalate to a real rebase only when surgery fails

The bold rebase is still available:

```sh
jj rebase -s <stack-base> -d <target-change>
```

Use it only after the conflict microscope stops reducing the surface or the user explicitly wants the actual rebase now. Before a broad rebase, say which workspace tips and bookmarks will move.

If a broad rebase creates conflict explosion, prefer operation recovery over hand-resolving dozens of descendants:

```sh
jj op log --limit 10
jj op restore <operation-before-rebase>
```

Completion criterion: the user understands that the operation moves a stack, not just a disposable microscope.

## Recovery rules

When graph surgery goes sideways, stop mutating and read the operation log.

```sh
jj status
jj log -r 'conflicts()|divergent()' --limit 80
jj op log --limit 12
```

Use `jj op restore <op>` when you need to return the whole repo view to a known pre-mutation state. Use `jj undo` only when the immediately previous operation is definitely the one to reverse. Do not stack blind undos across other workspace activity.

Completion criterion: recovery target is named by operation id, command, and observed graph state, not by vibes.

## Report format

When reporting progress to the user, keep the graph state and semantic lesson visible:

```text
Current graph:
- @: <change-id> <summary>
- target: <change-id> <summary>
- downstream previewed against: <change-id> <summary>
- conflicts/divergences: none | listed

Semantic moves made:
- <file/path>: <what moved> -> <owner commit>

Verification:
- <command>: passed/failed

Remaining risk:
- <one honest caveat, or "none observed in the microscope">
```

Never call a future rebase painless unless a conflict-free microscope or an actual rebase proves it.
