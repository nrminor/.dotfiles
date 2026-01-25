# Rust Heap Allocation Patterns

Comprehensive guide to heap allocation optimization in Rust.

## Contents

- [Heap-Allocated Types](#heap-allocated-types)
- [Quick Wins](#quick-wins-minutes)
- [Moderate Effort](#moderate-effort-hours)
- [Architectural Changes](#architectural-changes-days)
- [Profiling Tools](#profiling-tools)
- [Clippy Lints](#clippy-lints)
- [Crate Reference](#crate-reference)

---

## Heap-Allocated Types

Know which types allocate:

| Type | Allocates | Notes |
|------|-----------|-------|
| `Box<T>` | Always | Single heap allocation for T |
| `Vec<T>` | On first push (not `new()`) | Grows: 0→4→8→16→... (skips 1,2,3) |
| `String` | On first push (not `new()`) | Same growth as Vec |
| `HashMap<K,V>` | On first insert | Pre-allocates ~7 slots minimum |
| `HashSet<T>` | On first insert | Same as HashMap |
| `BTreeMap<K,V>` | On first insert | Node-based, many small allocations |
| `Rc<T>` / `Arc<T>` | On creation | Reference count + T |
| `Mutex<T>` / `RwLock<T>` | Depends on OS | May allocate for OS primitives |
| `PathBuf` | Like String | Wraps OsString |

**Null pointer optimization:** `Option<Box<T>>`, `Option<&T>`, `Option<NonNull<T>>` are
the same size as the inner type (None = null pointer).

---

## Quick Wins (Minutes)

### Use `with_capacity` when size is known

```rust
// Before: multiple reallocations as vec grows
let mut v = Vec::new();
for i in 0..1000 {
    v.push(i);
}

// After: single allocation
let mut v = Vec::with_capacity(1000);
for i in 0..1000 {
    v.push(i);
}
```

### Use `clone_from` to reuse allocations

```rust
// Before: always allocates new storage
a = b.clone();

// After: reuses a's allocation if capacity suffices
a.clone_from(&b);
```

### Reuse collections with `clear()`

```rust
let mut buf = Vec::new();
for item in items {
    buf.clear();  // Keeps capacity, no reallocation
    process(item, &mut buf);
}
```

### Accept `&str` instead of `String`

```rust
// Before: forces caller to allocate String
fn process(s: String) { /* ... */ }

// After: accepts &str, &String, String (via deref)
fn process(s: &str) { /* ... */ }

// Or for maximum flexibility:
fn process(s: impl AsRef<str>) { /* ... */ }
```

### Avoid `format!()` for static strings

```rust
// Before: allocates
return Err(format!("invalid input"));

// After: no allocation
return Err("invalid input".into());
```

### Use `Cow` for mixed static/dynamic strings

```rust
use std::borrow::Cow;

fn message(code: u32) -> Cow<'static, str> {
    match code {
        0 => Cow::Borrowed("success"),           // No allocation
        n => Cow::Owned(format!("error {n}")),   // Allocates only when needed
    }
}
```

### Avoid unnecessary `.to_string()` and `.clone()`

```rust
// Before: allocates unnecessarily
let name = user.name.clone();
println!("{}", name);

// After: borrow instead
println!("{}", user.name);
```

### Use `Box<[T]>` for fixed-size heap data

```rust
// Vec has 3 words: ptr, len, capacity
let v: Vec<u32> = vec![1, 2, 3];

// Box<[T]> has 2 words: ptr, len (saves one word, signals immutability)
let b: Box<[u32]> = vec![1, 2, 3].into_boxed_slice();
```

Note: `into_boxed_slice()` may reallocate if Vec has excess capacity.

---

## Moderate Effort (Hours)

### Consider `SmallVec` for typically-small collections

`SmallVec<[T; N]>` stores up to N elements inline, spilling to heap only when exceeded.

```rust
use smallvec::SmallVec;

// Inline storage for up to 4 elements
let mut items: SmallVec<[Item; 4]> = SmallVec::new();
items.push(item);  // No heap allocation if len <= 4
```

**Tradeoffs:**
- Adds inline/heap check overhead on every operation
- Struct size increases by N * size_of::<T>()
- Only beneficial when profiling shows many short-lived small Vecs

**Alternatives:** `arrayvec` (fixed capacity, no heap fallback), `tinyvec` (100% safe,
requires `Default`).

**Dependency consideration:** If you only need one SmallVec in your codebase, the
dependency may not be worth it. Consider if a fixed-size array or `ArrayVec` suffices.

### Box large enum variants

```rust
// Before: entire enum is as large as largest variant
enum Expr {
    Literal(i64),
    Complex { fields: [u8; 256] },  // Makes every Expr 256+ bytes
}

// After: enum stays small
enum Expr {
    Literal(i64),
    Complex(Box<ComplexData>),  // Expr is now ~16 bytes
}
```

Use `RUSTFLAGS=-Zprint-type-sizes cargo +nightly build --release` to find large types.

### String interning for repeated strings

When parsing or compiling, the same strings appear repeatedly. Intern them:

```rust
use string_interner::StringInterner;

let mut interner = StringInterner::default();
let sym1 = interner.get_or_intern("repeated_identifier");
let sym2 = interner.get_or_intern("repeated_identifier");
assert_eq!(sym1, sym2);  // O(1) comparison, single allocation
```

**Alternatives:** `smartstring` (inline strings up to 23 ASCII chars on 64-bit),
`compact_str`.

### Use `BufRead::read_line` with reused buffer

```rust
use std::io::BufRead;

// Before: allocates per line
for line in reader.lines() {
    let line = line?;
    process(&line);
}

// After: reuses buffer
let mut line = String::new();
while reader.read_line(&mut line)? != 0 {
    process(&line);
    line.clear();
}
```

### Avoid collecting iterators unnecessarily

```rust
// Before: allocates intermediate Vec
let sum: i32 = items.iter()
    .map(|x| x * 2)
    .collect::<Vec<_>>()  // Unnecessary allocation!
    .iter()
    .sum();

// After: no intermediate allocation
let sum: i32 = items.iter().map(|x| x * 2).sum();
```

---

## Architectural Changes (Days)

### Arena allocation for graphs and trees

When building structures with complex ownership (trees, graphs, ASTs), arena allocators
simplify lifetime management and improve cache locality:

```rust
use bumpalo::Bump;

let arena = Bump::new();

// All nodes allocated from same arena
let node1 = arena.alloc(Node { value: 1, children: vec![] });
let node2 = arena.alloc(Node { value: 2, children: vec![] });

// Entire arena freed at once when `arena` drops
```

**Critical:** `bumpalo` does NOT run `Drop` on allocated values unless you use
`bumpalo::boxed::Box`. Design accordingly or use `typed-arena` which does run Drop.

**When to use arenas:**
- Phase-oriented allocation (parse phase, then discard all)
- Self-referential structures
- Many small allocations with similar lifetimes

### Data-oriented design: Struct-of-Arrays

Traditional object-oriented design scatters related data across heap:

```rust
// Array-of-Structs: poor cache locality when iterating one field
struct Entity {
    position: Vec3,
    velocity: Vec3,
    health: u32,
    name: String,
}
let entities: Vec<Entity> = /* ... */;

// Iterating positions touches velocity, health, name (cache pollution)
for e in &entities {
    update_position(&mut e.position, &e.velocity);
}
```

Struct-of-Arrays keeps hot data contiguous:

```rust
// Struct-of-Arrays: excellent cache locality
struct Entities {
    positions: Vec<Vec3>,
    velocities: Vec<Vec3>,
    healths: Vec<u32>,
    names: Vec<String>,
}

// Iterating positions only touches position data
for (pos, vel) in entities.positions.iter_mut().zip(&entities.velocities) {
    *pos += *vel;
}
```

### Replace `HashMap` with direct indexing for dense integer keys

```rust
// Before: hash overhead for every lookup
let map: HashMap<usize, Data> = /* ... */;
let value = map.get(&42);

// After: O(1) direct indexing
let data: Vec<Option<Data>> = /* ... */;
let value = data.get(42).and_then(|x| x.as_ref());
```

### Custom allocators for specific patterns

For advanced use cases, implement `GlobalAlloc` or use `#[global_allocator]`:

```rust
use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicUsize, Ordering};

struct CountingAllocator;

static ALLOCATED: AtomicUsize = AtomicUsize::new(0);

unsafe impl GlobalAlloc for CountingAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        ALLOCATED.fetch_add(layout.size(), Ordering::SeqCst);
        System.alloc(layout)
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        ALLOCATED.fetch_sub(layout.size(), Ordering::SeqCst);
        System.dealloc(ptr, layout)
    }
}

#[global_allocator]
static GLOBAL: CountingAllocator = CountingAllocator;
```

---

## Profiling Tools

### DHAT (Rust crate) - Recommended

Add to `Cargo.toml`:
```toml
[features]
dhat-heap = []

[dependencies]
dhat = { version = "0.3", optional = true }
```

In `main.rs`:
```rust
#[cfg(feature = "dhat-heap")]
#[global_allocator]
static ALLOC: dhat::Alloc = dhat::Alloc;

fn main() {
    #[cfg(feature = "dhat-heap")]
    let _profiler = dhat::Profiler::new_heap();

    // ... your code ...
}
```

Run and view:
```bash
cargo run --release --features dhat-heap
# Opens dhat-heap.json in browser at:
# https://nnethercote.github.io/dh_view/dh_view.html
```

### heaptrack (Linux)

```bash
heaptrack ./target/release/myprogram
heaptrack_gui heaptrack.myprogram.*.gz
```

### Valgrind DHAT/Massif (Linux)

```bash
valgrind --tool=dhat ./target/release/myprogram
valgrind --tool=massif ./target/release/myprogram
ms_print massif.out.*
```

### Print type sizes

```bash
RUSTFLAGS=-Zprint-type-sizes cargo +nightly build --release 2>&1 | grep "print-type"
```

---

## Clippy Lints

Enable these allocation-related lints:

```toml
# In Cargo.toml or clippy.toml
[lints.clippy]
perf = "warn"
box_collection = "warn"       # Box<Vec<T>> is redundant
boxed_local = "warn"          # Unnecessary Box in local scope
rc_clone_in_vec_init = "warn" # vec![Rc::clone(&x); n] clones ref, not value
assigning_clones = "warn"     # Use clone_from instead of clone + assign
```

---

## Crate Reference

| Crate | Purpose | Consider When |
|-------|---------|---------------|
| `smallvec` | Inline + heap Vec | Many short Vecs, profile shows benefit |
| `arrayvec` | Fixed-capacity Vec | Known max size, no heap fallback needed |
| `tinyvec` | Safe smallvec alternative | Need Default on elements, avoid unsafe |
| `heapless` | Embedded collections | `no_std`, fixed capacity, static allocation |
| `bumpalo` | Bump allocator | Phase-oriented allocation, ASTs, graphs |
| `typed-arena` | Typed arena | Single-type arenas, need Drop to run |
| `bytes` | Zero-copy byte buffers | Networking, protocol parsing |
| `string-interner` | String deduplication | Compilers, parsers, symbol tables |
| `smartstring` | Inline short strings | Many short strings (<24 chars) |
| `dhat` | Heap profiler | Finding allocation hot spots |
| `tracking-allocator` | Allocation hooks | Custom allocation tracking |

**Before adding a dependency:** Ask whether the pattern can be achieved with `std`
(`Cow`, `Box<[T]>`, `with_capacity`), or if a small refactor eliminates the need.

---

## Anti-Patterns Summary

### High Priority (Common, Easy to Fix)

| Anti-Pattern | Fix |
|--------------|-----|
| `.clone()` in hot loops | Use references, `Cow`, or restructure ownership |
| `.to_string()` on string literals | Use `&'static str` or `Cow::Borrowed` |
| `format!()` for simple concatenation | Use `push_str()` or string interpolation |
| `collect::<Vec<_>>()` when iterator suffices | Keep as iterator, use `for_each` |
| `vec![x; n]` in hot path | Pre-allocate and reuse |
| Passing `String` instead of `&str` | Accept `impl AsRef<str>` or `&str` |

### Medium Priority

| Anti-Pattern | Fix |
|--------------|-----|
| `Box<Vec<T>>` or `Box<String>` | Just use `Vec<T>` or `String` (already heap-allocated) |
| Large enum variants | Box the large variant's data |
| `HashMap` with integer keys 0..N | Use `Vec` with direct indexing |
| Repeated string allocations | Use string interning |
| `lines()` iterator | Use `read_line` with reused buffer |

---

## Lesser-Known Tips

1. **`Vec` skips capacities 1, 2, 3** — Goes directly from 0 → 4 → 8 → 16...
2. **`Rc`/`Arc` clone doesn't allocate** — Only increments reference count.
3. **Types >128 bytes use `memcpy`** — Use `-Zprint-type-sizes` to find these.
4. **`Option<Box<T>>` same size as `Box<T>`** — Null pointer optimization.
5. **`bumpalo` doesn't run `Drop`** — Unless using `bumpalo::boxed::Box<T>`.
6. **`SmallVec` can be slower** — Inline/heap check adds overhead. Profile first.
7. **`HashMap` pre-allocates ~7 slots** — Even empty on first insert.
8. **`String::new()` doesn't allocate** — Only allocates on first push.
9. **`into_boxed_slice()` may reallocate** — If Vec has excess capacity.
10. **Cache line is 64 bytes** — Keep hot data within 64 bytes for cache efficiency.
