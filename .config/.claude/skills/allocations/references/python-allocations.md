# Python Heap Allocation Patterns

Guide to heap allocation optimization in Python.

## Contents

- [Quick Wins](#quick-wins-minutes)
- [Moderate Effort](#moderate-effort-hours)
- [Architectural Changes](#architectural-changes-days)
- [Profiling Tools](#profiling-tools)
- [Anti-Patterns Summary](#anti-patterns-summary)

---

## Quick Wins (Minutes)

### Use sets for membership testing

```python
# ❌ O(n) linear scan
big_list = list(range(1000000))
999999 in big_list  # ~15ms

# ✅ O(1) hash lookup
big_set = set(range(1000000))
999999 in big_set  # ~0.02ms
```

### Avoid unnecessary copies

```python
# ❌ Creates a copy
def modify_list(lst):
    new_lst = lst.copy()
    new_lst[0] = 999
    return new_lst

# ✅ Modify in place when safe
def modify_list(lst):
    lst[0] = 999
    return lst
```

### Use `__slots__` for memory efficiency

```python
# ❌ Default: each instance has a __dict__ (56+ bytes overhead)
class Point:
    def __init__(self, x, y):
        self.x = x
        self.y = y

# ✅ With __slots__: no __dict__, fixed attributes
class Point:
    __slots__ = ('x', 'y')

    def __init__(self, x, y):
        self.x = x
        self.y = y
```

`__slots__` reduces memory per instance and slightly speeds up attribute access.
Tradeoff: can't add dynamic attributes.

### Use `math` module functions

```python
import math

# ❌ Operator-based (slightly slower)
roots = [n ** 0.5 for n in numbers]

# ✅ C-optimized math functions
roots = [math.sqrt(n) for n in numbers]
```

### Pre-allocate lists when size is known

```python
# ❌ Dynamic growth
result = []
for i in range(1000000):
    result.append(i)

# ✅ Pre-allocated
result = [0] * 1000000
for i in range(1000000):
    result[i] = i

# ✅ Or use list comprehension (often fastest)
result = [i for i in range(1000000)]
```

### Avoid exceptions in hot loops

```python
# ❌ Exception handling is expensive
for i in numbers:
    try:
        total += i / (i % 2)
    except ZeroDivisionError:
        total += i

# ✅ Conditional check is faster
for i in numbers:
    if i % 2 != 0:
        total += i // 2
    else:
        total += i
```

### Use local variables in tight loops

```python
# ❌ Global lookup each iteration
def outer():
    result = 0
    for i in range(10000000):
        result = add_pair(result, i)  # Global lookup
    return result

# ✅ Local reference is faster
def outer():
    local_add = add_pair  # Cache in local scope
    result = 0
    for i in range(10000000):
        result = local_add(result, i)
    return result
```

### Cache function results outside loops

```python
# ❌ Repeated expensive call
for i in range(1000):
    result += expensive_operation()

# ✅ Cache the result
cached_value = expensive_operation()
for i in range(1000):
    result += cached_value
```

---

## Moderate Effort (Hours)

### Use `itertools` for combinatorial operations

```python
from itertools import product

items = [1, 2, 3] * 10

# ❌ Nested loops
result = []
for x in items:
    for y in items:
        result.append((x, y))

# ✅ C-optimized itertools (lazy evaluation)
result = list(product(items, repeat=2))
```

### Use `bisect` for sorted list operations

```python
import bisect

numbers = sorted(range(0, 1000000, 2))

# ❌ O(n) linear search
for i, num in enumerate(numbers):
    if num > 75432:
        numbers.insert(i, 75432)
        break

# ✅ O(log n) binary search
bisect.insort(numbers, 75432)
```

### Use `memoryview` for zero-copy slicing

```python
# ❌ Slicing creates a copy
data = bytearray(1000000)
chunk = data[1000:2000]  # New bytearray allocated

# ✅ memoryview shares underlying buffer
data = bytearray(1000000)
view = memoryview(data)
chunk = view[1000:2000]  # No copy, just a view
```

### Use `array.array` for homogeneous numeric data

```python
from array import array

# ❌ List of Python objects (28+ bytes per int)
numbers = [0] * 1000000

# ✅ Compact C array (4 bytes per int for 'i')
numbers = array('i', [0] * 1000000)
```

### Use generators instead of lists for iteration

```python
# ❌ Creates entire list in memory
def get_squares(n):
    return [i ** 2 for i in range(n)]

# ✅ Yields one item at a time
def get_squares(n):
    for i in range(n):
        yield i ** 2

# Or generator expression
squares = (i ** 2 for i in range(n))
```

---

## Architectural Changes (Days)

### Use NumPy for numerical computation

```python
import numpy as np

# ❌ Python list operations
result = [a + b for a, b in zip(list1, list2)]

# ✅ NumPy vectorized operations (C-level, no Python loop)
arr1 = np.array(list1)
arr2 = np.array(list2)
result = arr1 + arr2
```

NumPy arrays are contiguous in memory, cache-friendly, and operations are vectorized.

### Use `numpy` views instead of copies

```python
import numpy as np

arr = np.arange(1000000)

# ❌ Creates a copy
subset = arr[::2].copy()

# ✅ View shares memory (no allocation)
subset = arr[::2]  # This is already a view

# Check if it's a view
print(subset.base is arr)  # True = view, None = copy
```

### Use `dataclasses` with `slots=True` (Python 3.10+)

```python
from dataclasses import dataclass

@dataclass(slots=True)
class Point:
    x: float
    y: float
```

---

## Profiling Tools

### tracemalloc (built-in)

```python
import tracemalloc

tracemalloc.start()

# ... code to profile ...

snapshot = tracemalloc.take_snapshot()
top_stats = snapshot.statistics('lineno')

for stat in top_stats[:10]:
    print(stat)
```

### memory_profiler

```bash
pip install memory_profiler
```

```python
from memory_profiler import profile

@profile
def my_function():
    # ... code to profile ...
```

```bash
python -m memory_profiler script.py
```

### objgraph (for finding leaks)

```bash
pip install objgraph
```

```python
import objgraph

objgraph.show_most_common_types(limit=10)
objgraph.show_growth()
```

### Line-by-line memory usage

```python
from memory_profiler import profile

@profile
def process_data():
    data = [0] * 1000000  # Shows memory for this line
    result = sum(data)     # Shows memory for this line
    return result
```

---

## Anti-Patterns Summary

| Anti-Pattern | Fix |
|--------------|-----|
| `x in list` for membership | Use `set` |
| Unnecessary `.copy()` | Modify in place when safe |
| No `__slots__` on data classes | Add `__slots__` |
| `n ** 0.5` in loops | Use `math.sqrt(n)` |
| Dynamic list growth | Pre-allocate or comprehension |
| Exceptions for control flow | Use conditionals |
| Global lookups in loops | Cache in local variable |
| Repeated expensive calls | Cache result |
| Nested loops for combinations | Use `itertools` |
| Linear search in sorted data | Use `bisect` |
| Slicing large buffers | Use `memoryview` |
| Lists for numeric data | Use `array.array` or NumPy |
| Building lists for iteration | Use generators |
