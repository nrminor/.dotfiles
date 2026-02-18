---
description: Translate a natural language prompt into SQL, run it with DuckDB, and present the results
---

Answer a question about data by translating it to SQL and executing it with
DuckDB. Load the **duckdb** skill before writing any SQL.

## Process

### 1. Identify the data source

The user may name the data source in their prompt. If they don't, discover it
automatically with this precedence:

1. `.duckdb` files (persistent databases)
2. `.parquet` files
3. `.csv` or `.tsv` files
4. Ask the user

At each level, if there is exactly one candidate, use it. If there are multiple,
skip to asking the user which one they mean. Use `glob` to search — don't scan
the whole filesystem, just the project directory.

### 2. Inspect the schema

Before writing SQL, understand what you're querying:

```bash
duckdb -markdown -c "DESCRIBE 'source_file'"
```

For persistent `.duckdb` databases:

```bash
duckdb source.duckdb -markdown -c "SHOW TABLES"
duckdb source.duckdb -markdown -c "DESCRIBE table_name"
```

### 3. Write and run the SQL

Translate the user's question into DuckDB SQL. Run it with markdown output:

```bash
duckdb -markdown -c "SELECT ... FROM 'source_file' ..."
```

For persistent databases:

```bash
duckdb source.duckdb -markdown -c "SELECT ..."
```

If the query fails, read the error, adjust the SQL, and retry. Don't give up
after one attempt — schema misunderstandings and syntax issues are normal on a
first pass.

### 4. Present the results

Every response must include:

1. **The successful SQL query** in a code block. The user should be able to copy
   and rerun it.
2. **The query results** as a formatted table.
3. **A plain-language answer** to the original question, interpreting the results
   in context.

If intermediate queries failed before the successful one, you don't need to show
them — just the final working SQL.

<prompt>
$ARGUMENTS
</prompt>
