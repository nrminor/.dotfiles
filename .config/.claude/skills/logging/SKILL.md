---
name: logging
description: Write production logging that actually helps you debug. Teaches the wide event / canonical log line pattern — one rich, structured event per request per service instead of scattered log lines. Language-agnostic principles with idioms for Rust, Python, Go, and TypeScript. Use when adding logging, instrumentation, or observability to any codebase.
---

# Wide Events Logging

This skill teaches you to write logs that are way better than they need to be.
Not because you're a perfectionist, but because the cost of good logging is
nearly zero at write time and the cost of bad logging is enormous at debug time.

The core idea: **stop spraying log lines throughout your code. Instead, build up
one rich, structured event per request per service and emit it once at the end.**
This is variously called a "wide event" (Charity Majors / Honeycomb) or a
"canonical log line" (Stripe). The names differ; the principle is the same.

## Why This Matters

Traditional logging is optimized for writing, not querying. A developer writes
`log.info("Payment failed")` because it's easy in the moment. Nobody thinks
about the person who'll be searching for this at 2am during an outage.

The result: a single request generates 10-20 log lines scattered across your
codebase. Each line has a fragment of context. To reconstruct what happened, you
have to grep for a request ID, collate lines across services, and mentally
reassemble the timeline. This is archaeology, not engineering.

Wide events flip this. One event per request, with every piece of context
attached. When something goes wrong, you query structured fields — not strings —
and get the full picture immediately.

## The Pattern

Every wide event implementation follows the same three steps, regardless of
language:

1. **Initialize an empty event** at the start of the request (in middleware,
   a handler wrapper, or equivalent entry point).
2. **Enrich the event throughout the request lifecycle.** As you authenticate
   the user, query the database, call external services — attach the relevant
   context to the event. IDs, durations, outcomes, business context, feature
   flags, everything.
3. **Emit the event once** when the request completes (or errors). This single
   emission contains the full story of what happened.

The key insight: the incremental cost of adding one more field to an event
you're already emitting is nearly zero. So be generous with context. You're not
paying per-field; you're paying per-event.

## What Goes in a Wide Event

A good wide event answers the question: "If I could only see one line of output
for this request, what would I need to know?" At minimum:

**Always include:**
- Timestamp (ISO 8601)
- Request/trace ID (for correlation across services)
- Service name and version
- HTTP method, path, and response status code
- Total request duration
- Outcome (`success`, `failure`, `error`)

**Include when available:**
- User ID, account type, subscription tier
- Authentication method and key ID
- Database query count and total DB time
- Cache hit/miss and cache latency
- External service calls, their latencies, and their outcomes
- Error type, error code, and whether it's retriable
- Feature flags active for this request
- Rate limit state (quota, remaining, decision)
- Business context specific to the endpoint (cart value, item count, etc.)

**Don't include:**
- Full request/response bodies (too large, potential PII)
- Passwords, tokens, or secrets (obviously)
- Redundant information already captured by the trace ID

The goal is high cardinality (many unique values per field — user IDs, request
IDs, not just "GET"/"POST") and high dimensionality (many fields per event).
This is what makes wide events queryable: you can slice and dice on any
combination of fields.

## Field Naming

Consistent field names across your codebase matter more than which convention
you pick. Engineers develop muscle memory around field names; changing them is
disruptive.

The most widely adopted convention is OpenTelemetry semantic conventions:
lowercase, dot-namespaced, descriptive. Use these where they exist and are
stable:

| Field | Convention |
|-------|-----------|
| HTTP method | `http.request.method` |
| HTTP status | `http.response.status_code` |
| URL path | `url.path` |
| Service name | `service.name` |
| Service version | `service.version` |
| User ID | `user.id` |
| DB system | `db.system` |
| Error type | `error.type` |
| Client address | `client.address` |

For application-specific fields not covered by OTel semconv, follow the same
pattern: lowercase, dot-namespaced, no abbreviations. `payment.provider`,
`cart.item_count`, `feature_flags.new_checkout_flow`.

If the project already has an established naming convention, follow it. Internal
consistency beats external standards.

## Language Idioms

The pattern is the same everywhere. The mechanism for accumulating context
differs by language.

### Rust (`tracing`)

The `tracing` crate is the standard. Open a span at request start, record
fields on it throughout, and let the subscriber emit the span's data when it
closes.

```rust
use tracing::{info_span, field, Instrument};

async fn handle_request(req: Request) -> Response {
    let span = info_span!(
        "request",
        http.request.method = %req.method(),
        url.path = %req.uri().path(),
        http.response.status_code = field::Empty,
        user.id = field::Empty,
        duration_ms = field::Empty,
        db.query_count = field::Empty,
        outcome = field::Empty,
    );

    async move {
        let start = Instant::now();

        // Enrich as context becomes available
        let user = authenticate(&req).await?;
        tracing::Span::current().record("user.id", &user.id.as_str());

        let result = process(&req, &user).await;

        let span = tracing::Span::current();
        span.record("duration_ms", start.elapsed().as_millis() as u64);
        span.record("http.response.status_code", result.status().as_u16());
        span.record("outcome", if result.status().is_success() {
            "success"
        } else {
            "error"
        });

        result
    }
    .instrument(span)
    .await
}
```

Use `field::Empty` as a placeholder for fields you'll fill in later. Use
`.instrument(span)` for async code — not `span.enter()`, which doesn't work
correctly across await points.

For the subscriber, `tracing-subscriber` with a JSON layer gives you structured
output. `tracing-opentelemetry` exports to OTel-compatible backends.

### Python (`structlog`)

