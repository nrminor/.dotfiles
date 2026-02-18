---
name: back-of-envelope
description: Quick, disposable experiments to verify reasoning — runtime behavior with Bun TypeScript, type system contracts with TypeScript or Rust, data questions with DuckDB or nushell. Use when you need to check an assumption, sketch an API shape, or test whether an idea works before committing to it.
---

# Back-of-Envelope Sketching

This skill is for throwaway experiments — the computational equivalent of
scribbling on a napkin. You have a question about how something behaves, whether
a type constraint is expressible, or whether your mental model is correct. Write
the smallest possible script that answers the question, run it, read the answer,
and move on.

These sketches are disposable by default. Don't over-engineer them, don't add
error handling, don't make them pretty. They're thinking tools, not production
code. That said, if a sketch stumbles across something genuinely useful — an
elegant pattern, a surprising behavior, a reusable utility — flag it to the user
and suggest preserving it somewhere appropriate. Good ideas sometimes emerge from
napkin math.

## When to Sketch

Reach for a back-of-envelope sketch when:

- You're unsure whether an algorithm or approach actually works
- You want to verify a type-level design before building it into a codebase
- You need to check your mental model of how a library or language feature
  behaves
- You're comparing two approaches and want to see them side by side
- A conversation is getting abstract and concrete code would ground it

Don't sketch when the answer is already obvious, when reading documentation
would be faster, or when the question is better answered by searching the
codebase.

## Tool Selection

### Bun + TypeScript — the default

Use `bun run` for most sketches. Bun starts fast, TypeScript gives you type
checking, and the feedback loop is near-instant. This is your first choice for:

- Runtime behavior experiments ("what does this function return for these
  inputs?")
- Algorithm sketches ("does this approach produce the right output?")
- Data transformation prototypes ("what does this pipeline look like step by
  step?")
- API shape exploration ("does this interface make sense ergonomically?")

```bash
# Inline one-liner
bun -e "console.log([1,2,3].flatMap(x => [x, x*2]))"

# Quick file (write, run, delete)
bun run sketch.ts
```

For type-level sketches in TypeScript — where you're checking whether the
compiler accepts a design, not running anything — write the file and run
`bun build sketch.ts` or `bunx tsc --noEmit sketch.ts` to type-check without
executing. The question being answered is "does this compile?" not "what does
this output?"

TypeScript's type system is expressive enough for most contract sketching:
conditional types, mapped types, template literal types, discriminated unions,
and `satisfies` cover a lot of ground. Reach for Rust only when TypeScript's
type system can't express what you need.

### Rust — when you need stronger guarantees

Fall back to Rust when the sketch requires:

- **Ownership and borrowing** — modeling whether a design works with move
  semantics, lifetimes, or shared vs. exclusive references
- **Trait bounds with associated types** — sketching generic interfaces where
  the constraints are the point
- **Exhaustive pattern matching on enums with data** — TypeScript's
  discriminated unions get close, but Rust's `match` with compiler-enforced
  exhaustiveness is the real thing
- **"Does this compile?"** questions where the borrow checker or trait solver
  is the oracle you're consulting

```bash
# Quick single-file sketch
cat > /tmp/sketch.rs << 'EOF'
fn main() {
    // your sketch here
}
EOF
rustc /tmp/sketch.rs -o /tmp/sketch && /tmp/sketch

# Or with cargo for when you need dependencies
cargo new --name sketch /tmp/sketch
# edit /tmp/sketch/src/main.rs
cargo run --manifest-path /tmp/sketch/Cargo.toml
```

For type-level-only sketches in Rust, you don't even need `main` — just write
the types and traits and see if `rustc --edition 2021 /tmp/sketch.rs` accepts
them. The compiler error messages are the output.

### DuckDB — for data questions

When the question is about data rather than code — "how many rows match this
condition?", "what does this join look like?", "is this aggregation correct?" —
a DuckDB one-liner is faster than writing a script:

```bash
duckdb -markdown -c "SELECT ... FROM 'data.parquet' ..."
```

Load the **duckdb** skill if you need a refresher on syntax.

### Nushell — for structured data questions

When the question is about JSON shape, data transformation, or any structured
data manipulation, use nushell. Its pipeline model treats data as tables and
records natively, which is far more readable than jq for anything beyond trivial
filters:

```nu
# What does this API response look like?
http get https://api.example.com/data | get results | first

# Transform structured data
'{"a": {"b": [1, 2, 3]}}' | from json | get a.b | each { $in * 2 }

# Explore a JSON file's shape
open data.json | describe

# Filter and reshape
open records.json | where status == "active" | select name email | sort-by name
```

## Principles

**Keep it tiny.** A sketch should be 5-30 lines. If it's growing past that,
you're building something, not sketching. Step back and ask whether the question
can be decomposed into smaller questions.

**Run it immediately.** The value of a sketch is the instant feedback. Write it,
run it, read the output. Don't accumulate multiple sketches before running any
of them.

**Use /tmp or a scratch location.** Don't litter the project directory with
sketch files. Write to `/tmp/sketch.ts`, `/tmp/sketch.rs`, etc. If the user
wants to keep something, they'll say so.

**Print intermediate state.** The whole point is to see what's happening. Add
`console.log`, `println!`, `dbg!` liberally. These aren't production code —
visibility is the priority.

**Delete when done.** Unless the sketch revealed something worth preserving,
clean up after yourself. The sketch served its purpose the moment you read the
output.

**Elevate the surprising.** If a sketch reveals unexpected behavior, an elegant
pattern, or a useful utility, tell the user. "This one-off turned up something
interesting — want to keep it?" A good sketch occasionally graduates from napkin
to notebook.
