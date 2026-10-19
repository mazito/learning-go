# DRAFT-V3.md — SQL-connector-API (SCAPI) spec

Third iteration. Changes vs V2 are listed in §14. Design borrowed from the QRL
TOML format (`qualify-reports/docs/definitions/toml-format.md`): one ordered
`[[step]]` array, step kind = the key it carries, SQL does the column mapping.

## 1. Purpose

SCAPI runs next to a local SQL engine and exposes a **fixed, whitelisted** set
of JSON-RPC 2.0 methods (queries and mutations) to a remote Treme.io connector.
No method ever accepts raw SQL.

~~~
[ local sql engine | SCAPI ] --outbound--> << internet >> [ treme-connector ]
~~~

SCAPI always **dials out** to the connector and keeps a bidirectional channel
open; no inbound port is opened on the local side.

A method file has **three independent layers**:

| layer      | section                   | describes                                         |
|------------|---------------------------|---------------------------------------------------|
| signature  | `[params]`, `[results]`   | the JSON-RPC contract: shape, types, cardinality  |
| run        | `[[step]]`                | ordered SQL steps: `exec`, `query`, `emit`        |
| database   | (introspected at startup) | tables/columns the SQL touches; used to validate  |

The signature never references tables. The SQL never references the
signature except through bound values (`:params.x`) and shape refs
(`@results.x`) inside interpolation functions. The DB schema is **read from
the engine**, never written in TOML.

## 2. File layout

~~~
scapi/
  registry.toml                # connector, DB pools, enabled methods
  methods/
    get_clients.method.toml
    patch_client.method.toml
    patch_invoice.method.toml
~~~

All files are loaded, the referenced tables introspected, and everything
**validated at startup** (§11); any error aborts the start. Nothing is parsed
at request time except param values.

## 3. Registry — `registry.toml`

~~~toml
title = "SCAPI registry"
description = "Remote Connector, DB Pools and enabled JSON-RPC methods"

[connector]
id = "saltino01"                  # the connector ID (assigned in Treme)
url = "https://xio.treme.io"      # the Connectors API URL
user = "$ENV:XIO_USER"            # Treme user and password for login
password = "$ENV:XIO_PASSW"

[[pool]]
name = "pool01mssql2022"
driver = "mssql"                  # dialect: mssql | postgres | mysql | sqlite
server = 'localhost\mssql2022'    # 'host\instance' or 'host:port'
port = 1433
database = "database02"
user = "$ENV:SQL_USER"
password = "$ENV:SQL_PASSW"
max_open = 10
max_idle = 2
statement_timeout_ms = 30000

[[pool]]
name = "pool02mssql2014"
driver = "mssql"
server = 'localhost\mssql2014'
database = "database02"
user = "$ENV:SQL_USER"
password = "$ENV:SQL_PASSW"

[[method]]
name = "get_clients"
pool = "pool01mssql2022"

[[method]]
name = "patch_client"
pool = "pool01mssql2022"

[[method]]
name = "patch_invoice"
pool = "pool01mssql2022"
~~~

Rules:
- `driver` is **mandatory**: selects the SQL dialect used by interpolation
  functions and the introspection queries. Never inferred from the name.
- `[[method]].name` must match a file `methods/<name>.method.toml` and its
  inner `method` field. The registry only *enables and binds* a method to a
  pool; title and description live in the method file.
- A method file that exists but is not listed is **not exposed**.
- `$ENV:NAME` is resolved at load; missing env → startup error.

## 4. Method file — overview

~~~toml
method      = "get_clients"
title       = "Get clients"
description = "..."
version     = 1

[params]      # signature: input shape
[results]     # signature: output shape
[errors]      # which app errors this method can return, with messages (§9)
[[step]]      # ordered run: exec | query | emit
~~~

A method is a **query** when it has no `exec` step, a **mutation** otherwise.
Mutations run all steps in one transaction (§9). Every method ends with
exactly one `emit` step that fills `[results]`.

## 5. Signature — `[params]` and `[results]`

Pure JSON-RPC contract. Nothing here names a table or column.

