# query-example.toml — aspects worth improving

Status: notes, 2026-10-17. Refers to `query-example.toml` (bag-object version,
see §0). Assumes a two-phase runtime:

1. **compile pass at startup** — parse TOML, resolve references, run every
   static check, and produce an *almost-executable* **run file** per method
   (resolved types, column maps, prebuilt SQL skeletons, bind plan);
2. **run steps per request** — validate params against the compiled schema,
   fill the skeleton with bound values, execute, map rowsets to the result.

Each aspect says which phase owns it. Rule of thumb: **anything that does not
depend on request values belongs to the compile pass**, and the run file
should contain the *result* of that work, not the work.

---

## 0. The bag-object model (adopted)

Every step puts a **typed object** in the bag under the step name; the shape
depends on the step kind, and later steps read **fields** of it with plain
paths:

| kind | bag object |
|---|---|
| `select` | `{rows: any[], sql: {where: string}, length: int}` |
| `count`  | `{count: int, sql: {where: string}}` |

```toml
[[step]]
count = "_total"
from  = "invoices"
where = "_invoices.sql.where"          # reuse the select's WHERE (predicate + binds)

[[step]]
emit = "result"
returns = {
  invoices = {source = "_invoices.rows"},
  total    = {source = "_total.count"},
  count    = {source = "_invoices.length"}
}
```

Why it matters: one rule ("a step is a struct, read its fields") replaces
three special cases (WHERE reuse, rowset→array coercion, a `.length`
pseudo-field). New fields (`sql.order_by`, `max_id`, …) come for free. The
compile pass knows every bag shape, so **every `source` path is
type-checkable at startup** (`_total.rows` → error; `_invoices.sql.where` →
string).

Two rules to pin:
- Bag shapes are **fixed per kind** in the spec; a step cannot add fields.
- `sql.where` is a **compiled predicate plan, not text**: reusing it reuses
  the bound values too. `count` runs with the same binds as `select`.

---

## A. Readability

| # | aspect | now | consider |
|---|---|---|---|
| A1 | ~~`filters`/`search` repeated in `select` and `count`~~ | **done** | `where = "_invoices.sql.where"` (§0). |
| A2 | ~~`type = "InvoicesResult"` repeated in emit~~ | **done** | Emit reads `_invoices.rows`; the type comes from `[result]`. Compile pass checks the bag field kind matches the result field type. |
| A3 | `allow = [...]` lists repeated per binding | fine for 3 items, noisy at 15 | Allow `allow = "*"` (default) and an explicit list only to narrow — already the rule, make it visible in the doc of the step. |
| A4 | Operator enum inline in `FiltersParam` | long line | Built-in shape `Condition[]` (DRAFT-V3 §5.3) so method files write `filters = {type = "Condition[]"}`. Same for `OrderBy[]`. |
| A5 | `source` has three meanings (column / param path / rowset) | consistent by design | Keep; document the three in one table at the top of the spec. Compile pass resolves each by the key it sits under, never by string shape. |
| A6 | `##` section banners vs `#` comments | cosmetic | Keep `##` for banners, `#` for inline comments — already so. |
| A7 | Step kind = first key (`select`, `count`, `emit`) | implicit | Fine, but compile pass must **reject a step with two kind keys** and report "step N: kind". |

## B. Stricter definition (compile pass)

| # | aspect | consider |
|---|---|---|
| B1 | `[type.X]` is a map (not `[[type]]`) | ✓ keep — `type = "X"` is an index lookup. Reject a type named like a scalar (`"string"`, `"integer"`…). |
| B2 | Types = data shapes only | ✓ keep. Reject binding keys (`source`, `allow`, `over`, `default` at type level) inside `[type.X]` except `source` on a field (column rename). |
| B3 | `max` on arrays / strings / numbers | present for `FiltersParam`, `OrderByParam`, `q`, `limit`. Add a **spec default** (arrays 1000, strings none) so omission is a choice, not a hole. |
| B4 | `value = {type = "json"}` in filters | cardinality per operator (0 for `IS_*`, 1 scalar, N for `IN`, 2 for `BETWEEN`) is **run-time** (depends on request). Compile pass only fixes the table; document the table in the spec. |
| B5 | `required` on result fields | DRAFT-V3: results are always present (may be `null`). Decide: forbid `required` in result types, or treat as "never null". |
| B6 | `source` inside a result type is a DB detail | strip it from JSON-RPC discovery output; keep it in the run file as the column map. |
| B7 | Unknown keys anywhere | reject (closed structs) in types, params, result, steps, bindings. Name the offending path. |
| B8 | `version` | semantics still open (DRAFT-V3 §13). At least: integer ≥ 1. |
| B9 | `[errors]` | compile pass checks the method can only raise declared codes: a `select` with `returns = {type = object, required = true}` needs `NOT_FOUND`; paging/filters need `BAD_REQUEST`. |

