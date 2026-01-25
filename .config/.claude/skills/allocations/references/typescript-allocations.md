# TypeScript/JavaScript Heap Allocation Patterns

Comprehensive guide to heap allocation optimization in TypeScript and JavaScript.

## Contents

- [V8 Memory Model](#v8-memory-model)
- [Quick Wins](#quick-wins-minutes)
- [Moderate Effort](#moderate-effort-hours)
- [Architectural Changes](#architectural-changes-days)
- [TypedArray Reference](#typedarray-reference)
- [Profiling Tools](#profiling-tools)
- [Anti-Patterns Summary](#anti-patterns-summary)

---

## V8 Memory Model

Understanding V8's internals helps predict allocation costs.

### Generational Heap

- **Young Generation**: New objects land here. Minor GC (Scavenger) is fast.
- **Old Generation**: Objects surviving 2+ GCs are promoted. Major GC is expensive.

### Hidden Classes (Shapes)

Every object has a "hidden class" describing its property layout:

- Objects with same properties in same order share hidden classes
- Adding/deleting properties creates new hidden classes
- Inconsistent shapes cause **polymorphic** or **megamorphic** call sites (slow)

### Inline Caches

V8 optimizes property access based on observed shapes:

- **Monomorphic** (1 shape): Fastest, direct offset access
- **Polymorphic** (2-4 shapes): Decision tree, slower
- **Megamorphic** (>4 shapes): Hash table lookup, slowest

### Element Kinds

Arrays have internal "element kinds" that affect performance:

```
PACKED_SMI_ELEMENTS → PACKED_DOUBLE_ELEMENTS → PACKED_ELEMENTS
       ↓                      ↓                      ↓
HOLEY_SMI_ELEMENTS  → HOLEY_DOUBLE_ELEMENTS  → HOLEY_ELEMENTS
```

Transitions only go **downward** (more general). Once an array has holes or mixed
types, it can't go back to a more optimized representation.

---

## Quick Wins (Minutes)

### Avoid array holes

```typescript
// ❌ Creates HOLEY_ELEMENTS (slower)
const arr = new Array(3);
arr[0] = "a";
arr[1] = "b";
arr[2] = "c";

// ✅ Creates PACKED_ELEMENTS (faster)
const arr = ["a", "b", "c"];

// ✅ Also good
const arr = [];
arr.push("a", "b", "c");
```

### Maintain consistent object shapes

```typescript
// ❌ Different shapes depending on input
function Point(x, y) {
  this.x = x;
  if (y !== undefined) this.y = y;
}

// ✅ Same shape always
function Point(x, y) {
  this.x = x;
  this.y = y ?? 0;
}
```

### Don't delete properties

```typescript
// ❌ Transitions object to slow "dictionary mode"
delete obj.property;

// ✅ Set to undefined instead
obj.property = undefined;
```

### Avoid reading beyond array length

```typescript
// ❌ Triggers prototype chain lookup
for (let i = 0; (item = items[i]) != null; i++) {}

// ✅ Standard bounds check
for (let i = 0; i < items.length; i++) {}
```

### Use `JSON.parse` for large config objects

```typescript
// ❌ Object literal parsed twice (preparse + lazy parse)
const data = { foo: 42, bar: 1337 /* ... large object ... */ };

// ✅ JSON.parse is ~1.7x faster for objects >10kB
const data = JSON.parse('{"foo":42,"bar":1337}');
```

### Avoid element kind transitions

```typescript
// ❌ Transitions: SMI → DOUBLE → ELEMENTS (can't go back)
const arr = [1, 2, 3]; // PACKED_SMI_ELEMENTS
arr.push(4.56); // → PACKED_DOUBLE_ELEMENTS
arr.push("x"); // → PACKED_ELEMENTS

// ✅ Use TypedArray for numeric data
const numbers = new Float64Array(100);

// ✅ Or accept mixed types upfront
const mixed: (number | string)[] = [];
```

### Use rest parameters instead of `arguments`

```typescript
// ❌ arguments is array-like, not optimized
function sum() {
  return Array.prototype.reduce.call(arguments, (a, b) => a + b);
}

// ✅ Rest parameters are a real array
function sum(...args: number[]) {
  return args.reduce((a, b) => a + b);
}
```

---

## Moderate Effort (Hours)

### Object pooling

Reuse objects instead of creating new ones:

```typescript
class ObjectPool<T> {
  private pool: T[] = [];

  constructor(
    private factory: () => T,
    private reset: (obj: T) => void,
    initialSize = 10
  ) {
    for (let i = 0; i < initialSize; i++) {
      this.pool.push(factory());
    }
  }

  acquire(): T {
    return this.pool.pop() ?? this.factory();
  }

  release(obj: T): void {
    this.reset(obj);
    this.pool.push(obj);
  }
}

// Usage
const vectorPool = new ObjectPool(
  () => ({ x: 0, y: 0, z: 0 }),
  (v) => {
    v.x = 0;
    v.y = 0;
    v.z = 0;
  }
);

const v = vectorPool.acquire();
// ... use v ...
vectorPool.release(v);
```

### Avoid closures in hot loops

```typescript
// ❌ Creates new function object each iteration
items.forEach((item) => {
  process(item, someContext);
});

// ✅ Define function once outside
const processor = (item: Item) => process(item, someContext);
items.forEach(processor);

// ✅ Better for hot paths: plain for loop
for (let i = 0; i < items.length; i++) {
  process(items[i], someContext);
}
```

### Avoid chained array methods creating intermediates

```typescript
// ❌ Creates 2 intermediate arrays
const result = data
  .map((x) => x * 2)
  .filter((x) => x > 10)
  .reduce((a, b) => a + b, 0);

// ✅ Single pass
let result = 0;
for (let i = 0; i < data.length; i++) {
  const doubled = data[i] * 2;
  if (doubled > 10) result += doubled;
}

// ✅ Or single reduce
const result = data.reduce((acc, x) => {
  const doubled = x * 2;
  return doubled > 10 ? acc + doubled : acc;
}, 0);
```

### StringBuilder pattern for string assembly

```typescript
// ❌ Creates many intermediate strings
let result = "";
for (const item of items) {
  result += item.toString() + ", ";
}

// ✅ Single join operation
const result = items.map((item) => item.toString()).join(", ");

// ✅ For large strings: array accumulation
const parts: string[] = [];
for (const item of items) {
  parts.push(item.toString());
}
const result = parts.join(", ");
```

### Pre-allocate arrays when size is known

```typescript
// ❌ Array grows dynamically
const result = [];
for (let i = 0; i < 10000; i++) {
  result.push(compute(i));
}

// ✅ Pre-allocate (though JS engines are smart about this)
const result = new Array(10000);
for (let i = 0; i < 10000; i++) {
  result[i] = compute(i);
}
```

---

## Architectural Changes (Days)

### Data-oriented design with TypedArrays

```typescript
// ❌ Object-oriented: many small allocations, poor cache locality
class Particle {
  x: number;
  y: number;
  vx: number;
  vy: number;
}
const particles: Particle[] = new Array(10000);

// ✅ Data-oriented: single allocation, cache-friendly
class ParticleSystem {
  private count: number = 0;
  private x: Float32Array;
  private y: Float32Array;
  private vx: Float32Array;
  private vy: Float32Array;

  constructor(maxParticles: number) {
    this.x = new Float32Array(maxParticles);
    this.y = new Float32Array(maxParticles);
    this.vx = new Float32Array(maxParticles);
    this.vy = new Float32Array(maxParticles);
  }

  update(dt: number): void {
    for (let i = 0; i < this.count; i++) {
      this.x[i] += this.vx[i] * dt;
      this.y[i] += this.vy[i] * dt;
    }
  }
}
```

### Zero-copy binary data handling

```typescript
// Share underlying buffer between views
const buffer = new ArrayBuffer(1024);
const uint8View = new Uint8Array(buffer);
const float32View = new Float32Array(buffer);

// DataView for heterogeneous data with explicit endianness
const dv = new DataView(buffer);
dv.setFloat32(0, 3.14, true); // little-endian
dv.setUint16(4, 42, true);

// Transfer ownership to Web Worker (no copy)
worker.postMessage(buffer, [buffer]); // buffer becomes unusable here
```

### Ring buffer for fixed-capacity queues

```typescript
class RingBuffer<T> {
  private buffer: T[];
  private head = 0;
  private tail = 0;
  private _size = 0;

  constructor(capacity: number, defaultValue: T) {
    this.buffer = new Array(capacity).fill(defaultValue);
  }

  push(item: T): void {
    this.buffer[this.tail] = item;
    this.tail = (this.tail + 1) % this.buffer.length;
    if (this._size < this.buffer.length) {
      this._size++;
    } else {
      this.head = (this.head + 1) % this.buffer.length;
    }
  }

  get size(): number {
    return this._size;
  }
}
```

---

## TypedArray Reference

| Type | Use Case | Bytes |
|------|----------|-------|
| `Uint8Array` | Binary data, bytes, pixels | 1 |
| `Uint8ClampedArray` | Canvas ImageData (auto-clamps 0-255) | 1 |
| `Int16Array` / `Uint16Array` | Audio samples, short integers | 2 |
| `Int32Array` / `Uint32Array` | General integers, indices | 4 |
| `Float32Array` | Graphics, WebGL, moderate precision | 4 |
| `Float64Array` | Scientific computing, high precision | 8 |
| `BigInt64Array` / `BigUint64Array` | Large integers, timestamps | 8 |

**Buffer types:**

- `ArrayBuffer`: Single-owner binary data, transferable
- `SharedArrayBuffer`: Multi-threaded access (requires COOP/COEP headers in browsers)
- `DataView`: Heterogeneous data with explicit endianness

### Best Practices

```typescript
// Reuse buffers instead of creating new ones
const scratchBuffer = new Float32Array(1024);

function processData(input: Float32Array): Float32Array {
  for (let i = 0; i < input.length && i < scratchBuffer.length; i++) {
    scratchBuffer[i] = input[i] * 2;
  }
  return scratchBuffer.subarray(0, input.length);
}

// Use .set() for efficient copying
const dest = new Uint8Array(1024);
const src = new Uint8Array(512);
dest.set(src, 0);  // Copy src to dest starting at offset 0

// Create views into existing buffers (no copy)
const buffer = new ArrayBuffer(1024);
const header = new Uint32Array(buffer, 0, 4);      // First 16 bytes as uint32
const payload = new Uint8Array(buffer, 16);        // Rest as bytes
```

---

## Profiling Tools

### Chrome DevTools Memory Panel

1. Open DevTools → Memory tab
2. Select profiling type:
   - **Heap Snapshot**: Point-in-time memory state
   - **Allocation Timeline**: Track allocations over time
   - **Allocation Sampling**: Low-overhead sampling

**Finding leaks:**

1. Take snapshot before suspected leak
2. Perform leaking action
3. Take another snapshot
4. Compare (select newer, view as "Comparison")
5. Look for positive deltas in "# New" column

**Key metrics:**

- **Shallow Size**: Memory held by object itself
- **Retained Size**: Memory freed if object is GC'd

### Node.js Memory Profiling

```bash
# Enable inspector
node --inspect index.js

# Take heap snapshot on signal
node --heapsnapshot-signal=SIGUSR2 index.js
# Then: kill -USR2 <pid>

# Increase heap size
node --max-old-space-size=4096 index.js

# Expose GC for debugging
node --expose-gc --inspect index.js
```

**Programmatic snapshots:**

```typescript
import v8 from "v8";

v8.writeHeapSnapshot(); // Returns filename

const stats = v8.getHeapStatistics();
console.log(`Heap used: ${stats.used_heap_size / 1024 / 1024} MB`);
```

### Chrome Task Manager

- `Shift+Esc` or Menu → More tools → Task Manager
- Enable "JavaScript memory" column
- **Memory footprint**: OS memory (DOM nodes)
- **JavaScript Memory**: JS heap (live number in parentheses)

---

## Anti-Patterns Summary

| Anti-Pattern | Fix |
|--------------|-----|
| Array holes | Use literals or push |
| `delete obj.prop` | Set to `undefined` |
| Inconsistent object shapes | Always initialize all properties |
| Closures in hot loops | Define function outside loop |
| Chained `.map().filter().reduce()` | Single-pass loop or reduce |
| String concatenation in loops | Array + join |
| Using `arguments` | Use rest parameters |
| Megamorphic call sites | Keep shapes consistent |

---

## V8-Specific Insights

### Property Storage

1. **In-object properties**: Fastest, stored directly on object
2. **Fast properties**: Stored in separate array, indexed via HiddenClass
3. **Slow/Dictionary properties**: Self-contained dictionary, no IC optimization

### Optimization Killers

- `eval()` and `with` statements
- `arguments` object leaking
- `try-catch` in hot functions (better now, but still avoid in tight loops)
- Debugger statements
- Functions with too many parameters

### Browser vs Node.js Differences

| Aspect | Browser | Node.js |
|--------|---------|---------|
| Heap Size | Limited by tab/process | Configurable via `--max-old-space-size` |
| GC Visibility | DevTools only | `--expose-gc`, `--trace-gc` flags |
| Heap Snapshots | DevTools Memory panel | `v8.writeHeapSnapshot()`, `--heapsnapshot-signal` |
| SharedArrayBuffer | Requires COOP/COEP headers | Always available |
| Transfer | `postMessage` with transferables | Worker threads with `transferList` |
| Memory Pressure | Browser may kill tabs | Process may be OOM-killed |