### 5.1 Field definition

One inline table per scalar field:

~~~toml
name = { type = "string", required = true, default = "x", enum = ["a","b"], max = 200, description = "..." }
~~~

| key           | meaning                                                  |
|---------------|----------------------------------------------------------|
| `type`        | see 5.2                                                  |
| `required`    | default `false`; results: always present (may be null)   |
| `default`     | applied when absent (params only)                        |
| `enum`        | allowed literal values                                   |
| `max`         | max length (string/text), max value (numbers), max items (array) |
| `description` | free text                                                |

### 5.2 Types

Scalars: `string`, `text`, `integer`, `bigint`, `double`, `decimal`,
`boolean`, `uuid`, `date`, `datetime`, `json`.

Scalar arrays: `type = "string[]"`, `"integer[]"`, ...

Composite (`object`, `array`) are **subtables**, because TOML inline tables
cannot be extended later:

~~~toml
[params]
uid = { type = "uuid", required = true }

[params.client]
type        = "object"
required    = true
description = "any subset of writable fields"
[params.client.fields]
full_name = { type = "string", max = 200 }
address   = { type = "string", max = 400 }
notes     = { type = "text" }

[params.items]
type = "array"
max  = 500
[params.items.fields]            # shape of ONE element
id          = { type = "integer", required = true }
description = { type = "string" }
price       = { type = "double" }
quantity    = { type = "integer" }
total       = { type = "double" }
~~~

- `object` + `fields`: keys not declared are **rejected** (-32602).
- `array` + `fields`: array of objects; `array` without `fields` needs a
  scalar `type` via `of = "integer"`.
- `[results.x]` uses the same syntax; `type = "object"` yields one object,
  `type = "array"` an array of objects.

### 5.3 Built-in shapes

Available as types in `[params]`:

~~~toml
# Condition — type = "Condition[]"
col      = { type = "string", required = true }
operator = { type = "string", required = true, enum = ["EQ","NEQ","GT","GTE","LT","LTE","IN","NOT_IN","LIKE","IS_NULL","IS_NOT_NULL","BETWEEN"] }
values   = { type = "json[]", default = [] }   # 0 for IS_*, 1 scalar, N for IN, 2 for BETWEEN
~~~

~~~toml
# OrderBy — type = "OrderBy[]"
col   = { type = "string", required = true }
order = { type = "string", default = "asc", enum = ["asc","desc"] }
~~~

Shared custom shapes across methods: **not in V3** (inline only). See §13.

## 6. Run — `[[step]]`

One ordered array; file order = execution order. The kind is the key the
step carries:

| key                | kind     | effect                                                  |
|--------------------|----------|---------------------------------------------------------|
| `exec = "<name>"`  | write    | runs `sql`; checks `expect`; no rowset                  |
| `query = "<name>"` | read     | runs `sql`; rows kept as rowset `<name>`                |
| `emit = "results"` | map      | fills `[results]` from rowsets / params; always last    |

Common keys: `when` (skip step when a value ref is absent/null/empty),
`driver` (pin to a dialect, §7.10).

### 6.1 `exec`

~~~toml
[[step]]
exec    = "update_header"
expect  = "one"                  # one | some | any (default any)
foreach = ":params.items"        # optional: run once per element, binds :item
when    = ":params.summary"      # optional
sql = """ ... """
~~~

| key       | meaning                                                            |
|-----------|--------------------------------------------------------------------|
| `expect`  | `one` = exactly 1 row affected, `some` = ≥1, `any` = no check      |
| `foreach` | array value ref; `:item` is the element; `expect` applies per item |
| `on_zero` | override error on `expect` violation: `NOT_FOUND` \| `CONFLICT`    |

### 6.2 `query`

~~~toml
[[step]]
query = "clients"
sql = """ SELECT ... """
~~~

Column names of the rowset are the SQL output names (aliases). **The SELECT
list is the column→field mapping**; `expand_columns` writes `col AS field`
for you (§7.1), hand-written aliases work the same.

Optional `[step.columns]` subtable: field → column renames used by
functions in that step (`expand_columns`, `expand_set`, ...):

