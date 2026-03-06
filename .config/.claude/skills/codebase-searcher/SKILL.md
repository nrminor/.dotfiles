---
name: codebase-searcher
description: Efficient codebase search using a three-tier strategy — codemogger (semantic), ast-grep (structural), and ripgrep (textual fallback) — with VCS-aware tooling. Teaches agents to find information in codebases with minimal token overhead by choosing the right level of search abstraction rather than defaulting to text grep.
---

# Codebase Search Skill

This skill teaches you to search codebases the way a query engine searches a
database: plan your query, push filters as close to the source as possible, and
only materialize the rows (lines) you actually need. Every file you read in full
is a table scan. Don't do table scans.

More importantly, this skill teaches you to **choose the right level of search
abstraction**. Your primary search tools are bash commands — `codemogger` first
for maximally efficient semantic search, then `sg`/`ast-grep` for structural search,
and then `rg` (ripgrep) for textual search as the least efficient last resort. Do
not default to using Glob + Read as a search strategy. Globbing for files and then
reading them one by one to find information is the most token-expensive and least
focused approach possible. Use your bash search tools to find what you're looking for,
then use Read only to pull the specific line ranges you need from the results.

## The Pushdown Principle

The single most important idea in this skill is **pushdown optimization**: never
load data into context that you could have filtered out earlier. In practice:

1. **Start with the most semantically appropriate tool.** A conceptual query
   deserves a semantic search tool, not a regex. A structural query deserves an
   AST-aware tool, not a string match.
2. **Filter by language/path before searching content.** Language filters
   eliminate irrelevant files before any content is examined.
3. **Use context lines sparingly.** `-C 3` gives you orientation; `-C 20` gives
   you token bloat. If you need more, use `read` with a targeted line range.
4. **Never `cat` a file to search it.** That's a full table scan followed by a
   client-side filter.
5. **Refine iteratively.** But if you find yourself doing three or four rounds
   of increasingly specific ripgrep queries, that's a sign you should have
   started with a higher-tier tool.

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

## Tool Selection: The Three-Tier Strategy

Your tools are organized into three tiers, from most focused to least. **Start
at the highest applicable tier and fall back only when needed.** The tiers
aren't about tool quality — they're about search precision. Higher tiers
understand more about your code and return more focused results.

### Tier 1: `bunx codemogger` — semantic search

Codemogger parses source code with tree-sitter, chunks it into semantic units
(functions, structs, classes, impl blocks), embeds them with a local ML model,
and stores everything in a SQLite database with vector and full-text search. No
API keys, no external services — everything runs locally.

**This is your first line of defense** for conceptual or exploratory queries,
especially in unfamiliar codebases. When you don't know the exact name of what
you're looking for but can describe what it does, codemogger is the right tool.

**A note on maturity:** codemogger is young (v0.1.x) and experimental. It works
remarkably well when it works, but you should expect rough edges. If it fails or
produces poor results, fall back gracefully to Tier 2 or 3. Don't spend time
debugging codemogger itself — just move on.

**Indexing a codebase:**

Before you can search semantically, the codebase needs a one-time index step.
Check for an existing index first, then create one if needed:

```bash
# Check if an index already exists (look for a .db file in the project root)
ls *.db 2>/dev/null

# Index the codebase (one-time cost — subsequent searches are fast)
bunx codemogger index .

# Re-index after files have changed (incremental — only processes changed files)
bunx codemogger reindex
```

Indexing time is dominated by embedding computation. For large codebases this
can take a minute or two on first run, but incremental reindexing is fast since
it only processes files whose content has changed (tracked by SHA-256 hash).

**Searching:**

```bash
# Semantic search — natural language queries
bunx codemogger search "authentication middleware"
bunx codemogger search "retry logic with exponential backoff"
bunx codemogger search "database connection pooling"

# Keyword search — precise identifier lookup (faster than ripgrep on indexed codebases)
bunx codemogger search --mode keyword "ProcessRequest"
bunx codemogger search --mode keyword "handle_connection"
```

