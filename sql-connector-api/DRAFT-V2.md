# DRAFT-V2.md — SQL-connector-API (SCAPI) spec

Second iteration of `DRAFT.md`. Same goals, tighter rules. Changes vs V1 are
listed at the end (§12).

## 1. Purpose

SCAPI runs next to a local SQL engine and exposes a **fixed, whitelisted** set
of JSON-RPC 2.0 methods (queries and mutations) to a remote Treme.io connector.
No method ever accepts raw SQL. Every method is a `.toml` file: typed params,
typed results, and one or more SQL templates that the engine compiles, binds
and runs.

~~~
[ local sql engine | SCAPI ] --outbound--> << internet >> [ treme-connector ]
~~~

SCAPI always **dials out** to the connector and keeps a bidirectional channel
open; no inbound port is opened on the local side.

## 2. File layout

~~~
scapi/
  registry.toml                 # registry: connections + enabled methods
  models/
    Client.model.toml        # shared row schemas (one per model)
    Invoice.model.toml
    InvoiceItem.model.toml
  methods/
    get_clients.method.toml
    patch_client.method.toml
    patch_invoice.method.toml
~~~

All files are loaded and **fully validated at startup**; any error aborts the
start (see §10). Nothing is parsed at request time except param values.

## 3. Registry — `registry.toml`

~~~toml
title = "SCAPI registry"
description = "Remote Connector, DB Pools and enabled JSON-RPC methods"

[connector]
id = "saltino01" # the connector ID (assigned in Treme)
url = "https://xio.treme.io" # the Connectors API URL
user = "$ENV:XIO_USER" # Treme user and passowrd for login
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
- `driver` is **mandatory**: it selects the SQL dialect used by the
  interpolation functions. Never inferred from the pool name.
- `[[method]].name` must match a file `methods/<name>.method.toml` and its
  inner `method` field. The registry only *enables and binds* a method; title
  and description live in the method file (single source).
- A method file that exists but is not listed is **not exposed**.
- `$ENV:NAME` is resolved at load; missing env → startup error.

## 4. Schema language

Used in `[fields]` of models and in `[params]` / `[results]` of methods.
One line per field, always an inline table:

~~~toml
name = { type = "string", required = true, default = "x", description = "..." }
~~~

| key           | meaning                                                    |
|---------------|------------------------------------------------------------|
| `type`        | see table below; `Model` or `Model[]` for refs             |
| `required`    | default `false`                                            |
| `default`     | used when absent and not required                          |
| `enum`        | array of allowed literal values                            |
| `col`         | SQL column name when it differs from the field name        |
| `key`         | `true` → part of the row identity (skipped by `expand_set`)|
| `readonly`    | `true` → never written by `expand_set` / `expand_insert`   |
| `max`         | max length (string/text) or max value (numbers)            |
| `description` | free text                                                  |

Scalar types: `string`, `text`, `integer`, `bigint`, `double`, `decimal`,
`boolean`, `uuid`, `date`, `datetime`, `json`.

Composite types:
- `type = "Client"` — object with the fields of model `Client`.
- `type = "Client[]"` — array of such objects.
- `type = "string[]"` — array of scalars.
- `type = "Client?"` — partial object: every field optional (patch payload).

Built-in models (no file needed):

~~~toml
# Condition
col      = { type = "string", required = true }
operator = { type = "string", required = true, enum = ["EQ","NEQ","GT","GTE","LT","LTE","IN","NOT_IN","LIKE","IS_NULL","IS_NOT_NULL","BETWEEN"] }
values   = { type = "json[]", default = [] }     # [] for IS_NULL, 1 scalar, N for IN, 2 for BETWEEN
~~~

~~~toml
# OrderBy
col   = { type = "string", required = true }
order = { type = "string", default = "asc", enum = ["asc","desc"] }
~~~

### Model file — `models/Client.model.toml`

~~~toml
model = "Client"
version = 1
table = "clients"
description = "A client row"

[fields]
id        = { type = "integer", key = true, readonly = true }
uid       = { type = "uuid", key = true, description = "UUIDv7 public id" }
vrs       = { type = "integer", readonly = true, description = "row version for optimistic locking" }
full_name = { type = "string", required = true, max = 200, col = "FullName" }
address   = { type = "string", max = 400 }
notes     = { type = "text" }
~~~