~~~toml
[[step]]
query = "clients"
sql = "SELECT ${expand_columns(\"clients\", @results.clients)} FROM clients"
[step.columns]
full_name = "FullName"
~~~

### 6.3 `emit`

~~~toml
[[step]]
emit = "results"
[step.fields]
clients = "clients"                         # rowset → array of objects
count   = "count.n"                         # rowset.column → scalar from first row
client  = { from = "client", one = true }   # exactly one row → object; 0 rows → NOT_FOUND
echo    = ":params.uid"                     # a param value, passed through
~~~

Rules:
- every `[results]` field must be assigned; every assignment must target a
  declared field.
- rowset columns must be a subset of the target shape's fields; extra
  columns → startup error (when the statement can be described, §11.9) or
  runtime `INTERNAL`; declared fields missing in the rowset → `null`.
- `one = true` with >1 rows → `INTERNAL` (a bug in the SQL).
- values are converted to the declared `type` (`uuid` text, `datetime` ISO
  8601 UTC, `decimal` string).

## 7. SQL templates and interpolation functions

A template is plain SQL plus three token kinds:

| token                    | meaning                                                      |
|--------------------------|--------------------------------------------------------------|
| `:params.a.b`, `:item.x` | **value ref** → bound as a query parameter, never inlined    |
| `@results.x`, `@params.x`| **shape ref** → compile-time only; gives a field list        |
| `${fn(...)}`             | **interpolation function** → replaced by a SQL fragment      |

Table and column names appear as **string literals** in function arguments
(`"clients"`, `["full_name","address"]`). They are validated at startup
against the introspected schema (§11) and then inlined. Nothing coming from
the request is ever inlined: `Condition.col`, `OrderBy.col` and object keys
are matched against these literal allowlists first.

### Value refs — one token, one meaning

`:params.a.b` (and `:item.x` inside a `foreach` step) always means "the value
of this param". It is **never inlined**, in any position:

| where it appears | example                                  | effect                                                        |
|------------------|------------------------------------------|---------------------------------------------------------------|
| bare in SQL      | `WHERE uid = :params.uid`                | exactly one bound placeholder; value must be a **scalar**     |
| function arg     | `expand_set(:params.client, "clients")`  | the function receives the value and emits N placeholders      |
| step key         | `foreach = ":params.items"`, `when = ...` | read by the runner; no SQL                                    |
| emit             | `echo = ":params.uid"`                   | passed through to the result                                  |

- a bare ref to an `object` or `array` in SQL is a **startup error**: use a
  function (`expand_in`, `expand_set`, ...). No auto-expansion.
- the `params.` prefix is mandatory: it keeps `:params.*` and `:item.*`
  distinct and mirrors `@results.*` / `@params.*`.

Other rules:
- bound placeholders follow the driver (`@p1` / `$1` / `?`).
- a function with no data emits an **empty string** unless stated otherwise.
- nested calls only inside `expand_where`.
- all refs/literals checked at startup (§11).

### 7.1 `expand_columns("table", @results.x)`

`SELECT` list: `col AS field` for every field of the shape (object → its
fields; array → element fields). `col` = field name, or `[step.columns]`
rename. Every `col` must exist in `table`. Optional third arg: alias prefix
(`"c"` → `c.FullName AS full_name`).

### 7.2 `expand_where(frag, frag, ...)`

Joins non-empty predicate fragments with `AND`, prefixes `WHERE`; all empty
→ empty string. Accepts `expand_conditions`, `expand_search`, or a literal
predicate (`"deleted = 0"`).

### 7.3 `expand_conditions(:params.filters, ["col", ...])`

- input `Condition[]`; `col` must be in the literal allowlist; `operator`
  in the enum; `values` cardinality checked per operator.
- emits `col OP ?` joined with `AND`; `IN (?, ?, ...)` one placeholder per
  value; `LIKE` binds the value as given (caller adds `%`); `IS_NULL` /
  `IS_NOT_NULL` take no value.
- bind type for each `?` = DB column type (introspected).

### 7.4 `expand_search(:params.q, ["col", ...])`

