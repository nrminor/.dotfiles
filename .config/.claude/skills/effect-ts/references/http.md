# Effect HTTP — Client, Server, and Generated Typed Client

## HttpClient — typed API clients as services

The `HttpClient` module provides a composable HTTP client that integrates with
Effect's service, error, and tracing systems.

```ts
import { Effect, flow, Layer, Schedule, Schema, ServiceMap } from "effect"
import {
  FetchHttpClient, HttpClient, HttpClientRequest, HttpClientResponse
} from "effect/unstable/http"

class Todo extends Schema.Class<Todo>("Todo")({
  userId: Schema.Number,
  id: Schema.Number,
  title: Schema.String,
  completed: Schema.Boolean
}) {}

export class JsonPlaceholderError extends Schema.TaggedErrorClass<JsonPlaceholderError>()(
  "JsonPlaceholderError",
  { cause: Schema.Defect }
) {}

export class JsonPlaceholder extends ServiceMap.Service<JsonPlaceholder, {
  readonly allTodos: Effect.Effect<ReadonlyArray<Todo>, JsonPlaceholderError>
  getTodo(id: number): Effect.Effect<Todo, JsonPlaceholderError>
  createTodo(todo: Omit<Todo, "id">): Effect.Effect<Todo, JsonPlaceholderError>
}>()(
  "app/JsonPlaceholder"
) {
  static readonly layer = Layer.effect(
    JsonPlaceholder,
    Effect.gen(function*() {
      // Get the HttpClient service and configure it with middleware
      const client = (yield* HttpClient.HttpClient).pipe(
        // Base URL + default headers for all requests
        HttpClient.mapRequest(flow(
          HttpClientRequest.prependUrl("https://jsonplaceholder.typicode.com"),
          HttpClientRequest.acceptJson
        )),
        // Fail on non-2xx responses
        HttpClient.filterStatusOk,
        // Retry transient errors (network issues, 5xx)
        HttpClient.retryTransient({
          schedule: Schedule.exponential(100),
          times: 3
        })
      )

      // GET with schema-validated response
      const allTodos = client.get("/todos").pipe(
        Effect.flatMap(HttpClientResponse.schemaBodyJson(Schema.Array(Todo))),
        Effect.mapError((cause) => new JsonPlaceholderError({ cause })),
        Effect.withSpan("JsonPlaceholder.allTodos")
      )

      const getTodo = Effect.fn("JsonPlaceholder.getTodo")(function*(id: number) {
        yield* Effect.annotateCurrentSpan({ id })
        return yield* client.get(`/todos/${id}`, {
          urlParams: { format: "json" }
        }).pipe(
          Effect.flatMap(HttpClientResponse.schemaBodyJson(Todo)),
          Effect.mapError((cause) => new JsonPlaceholderError({ cause }))
        )
      })

      // POST with request builder
      const createTodo = Effect.fn("JsonPlaceholder.createTodo")(
        function*(todo: Omit<Todo, "id">) {
          return yield* HttpClientRequest.post("/todos").pipe(
            HttpClientRequest.setUrlParams({ format: "json" }),
            HttpClientRequest.bodyJsonUnsafe(todo),
            client.execute,
            Effect.flatMap(HttpClientResponse.schemaBodyJson(Todo)),
            Effect.mapError((cause) => new JsonPlaceholderError({ cause }))
          )
        }
      )

      return JsonPlaceholder.of({ allTodos, getTodo, createTodo })
    })
  ).pipe(
    // Provide the fetch-based HttpClient implementation
    Layer.provide(FetchHttpClient.layer)
  )
}
```

Key patterns:

- The `HttpClient` is itself a service — `yield*` it from the service map
- Configure with middleware via pipe: `mapRequest`, `filterStatusOk`, `retryTransient`
- Validate responses with `HttpClientResponse.schemaBodyJson(MySchema)`
- Build complex requests with `HttpClientRequest.post()`, `.bodyJsonUnsafe()`, etc.
- `FetchHttpClient.layer` provides the implementation (also available: `NodeHttpClient`, `BunHttpClient`)