- `table` is the default target for functions that need one.
- `col` lets JSON names differ from SQL names; functions always emit
  `col AS field` on read and `col = ?` on write.

## 5. Method file

~~~toml
method      = "get_clients"
title       = "Get clients"
description = "Client list with search, filters, order and paging"
version     = 1

[params]      # input schema (see §4)
[results]     # output schema
[errors]      # app error codes → message (see §8)
[query]       # ONE read; or
[[exec]]      # ONE OR MORE ordered writes, in one transaction (§7)
[query.count] # optional, with [query] only
~~~

A method is either a **query** (`[query]`, optionally `[query.count]`) or an
**mutation** (`[[exec]]`... optionally followed by a `[query]` that reads the
result back inside the same transaction). Mixing in any other order is a
load error.

### 5.1 Query example — `methods/get_clients.method.toml`

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
count   = { type = "integer" }
clients = { type = "Client[]" }

[errors]
BAD_REQUEST = "Bad params for request"

[query]
schema = "Client"        # row schema used to validate col names in functions
rows   = "clients"       # which result field receives the rows
sql = """
  SELECT ${expand_columns(@Client)}
  FROM clients
  ${expand_where(expand_conditions(:params.filters), expand_search(:params.q, ["full_name","address","notes"]))}
  ${expand_order_by(:params.order_by, "id asc")}
  ${expand_paging(:params.offset, :params.limit)}
"""

[query.count]
rows = "count"
sql = """
  SELECT COUNT(*)
  FROM clients
  ${expand_where(expand_conditions(:params.filters), expand_search(:params.q, ["full_name","address","notes"]))}
"""
~~~

### 5.2 Mutation example — `methods/patch_client.method.toml`

~~~toml
method      = "patch_client"
title       = "Patch a client"
description = "Partial update of one client, optimistic-locked by vrs"
version     = 1

[params]
uid    = { type = "uuid", required = true }
vrs    = { type = "integer", required = true }
client = { type = "Client?", required = true, description = "any subset of writable fields" }

[results]
client = { type = "Client" }

[errors]
NOT_FOUND   = "Client does not exist"
CONFLICT    = "Client was modified by someone else (vrs mismatch)"
BAD_REQUEST = "Bad params on request"

[[exec]]
name   = "update"
expect = "one"                       # 0 rows → NOT_FOUND / CONFLICT (§8)
sql = """
  UPDATE clients
  SET ${expand_set(:params.client, @Client)}, vrs = vrs + 1
  WHERE uid = :params.uid AND vrs = :params.vrs
"""

[query]
schema = "Client"
rows   = "client"
one    = true                        # single object, not an array
sql = """
  SELECT ${expand_columns(@Client)} FROM clients WHERE uid = :params.uid
"""
~~~

### 5.3 Multi-table action — `methods/patch_invoice.method.toml`

~~~toml
method      = "patch_invoice"
title       = "Patch an invoice"
description = "Header + lines + summary in one transaction"
version     = 1

[params]
uid     = { type = "uuid", required = true }
vrs     = { type = "integer", required = true }
invoice = { type = "Invoice?", required = true }
items   = { type = "InvoiceItem?[]", default = [] }
summary = { type = "InvoiceSummary?" }

[results]
invoice = { type = "Invoice" }
items   = { type = "InvoiceItem[]" }

[errors]
NOT_FOUND = "Invoice does not exist"
CONFLICT  = "Invoice was modified by someone else"

[[exec]]
name   = "header"
expect = "one"
sql = """
  UPDATE invoice
  SET ${expand_set(:params.invoice, @Invoice)}, vrs = vrs + 1
  WHERE uid = :params.uid AND vrs = :params.vrs
"""

[[exec]]
name    = "lines"
foreach = ":params.items"            # binds :item for each element
expect  = "one"
sql = """
  UPDATE details
  SET ${expand_set(:item, @InvoiceItem)}
  WHERE id = :item.id AND invoice_id = :params.invoice.id
"""

[[exec]]
name   = "summary"
when   = ":params.summary"           # skipped when the param is absent
expect = "one"
sql = """
  UPDATE summary
  SET ${expand_set(:params.summary, @InvoiceSummary)}
  WHERE invoice_id = :params.invoice.id AND id = :params.summary.id
"""

