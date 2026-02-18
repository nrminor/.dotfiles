---
name: codebase-searcher
description: Efficient codebase search using ripgrep, ast-grep, and VCS-aware tooling. Teaches agents to find information in codebases with minimal token overhead, like a query engine with pushdown optimizations. Use when you need to find definitions, call sites, imports, or understand code structure without reading entire files.
---

# Codebase Search Skill

This skill teaches you to search codebases the way a query engine searches a
database: plan your query, push filters as close to the source as possible, and
only materialize the rows (lines) you actually need. Every file you read in full
is a table scan. Don't do table scans.

## The Pushdown Principle

The single most important idea in this skill is **pushdown optimization**: never
load data into context that you could have filtered out earlier. In practice:

1. **Start with the narrowest query that could work.** `rg -l` to find files,
   not `rg` to dump every match. `rg -c` to count hits, not `rg` to read them.
2. **Filter by language/path before searching content.** `rg -trust` or
   `sg -l rs` eliminates irrelevant files before any content is examined.
3. **Use context lines sparingly.** `-C 3` gives you orientation; `-C 20` gives
   you token bloat. If you need more, use `read` with a targeted line range.
4. **Never `cat` a file to search it.** That's a full table scan followed by a
   client-side filter. Use `rg pattern file` or `sg -p pattern file` instead.
5. **Refine iteratively.** A broad `rg -l` to find candidate files, then a
   targeted `rg -n` or `sg` on those files, then `read` with offset/limit for
   the specific section you need.

## Presenting Results

When you find what you're looking for, **show it**. Always include:

- **File path and line numbers** for every result. The caller needs to know
  exactly where something lives, not just that it exists.
- **Code blocks** illustrating what you found. A 5-10 line excerpt with context
  is almost always more useful than a prose summary of what the code does. Let
  the code speak for itself.
- **Your interpretation after the code**, not instead of it. Summarize what the
  excerpt shows, but the excerpt comes first.

The goal is that the caller could navigate directly to the relevant code from
your response without any additional searching.

## Tool Selection

### `rg` (ripgrep) — text/regex search

Use `rg` for any content search that doesn't require structural awareness:
string literals, identifiers, error messages, comments, config values, or any
pattern expressible as a regex.

`rg` respects `.gitignore` automatically, skips binary files, and is
dramatically faster than `grep`. Always prefer it over the built-in grep tool
for bash-based searches.

**Key flags for efficient searching:**

| Flag | Purpose | When to use |
|------|---------|-------------|
| `-l` | Filenames only | First pass — scope before reading |
| `-c` | Match count per file | Gauging usage breadth |
| `--count-matches` | Total matches (not lines) | Precise usage counts |
| `-t <lang>` | Language filter (`-trust`, `-tpy`, `-tts`) | Always, in polyglot repos |
| `-g '<glob>'` | Path glob filter (`-g '!*test*'`) | Excluding tests, fixtures |
| `-n` | Line numbers | Always when piping (on by default in terminal) |
| `-w` | Word boundary | Preventing `foo` matching `foobar` |
| `-F` | Fixed string (no regex) | Patterns with `.`, `[`, `(`, etc. |
| `-C <n>` | Context lines | Use `-C 3`, not `-C 20` |
| `-A`/`-B <n>` | Asymmetric context | When you need lines after but not before |
| `-U` | Multiline mode | Cross-line patterns |
| `-o` | Only matching portion | Extracting specific substrings |
| `--no-ignore` | Include gitignored files | Searching build output or vendored code |

**Examples:**

```bash
# Find which files import a module (filenames only — cheap first pass)
rg -l 'from pathlib import' -tpy

# Count API usage across the codebase
rg -c 'useState\(' -tts | sort -t: -k2 -rn

# Find a function definition with its signature
rg 'fn process_batch\(' -trust -n -A 5

# Find a TypeScript interface and its fields
rg '^(export )?interface UserConfig' -tts -n -A 10

# Search for a literal string with regex metacharacters
rg -F 'array[0].value' -tts -n
```

**Anti-patterns:**