- `q` split on whitespace; each word → `%word%` (`%` `_` escaped), bound
  once per column; `(c1 LIKE ? OR c2 LIKE ?)` per word, words joined `AND`.
- columns must be text-like in the DB.

### 7.5 `expand_order_by(:params.order_by, ["col", ...], "default")`

- `col` in allowlist, `order` whitelisted and inlined.
- `"default"` literal `"col dir[, col dir]"` used when input empty; needed
  because paging requires a deterministic order.

### 7.6 `expand_paging(:params.offset, :params.limit)`

- mssql: `OFFSET ? ROWS FETCH NEXT ? ROWS ONLY`; others: `LIMIT ? OFFSET ?`.
- both bound; `limit` capped by its param `max`.
- startup error if the template has no `expand_order_by` before it.

### 7.7 `expand_set(:params.obj, "table")`

- `obj` is an `object` param (or `:item`); its **present** keys become
  `col = ?` (rename via `[step.columns]`).
- every key must be a column of `table`; columns that are PK, identity,
  computed or rowversion are **skipped** (introspected).
- zero writable keys present → `BAD_REQUEST`.
- emits the bare list; the template writes `SET` so it can append
  `, vrs = vrs + 1`.

### 7.8 `expand_insert(:params.obj, "table")`

- `(col, ...) VALUES (?, ...)` for present keys, skipping identity/computed.
- startup check: every NOT NULL column without default of `table` is either
  a `required` field of the shape or written elsewhere in the same SQL.
- template: `INSERT INTO clients ${expand_insert(:params.client, "clients")}`.

### 7.9 `expand_in(:params.ids)`

`(?, ?, ...)` for a scalar array; empty → `BAD_REQUEST`.

### 7.10 `expand_values_table(:params.items, ["col", ...], "v")` — bulk, optional

Full derived table for the dialect, alias and column list included:

- mssql / postgres: `(VALUES (?,...),(?,...)) AS v(id, invoice_id, ...)`
- mysql ≥ 8.0.19: `(VALUES ROW(?,...),ROW(?,...)) AS v(id, ...)`
- sqlite: `(SELECT ? AS id, ... UNION ALL SELECT ?, ...) AS v`

The surrounding `UPDATE ... FROM/JOIN` is dialect-specific, so the step
must declare `driver = "mssql"`; startup fails if the pool differs. Prefer
`foreach` unless row counts make round trips matter.

## 8. Examples

### 8.1 Query — `methods/get_clients.method.toml`

~~~toml
method      = "get_clients"
title       = "Get clients"
description = "Client list with search, filters, order and paging"
version     = 1

[params]
q        = { type = "string", description = "one or more words" }
filters  = { type = "Condition[]", default = [] }
order_by = { type = "OrderBy[]", default = [] }
offset   = { type = "integer", default = 0 }
limit    = { type = "integer", default = 1000, max = 5000 }

[results]
count = { type = "integer" }

[results.clients]
type = "array"
[results.clients.fields]
id        = { type = "integer" }
uid       = { type = "uuid" }
vrs       = { type = "integer" }
full_name = { type = "string" }
address   = { type = "string" }
notes     = { type = "text" }

[errors]
BAD_REQUEST = "Bad params for request"

[[step]]
query = "clients"
sql = """
  SELECT ${expand_columns("clients", @results.clients)}
  FROM clients
  ${expand_where(expand_conditions(:params.filters, ["id","full_name","address"]), expand_search(:params.q, ["full_name","address","notes"]))}
  ${expand_order_by(:params.order_by, ["id","full_name"], "id asc")}
  ${expand_paging(:params.offset, :params.limit)}
"""
[step.columns]
full_name = "FullName"

[[step]]
query = "count"
sql = """
  SELECT COUNT(*) AS n
  FROM clients
  ${expand_where(expand_conditions(:params.filters, ["id","full_name","address"]), expand_search(:params.q, ["full_name","address","notes"]))}
"""
[step.columns]
full_name = "FullName"

[[step]]
emit = "results"
[step.fields]
clients = "clients"
count   = "count.n"
~~~