[query]
schema = "Invoice"
rows   = "invoice"
one    = true
sql = "SELECT ${expand_columns(@Invoice)} FROM invoice WHERE uid = :params.uid"
~~~

`foreach` replaces the V1 `(VALUES ...) JOIN` bulk form: one bound statement
per element, same prepared statement reused, all inside the transaction.
Portable across dialects, explicit, and `expect` applies per row. A bulk
form stays available as an optimisation (§6.10) but is not the default.

## 6. SQL templates

A template is plain SQL plus three token kinds:

| token                 | meaning                                                        |
|-----------------------|----------------------------------------------------------------|
| `:params.a.b`, `:item.x` | **value reference** → bound as a query parameter, never inlined |
| `@Model`              | **schema reference** → compile-time only, never a value         |
| `${fn(...)}`          | **interpolation function** → replaced by a SQL fragment         |

Rules:
- Values are always bound (`?` / `@p1` / `$1` per driver). Structural tokens
  (column names, operators, sort direction) **cannot** be bound, so they are
  whitelist-validated against the `@Model` / `enum` and then inlined.
- Function arguments may be value refs, schema refs, literals (`"x"`,
  `["a","b"]`, `42`) or nested function calls. Nesting is used only by
  `expand_where`.
- A function with no data emits an **empty string** unless stated otherwise.
- Dialect-dependent output is decided by the connection `driver`.
- Everything a template references (`:params.*`, `@Model`, column literals)
  is checked at load time (§10).

### 6.1 `expand_columns(@Model, alias?)`

`SELECT` list: `col AS field` for every field of the model.
`alias` (string literal) prefixes columns: `d.FullName AS full_name`.

### 6.2 `expand_where(fragment, fragment, ...)`

Joins non-empty predicate fragments with `AND` and prefixes `WHERE`. All
empty → empty string. Only accepts outputs of `expand_conditions`,
`expand_search` or a literal predicate string (`"deleted = 0"`).
This replaces the V1 implicit "WHERE-side fragments are auto-joined" rule:
the template now says explicitly where the `WHERE` goes.

### 6.3 `expand_conditions(:params.filters, @Model?)`

- input `Condition[]`; `col` validated against `@Model` (defaults to
  `[query].schema`), `operator` against the enum.
- `values` cardinality checked per operator (0 / 1 / N / 2).
- emits `col OP ?` per condition, joined with `AND`; `IN (?, ?, ...)` with one
  placeholder per value; `LIKE` binds the value as given (caller adds `%`).
- empty → empty string.

### 6.4 `expand_search(:params.q, ["col", ...])`

- `q` split on whitespace; every word becomes `%word%` bound once per column
  (`%` and `_` in the word are escaped).
- one group per word: `(c1 LIKE ? OR c2 LIKE ?)`; groups joined with `AND`.
- column list is a **literal array**, validated against the schema.
- empty `q` → empty string.

### 6.5 `expand_order_by(:params.order_by, "default")`

- `col` validated against schema (uses `col` mapping), `order` whitelisted.
- `default` is a literal `"col dir[, col dir]"` used when the array is empty;
  required because paging needs a deterministic order.
- emits `ORDER BY ...`.

### 6.6 `expand_paging(:params.offset, :params.limit)`

- mssql: `OFFSET ? ROWS FETCH NEXT ? ROWS ONLY`
- postgres / sqlite / mysql: `LIMIT ? OFFSET ?`
- both values bound; `limit` capped by the param `max` at validation.
- load error if the template has no `expand_order_by` before it.

### 6.7 `expand_set(:params.obj, @Model)`

- input: partial object (`Model?`), keys validated against the model.
- emits `col = ?` for every **present** key, skipping fields marked
  `key = true` or `readonly = true`.
- zero writable keys present → `BAD_REQUEST` at runtime (nothing to update).
- emits the bare list; the template writes `SET` (so it can append
  `, vrs = vrs + 1`).

### 6.8 `expand_insert(:params.obj, @Model)`

- emits `(col, col, ...) VALUES (?, ?, ...)` for present, non-`readonly`
  fields. Keys with `required = true` in the model must be present.
- the template writes `INSERT INTO table ${expand_insert(...)}`.

### 6.9 `expand_in(:params.ids)`

