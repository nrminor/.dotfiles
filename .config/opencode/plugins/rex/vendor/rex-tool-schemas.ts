/**
 * JSON Schemas and JSON values for the Rex codemode tools, derived from the SDK's Effect Schemas so
 * tool parameters and results cannot drift from the SDK.
 *
 * - Parameters: one flat object. SDK positional arguments become named fields, and the SDK's input
 *   object spreads into top-level fields beside them.
 * - Results: the SDK's decoded domain values as plain JSON. Effect `Option` becomes `value | null`,
 *   and `void` becomes `null`.
 */
import { Duration, Option, Schema } from "effect";

/** A JSON Schema node. */
export type JsonSchema = { readonly [key: string]: unknown };

/** A JSON value returned to codemode scripts as `structuredContent`. */
export type RexToolJson =
  | null
  | boolean
  | number
  | string
  | RexToolJson[]
  | { [key: string]: RexToolJson };

/** JSON Schema of a tool that resolves to nothing. */
export const rexToolVoidOutputJsonSchema: JsonSchema = { type: "null" };

/** Field accepted by every Rex tool: the local SDK deadline for each request the call makes. */
export const REX_REQUEST_TIMEOUT_FIELD = "requestTimeoutMs";

/** Whether `value` is a JSON object (not an array or null). */
export function isJsonObject(value: unknown): value is { readonly [key: string]: unknown } {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function toJsonSchema(value: unknown): JsonSchema {
  if (!isJsonObject(value)) throw new Error("Rex tool schema is not a JSON Schema object");
  return value;
}

function stringsOf(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

function mapJsonSchema(
  node: unknown,
  visit: (node: JsonSchema) => JsonSchema | undefined,
): unknown {
  if (Array.isArray(node)) return node.map((item) => mapJsonSchema(item, visit));
  if (!isJsonObject(node)) return node;
  const replaced = visit(node);
  if (replaced !== undefined) return replaced;
  return Object.fromEntries(
    Object.entries(node).map(([key, value]) => [key, mapJsonSchema(value, visit)]),
  );
}

const STRUCTURAL_KEYWORDS = ["type", "$ref", "anyOf", "oneOf", "allOf", "properties", "items"];

/**
 * Effect emits checks as `{ type: "number", allOf: [{ minimum: 0 }] }`. Codemode declarations
 * render that as `unknown`, so fold constraint-only `allOf` members into their parent.
 */
function mergeConstraintAllOf(node: unknown): unknown {
  return mapJsonSchema(node, (candidate) => {
    const members = candidate.allOf;
    if (!Array.isArray(members)) return undefined;
    const constraints = members.filter(isJsonObject);
    const allConstraints =
      constraints.length === members.length &&
      constraints.every((member) => !STRUCTURAL_KEYWORDS.some((key) => key in member));
    if (!allConstraints) return undefined;
    const { allOf: _allOf, ...rest } = candidate;
    const merged: Record<string, unknown> = { ...rest };
    for (const member of constraints) {
      for (const [key, value] of Object.entries(member)) if (!(key in merged)) merged[key] = value;
    }
    return toJsonSchema(mergeConstraintAllOf(merged));
  });
}

/** Whether `node` is Effect's JSON form of a number that may be non-finite. */
function isNonFiniteNumberUnion(node: JsonSchema): boolean {
  const variants = node.anyOf;
  if (!Array.isArray(variants) || variants.length !== 2) return false;
  const [number, special] = variants;
  return (
    isJsonObject(number) &&
    number.type === "number" &&
    isJsonObject(special) &&
    special.type === "string" &&
    JSON.stringify(special.enum) === JSON.stringify(["Infinity", "-Infinity", "NaN"])
  );
}

/**
 * Effect describes a plain `Number` as `number | "Infinity" | "-Infinity" | "NaN"`. Tool arguments
 * and results are plain JSON numbers (results encode non-finite numbers as null), so keep `number`.
 */
function collapseNonFiniteNumbers(node: unknown): unknown {
  return mapJsonSchema(node, (candidate) => {
    if (!isNonFiniteNumberUnion(candidate)) return undefined;
    const { anyOf: _anyOf, ...rest } = candidate;
    const [number] = Array.isArray(candidate.anyOf) ? candidate.anyOf : [];
    return { ...rest, ...(isJsonObject(number) ? number : {}) };
  });
}

interface JsonSchemaParts {
  readonly schema: JsonSchema;
  readonly definitions: Record<string, JsonSchema>;
}

function toJsonSchemaParts(schema: Schema.Top): JsonSchemaParts {
  const document = Schema.toJsonSchemaDocument(schema);
  return {
    schema: toJsonSchema(collapseNonFiniteNumbers(mergeConstraintAllOf(document.schema))),
    definitions: Object.fromEntries(
      Object.entries(document.definitions).map(([name, definition]) => [
        name,
        toJsonSchema(collapseNonFiniteNumbers(mergeConstraintAllOf(definition))),
      ]),
    ),
  };
}

/**
 * Collects `$defs` from several schema documents into one, renaming colliding definitions and
 * rewriting the `#/$defs/...` references of each document that was renamed.
 */
class RexJsonSchemaDefinitions {
  readonly definitions: Record<string, JsonSchema> = {};

  adopt(parts: JsonSchemaParts): JsonSchema {
    const renames = new Map<string, string>();
    for (const [name, definition] of Object.entries(parts.definitions)) {
      const existing = this.definitions[name];
      if (existing === undefined || JSON.stringify(existing) === JSON.stringify(definition))
        continue;
      let index = 1;
      while (this.definitions[`${name}_${index}`] !== undefined) index++;
      renames.set(name, `${name}_${index}`);
    }
    const rewrite = (node: unknown): JsonSchema =>
      toJsonSchema(
        mapJsonSchema(node, (candidate) => {
          const ref = candidate.$ref;
          if (typeof ref !== "string" || !ref.startsWith("#/$defs/")) return undefined;
          const renamed = renames.get(ref.slice("#/$defs/".length));
          return renamed === undefined ? undefined : { ...candidate, $ref: `#/$defs/${renamed}` };
        }),
      );
    for (const [name, definition] of Object.entries(parts.definitions)) {
      this.definitions[renames.get(name) ?? name] = rewrite(definition);
    }
    return rewrite(parts.schema);
  }

  attachTo(schema: JsonSchema): JsonSchema {
    return Object.keys(this.definitions).length === 0
      ? schema
      : { ...schema, $defs: this.definitions };
  }
}

/** Object variants of an input schema: one for an object, several for a union of objects. */
function objectVariantsOf(schema: JsonSchema): readonly JsonSchema[] | undefined {
  if (schema.type === "object") return [schema];
  const variants = schema.anyOf;
  if (!Array.isArray(variants)) return undefined;
  const objects = variants.filter(isJsonObject);
  return objects.length === variants.length && objects.every((variant) => variant.type === "object")
    ? objects
    : undefined;
}

/** Parameter layout of one Rex tool. */
export interface RexToolParameterShape {
  /** Named fields for SDK positional arguments, such as `{ sessionId, blockId }`. */
  readonly fields: Schema.Struct.Fields;
  /** SDK input object whose fields become top-level tool fields; `fields` win on shared keys. */
  readonly input: Schema.Top | undefined;
}

/**
 * Flat JSON Schema for a tool's parameters, from the type side of the SDK's schemas. Throws when
 * the input is not an object, so a bad operation table fails at registration and in tests.
 */
export function rexToolParametersJsonSchema(shape: RexToolParameterShape): JsonSchema {
  const definitions = new RexJsonSchemaDefinitions();
  const properties: Record<string, unknown> = {};
  const required = new Set<string>();

  const fieldNames = Object.keys(shape.fields);
  if (shape.input !== undefined) {
    const inputSchema = definitions.adopt(toJsonSchemaParts(Schema.toType(shape.input)));
    const variants = objectVariantsOf(inputSchema);
    if (variants === undefined) throw new Error("Rex tool input must be an object");
    for (const variant of variants) {
      const variantProperties = isJsonObject(variant.properties) ? variant.properties : {};
      for (const [key, property] of Object.entries(variantProperties)) {
        if (fieldNames.includes(key)) continue;
        const previous = properties[key];
        if (previous !== undefined && JSON.stringify(previous) !== JSON.stringify(property)) {
          throw new Error(`Rex tool parameter "${key}" differs between input variants`);
        }
        properties[key] = property;
      }
    }
    if (variants.length === 1) {
      for (const key of stringsOf(variants[0]?.required))
        if (!fieldNames.includes(key)) required.add(key);
    }
  }
  if (fieldNames.length > 0) {
    const fieldsSchema = definitions.adopt(
      toJsonSchemaParts(Schema.toType(Schema.Struct(shape.fields))),
    );
    const fieldProperties = isJsonObject(fieldsSchema.properties) ? fieldsSchema.properties : {};
    for (const [key, property] of Object.entries(fieldProperties)) properties[key] = property;
    for (const key of stringsOf(fieldsSchema.required)) required.add(key);
  }
  if (REX_REQUEST_TIMEOUT_FIELD in properties) {
    throw new Error(`Rex tool parameter "${REX_REQUEST_TIMEOUT_FIELD}" is reserved`);
  }
  // A plain number keeps every declaration short; the SDK rejects negative or non-finite deadlines.
  properties[REX_REQUEST_TIMEOUT_FIELD] = { type: "number" };

  return definitions.attachTo({
    type: "object",
    properties,
    ...(required.size > 0 ? { required: [...required] } : {}),
    additionalProperties: false,
  });
}

/** Validation-only keywords; result schemas document shape, so they drop these. */
const RESULT_SCHEMA_VALIDATION_KEYWORDS = new Set([
  "minLength",
  "maxLength",
  "minimum",
  "maximum",
  "exclusiveMinimum",
  "exclusiveMaximum",
  "minItems",
  "maxItems",
  "pattern",
  "format",
  "additionalProperties",
]);

/** Result schemas keep types and field names only: `integer` becomes `number`, constraints go. */
function toResultShapeSchema(node: unknown): unknown {
  return mapJsonSchema(node, (candidate) => {
    const output: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(candidate)) {
      if (RESULT_SCHEMA_VALIDATION_KEYWORDS.has(key) && !isJsonObject(value)) continue;
      if (key === "type" && value === "integer") {
        output[key] = "number";
        continue;
      }
      output[key] =
        (key === "properties" || key === "$defs") && isJsonObject(value)
          ? Object.fromEntries(
              Object.entries(value).map(([name, child]) => [name, toResultShapeSchema(child)]),
            )
          : toResultShapeSchema(value);
    }
    return output;
  });
}

/** Effect Schema's JSON form of `Option<A>`: `{ _tag: "Some", value: A } | { _tag: "None" }`. */
function optionValueSchema(node: JsonSchema): unknown {
  const variants = node.anyOf;
  if (!Array.isArray(variants) || variants.length !== 2) return undefined;
  const [some, none] = variants;
  const tagOf = (variant: unknown): unknown => {
    if (!isJsonObject(variant) || !isJsonObject(variant.properties)) return undefined;
    const tag = variant.properties._tag;
    if (!isJsonObject(tag)) return undefined;
    return Array.isArray(tag.enum) ? tag.enum[0] : tag.const;
  };
  if (tagOf(some) !== "Some" || tagOf(none) !== "None") return undefined;
  return isJsonObject(some) && isJsonObject(some.properties) ? some.properties.value : undefined;
}

function rewriteOptions(node: unknown): unknown {
  return mapJsonSchema(node, (candidate) => {
    const value = optionValueSchema(candidate);
    return value === undefined ? undefined : { anyOf: [rewriteOptions(value), { type: "null" }] };
  });
}

/** JSON Schema of a tool result, matching what {@link encodeRexToolResult} produces. */
export function rexToolOutputJsonSchema(schema: Schema.Top): JsonSchema {
  const definitions = new RexJsonSchemaDefinitions();
  const parts = toJsonSchemaParts(Schema.toType(schema));
  const root = definitions.adopt({
    schema: toJsonSchema(rewriteOptions(parts.schema)),
    definitions: Object.fromEntries(
      Object.entries(parts.definitions).map(([name, definition]) => [
        name,
        toJsonSchema(rewriteOptions(definition)),
      ]),
    ),
  });
  return toJsonSchema(toResultShapeSchema(definitions.attachTo(root)));
}

/** Converts a decoded SDK value into the plain JSON a script receives. */
export function encodeRexToolResult(value: unknown): RexToolJson {
  if (value === undefined || value === null) return null;
  if (Option.isOption(value)) return Option.isSome(value) ? encodeRexToolResult(value.value) : null;
  if (Duration.isDuration(value)) return Duration.toMillis(value);
  if (value instanceof Date) return value.toISOString();
  if (value instanceof Uint8Array) return Buffer.from(value).toString("base64");
  if (Array.isArray(value)) return value.map(encodeRexToolResult);
  switch (typeof value) {
    case "boolean":
    case "string":
      return value;
    case "number":
      return Number.isFinite(value) ? value : null;
    case "bigint":
      return value.toString();
    case "object": {
      const output: { [key: string]: RexToolJson } = {};
      for (const [key, field] of Object.entries(value)) {
        if (field !== undefined) output[key] = encodeRexToolResult(field);
      }
      return output;
    }
    default:
      throw new Error(`Rex tool result contains an unsupported ${typeof value} value`);
  }
}