### 8.2 Mutation — `methods/patch_client.method.toml`

~~~toml
method      = "patch_client"
title       = "Patch a client"
description = "Partial update of one client, optimistic-locked by vrs"
version     = 1

[params]
uid = { type = "uuid", required = true }
vrs = { type = "integer", required = true }

[params.client]
type     = "object"
required = true
[params.client.fields]
full_name = { type = "string", max = 200 }
address   = { type = "string", max = 400 }
notes     = { type = "text" }

[results.client]
type = "object"
[results.client.fields]
id        = { type = "integer" }
uid       = { type = "uuid" }
vrs       = { type = "integer" }
full_name = { type = "string" }
address   = { type = "string" }
notes     = { type = "text" }

[errors]
NOT_FOUND   = "Client does not exist"
CONFLICT    = "Client was modified by someone else (vrs mismatch)"
BAD_REQUEST = "Bad params on request"

[[step]]
exec    = "update"
expect  = "one"
on_zero = "CONFLICT"
sql = """
  UPDATE clients
  SET ${expand_set(:params.client, "clients")}, vrs = vrs + 1
  WHERE uid = :params.uid AND vrs = :params.vrs
"""
[step.columns]
full_name = "FullName"

[[step]]
query = "client"
sql = """
  SELECT ${expand_columns("clients", @results.client)}
  FROM clients WHERE uid = :params.uid
"""
[step.columns]
full_name = "FullName"

[[step]]
emit = "results"
[step.fields]
client = { from = "client", one = true }
~~~

Note: with `on_zero = "CONFLICT"` the method cannot distinguish "no such
uid" from "vrs mismatch" in one statement. If needed, add a prior
`query = "exists"` step and `expect`-like check — open question §13.

### 8.3 Multi-table mutation — `methods/patch_invoice.method.toml`

~~~toml
method      = "patch_invoice"
title       = "Patch an invoice"
description = "Header + lines + summary in one transaction (fixed order: header, lines, summary)"
version     = 1

[params]
uid = { type = "uuid", required = true }
vrs = { type = "integer", required = true }

[params.invoice]
type     = "object"
required = true
[params.invoice.fields]
id          = { type = "integer", required = true }
client_name = { type = "string" }
address     = { type = "string" }
notes       = { type = "text" }

[params.items]
type = "array"
max  = 500
[params.items.fields]
id          = { type = "integer", required = true }
description = { type = "string" }
price       = { type = "double" }
quantity    = { type = "integer" }
total       = { type = "double" }

[params.summary]
type = "object"
[params.summary.fields]
id    = { type = "integer", required = true }
total = { type = "double" }

[results.invoice]
type = "object"
[results.invoice.fields]
id          = { type = "integer" }
uid         = { type = "uuid" }
vrs         = { type = "integer" }
client_name = { type = "string" }
address     = { type = "string" }
notes       = { type = "text" }

[results.items]
type = "array"
[results.items.fields]
id          = { type = "integer" }
description = { type = "string" }
price       = { type = "double" }
quantity    = { type = "integer" }
total       = { type = "double" }

[errors]
NOT_FOUND = "Invoice does not exist"
CONFLICT  = "Invoice was modified by someone else"

[[step]]
exec    = "header"
expect  = "one"
on_zero = "CONFLICT"
sql = """
  UPDATE invoice
  SET ${expand_set(:params.invoice, "invoice")}, vrs = vrs + 1
  WHERE uid = :params.uid AND vrs = :params.vrs
"""

[[step]]
exec    = "lines"
foreach = ":params.items"
expect  = "one"
sql = """
  UPDATE details
  SET ${expand_set(:item, "details")}
  WHERE id = :item.id AND invoice_id = :params.invoice.id
"""

[[step]]
exec   = "summary"
when   = ":params.summary"
expect = "one"
sql = """
  UPDATE summary
  SET ${expand_set(:params.summary, "summary")}
  WHERE invoice_id = :params.invoice.id AND id = :params.summary.id
"""

[[step]]
query = "invoice"
sql = "SELECT ${expand_columns(\"invoice\", @results.invoice)} FROM invoice WHERE uid = :params.uid"