- `(?, ?, ...)` for a scalar array; empty array → `BAD_REQUEST`.
- template: `WHERE id IN ${expand_in(:params.ids)}`.

### 6.10 `expand_values_table(:params.items, @Model, "v")` — optional, bulk

Emits a full derived table for the dialect, including alias and column list:

- mssql / postgres: `(VALUES (?,?,...),(?,?,...)) AS v(id, invoice_id, ...)`
- mysql 8.0.19+: `(VALUES ROW(?,...),ROW(?,...)) AS v(id, ...)`
- sqlite: `(SELECT ? AS id, ? AS invoice_id ... UNION ALL SELECT ?, ? ...) AS v`

The alias list is derived from the model, so the template cannot drift from
the schema (V1 required the author to repeat it). The surrounding
`UPDATE ... JOIN` / `UPDATE ... FROM` syntax is still dialect-specific, so a
template using this function is **tied to one driver**; load fails if the
pool driver differs from `[[exec]].driver`:

~~~toml
[[exec]]
name   = "lines"
driver = "mssql"
expect = "some"
sql = """
  UPDATE d
  SET d.description = v.description, d.price = v.price, d.quantity = v.quantity, d.total = v.total
  FROM details AS d
  JOIN ${expand_values_table(:params.items, @InvoiceItem, "v")} ON v.id = d.id
  WHERE d.invoice_id = :params.invoice.id
"""
~~~

Prefer `foreach` (§5.3) unless row counts make the round trips matter.

### Removed from V1
- `expand_set_values` → `expand_set` (no hard-coded `uid` skip; uses `key`).
- `expand_limits(limit, start)` → `expand_paging(offset, limit)` (arg order
  matched to the SQL it emits and to the param names).
- `expand_value_rows` → `expand_values_table` (whole derived table, per
  dialect) or `foreach`.
- Implicit WHERE joining → `expand_where`.

## 7. Transactions and `[[exec]]`

- All `[[exec]]` steps and the trailing `[query]` of an action run in **one
  transaction**, in file order. First failure → rollback everything, return
  the mapped error. No savepoints in v1 (all-or-nothing is the contract).
- `[[exec]]` fields:

| field     | meaning                                                             |
|-----------|---------------------------------------------------------------------|
| `name`    | required; used in logs and in the `data.step` of error responses    |
| `sql`     | required                                                            |
| `expect`  | `one` (exactly 1 row affected) / `some` (≥1) / `any` (default)       |
| `foreach` | value ref to an array param; binds `:item`; `expect` applies per item|
| `when`    | value ref; step skipped when the value is absent/null/empty          |
| `driver`  | pins the step to a dialect (needed with non-portable SQL)            |

- `expect` violation → `NOT_FOUND` if the method declares it, else
  `CONFLICT` if declared, else generic `-32000` (see §8). A step can override:
  `on_zero = "CONFLICT"`.
- Fixed step order per method (header → lines → summary) is the
  deadlock-avoidance rule; document it in the method `description`.
- Isolation level: driver default. A method may set `isolation =
  "serializable"` at top level (future).

## 8. JSON-RPC mapping

Request:
~~~json
{ "jsonrpc": "2.0", "id": 7, "method": "patch_client",
  "params": { "uid": "0190...", "vrs": 3, "client": { "notes": "VIP" } } }
~~~

Response:
~~~json
{ "jsonrpc": "2.0", "id": 7,
  "result": { "client": { "id": 12, "uid": "0190...", "vrs": 4, "full_name": "...", "address": null, "notes": "VIP" } } }
~~~

Error:
~~~json
{ "jsonrpc": "2.0", "id": 7,
  "error": { "code": -32001, "message": "Client does not exist",
             "data": { "error": "NOT_FOUND", "method": "patch_client", "step": "update" } } }
~~~

Codes:

| code   | when                                                | `data.error` |
|--------|-----------------------------------------------------|--------------|
| -32601 | method not enabled                                  | —            |
| -32602 | param validation failed (type, required, enum, max, unknown key) | `BAD_REQUEST` + `data.field` |
| -32001 | `expect` violated, mapped to `NOT_FOUND`            | `NOT_FOUND`  |
| -32002 | `expect` violated, mapped to `CONFLICT`             | `CONFLICT`   |
| -32000 | SQL error, timeout, unmapped failure                | `INTERNAL`   |