Semantic mode (the default) uses vector similarity to find code that's
conceptually related to your query, even if it doesn't contain the exact words.
Keyword mode uses full-text search and is useful when you know the identifier
name — it's often faster than ripgrep because it searches an index rather than
scanning files.

**When to use codemogger:**

- You can describe what you're looking for but don't know the exact name
- You're exploring an unfamiliar codebase and need to find where concepts live
- You want definitions and implementations, not just string matches
- The codebase is already indexed (or worth indexing for repeated searches)

**When to skip codemogger:**

- The codebase isn't indexed and you only need one quick search (indexing
  overhead isn't worth it for a single query)
- The language isn't supported (codemogger supports: Rust, C, C++, Go, Python,
  Zig, Java, Scala, JavaScript, TypeScript, TSX, PHP, Ruby)
- You need regex patterns or complex text matching
- You're searching non-code files (markdown, config, logs)

**Supported languages:** Rust, C, C++, Go, Python, Zig, Java, Scala,
JavaScript, TypeScript, TSX, PHP, Ruby (13 languages via tree-sitter WASM
grammars).

### Tier 2: `sg` (ast-grep) — structural/AST search

Use `sg` when you know the syntactic shape of what you're looking for. `sg`
parses source into an AST and matches against it, so it ignores formatting,
skips comments and string literals, and can distinguish definitions from call
sites. This is the workhorse for precise structural queries.

**When `sg` is the right starting point:**