`structlog` treats log entries as dictionaries. Use context variables for
async-safe context propagation across the call stack.

```python
import structlog
from structlog.contextvars import bind_contextvars, clear_contextvars

# In middleware — start of request
clear_contextvars()
bind_contextvars(
    request_id=request.id,
    http_request_method=request.method,
    url_path=request.path,
    service_name="checkout-service",
)

# In auth layer
bind_contextvars(user_id=user.id, auth_type="api_key")

# In business logic
bind_contextvars(
    cart_item_count=len(cart.items),
    cart_total_cents=cart.total,
)

# At request end — emit the wide event
# All bound context vars are automatically included
log = structlog.get_logger()
log.info(
    "request_finished",
    http_response_status_code=response.status_code,
    duration_ms=elapsed_ms,
    outcome="success" if response.ok else "error",
)
```

`clear_contextvars()` at the start of each request prevents context leaking
between requests. The `merge_contextvars` processor (included in structlog's
default config) merges all bound context into every emitted event.

### Go (`log/slog`)

`slog` (standard library, Go 1.21+) accumulates context via `Logger.With()`,
which returns a new logger with additional attributes pre-attached.

```go
func handleRequest(w http.ResponseWriter, r *http.Request) {
    start := time.Now()

    // Initialize with request context
    log := slog.Default().With(
        "request_id", r.Header.Get("X-Request-ID"),
        "http.request.method", r.Method,
        "url.path", r.URL.Path,
        "service.name", "checkout-service",
    )

    // Enrich as context becomes available
    user, err := authenticate(r)
    if err == nil {
        log = log.With("user.id", user.ID, "auth_type", "api_key")
    }

    // Process and emit
    status := process(w, r, log)

    log.InfoContext(r.Context(), "request_finished",
        slog.Int("http.response.status_code", status),
        slog.Float64("duration_ms", float64(time.Since(start).Milliseconds())),
        slog.String("outcome", outcomeFromStatus(status)),
    )
}
```

Use `slog.Group()` to namespace related fields: `slog.Group("payment",
slog.String("provider", "stripe"), slog.Int("latency_ms", 89))` renders as
`payment.provider=stripe payment.latency_ms=89`.

### TypeScript (`pino`)

Pino accumulates context via child loggers. Create a child at request start,
further children as context is established.

```typescript
import pino from 'pino'

const rootLogger = pino()

// In request middleware
app.use((req, res, next) => {
  const start = Date.now()

  req.log = rootLogger.child({
    requestId: req.id,
    'http.request.method': req.method,
    'url.path': req.path,
    'service.name': 'checkout-service',
  })

  // Emit wide event when response finishes
  res.on('finish', () => {
    req.log.info({
      'http.response.status_code': res.statusCode,
      duration_ms: Date.now() - start,
      outcome: res.statusCode < 400 ? 'success' : 'error',
    }, 'request_finished')
  })

  next()
})

// In auth middleware
req.log = req.log.child({ 'user.id': user.id, auth_type: 'api_key' })

// In business logic
req.log = req.log.child({
  'cart.item_count': cart.items.length,
  'cart.total_cents': cart.total,
})
```

Child logger creation is fast (~150-260ms per 10,000 creations). Fields are
serialized once at child creation time, not on every log call.

## Sampling

At scale, storing 100% of wide events gets expensive. Sample — but sample
intelligently.

**Tail sampling** means you decide whether to keep an event *after* the request
completes, based on its outcome. The rules:

1. **Always keep errors.** 100% of 5xx responses, exceptions, and failures.
2. **Always keep slow requests.** Anything above your p99 latency threshold.
3. **Always keep flagged requests.** VIP users, internal test accounts, active
   feature flag rollouts, requests you're actively debugging.
4. **Randomly sample the rest.** Happy, fast requests — keep 1-10% depending on
   volume and budget.

This gives you full visibility into problems while keeping costs manageable.
Never use naive random sampling — you'll drop the one request that explains your
outage.

## Common Mistakes

**Scattering context across many log lines.** If you emit 15 lines per request,
each with a fragment of context, you've defeated the purpose. One event. All
context. Emit once.

**Logging what your code is doing instead of what happened.** "Entering
processPayment" and "Exiting processPayment" are diary entries, not telemetry.
Log the outcome: payment succeeded, payment failed with code X, payment took Y
ms.

**Missing business context.** Technical fields (status codes, durations) are
necessary but not sufficient. The user's subscription tier, their cart value,
the feature flags they're seeing — this is what turns a log line into an
actionable insight.

**Inconsistent field names.** If one service logs `userId` and another logs
`user_id` and a third logs `user.id`, your queries will miss data. Pick a
convention and enforce it.

**Using log levels as a filtering mechanism.** Don't emit debug-level wide
events and info-level wide events for the same request. Emit one event. If you
need to control verbosity, control which *fields* you include, not how many
events you emit.

**Logging inside tight loops.** Wide events are per-request, not per-iteration.
If you need to understand loop behavior, aggregate it into fields on the wide
event: `iterations=1000`, `failures=3`, `total_duration_ms=847`.

## Further Reading

- [Stripe: Canonical Log Lines](https://stripe.com/blog/canonical-log-lines)
  — the original post by Brandur Leach that popularized the pattern
- [Charity Majors: Logs vs. Structured Events](https://charity.wtf/2019/02/05/logs-vs-structured-events/)
  — the philosophical case for wide events over traditional logging
- [loggingsucks.com](https://loggingsucks.com/) — interactive guide to wide
  events by Boris Tane
- [OpenTelemetry Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)
  — the emerging standard for field naming