`[errors]` in a method file declares which of `NOT_FOUND` / `CONFLICT` /
`BAD_REQUEST` the method can return and their messages. Declaring one the
engine can never raise is a load warning. SQL error text is **never** sent to
the client; it is logged with the request id.

Result shaping:
- query: `[results]` is filled from `[query]` rows (field `rows`) and
  `[query.count]`. `one = true` → single object or `NOT_FOUND`.
- action: `success` is implied by a non-error response; no `success` field.
- Field names in rows are the model **field** names (not `col`).

## 9. Security

- Methods are a closed whitelist; unknown method → -32601.
- Params validated **before** any SQL is built: unknown keys rejected
  (no silent drop), `max` enforced, arrays capped (`max` on array params =
  max length, default 1000).
- Only bound parameters reach the engine; inlined tokens come from a
  whitelist, never from input.
- Per-connection `statement_timeout_ms`; per-method optional `timeout_ms`.
- Connector authentication (token on the outbound dial) is out of scope of
  this file; see connector spec.

## 10. Load-time validation (startup fails on any error)

1. TOML parses (TOML 1.0; no multi-line inline tables, no trailing commas).
2. Every `[[method]]` has a file; every file's `method` matches its name.
3. Every `type` resolves (scalar, built-in, or a loaded model); `enum` and
   `default` are consistent with `type`.
4. Every `:params.x` path exists in `[params]`; `:item` only inside a
   `foreach` step; `@Model` is loaded.
5. Column literals in `expand_search`, `expand_order_by` defaults, and
   `expand_where` literal predicates reference existing model fields.
6. `expand_paging` has a preceding `expand_order_by`.
7. `[[exec]].driver`, when set, equals the pool `driver`.
8. `rows` targets exist in `[results]` and their type matches (`Model[]` vs
   `one = true` → `Model`).
9. Optional: prepare every statement against the live connection with an
   empty/dummy binding set and report SQL syntax errors at startup.

## 11. Open questions

- Should `Model?[]` (array of partials) be allowed, or should `foreach` steps
  always require full `Model[]` rows?
- `vrs` bump: always `vrs = vrs + 1` in the template (explicit, as above) vs
  a model flag `version = true` that `expand_set` appends automatically.
- Inserts via `foreach` with `expect = "one"` — enough for "post_invoice", or
  do we need `expand_values_table` + `INSERT ... SELECT` from day one?
- `[query.count]` duplicates the WHERE template; worth a `${where}` named
  fragment reuse (`[fragments] where = "..."`) if it becomes common.
- Isolation level and lock hints per method.

## 12. Changes vs DRAFT.md (V1)

| area           | V1                                             | V2                                                   |
|----------------|------------------------------------------------|------------------------------------------------------|
| registry       | `methods.enabled.toml`, `describe` duplicated  | `scapi.toml`; `driver` mandatory; metadata only in method file |
| schemas        | duplicated inline per method                   | `models/*.model.toml`, `Model`, `Model[]`, `Model?` refs |
| field keys     | `type`, `required`, `describe`                 | + `enum`, `col`, `key`, `readonly`, `max`, `description` |
| operator type  | `type = "EQ \| NEQ ..."` string                | `enum = [...]`, `values` as typed array              |
| WHERE          | implicit AND-join of fragments                 | explicit `expand_where(...)`                         |
| paging         | `expand_limits(limit, start)`                  | `expand_paging(offset, limit)`, dialect by `driver`  |
| set clause     | `expand_set_values`, hard-coded `uid` skip     | `expand_set`, skips `key`/`readonly`                 |
| bulk update    | `expand_value_rows` + hand-written alias list  | `foreach` steps (default) or `expand_values_table`   |
| exec           | `[exec]` and `[[exec]]`                        | always `[[exec]]` + `name`, `expect`, `foreach`, `when` |
| results        | `success` boolean; unclear origin of `client`  | trailing `[query]` inside the tx; `rows`, `one`      |
| errors         | free `[errors]` list                           | fixed set mapped to JSON-RPC codes + `data.step`     |
| count          | undefined                                      | `[query.count]`                                      |
| `:results.x`   | schema ref using value syntax                  | `@Model` schema ref syntax                           |
| `vrs`          | declared, unused                               | `WHERE ... AND vrs = ?` + `vrs = vrs + 1`, `CONFLICT`|