- Finding function definitions vs. call sites (text search can't tell them apart)
- Matching regardless of formatting (wrapped arguments, different indentation)
- Avoiding false positives in strings and comments
- Capturing sub-expressions with metavariables
- You know the syntactic pattern but not the specific identifiers

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

| Flag                | Purpose                                                           |
| ------------------- | ----------------------------------------------------------------- |
| `-p <pattern>`      | The AST pattern to match (required)                               |
| `-l <lang>`         | Language: `rs`, `py`, `ts`, `tsx`, `js`, `go`, `java`, `c`, `cpp` |
| `--json`            | JSON output (pipe to `jq` for extraction)                         |
| `-C <n>`            | Context lines                                                     |
| `--debug-query=ast` | Print pattern's AST — essential for debugging                     |

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

### Tier 3: `rg` (ripgrep) — textual/regex search

Ripgrep is fast, brute-force text search. It respects `.gitignore`
automatically, skips binary files, and is dramatically faster than `grep`. But
it is inherently unfocused — it matches text in code, comments, strings, and
documentation indiscriminately.

**Ripgrep is essential for:**

- Searching non-code files (markdown, config, logs, READMEs)
- Languages not supported by codemogger or ast-grep
- Literal string searches (error messages, URLs, magic constants)
- Simple identifier counts when you just need breadth (`rg -c`)
- Quick filename scoping (`rg -l`) before a more targeted search

**Ripgrep is a poor choice for:**

- Finding where a concept is implemented (use codemogger)
- Distinguishing definitions from call sites (use ast-grep)
- Any query where you find yourself adding exclusion after exclusion to filter
  out false positives — that's a signal you need a higher-tier tool

**Key flags for efficient searching:**

| Flag              | Purpose                                    | When to use                                    |
| ----------------- | ------------------------------------------ | ---------------------------------------------- |
| `-l`              | Filenames only                             | First pass — scope before reading              |
| `-c`              | Match count per file                       | Gauging usage breadth                          |
| `--count-matches` | Total matches (not lines)                  | Precise usage counts                           |
| `-t <lang>`       | Language filter (`-trust`, `-tpy`, `-tts`) | Always, in polyglot repos                      |
| `-g '<glob>'`     | Path glob filter (`-g '!*test*'`)          | Excluding tests, fixtures                      |
| `-n`              | Line numbers                               | Always when piping (on by default in terminal) |
| `-w`              | Word boundary                              | Preventing `foo` matching `foobar`             |
| `-F`              | Fixed string (no regex)                    | Patterns with `.`, `[`, `(`, etc.              |
| `-C <n>`          | Context lines                              | Use `-C 3`, not `-C 20`                        |
| `-A`/`-B <n>`     | Asymmetric context                         | When you need lines after but not before       |
| `-U`              | Multiline mode                             | Cross-line patterns                            |
| `-o`              | Only matching portion                      | Extracting specific substrings                 |
| `--no-ignore`     | Include gitignored files                   | Searching build output or vendored code        |

**Examples:**

```bash
# Find which files import a module (filenames only — cheap first pass)
rg -l 'from pathlib import' -tpy

# Count API usage across the codebase
rg -c 'useState\(' -tts | sort -t: -k2 -rn

# Search for a literal string with regex metacharacters
rg -F 'array[0].value' -tts -n

# Search for an error message across all file types
rg -F 'connection refused' -n -C 3
```

**Anti-patterns:**

- Reaching for `rg` as the default tool for every search — it's Tier 3 for a
  reason
- `rg pattern` without `-l` when you only need filenames — dumps every match
- `rg pattern` without `-t` in a polyglot repo — searches everything
- `-C 20` speculatively — use `-C 3` then `read` the file if you need more
- Forgetting `-F` for literal strings with regex metacharacters
- Multiple rounds of `rg` with increasingly complex exclusions — step back and
  use ast-grep or codemogger instead
- Using `cat file | grep pattern` instead of `rg pattern file`

### Built-in tools: `glob` and `read`

The built-in tools still have their place:

- **`glob`** — finding files by name pattern. Faster than `rg --files` when you
  know the filename pattern and don't need content search.
- **`read`** with offset/limit — the precision tool. Once you know the file and
  approximate line range from any of the three tiers, use `read` to pull exactly
  the lines you need with full context. This is the "index lookup" after the
  "index scan."

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

3. **Clone, then index, then search.** After cloning, consider running
   `bunx codemogger index .` so that subsequent searches benefit from semantic
   search. Local indexed search is faster and more thorough than anything else.

## Search Strategy Patterns

### "Where is X defined?"

```bash
# 1. If the codebase is indexed, try semantic search first
bunx codemogger search "X"
bunx codemogger search --mode keyword "X"

# 2. Try ast-grep for structural match (most precise for known syntax)
sg -p 'fn X($$$)' -l rs           # Rust function
sg -p 'class X { $$$ }' -l py     # Python class
sg -p 'interface X { $$$ }' -l ts  # TypeScript interface

# 3. Fall back to rg with definition-like patterns
rg '^(pub )?(fn|struct|enum|trait|type|const) X' -trust -n -A 5
rg '^(export )?(function|class|interface|type|const) X' -tts -n -A 5
rg '^(def|class) X' -tpy -n -A 5
```

### "Where is X used?"

```bash
# 1. For call sites specifically, use ast-grep (no false positives)
sg -p 'X($$$)' -l rs

# 2. Count usage breadth with rg (cheap scoping)
rg -c 'X' -trust

# 3. If many hits, narrow by excluding definitions and tests
rg 'X' -trust -g '!*test*' -g '!*spec*' -n -C 3
```

### "How does the authentication / retry / caching work?"

This is a conceptual query — codemogger shines here:

```bash
# Semantic search finds implementations by concept, not name
bunx codemogger search "authentication middleware"
bunx codemogger search "retry logic with backoff"
bunx codemogger search "cache invalidation strategy"
```

If the codebase isn't indexed, fall back to keyword-based approaches with
ast-grep and ripgrep, but expect to spend more rounds narrowing down results.

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
# 1. Find where X lives (use the best available tool)
bunx codemogger search --mode keyword "X"  # if indexed
rg -l 'X' -trust                            # fallback

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