## HttpApi — schema-first HTTP servers

HttpApi gives you schema-first, type-safe HTTP APIs with runtime validation,
typed clients, and OpenAPI docs from one definition. The API definition is
separate from the implementation so it can be shared between server and client.

### Architecture

```
api/  (shared — could be its own package)
├── Api.ts              — root API, combines groups
├── Users.ts            — endpoint group with schemas
├── Authorization.ts    — middleware + security scheme
└── System.ts           — health check group

domain/
├── User.ts             — Schema.Class + branded types
└── UserErrors.ts       — error types with httpApiStatus

server/
├── Users.ts            — domain service implementation
├── Users/http.ts       — handler wiring (API schema → service)
└── Authorization.ts    — middleware implementation
```

### Defining the API

```ts
// api/Users.ts
import { Schema } from "effect"
import { HttpApiEndpoint, HttpApiGroup, HttpApiSchema, OpenApi } from "effect/unstable/httpapi"

export class UsersApi extends HttpApiGroup.make("users")
  .add(
    HttpApiEndpoint.get("list", "/", {
      query: { search: Schema.optional(Schema.String) },
      success: Schema.Array(User)
    }),
    HttpApiEndpoint.get("getById", "/:id", {
      params: {
        // Path params decode from strings — use Schema.decodeTo to bridge
        id: Schema.FiniteFromString.pipe(Schema.decodeTo(UserId))
      },
      success: User,
      error: UserNotFound.pipe(HttpApiSchema.asNoContent({
        decode: () => new UserNotFound()
      }))
    }),
    HttpApiEndpoint.post("create", "/", {
      // POST payload defaults to JSON body
      payload: Schema.Struct({ name: Schema.String, email: Schema.String }),
      success: User
    }),
    HttpApiEndpoint.get("search", "/search", {
      // GET payload uses query string
      payload: { search: Schema.String },
      // Multiple success types
      success: [
        Schema.Array(User),
        Schema.String.pipe(HttpApiSchema.asText({ contentType: "text/csv" }))
      ],
      // Multiple error types
      error: [
        SearchQueryTooShort.pipe(HttpApiSchema.asNoContent({
          decode: () => new SearchQueryTooShort()
        })),
        HttpApiError.RequestTimeoutNoContent
      ]
    })
  )
  .middleware(Authorization)
  .prefix("/users")
  .annotateMerge(OpenApi.annotations({ title: "Users" }))
{}

// api/Api.ts
export class Api extends HttpApi.make("my-api")
  .add(UsersApi)
  .add(SystemApi)
  .annotateMerge(OpenApi.annotations({ title: "My API" }))
{}

// api/System.ts — top-level group (no prefix nesting in client)
export class SystemApi extends HttpApiGroup.make("system", { topLevel: true })
  .add(HttpApiEndpoint.get("health", "/health", {
    success: HttpApiSchema.NoContent
  }))
{}
```

### Defining middleware

```ts
// api/Authorization.ts
export class CurrentUser extends ServiceMap.Service<CurrentUser, User>()(
  "app/Authorization/CurrentUser"
) {}

export class Unauthorized extends Schema.TaggedErrorClass<Unauthorized>()(
  "Unauthorized",
  { message: Schema.String },
  { httpApiStatus: 401 }
) {}

export class Authorization extends HttpApiMiddleware.Service<Authorization, {
  provides: CurrentUser    // injected into downstream endpoints
  requires: never
}>()(
  "app/Authorization",
  {
    requiredForClient: true,  // client must also implement this
    security: { bearer: HttpApiSecurity.bearer },
    error: Unauthorized
  }
) {}
```

### Server implementation