## C. Cleaner and stricter execution steps

### C1. What the compile pass must check for `select` / `count`

- `from` table exists (DB introspection).
- `returns.type` resolves to an **array or object type** with `fields`.
- Every result field maps to a column: `source` if given, else the field
  name; the column exists in `from` and its DB type is compatible with the
  field `type` (introspection, DRAFT-V3 §11 table).
- `filters.source` / `order_by.source` → an **array** param whose shape is
  (or is compatible with) `Condition[]` / `OrderBy[]`.
- `search.source` → a **string** param. `search.over` ⊆ result fields and
  every one is **text-like** in the DB.
- `allow` ⊆ result fields. Default = all result fields.
- `order_by.default` columns ∈ `allow`; `dir` ∈ {asc, desc}.
- `limit.source` / `offset.source` → **integer** params. **Both or neither**,
  and `order_by` (or its default) must exist when they do — paging requires a
  deterministic ORDER BY (MSSQL `OFFSET … FETCH`).
- `count` step: no `returns`, `order_by`, `limit`, `offset` allowed.
- `where = "<step>.sql.where"`: the referenced step exists, is **earlier**,
  and is a `select`/`count` (has `sql.where`).
- `emit`: every `[result]` field assigned exactly once; every `source` is a
  path into a known bag object (`_x.rows`, `_x.length`, `_x.count`, …) and its
  kind matches the result field type (array ← `rows`, integer ← `length` /
  `count`). Unknown bag field → compile error.
- Exactly one `emit`, last. Rowset names unique and start with `_`
  (convention; make it a rule or drop the convention).

### C2. What the run file should contain (per step)

Compile once, so the run step does no lookups:

```text
step[0] select "_invoices"            -> bag {rows, sql.where, length}
  sql.skeleton : SELECT id, uid, vrs, client_name AS client, address, notes, total
                 FROM invoices
                 {WHERE}            <- slot  (also published as bag.sql.where)
                 {ORDER_BY}         <- slot, default "ORDER BY id ASC"
                 {PAGING}           <- slot, dialect text fixed: "OFFSET ? ROWS FETCH NEXT ? ROWS ONLY"
  filters      : param=filters  allow={id:id, client:client_name, total:total}  op-table
  search       : param=q        over={client:client_name, address:address, notes:notes}
  order_by     : param=order_by allow={...} default=[(id, asc)]
  paging       : limit=params.limit(max 5000) offset=params.offset
  bind.types   : from DB introspection, per column
step[1] count "_total"                -> bag {count, sql.where}
  sql.skeleton : SELECT COUNT(*) FROM invoices {WHERE}
  where        : ref step[0].sql.where   (plan + binds, resolved at compile time)
step[2] emit
  invoices <- step[0].rows (array)   total <- step[1].count (int)   count <- step[0].length (int)
```

Everything above is request-independent. The run step only: validates the
request against the compiled param schema → fills `{WHERE}` / `{ORDER_BY}` /
`{PAGING}` from allowlisted inputs → binds values → executes → maps.

### C3. Run-step rules to pin in the spec (request-dependent)

- Unknown param keys → `BAD_REQUEST` (no silent drop).
- `filters`: AND-join; `col OP ?`; `IN (?, …)` one placeholder per value;
  `LIKE` binds as given; `IS_*` take no value; cardinality per B4.
- `search`: split `q` on whitespace; `%word%` with `%`/`_` escaped; per word
  `(c1 LIKE ? OR c2 LIKE ?)`; words AND-joined; empty `q` → no predicate.
- `order_by`: columns ∈ `allow`, `dir` whitelisted and inlined; empty →
  default.
- `limit` capped at `max`; `offset ≥ 0`.
- `count` with `where = "_x.sql.where"` reuses the exact predicate **and
  binds** of step `_x` (one source of truth at run time too).
- Nothing from the request is ever inlined; only allowlisted identifiers
  from the run file are.

### C4. Things still to confirm

- `count = "_total"` as a step kind (vs `select` + scalar return).
- Exact bag shapes per kind (§0) — e.g. should `select` also expose
  `sql.order_by`? should `exec` expose `affected`?
- Whether a bag path may cross into `params` (`params.uid`) with the same
  syntax, or stays `_step.field` only.

---

## D. Small concrete edits to the current file (if adopting the above)

1. ~~`count` step: reuse the select's WHERE~~ — done (`where = "_invoices.sql.where"`).
2. ~~Emit: drop `type = "InvoicesResult"`~~ — done (emit reads bag paths).
3. Replace `FiltersParam` / `OrderByParam` with built-ins `Condition[]` / `OrderBy[]` once the spec defines them.
4. Add `NOT_FOUND` only if a future `select` returns a required object.

---

**► Your comments**

> 