- `rg pattern` without `-l` when you only need filenames — dumps every match
- `rg pattern` without `-t` in a polyglot repo — searches everything
- `-C 20` speculatively — use `-C 3` then `read` the file if you need more
- Forgetting `-F` for literal strings with regex metacharacters
- Using `cat file | grep pattern` instead of `rg pattern file`

### `sg` (ast-grep) — structural/AST search

Use `sg` when text search would produce false positives or miss structurally
equivalent code. `sg` parses source into an AST and matches against it, so it
ignores formatting, skips comments and string literals, and can distinguish
definitions from call sites.

**When `sg` beats `rg`:**

- Finding function definitions vs. call sites (text search can't tell them apart)
- Matching regardless of formatting (wrapped arguments, different indentation)
- Avoiding false positives in strings and comments
- Capturing sub-expressions with metavariables

**Pattern syntax essentials:**

Patterns are written as real code with metavariables for the parts you want to
match:

- `$NAME` — matches any single AST node (like a typed `.` in regex)
- `$$$` or `$$$ARGS` — matches zero or more nodes (argument lists, statement bodies)
- Same-name metavariables are backreferences: `$A == $A` matches only when both
  sides are identical
- Metavariable names must be `UPPER_CASE` — `$foo` is a literal `$foo`, not a
  metavariable

**Key flags:**

| Flag | Purpose |
|------|---------|
| `-p <pattern>` | The AST pattern to match (required) |
| `-l <lang>` | Language: `rs`, `py`, `ts`, `tsx`, `js`, `go`, `java`, `c`, `cpp` |
| `--json` | JSON output (pipe to `jq` for extraction) |
| `-C <n>` | Context lines |
| `--debug-query=ast` | Print pattern's AST — essential for debugging |

Always specify `-l`. Without it, `sg` infers from file extensions, which can be
surprising.

**Examples:**

```bash
# Find all call sites of a function (not just the string)
sg -p 'process_request($$$)' -l py

# Find async function definitions in Rust
sg -p 'async fn $NAME($$$) { $$$ }' -l rs

# Find all ES imports from a specific package
sg -p "import $$$NAMES from 'react'" -l ts

# Find method definitions (Python)
sg -p 'def $NAME(self, $$$): $$$' -l py

# Find calls that pass a mutable reference
sg -p '$FUNC(&mut $ARG)' -l rs
```

**Anti-patterns:**

- Using `sg` for simple string searches — `rg` is faster and simpler for those
- Lowercase metavariables (`$foo`) — these are literals, not captures
- `$VAR` when you mean `$$$` — `console.log($ARG)` won't match
  `console.log(a, b)`; use `console.log($$$)`
- Forgetting `-l` — always specify the language explicitly
- Cross-language searches — `sg` targets one language per invocation

**If a pattern isn't matching**, use `--debug-query=ast` to see how `sg` parsed
it, or test in the [playground](https://ast-grep.github.io/playground.html).

### Built-in tools: `grep`, `glob`, `read`

The built-in tools still have their place:

- **`glob`** — finding files by name pattern. Faster than `rg --files` when you
  know the filename pattern and don't need content search.
- **`grep`** (built-in) — acceptable for quick searches, but `rg` via bash is
  faster and smarter about ignoring irrelevant files.
- **`read`** with offset/limit — the precision tool. Once you know the file and
  approximate line range from `rg -n` or `sg`, use `read` to pull exactly the
  lines you need with full context. This is the "index lookup" after the "index
  scan."

## VCS-Aware Search

Version control history is a powerful search index that most agents ignore.
Before doing a broad codebase search, consider whether the VCS can shortcut you
to the answer.

### Finding what changed

```bash
# What files were touched in the last 5 commits? (narrows your search space)
jj log -r 'ancestors(@, 5)' --stat
git log --oneline --stat -5

# What changed in a specific file recently?
jj diff -r 'ancestors(@, 10)' -- path/to/file.rs
git log -p -5 -- path/to/file.rs

# Who last touched a specific line range?
git blame -L 42,60 path/to/file.rs
```

### Using difftastic for structural diffs

`difft` is a structural diff tool — it parses code into ASTs and diffs the
trees, ignoring formatting changes. Use it when a regular diff is noisy with
reformatting:

```bash
# Structural diff of uncommitted changes
git -c diff.external=difft diff

# Structural diff of a specific commit
git -c diff.external=difft show --ext-diff HEAD~1

# Compare two files directly
difft old_version.rs new_version.rs
```

`difft` is especially useful when reviewing refactors that mixed formatting
changes with logic changes — it shows only the semantic differences.

### Bisecting to find when something changed

When you need to find which commit introduced a behavior:

```bash
# git bisect with a test command
git bisect start HEAD v1.0.0
git bisect run cargo test --test specific_test

# jj equivalent: inspect the log for the relevant change
jj log -r 'ancestors(@) & ~ancestors(tag("v1.0.0"))' --stat
```

Always detect the VCS first (see the **vcs-detect** skill) — use `jj` commands
in jj repos and `git` commands in git repos.

## Acquiring Source Code

Sometimes you need to search a codebase you don't have locally — a dependency's
source, an upstream library, a reference implementation. Before cloning:

1. **Find the repository URL.** If you don't know it, ask the
   **documentation-nerd** agent to look it up. Don't guess at URLs.

2. **Ask the user before cloning.** Specifically:
   - **Where** should the clone go? Don't put repos in arbitrary locations.
   - **Which VCS** — `jj git clone` or `git clone`? Detect the project's VCS
     preference with the **vcs-detect** skill and suggest accordingly.
   - **Shallow or deep?** Default to shallow (`git clone --depth 1` or
     `jj git clone --depth 1`) unless the user needs full history for bisect or
     blame.
   - **Should this be part of a setup recipe?** If the project has a `justfile`
     or `Makefile`, the user may want the clone added as a recipe/rule rather
     than done ad hoc.

3. **Clone, then search.** Don't try to read source code from web interfaces
   when you could clone and use `rg`/`sg` locally. Local search is faster and
   more thorough.

## Search Strategy Patterns

### "Where is X defined?"

```bash
# 1. Try ast-grep for structural match (most precise)
sg -p 'fn $NAME($$$)' -l rs    # function definitions
sg -p 'class $NAME { $$$ }' -l py  # class definitions
sg -p 'interface $NAME { $$$ }' -l ts  # interface definitions

# 2. Fall back to rg with definition-like patterns
rg '^(pub )?(fn|struct|enum|trait|type|const) X' -trust -n -A 5
rg '^(export )?(function|class|interface|type|const) X' -tts -n -A 5
rg '^(def|class) X' -tpy -n -A 5
```

### "Where is X used?"

```bash
# 1. Count usage breadth first (cheap)
rg -c 'X' -trust

# 2. If many hits, narrow by excluding definitions and tests
rg 'X' -trust -g '!*test*' -g '!*spec*' -n -C 3

# 3. For call sites specifically, use ast-grep
sg -p 'X($$$)' -l rs
```

### "What does X depend on?" / "What depends on X?"

```bash
# Imports of X (what X's users look like)
rg -l 'use .*X' -trust        # Rust
rg -l "from.*import.*X" -tpy  # Python
rg -l "import.*X" -tts        # TypeScript

# X's own imports (what X depends on)
rg '^use ' path/to/x.rs -n    # Rust
rg '^(from|import) ' path/to/x.py -n  # Python
```

### "What changed about X recently?"

```bash
# 1. Find where X lives
rg -l 'X' -trust

# 2. Check recent changes to those files
git log --oneline -10 -- path/to/file.rs
jj log -r 'ancestors(@, 10)' -- path/to/file.rs

# 3. See the actual changes
git log -p -5 -- path/to/file.rs | rg -C 3 'X'
```

## Escalation

- **Can't find documentation for an API?** → **documentation-nerd** agent
- **Need to understand architectural decisions behind the code?** → **oracle** agent
- **Found something that looks like a design problem?** → **architecture-advice** agent
