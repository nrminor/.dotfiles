---
description: Find and clean up empty or undescribed intermediate commits in the graph
---

Load the **jj** skill, then audit the commit graph for hygiene issues.

## 1. Read the Graph

Run `jj log` to see the full local commit graph. Identify intermediate commits
(everything except `@`) that have any of these problems:

- **Empty commits** — no file changes, just a node in the graph
- **Undescribed commits** — have changes but no description (or only the default
  "(no description set)" placeholder)
- **Vague or placeholder descriptions** — things like "wip", "temp", "fixup",
  "asdf", or other non-descriptive messages

Ignore `@` — the working copy commit is expected to be in-progress.

## 2. Report Findings

List every problematic commit you found with its change ID, current description
(or lack thereof), and what files it touches (if any). Group them by issue type.

## 3. Recommend Actions

For each problematic commit, recommend one of:

- **Abandon** — if the commit is empty and has no descendants that depend on it.
  Command: `jj abandon <id>`
- **Squash into parent** — if the commit is a small leftover that logically
  belongs with its parent. Command: `jj squash -r <id>`
- **Describe** — if the commit has meaningful changes but was never given a
  proper description. Suggest a description based on the diff.

Present the recommendations and **wait for the user's approval** before
executing any of them. Don't abandon or squash commits without confirmation —
the user may have context about why a commit looks the way it does.

## 4. Execute Approved Cleanups

After the user approves (all or a subset), execute the agreed-upon operations.
After each operation, run `jj log` to verify the graph looks correct before
proceeding to the next.

$ARGUMENTS
