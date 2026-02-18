---
name: jj
description: Jujutsu (jj) version control for the user's preferred workflow — graph-aware, describe-first, split-oriented, with stacked PRs. Use when working with jj repositories, manipulating the commit graph, creating PRs, or any version control operation in a jj repo. Load the vcs-detect skill first if unsure whether the repo uses jj.
---

# Jujutsu (jj) Version Control

jj is a version control system built on a mutable directed acyclic graph of
commits. That sentence is the most important thing in this skill. Everything
else follows from it: every operation you perform — new, describe, split,
rebase, bookmark — is a graph manipulation. Your job is to understand the graph,
reason about it, and transform it.

## Before Doing Anything: Read the Graph

**Always run `jj status` and `jj log` before performing any operation.** This is
not optional. You need to know:

- What changes are in the working copy (`@`)
- What the commit graph looks like — parent/child relationships, where bookmarks
  point, what's been pushed to remotes
- Whether there are conflicts (marked with `×` in the log)
- Whether bookmarks are divergent (marked with `??`)

```bash
jj status    # Working copy state — what files changed, any conflicts
jj log       # The commit graph — topology, bookmarks, descriptions
```

If you skip this step and start making changes blind, you will make mistakes.
The graph is your map. Read it first.

## The User's Workflow: Describe-First, Split-Later

This is how the user works. Internalize it:

1. **Start a new commit and declare intent.** `jj new` to create a fresh
   working copy commit, then `jj describe -m "feat: implement X"` to state what
   this commit will contain. The description is a contract — it says what the
   commit is *for* before any code is written.

2. **Implement.** Write code in the working copy. jj tracks everything
   automatically — there's no staging area.

3. **Split if the commit grew too large.** If the implementation touched more
   than one logical concern, use `jj split` to carve out separate commits. Each
   resulting commit should be a focused, standalone unit.

4. **Each commit must be a standalone unit.** It compiles. It passes checks. It
   passes tests. This is non-negotiable — it enables `jj bisect` and keeps the
   history useful. Never create fragmentary commits that only make sense as part
   of a sequence.

The user does **not** typically work by creating many tiny `jj new` commits and
squashing them together. The direction is: one commit that grows, then split
into focused pieces. `jj squash` is used occasionally but is not the primary
tool.

## Core Commands

### Creating and Describing Commits

⚠️ **Do not reflexively run `jj new -m "..."`.** The user will almost always
have already created a new empty commit at the right point in the graph before
handing off to you. If you run `jj new -m` without checking, you'll leave
behind an empty commit. **Always `jj status` first** to see whether `@` is
already an empty commit waiting to be described. If it is, use `jj describe`,
not `jj new`.

When writing commit descriptions with `jj describe`, **review recent commits
first** (`jj log -r '::@' --limit 10` or similar) to match the style the user
has been using. Don't impose a commit message convention; follow the one that's
already in the history.

**Commit descriptions have two parts:**

1. **A short summary line** that fits neatly in `jj log` output — concise
   enough to scan at a glance. This is the first line of the description.

2. **A detailed body** separated from the summary by a blank line. The body
   should exhaustively describe what changed and why, organized into sections
   with blank lines between them. Write it almost like a short blog post — it
   should be readable on its own and provide enough context that someone
   encountering this commit in a `jj show` or a PR description understands the
   full picture without needing to read the diff. Each commit should be able to
   serve as its own PR description if needed.

```bash
jj new                        # New empty working copy commit on top of @
jj new <parent>               # New commit with specific parent
jj new <parent1> <parent2>    # New merge commit with multiple parents
jj describe -m "message"      # Set description of working copy (@)
jj describe -r <id> -m "msg"  # Set description of a specific commit
jj commit -m "message"        # Shorthand: describe @ and create new @
```

### Splitting and Squashing

```bash
jj split                      # Interactively split @ into two commits
jj split -r <id>              # Split a specific commit
jj squash                     # Squash @ into its parent
jj squash -r <id>             # Squash a specific commit into its parent
jj squash --into <id>         # Squash @ into a specific target commit
```

### Rebasing

Rebase is the most common graph operation after describe. The user works with
stacked commits and stacked PRs, which means rebase comes up constantly —
especially after fetching remote changes or when reordering commits in a stack.

```bash
jj rebase -d <dest>                  # Rebase @ onto a new parent
jj rebase -r <id> -d <dest>          # Rebase a single commit (children follow)
jj rebase -s <id> -d <dest>          # Rebase a commit and all its descendants
jj rebase -b <id> -d <dest>          # Rebase a commit and all its ancestors
                                     #   up to the nearest common ancestor with dest
```

**Anticipate rebase needs.** When you see that `main@origin` has moved ahead of
the base of a commit stack, or that a PR's bookmark is behind, suggest or
perform a rebase. Don't wait for the user to notice.

### Bookmarks (Not Branches)

jj uses "bookmarks" where git uses "branches." Bookmarks are pointers to
commits — they don't auto-advance.

```bash
jj bookmark create <name>              # Point a bookmark at @
jj bookmark create <name> -r <id>      # Point at a specific commit
jj bookmark move <name> --to <id>      # Move a bookmark to a different commit
jj bookmark delete <name>              # Delete a local bookmark
jj bookmark list                       # List all bookmarks
jj bookmark list -a                    # List all bookmarks including remote
jj bookmark track <name>@<remote>      # Track a remote bookmark locally
```

### Syncing with Remotes

```bash
jj git fetch                           # Fetch from all remotes
jj git push --bookmark <name>          # Push a specific bookmark
jj git push -c <id>                    # Push a commit (auto-creates bookmark)
```

The user also has custom commands:

- **`jj tug`** — fetches from remote and rebases the current commit onto the
  updated remote tracking bookmark. Equivalent to `jj git fetch` followed by a
  rebase.
- **`jj tush`** — tug followed by push. The user typically prefers to handle
  pushing themselves, so don't run `jj tush` or `jj git push` without asking.

### Viewing and Navigating

```bash
jj status                    # Working copy state
jj log                       # Commit graph
jj log -r <revset>           # Filtered view
jj show <id>                 # Full diff of a commit
jj diff                      # Working copy diff
jj diff -r <id>              # Diff of a specific commit
jj op log                    # Operation history (your undo stack)
```

### Undoing and Recovery

```bash
jj undo                      # Undo the last operation
jj op log                    # View operation history
jj op restore <op-id>        # Restore to a specific operation state
```

⚠️ **Never `jj undo` after `jj git push`.** This creates stale remote state.
Make forward fixes instead.

## Revsets

Revsets are jj's query language for selecting commits. They're how you express
"which commits" for any operation.

```bash
@                    # Working copy
@-                   # Parent of working copy
@--                  # Grandparent
::@                  # All ancestors of @
@::                  # All descendants of @
main..@              # Commits reachable from @ but not from main
main@origin..@       # Commits ahead of remote main
description("fix")   # Commits whose description contains "fix"
author("alice")      # Commits by alice
bookmarks()          # All commits with bookmarks
```

Revsets are composable with `|` (union), `&` (intersection), and `~` (negation):

```bash
jj log -r 'main@origin..@ & ~empty()'   # Non-empty commits ahead of remote main
```

## Stacked PRs

The user frequently works with stacked PRs — multiple commits in a chain, each
with its own bookmark and its own GitHub PR. The typical structure:

```
main@origin
  └── feat-base (bookmark, PR #1)
        └── feat-part2 (bookmark, PR #2)
              └── feat-part3 (bookmark, PR #3)
                    └── @ (working copy)
```

### Creating a Stack

```bash
jj new main@origin
jj describe -m "feat: base infrastructure for X"
# ... implement ...
jj bookmark create feat-base
jj git push --bookmark feat-base

jj new
jj describe -m "feat: add Y on top of base"
# ... implement ...
jj bookmark create feat-part2
jj git push --bookmark feat-part2
```

### Updating a Stack After Review Feedback

When you need to change a commit in the middle of a stack:

```bash
# Edit the commit that needs changes
jj new <commit-to-fix>
# ... make fixes ...
jj squash                    # Squash fixes into the target commit

# All descendants automatically rebase — but check the graph:
jj log
# Verify no conflicts, then update bookmarks and push
```

### Rebasing a Stack onto Updated Main

```bash
jj git fetch
jj rebase -s <stack-base> -d main@origin
# All commits in the stack rebase together
# Update bookmarks if needed, then push
```

### After a PR in the Stack is Merged

When a PR at the base of the stack is merged on GitHub:

```bash
jj git fetch                              # Fetch the merge
jj rebase -s <next-in-stack> -d main@origin  # Rebase remaining stack
jj bookmark delete <merged-bookmark>      # Clean up merged bookmark
```

## Conflict Resolution

Conflicts are recorded in the commit graph, not in your working copy files (until
you check out the conflicted commit). They're marked with `×` in `jj log`.

```bash
# Check out the conflicted commit
jj new <conflicted-id>

# Files now contain conflict markers — resolve them in your editor:
# <<<<<<< Conflict 1 of 1
# +++++++ Contents of side #1
# ...
# ------- Contents of base
# ...
# +++++++ Contents of side #2
# ...
# >>>>>>> Conflict 1 of 1 ends

# After resolving, squash the resolution into the conflicted commit:
jj squash
```

## Safety Rules

- **Always read the graph first.** `jj status` and `jj log` before any
  operation.
- **Don't `jj new` without checking status.** The user has almost certainly
  already created the commit for you. Check before creating another one.
- **Match the existing commit message style.** Review recent history before
  writing descriptions.
- **Never `jj undo` after pushing.** Make forward fixes instead.
- **Don't mix raw git commands with jj** in the same repo session. Use jj for
  everything; it manages the git backend.
- **Don't push without asking.** The user prefers to control when things go to
  the remote. You can prepare bookmarks and suggest pushing, but let the user
  pull the trigger.
- **Divergent bookmarks (`??`) cannot be pushed.** Resolve with
  `jj bookmark move <name> --to <commit>` first.

## Working with GitHub (`gh` CLI)

The user frequently uses `jj` in tandem with the `gh` GitHub CLI for creating
PRs, reviewing PR status, checking CI results, and managing issues. Expect to
combine `jj` graph operations with `gh` commands regularly — they are
complementary tools, not alternatives.

Useful `gh` commands in the jj workflow:

```bash
gh pr list                                # See open PRs
gh pr view <number>                       # View a specific PR
gh pr checks <number>                     # Check CI status on a PR
gh pr create --base <branch> --head <bm>  # Create a PR from a bookmark
gh pr merge <number> --squash             # Merge a PR (then fetch + rebase locally)
gh issue list                             # See open issues
gh issue view <number>                    # View a specific issue
```

### Creating PRs from jj Commits

To create a PR from a jj commit:

```bash
# 1. Push the commit (creates a bookmark automatically if needed)
jj git push -c <change-id>
# Note the bookmark name from the output

# 2. Get the default branch
gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'

# 3. Create the PR
gh pr create \
  --base <default-branch> \
  --head <bookmark-name> \
  --title "<first line of jj description>" \
  --body "<PR description>"
```

For stacked PRs, set `--base` to the bookmark of the parent PR rather than
main.