[[step]]
query = "items"
sql = "SELECT ${expand_columns(\"details\", @results.items)} FROM details WHERE invoice_id = :params.invoice.id ORDER BY id"

[[step]]
emit = "results"
[step.fields]
invoice = { from = "invoice", one = true }
items   = "items"
~~~

`expand_set(:params.invoice, "invoice")` skips `id` because it is the PK
(introspected), so sending it in the payload is harmless and lets the
`WHERE` clauses reuse `:params.invoice.id`.

## 9. Transactions and errors

- A **mutation** (≥1 `exec`) runs every step, including trailing `query`
  steps, in **one transaction**, file order. First failure → rollback all,
  return the mapped error. No savepoints in v1.
- A **query** method runs its steps outside a transaction (read committed;
  `count` and `rows` may drift under load — accepted).
- Fixed step order is the deadlock-avoidance rule; state it in `description`.

Error mapping:

| situation                                        | `data.error`  | code   |
|--------------------------------------------------|---------------|--------|
| method not enabled                               | —             | -32601 |
| param validation (type, required, enum, max, unknown key, cardinality) | `BAD_REQUEST` + `data.field` | -32602 |
| `expect` violated (default) / `emit` `one` with 0 rows | `NOT_FOUND`  | -32001 |
| `expect` violated with `on_zero = "CONFLICT"`    | `CONFLICT`    | -32002 |
| SQL error, timeout, emit shape mismatch          | `INTERNAL`    | -32000 |

`[errors]` declares which of `NOT_FOUND` / `CONFLICT` / `BAD_REQUEST` the
method can raise and their messages; declaring one the steps can never raise
is a startup warning. `data.step` carries the step name. SQL error text is
**never** sent to the client; it is logged with the request id.

## 10. JSON-RPC

Request:
~~~json
{ "jsonrpc": "2.0", "id": 7, "method": "patch_client",
  "params": { "uid": "0190...", "vrs": 3, "client": { "notes": "VIP" } } }
~~~

Response (shape = `[results]`):
~~~json
{ "jsonrpc": "2.0", "id": 7,
  "result": { "client": { "id": 12, "uid": "0190...", "vrs": 4, "full_name": "...", "address": null, "notes": "VIP" } } }
~~~

Error:
~~~json
{ "jsonrpc": "2.0", "id": 7,
  "error": { "code": -32002, "message": "Client was modified by someone else (vrs mismatch)",
             "data": { "error": "CONFLICT", "method": "patch_client", "step": "update" } } }
~~~

No `success` field: a non-error response is success.

## 11. DB introspection and startup validation

At startup, per pool, SCAPI introspects every table named in the enabled
methods' templates (`information_schema` for mssql / postgres / mysql,
`PRAGMA table_info` for sqlite): columns, SQL type, nullable, default,
length, PK, identity / computed / rowversion. DB unreachable → **startup
fails** (no schema cache in v1).

Driver type map (SQL → signature type), used to check `expand_*` binds and
emit conversions:

| signature  | mssql                         | postgres            | mysql           |
|------------|-------------------------------|---------------------|-----------------|
| `string`   | varchar, nvarchar, char       | varchar, char, text | varchar, char   |
| `text`     | varchar(max), nvarchar(max)   | text                | text, longtext  |
| `integer`  | int, smallint, tinyint        | int2, int4          | int, smallint   |
| `bigint`   | bigint                        | int8                | bigint          |
| `double`   | float, real                   | float4, float8      | float, double   |
| `decimal`  | decimal, numeric, money       | numeric             | decimal         |
| `boolean`  | bit                           | bool                | tinyint(1), bool|
| `uuid`     | uniqueidentifier, char(36)    | uuid                | char(36), binary(16) |
| `date`     | date                          | date                | date            |
| `datetime` | datetime2, datetime, datetimeoffset | timestamp(tz) | datetime, timestamp |
| `json`     | nvarchar(max)                 | json, jsonb         | json            |

Startup checks (any failure aborts):

