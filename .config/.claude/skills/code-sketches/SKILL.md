---
name: code-sketches
description: Use when proposing, reviewing, or comparing API designs, refactors, architecture changes, or implementation plans with code sketches. Requires sketches to cover internals, callsites, docs/teaching cost, and library-vs-application API tradeoffs instead of ad hoc snippets.
---

# Code Sketches

Code sketches are not miscellaneous snippets. Use them to test a design across three axes:

```text
internals  -> what changes behind the seam?
callsites  -> what changes for callers, or what stays unchanged?
docs       -> how would we teach this API after the change?
```

For each proposed design, cover all three axes.

## Internals

If the proposal changes internals, sketch the internal shape: key types, functions, data flow, invariants, or hidden complexity. If internals do not change, say so.

## Callsites

Sketch caller code. If public callsites remain unchanged, explicitly say that and show the unchanged callsite as a reminder.

## Docs / teaching cost

Sketch how the API would be explained to someone learning the codebase:

```md
Use X when...
Provide Y because...
Avoid Z because...
```

Then state whether the proposal makes the API easier or harder to teach. Treat extra teaching burden as evidence against the design unless it buys clear leverage.

## Library vs application usage

Ask whether the API is mainly for making libraries, making applications, or both. Where relevant, sketch both usage modes:

```rust
// library author
pub fn extension<T: Trait>(input: T) -> impl LibraryThing<T> { ... }

// application author
let thing = Thing::new(config);
thing.run()?;
```

Name the tradeoff directly. In generic-heavy languages, a design can make library creation easier while making application code harder, or vice versa.

## Compact shape

```md
### Sketch: <proposal>

Internals:
<code sketch, or "unchanged">

Callsites:
<code sketch, including unchanged callsites if unchanged>

Docs:
<how we would teach this>
Teaching cost: easier / harder / mixed because...

Library/app impact:

- Library authors:
- Application authors:
```

Keep sketches small and disposable and always provide more than one. They are a design instrument, not an implementation commitment.