```ts
// server/Authorization.ts
export const AuthorizationLayer = Layer.effect(
  Authorization,
  Effect.gen(function*() {
    return Authorization.of({
      bearer: Effect.fn(function*(httpEffect, { credential }) {
        const token = Redacted.value(credential)
        if (token !== "valid-token") {
          return yield* new Unauthorized({ message: "invalid token" })
        }
        // Provide CurrentUser to downstream endpoints
        return yield* Effect.provideService(
          httpEffect,
          CurrentUser,
          new User({ id: UserId.makeUnsafe(1), name: "Dev", email: "dev@acme.com" })
        )
      })
    })
  })
)

// server/Users/http.ts
export const UsersApiHandlers = HttpApiBuilder.group(
  Api,
  "users",
  Effect.fn(function*(handlers) {
    const users = yield* Users  // domain service

    return handlers
      .handle("list", ({ query }) =>
        users.list(query.search).pipe(Effect.orDie))
      .handle("getById", ({ params }) =>
        users.getById(params.id).pipe(
          Effect.catchReasons("UsersError", {
            UserNotFound: Effect.fail  // re-fail as endpoint error
          }, Effect.die)               // unexpected reasons → 500
        ))
      .handle("create", ({ payload }) =>
        users.create(payload).pipe(Effect.orDie))
      .handle("me", () => CurrentUser.asEffect())
  })
).pipe(
  Layer.provide([Users.layer, AuthorizationLayer])
)
```

### Serving

```ts
// Traditional server
const HttpServerLayer = HttpRouter.serve(
  HttpApiBuilder.layer(Api, { openapiPath: "/openapi.json" }).pipe(
    Layer.provide([UsersApiHandlers, SystemApiHandlers])
  )
).pipe(
  Layer.provide(NodeHttpServer.layer(createServer, { port: 3000 }))
)

Layer.launch(HttpServerLayer).pipe(NodeRuntime.runMain)

// Serverless web handler
const { handler, dispose } = HttpRouter.toWebHandler(AllRoutes.pipe(
  Layer.provide(HttpServer.layerServices)
))

// OpenAPI docs UI
const DocsRoute = HttpApiScalar.layer(Api, { path: "/docs" })
```

### Generated typed client

The client is generated from the same API definition — renames and schema
changes are checked end-to-end at compile time.

```ts
// Client-side middleware implementation
const AuthorizationClient = HttpApiMiddleware.layerClient(
  Authorization,
  Effect.fn(function*({ next, request }) {
    return yield* next(HttpClientRequest.bearerToken(request, "my-token"))
  })
)

// Generated client as a service
export class ApiClient extends ServiceMap.Service<
  ApiClient,
  HttpApiClient.ForApi<typeof Api>
>()(
  "app/ApiClient"
) {
  static readonly layer = Layer.effect(
    ApiClient,
    HttpApiClient.make(Api, {
      transformClient: (client) => client.pipe(
        HttpClient.mapRequest(HttpClientRequest.prependUrl("http://localhost:3000")),
        HttpClient.retryTransient({ schedule: Schedule.exponential(100), times: 3 })
      )
    })
  ).pipe(
    Layer.provide(AuthorizationClient),
    Layer.provide(FetchHttpClient.layer)
  )
}

// Usage — mirrors the API definition exactly
const client = yield* ApiClient
yield* client.list({ search: "alice" })
yield* client.getById({ id: 1 })
yield* client.create({ name: "Bob", email: "bob@example.com" })
yield* client.health()  // top-level group → no nesting
```

### Error handling in handlers

The reason error pattern is particularly useful in HTTP handlers. Services use
a single wrapper error, and handlers selectively promote specific reasons:

```ts
// Service uses wrapper error
class UsersError extends Schema.TaggedErrorClass<UsersError>()("UsersError", {
  reason: Schema.Union([UserNotFound, SearchQueryTooShort])
}) {}

// Handler unwraps the specific reasons it cares about
handlers.handle("getById", ({ params }) =>
  users.getById(params.id).pipe(
    Effect.catchReasons("UsersError", {
      UserNotFound: Effect.fail    // becomes the endpoint's error
    }, Effect.die)                 // everything else → 500
  ))

// Alternative: flatten all reasons, handle individually
handlers.handle("search", ({ payload }) =>
  users.list(payload.search).pipe(
    Effect.unwrapReason("UsersError"),
    Effect.catchTags({
      SearchQueryTooShort: Effect.fail,
      UserNotFound: Effect.die
    })
  ))
```