1. TOML parses (TOML 1.0: no multi-line inline tables, no trailing commas).
2. Every `[[method]]` has a file; file `method` matches; pool exists.
3. Signature: every `type` resolves; `enum`/`default`/`max` consistent with
   `type`; `object`/`array` have `fields` or `of`.
4. Steps: exactly one `emit`, last; every `exec`/`query` has `sql`;
   `foreach` targets an `array` param; `when`/`foreach` refs exist.
5. Templates: every `:params.*` path exists; `:item` only inside `foreach`;
   bare refs in SQL are scalars; `@results.x` / `@params.x` exist and are
   `object`/`array`.
6. Literals: every table exists; every column literal and `[step.columns]`
   target exists in its table; `expand_search` columns are text-like;
   `expand_set`/`expand_insert` shapes map to writable columns.
7. `expand_paging` preceded by `expand_order_by`; `expand_values_table` only
   in a step with `driver` equal to the pool driver.
8. `emit`: every `[results]` field assigned once; every source rowset /
   param exists; `one = true` only on `object` targets, plain rowset only on
   `array` targets; `rowset.col` only on scalar targets.
9. Optional (recommended): describe every statement against the live
   connection (`sp_describe_first_result_set` / `PREPARE`) with dummy binds;
   report SQL syntax errors and rowset/shape column mismatches at startup.

## 12. Security

- Methods are a closed whitelist; unknown method → -32601.
- Params validated **before** any SQL is built; unknown keys rejected (no
  silent drop); `max` enforced; arrays capped (`max`, default 1000).
- Only bound parameters reach the engine; every inlined token comes from a
  literal allowlist in the method file, checked against the DB at startup.
- Per-pool `statement_timeout_ms`; optional per-method `timeout_ms`.
- Connector authentication: `[connector]` credentials on the outbound dial;
  details in the connector spec.

## 13. Open questions

- Shared signature shapes across methods (`Client` used in 3 files): inline
  for now; revisit `shapes/` or `[shapes]` when duplication hurts.
- `version`: semantics pending (user note).
- NOT_FOUND vs CONFLICT in one `UPDATE ... WHERE uid = ? AND vrs = ?`:
  accept `CONFLICT` only, or add a cheap `query = "exists"` step with
  `expect = "one"` on queries too?
- `[step.columns]` repeated per step (get_clients has it twice): allow a
  method-level `[columns]` default, or a `[fragments]` section to reuse the
  WHERE template between `clients` and `count`?
- `vrs` bump: explicit in SQL (current) vs a step flag.
- Isolation level / lock hints per method; schema drift handling (restart
  vs SIGHUP re-introspect).
- Mutation results for `foreach` inserts (generated ids back to the client).

## 14. Changes vs DRAFT-V2

| area        | V2                                              | V3                                                        |
|-------------|-------------------------------------------------|-----------------------------------------------------------|
| models      | `models/*.model.toml`, typed by hand            | removed; DB introspected at startup, used only to validate |
| signature   | `type = "Client"`, `Client[]`, `Client?` refs   | pure JSON shapes; `object`/`array` subtables with `fields` |
| field keys  | `col`, `key`, `readonly` in signature           | gone from signature; renames in `[step.columns]`, PK/identity from DB |
| run         | `[query]`, `[query.count]`, `[[exec]]`          | one ordered `[[step]]`; kind = `exec` \| `query` \| `emit` |
| results     | `rows`, `one` on `[query]`                      | `emit` step: `[step.fields]` rowset/param → result field   |
| functions   | `@Model` args                                   | table/column **literals** + `@results.x` shape refs        |
| allowlists  | whole model columns                             | explicit per-call column arrays (filter/search/order)      |
| bulk        | `expand_values_table(:x, @Model, "v")`          | `expand_values_table(:x, ["col",...], "v")`, step `driver` |
| errors      | `expect` → NOT_FOUND/CONFLICT by declaration    | default NOT_FOUND; `on_zero` per step                      |
| naming      | "action"/"mutation" mixed, `scapi.toml`         | "mutation", `registry.toml`, `[connector]`, `[[pool]]`     |
