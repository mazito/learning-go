# CUE-FUNCTIONS — interpolation functions in CUE

Status: research, 2026-10-17. Every snippet below was run with `cue v0.17.1`;
sources live in `docs/cue-lab/` (see its README for how to run / break them).

Blocks marked **► Your comments** are for you. Nothing here touches the
example `.cue` files yet.

---

## 0. The question

DRAFT-V3 §7 defines ten `expand_*` functions that the Go runner executes
inside SQL strings (`${expand_set(:params.client, "clients")}`), plus two
token kinds (`:params.x` value refs, `@results.x` shape refs). §11 lists
~9 startup checks the runner must implement to keep those strings safe.

If the method files move to CUE: **what can CUE do for these functions —
define them, replace them, check them — and how would a method author use
them?**

---

## 1. Facts about CUE that decide everything

Verified, not assumed.

| # | fact | consequence |
|---|---|---|
| F1 | **No user functions, no lambdas.** | The only "function" is a definition with input fields and an `out` field; the call is `(#Fn & {in: x}).out`. |
| F2 | **Evaluation happens at load time**, never per request. | Anything that depends on request data (`which keys did the client send`) cannot be computed in CUE. Only the *shape* is known. |
| F3 | Has `strings`, `list`, `regexp`, `strconv`; string interpolation `\( )`; list/struct comprehensions; `or([...])` to turn a list into a disjunction. | Enough to build SELECT lists, allowlists, dialect switches, and even lint strings. |
| F4 | Definitions (`#X`) are **closed**; `#A \| #B` is **ambiguous** unless each has a required constant that conflicts. | Every fragment/function struct needs a fixed discriminator (`fn: "set"`). |
| F5 | **Errors inside hidden fields (`_x`) do not fail `cue vet`.** | Put every *check* in a regular field. Hidden fields are fine for *inputs*. |
| F6 | A label alias gives a field its own name: `[K=string]: #Field & {source: *K \| string}`. | "`source` defaults to the field name" costs one line. |
| F7 | `\( )` is CUE's interpolation; `${ }` is just text to CUE. | Both can live in one SQL string; CUE folds `\( )` at load, the runner handles `${ }` at request time. |
| F8 | Hidden fields (`_x`) are **package-private**; definition fields (`#x`) are settable across packages and are not exported. | Pass inputs to a shared definition via `#x` (e.g. `#params`), never `_x`. |
| F9 | In `*a \| S` the default `a` is accepted even if `a ∉ S`. | To default *inside* a set write `(*a \| string) & S`. |

---

## 2. Static vs dynamic — the real split

What each §7 function needs, and therefore who can evaluate it:

| function | needs request data? | CUE can… | runner must… |
|---|---|---|---|
| `expand_columns("t", @results.x [, alias])` | no | **fold completely** (SELECT list from the shape, with `source` renames) | nothing |
| `expand_paging(:offset, :limit)` | values only | fold the **text** per dialect; type-check both refs | bind 2 values |
| `expand_where(frag, …)` | depends on parts | type-check the parts, allow literals | join non-empty with `AND`, prefix `WHERE` |
| `expand_conditions(:filters, [cols])` | yes | **fix the allowlist** `field → column`, enforce cols ⊆ shape | build `col OP ?` from the request |
| `expand_search(:q, [cols])` | yes | same + enforce **text-like columns only** | split words, build `LIKE` |
| `expand_order_by(:order_by, [cols], "default")` | yes | allowlist + default literal | pick & inline whitelisted cols |
| `expand_set(:obj, "t")` | yes (present keys) | fix `field → column` for the **object param's shape**; reject scalar refs | emit `col = ?` for present keys; skip PK/identity (DB) |
| `expand_insert(:obj, "t")` | yes | same | same + NOT NULL check (DB) |
| `expand_in(:ids)` | yes | reject non-array refs | `(?, ?, …)` |
| `expand_values_table(:items, [cols], "v")` | yes | allowlist + `driver` pin check | dialect-specific derived table |

Takeaway: **one** function is fully static, **one** is static text, the other
eight are runtime — but for all of them CUE can own the part §11 calls
"startup checks": path existence, scalar-vs-object, allowlist ⊆ shape,
text-like columns, dialect pins. What stays in Go is request-dependent SQL
assembly and anything needing DB introspection (column exists, PK/identity,
NOT NULL).

---

Proposals: **A** lint strings · **B** hybrid · **C** fragments · **D** declarative (§5b, from your sketch).

---

## 3. Proposal A — keep `${fn(...)}` strings, let CUE lint them

Zero change to the template syntax. CUE extracts tokens with `regexp` and
unifies them against the registry and the `params` tree.

```cue
// docs/cue-lab/02-lint-strings/lint.cue (trimmed)
import "regexp"

#FnName: "expand_columns" | "expand_where" | "expand_conditions" | "expand_search" |
	"expand_order_by" | "expand_paging" | "expand_set" | "expand_insert" | "expand_in"

sql: """
	UPDATE invoice
	SET ${expand_set(:params.invoice, "invoice")}, vrs = vrs + 1
	WHERE uid = :params.uid AND vrs = :params.vrs
	"""

// ${fn(   -> every name must be a known function
_fnCalls: regexp.FindAllSubmatch(#"\$\{([a-z_]+)\("#, sql, -1)
fnCheck: [for m in _fnCalls {m[1] & #FnName}]

// :params.a[.b]  -> every path must exist in `params`
_refs: regexp.FindAllSubmatch(#":params\.([a-zA-Z_]\w*)(?:\.([a-zA-Z_]\w*))?"#, sql, -1)
refCheck: [for m in _refs {
	let s1 = m[1]
	let s2 = m[2]
	seg1: s1 & or([for k, _ in params {k}])
	if s2 != "" {seg2: s2 & or([for k, _ in params[s1].fields {k}])}
}]
```

Verified: `${expand_bogus(...)}` → `conflicting values "expand_set" and
"expand_bogus"`; `:params.nope` → `conflicting values "invoice" and "nope"`;
clean template → `cue vet` OK.

**What it buys**

- §11 checks 5 (refs exist) and part of 4, for free, no Go.
- Method files look exactly like the TOML ones.

**What it cannot do**

- Parse **arguments**: `expand_set(:params.uid, …)` passing a scalar, or a
  column allowlist with a typo, is invisible to a regex.
- **Nesting** (`expand_where(expand_conditions(…), expand_search(…))`) — a
  regex finds the names but not the structure.
- Anything semantic (text-like columns, scalar-vs-object).
- Regexes in CUE are RE2 (no lookbehind). Fine here, but it is a mini-parser
  written in a language that is not meant to parse.

**Verdict**: a cheap safety net on top of today's design, not a design.

**► Your comments**

> 

---

## 4. Proposal B — hybrid: CUE `\( )` for the static part, runner `${ }` for the rest

Fold what is static at load time with real CUE expressions; leave the
request-dependent functions as runner tokens.

```cue
// docs/cue-lab/04-allowlist-reuse-hybrid/misc.cue (trimmed)
#Field: {type: "uuid" | "integer" | "double" | "string" | "text", source?: string}
#Shape: [K=string]: #Field & {source: *K | string}        // F6: default source = name
#Clients: #Shape & {id: {type: "integer"}, full_name: {type: "string", source: "FullName"}, ...}

#Columns: {of: #Shape, out: strings.Join([for k, f in of {"\(f.source) AS \(k)"}], ", ")}

hybrid: """
	SELECT \((#Columns & {of: #Clients}).out)
	FROM clients
	${expand_where(expand_conditions(:params.filters, ["id","full_name"]))}
	"""
```

Exports to:

```sql
SELECT id AS id, FullName AS full_name, address AS address, notes AS notes
FROM clients
${expand_where(expand_conditions(:params.filters, ["id","full_name"]))}
```

**What it buys**

- `expand_columns` disappears as a runtime function: the SELECT list is a
  pure consequence of the result shape + `source`. `[step.columns]` renames
  (§6.2) are no longer needed — `source` already is that mapping.
- Dialect-static text (`expand_paging`) can be folded the same way with a
  `driver` switch (see 5.3).
- Can be combined with Proposal A for the remaining `${ }` tokens.

**What it costs**

- Two interpolation syntaxes in one string (`\(` CUE, `${` runner). Readers
  must know which runs when.
- Still strings: the dynamic functions remain unparsed, so A's limits apply
  to them.

**Verdict**: good stepping stone; removes the only fully-static function and
the `[step.columns]` duplication (§13 open question) without touching the
runner's token syntax.

**► Your comments**

> 

---

## 5. Proposal C — structured SQL: fragment list, typed function structs

Stop writing SQL as one string. A template is a **list of fragments**: literal
strings and closed function structs. CUE validates every argument against the
schema at load; `cue export` hands Go a small JSON AST — **no `${ }` parsing
in Go at all**.

### 5.1 Fragments

```cue
// docs/cue-lab/03-fragments/fragments.cue (trimmed)
#Fragment: string | #ScalarRef | #Columns | #Set | #Paging

// ":params.uid" -> one bound placeholder. The path is resolved NOW.
#Ref: {
	fn:   "ref"                                 // F4: discriminator
	path: string
	let segs = strings.Split(path, ".")
	type: [                                     // F5: regular field => a bad path FAILS vet
		if segs[0] == "params" && len(segs) == 2 {params[segs[1]].type},
		if segs[0] == "params" && len(segs) == 3 {params[segs[1]].fields[segs[2]].type},
	][0]                                        // wrong root -> empty list -> index error
	static: false
}
#ScalarRef: #Ref & {type: !="object" & !="array"}   // §7: bare ref must be scalar
#ObjectRef: #Ref & {type: "object"}
#ArrayRef:  #Ref & {type: "array"}

// expand_columns: fully static
#Columns: {
	fn: "columns", of: #Shape, alias: string | *""
	static: true
	let pre = [if alias != "" {alias + "."}, ""][0]
	out: strings.Join([for k, f in of {"\(pre)\(f.source) AS \(k)"}], ", ")
}

// expand_set: runtime, but the allowed field->column map is fixed here
#Set: {
	fn: "set", ref: #ObjectRef, table: string
	columns: {for k, f in params[strings.Split(ref.path, ".")[1]].fields {(k): f.source}}
	static: false
}

// expand_paging: static text per dialect, values bound at runtime
#Paging: {
	fn: "paging", offset: #Ref, limit: #Ref
	static: true
	out: {mssql: "OFFSET ? ROWS FETCH NEXT ? ROWS ONLY", postgres: "LIMIT ? OFFSET ?",
	      mysql: "LIMIT ? OFFSET ?", sqlite: "LIMIT ? OFFSET ?"}[driver]
}
```

### 5.2 A template

```cue
sql: [...#Fragment]
sql: [
	"SELECT ", #Columns & {of: #InvoiceResult, alias: "i"},
	" FROM invoice i WHERE uid = ", #ScalarRef & {path: "params.uid"},
	" ORDER BY id ", #Paging & {offset: {path: "params.offset"}, limit: {path: "params.limit"}},
]

update: ["UPDATE invoice SET ", #Set & {ref: {path: "params.invoice"}, table: "invoice"},
         ", vrs = vrs + 1 WHERE uid = ", #ScalarRef & {path: "params.uid"}]
```

### 5.3 What CUE catches — all verified

| mistake | result |
|---|---|
| `#Ref & {path: "params.nope"}` | `undefined field: nope` |
| `#Ref & {path: "params.invoice.nope"}` | `undefined field: nope` |
| wrong root `#Ref & {path: "results.uid"}` | `index out of range [0] with length 0` |
| object param used bare: `#ScalarRef & {path: "params.invoice"}` | `invalid value "object" (out of bound !="object")` |
| scalar passed to `expand_set`: `#Set & {ref: {path: "params.uid"}}` | `conflicting values "uuid" and "object"` |
| allowlist typo: `#Conditions & {cols: ["id", "nope"]}` | `conflicting values "address" and "nope"` |
| search on non-text column: `#Search & {cols: ["id"]}` | rejected (allowlist built from `type == "string" \| "text"`) |
| `driver: "postgres"` | preview switches to `LIMIT ? OFFSET ?` automatically |

That is §11 checks 3–5 and 7 (minus DB introspection) done by `cue vet`.

### 5.4 What Go receives

```json
// cue export -e 'update[1]'
{
  "fn": "set",
  "ref": {"fn": "ref", "path": "params.invoice", "type": "object", "static": false},
  "table": "invoice",
  "columns": {"id": "id", "notes": "notes"},
  "static": false
}
```

Go decodes `sql` as `[]json.RawMessage`, peeks `fn`, and dispatches. The
runner never infers a column name: `columns` *is* the allowlist. Static
fragments arrive pre-rendered (`out`), so Go concatenates.

Sketch (not run):

```go
type Fragment struct{ Fn string `json:"fn"`; Static bool `json:"static"`; Out string `json:"out"` }
type SetFn struct{ Fragment; Ref Ref `json:"ref"`; Table string; Columns map[string]string }
// switch frag.Fn { case "ref": ... case "set": ... }
```

### 5.5 Nesting and reuse fall out naturally

```cue
// docs/cue-lab/06-nested-where/nested.cue
#Where: {fn: "where", parts: [...(#Conditions | #Search | string)], static: false}

w: #Where & {parts: [
	#Conditions & {ref: "params.filters", _of: #Clients, cols: ["id", "full_name"]},
	#Search     & {ref: "params.q",       _of: #Clients, cols: ["full_name", "notes"]},
	"deleted = 0",
]}
```

```cue
// docs/cue-lab/04-allowlist-reuse-hybrid/misc.cue — §13 "share WHERE between list and count"
_where:   [" WHERE ", #Conditions & {...}]
listSQL:  list.Concat([["SELECT ... FROM clients"], _where, [" ORDER BY id"]])
countSQL: list.Concat([["SELECT COUNT(*) AS n FROM clients"], _where])
```

### 5.6 CUE-side preview (optional, for authors)

Disjunction-as-dispatch renders what the runner will see; dynamic parts show
as `<fn>`:

```cue
#Render: {in: string, out: in} |
	{in: {static: true, out: string, ...}, out: in.out} |
	{in: {static: false, fn: string, ...}, out: "<\(in.fn)>"}
preview: strings.Join([for f in sql {(#Render & {in: f}).out}], "")
// "SELECT i.id AS id, i.uid AS uid, i.client_name AS client FROM invoice i
//  WHERE uid = <ref> ORDER BY id OFFSET ? ROWS FETCH NEXT ? ROWS ONLY"
```

### 5.7 Costs

- **Readability**: SQL is chopped into list items. Mitigation: keep literal
  chunks long, one fragment per line, and use `preview` while authoring.
- **Learning curve**: authors write `#ScalarRef & {path: "params.uid"}`
  instead of `:params.uid`. A short alias layer helps (e.g. `#P: #ScalarRef`
  → `#P & {path: "params.uid"}`), but it is still a struct.
- **Runner rewrite**: the Go side becomes an interpreter over a JSON AST
  instead of a string tokenizer. Simpler code, but a rewrite.
- **Bounded path depth**: `#Ref` handles 2–3 segments; CUE cannot recurse
  over an arbitrary path. Our params are at most `params.obj.field`, fine.
- Hidden inputs (`_of`) keep the export slim (5 in cue-lab), but remember F5:
  checks must stay in regular fields.

**Verdict**: this is the design where CUE earns its place: the method file
is validated end-to-end at load, the runner shrinks, and the `${}`
mini-language disappears.

**► Your comments**

> The idea is good, the issue is readibility andhard to build structs.
> 1) I take the idea of building sql in parts but need to simplify building
> Example, is this possible ?


> Rough idea of how to simplifify it
~~~
////////////////////////////////////////////////////////////////////////////////
//
// Type definitions shared by many methods
//
////////////////////////////////////////////////////////////////////////////////

#ColumnsParam: #IsArray & {
  required: {type: "boolean", default: false}
  source:  {type: "string"}
  fields: {
    name:   #Field & {type: "string", required: true}
    alias:  #Field & {type: "string", reuired: false}
  }
}    

#FiltersParam: #IsArray & {
  required: {type: "boolean", default: false}
  source:  {type: "string"}
  fields: {
    column:       #Field & {type: "string", required: true}
    conditions:   #IsArray & {
      required: true
      fields: {
        operator: #Field & {type: "string"} // BUT should be an enum of opcodes
        value:    #Field & {type: "any"}
      }  
    }
  }
}    

#SearchParam: #IsObject & {
  source:  {type: "string"}
  over:  {type: "string"}
}

////////////////////////////////////////////////////////////////////////////////
//
// These are SPECIFIC to the JSONRPC method we want to describe
//
////////////////////////////////////////////////////////////////////////////////

// [params] — flat scalars + composite object/array params.
params: {
	columns: #ColumnParams & {required: false} 
	filters: #FiltersParam  & {required: false} 
  limit: #Field {type: "integer", default: 1000}
  offset: #Field {type: "integer", default: 0}
}

// Result row schemas (named once, reused by query `returns` and [results]).
// `source` only where the column name differs from the field name (`client`).
#InvoiceResult: {
	id:          #Field & {type: "integer"}
	uid:         #Field & {type: "uuid"}
	vrs:         #Field & {type: "integer"}
	client:      #Field & {type: "string", source: "client_name"}
	address:     #Field & {type: "string"}
	notes:       #Field & {type: "text"}
}

// [results] — the JSON-RPC output contract.
results: {
	invoices: #IsArray & {fields: #InvoiceResult, source: "_invoices"}
}

// [errors]
errors: [string]: string
errors: {
	NOT_FOUND: "Invoices not exist"
}

/// QUERIES 
step: [...#Step]
step: [
	#QueryStep & {
		query:   "_invoices"
    from: "invoices" 
    columns: #ColumnsParam & {source: "params.columns" }
    filters: #FiltersParam & {source: "params.filters"}
    search: #SearchParam & {source: "params.q", over: "client,notes,address"}
    order_by: #OrderByParam & {source: "params.order_by"}
    limit: #Field & {type: integer, source: "params.limit"}
    offset: #Field & {type: integer, source: "params.offset"}
		returns: #IsArray & {
      required: true, 
      fields: #InvoiceResult
    }
	},
]
~~~





**Answer (2026-10-17):** yes, with fixes — and it is a different design, not a
simplification of C. Written up as **Proposal D** below; your sketch above is
the origin.

---

## 5b. Proposal D — declarative SELECT step (from your sketch)

In C the author *assembles SQL* from typed fragments. In D the author
**declares the query**: a table plus which standard params feed it. **No SQL
text for the list/search case.** CUE validates the declaration; the Go runner
generates the SELECT (a query builder, not a template runner).

Full working file: `query-example.cue` (vets in ~30 ms, 10/10 negative tests
caught). Reusable types live in **`shared/shared.cue`** (`import
"scapi.local/shared"`, module root `cue.mod/`). Perf note:
`docs/cue-lab/07-declarative/perf_note.md`.

Revised after your review of the first version (your three points, all
adopted): no `shape` field; bindings use **`source`** (not `param`) and
default to the same-named param; allowlists **default to all result fields**
instead of being mandatory.

### 5b.1 What changed vs the sketch

| sketch | problem | fix used |
|---|---|---|
| `required: {type: "boolean", default: false}` on `#IsArray` | `required` is `bool`, not a `#Field` | `required: bool \| *false` |
| `source: {type: "string"}` on step bindings | `source` is a plain string, not a `#Field` | `source: "params.x"` — must be one of the **existing param paths of the right kind** (`or([for k, f in #params if f.type == "array" {"params.\(k)"}])`), defaults to the same-named param |
| `#Field & {type: "any"}` | not in the enum | `"json"` (DRAFT-V3 §5.2) |
| `operator: {type: "string"}` "should be an enum" | free string | `#Field.enum?` + `enum: [...#Operator] & [...]` → a typo in the list is a vet error |
| `over: "client,notes,address"` | CSV, unchecked | `over: {list: [...]}` bound to the **text-like** fields of the shape |
| `limit: #Field & {type: integer, source: "params.limit"}` | `integer` unquoted; a binding is not a `#Field` | `paging: {}` (defaults to `params.limit`/`params.offset`, both must be `integer` params) |
| `columns: #ColumnsParam & {source: ...}` in the step | `#ColumnsParam` is a closed `#IsArray`: it cannot carry `allow`/`map` | `#XxxParam` live in `params`; the step binding is a small `{}` with optional `source`/`allow` |
| nested `conditions: #IsArray` inside `fields` | 25 s `cue vet` (see 6.5) | flat `Condition[]` as in DRAFT-V3 §5.3 |

### 5b.2 The step (in `shared/shared.cue`)

```cue
#SelectStep: {
	#params: [string]: {type: string, ...}   // the method's [params]; bound once per method

	select:  string                          // rowset name
	from:    string                          // table (DB-checked by the runner)
	returns: #IsObject | #IsArray            // row shape (`fields`) + how rows are delivered

	_shape: returns.fields
	_keys:  [for k, _ in _shape {k}]
	_text:  [for k, f in _shape if f.type == "string" || f.type == "text" {k}]
	_arrayPath:   or([for k, f in #params if f.type == "array"   {"params.\(k)"}])
	_stringPath:  or([for k, f in #params if f.type == "string"  {"params.\(k)"}])
	_integerPath: or([for k, f in #params if f.type == "integer" {"params.\(k)"}])

	columns?:  {source: (*"params.columns"  | string) & _arrayPath,  allow: [...or(_keys)] | *_keys, map: {...}}
	filters?:  {source: (*"params.filters"  | string) & _arrayPath,  allow: [...or(_keys)] | *_keys, map: {...}}
	search?:   {source: (*"params.q"        | string) & _stringPath, over: [...or(_text)],           map: {...}}
	order_by?: {source: (*"params.order_by" | string) & _arrayPath,  allow: [...or(_keys)] | *_keys, map: {...},
	            default: [...{column: or(_keys), dir: "asc" | "desc"}]}
	paging?:   {limit: (*"params.limit" | string) & _integerPath, offset: (*"params.offset" | string) & _integerPath}
}
// map: {for f in allow {(f): *_shape[f].source | f}}   -> field -> column, for the runner

#Step: #ExecStep | #QueryStep | #SelectStep | #EmitStep
```

Three CUE tricks doing the work:

- **`source` as a disjunction of valid paths** — no regex, no extra exported
  field: a wrong name, wrong kind or wrong root simply has nothing to unify
  with.
- **default unified with the set**: `(*"params.columns" | string) &
  _arrayPath`. Written as `*"params.columns" | _arrayPath` the default would
  bypass the check (verified: that version let `columns: {}` pass with no
  `params.columns`).
- **`#params` is a definition field**: settable from another package (hidden
  `_x` fields are package-private), not exported. The method binds it once:
  `#Select: shared.#SelectStep & {#params: params}`.

### 5b.3 A method (`query-example.cue`)

```cue
import "scapi.local/shared"

#Select: shared.#SelectStep & {#params: params}   // bind once

params: {
	columns:  shared.#ColumnsParam
	filters:  shared.#FiltersParam            // [{column, operator, value}]
	q:        shared.#SearchParam
	order_by: shared.#OrderByParam            // [{column, dir}]
	limit:    shared.#LimitParam & {max: 5000}
	offset:   shared.#OffsetParam
}

results: invoices: shared.#IsArray & {fields: #InvoiceResult}

step: [
	#Select & {
		select:  "_invoices"
		from:    "invoices"
		returns: shared.#IsArray & {min: 0, max: 5000, fields: #InvoiceResult}

		columns:  {}                                       // params.columns, any field
		filters:  {allow: ["id", "client", "total"]}       // params.filters, narrowed
		search:   {over: ["client", "notes", "address"]}   // params.q
		order_by: {default: [{column: "id", dir: "asc"}]}  // params.order_by, any field
		paging:   {}                                       // params.limit / params.offset
	},
	shared.#EmitStep & {emit: "results", returns: invoices: shared.#IsArray & {source: "_invoices"}},
]
```

Why allowlists stay (with a default): DB introspection proves a column
**exists**, not that the client may **use** it. `filters`/`order_by` take
column names from the request; without a list, `WHERE password_hash LIKE
'a%'` is a probe on a column the method never returns. Default = every field
of `returns`; write `allow` only to narrow.

### 5b.4 What `cue vet` catches — all verified (10/10)

| mistake | error |
|---|---|
| allowlist typo `"cliente"` | `conflicting values "address" and "cliente"` |
| search over `id` (not text-like) | rejected |
| `source: "params.colz"` (unknown) | `conflicting values "params.columns" and "params.colz"` |
| `source: "params.q"` for `columns` (scalar, not array) | rejected |
| wrong root `results.columns` | rejected |
| `order_by.default` on unknown column / `dir: "up"` | rejected |
| `paging: {limit: "params.q"}` (string, not integer) | rejected |
| `columns: {}` but no `params.columns` | `incomplete value "params.filters" \| "params.order_by"` |
| `sql:` given to a `#SelectStep` | `field not allowed` |
| `shared.#SelectStep` used without the `#params` binding | `conflicting values 0 and {type...}` |

### 5b.5 What Go receives

```json
// cue export -e 'step[0].filters'
{"source": "params.filters",
 "allow":  ["id", "client", "total"],
 "map":    {"id": "id", "client": "client_name", "total": "total"}}
// cue export -e 'step[0].paging'
{"limit": "params.limit", "offset": "params.offset"}
```

Every binding = `source` (which param) + `allow`/`over` (which fields) + `map`
(field → column). The runner never infers a column name; it builds
`SELECT … FROM from WHERE … ORDER BY … <paging>` from these maps plus the
request values. Table/column existence, PK/identity remain DB-side checks.

### 5b.6 Where it lands

| | A lint | C fragments | **D declarative** |
|---|---|---|---|
| author writes SQL | yes | in pieces | **no** (SELECTs) |
| CUE validates | names/paths | every argument | param shapes + allowlists + enums |
| Go does | tokenize + expand | interpret AST | **generate SQL** (query builder) |
| covers | everything | everything | list/search/order/page; writes, joins, aggregates still need SQL |
| readability | ✓ | ✗ | **✓✓** |

D is the best UX for the 80% case (`get_*` lists). Writes (`expand_set`),
multi-table and anything with a JOIN still need SQL → raw `#QueryStep`
and/or C fragments. `#Step` being a disjunction makes them coexist.

**► Your comments**

> 

---

## 6. Cross-cutting choices (apply to B and C)

### 6.1 Where does `source` default?

| option | code | export | note |
|---|---|---|---|
| at schema (recommended) | `[K=string]: #Field & {source: *K \| string}` | every field shows `source` | runner never guesses; one rule |
| at use | `source?: string` + `[if f.source != _|_ {f.source}, k][0]` in each function | `source` only when set | slimmer export, logic repeated per function |

Both verified (`01-fn-struct`, `04-…` item 4).

### 6.2 Allowlists bound to the shape

```cue
cols: [...or([for k, _ in _of {k}])]                          // any field
cols: [...or([for k, f in _of if f.type == "text" || f.type == "string" {k}])]  // text-like
columns: {for c in cols {(c): _of[c].source}}                  // field -> column for Go
```

Replaces the free-text `["id","full_name"]` arrays of §7.3–7.5 with arrays
that **cannot** name a field that does not exist.

### 6.3 `driver`

A single `driver: "mssql" | "postgres" | "mysql" | "sqlite"` field, injected
from the pool definition, drives `#Paging` and would drive `#ValuesTable`
(§7.10) and the placeholder style (`?` / `@p1` / `$1`). The §7.10 "step must
declare `driver`" rule becomes `#ValuesTable: {driver: driver}` — a
unification that fails if the step pins a different dialect.

### 6.5 Performance: disjunctions inside pattern constraints (learned the hard way)

`fields?: [string]: #Field | #IsObject | #IsArray` (to allow nested params)
combined with `returns: #IsObject | #IsArray` + comprehensions over
`returns.fields` made `cue vet` on `query-example.cue` take **> 25 s**. With
`fields: [string]: #Field` and the shape given once: **23 ms**. Cause: 2 outer
× 3^7 inner disjuncts, fanned out through every comprehension. Details and
the bisection table: `docs/cue-lab/07-declarative/perf_note.md`.

Rules:
1. `fields` holds **scalars only**. Nesting composites inside `fields` is out
   (DRAFT-V3 §5.3 `Condition[]` is flat anyway).
2. Declare a shape **once** and derive from it; never let a comprehension
   iterate a field of an unresolved disjunction.

### 6.6 `source` — one meaning per place

| key | on | means |
|---|---|---|
| `source` | `#Field` | column name (only when ≠ field name) |
| `source` | `#IsObject` / `#IsArray` in an emit | rowset name |
| `source` | `#SelectStep` bindings (`columns`, `filters`, `search`, `order_by`, `paging`) | `"params.x"` path; must be an existing param of the right kind; defaults to the same-named param |

### 6.4 `:item` inside `foreach`

Not prototyped. Plan: `#ExecStep` with `foreach: #ArrayRef` exposes the
element shape as `_item: foreach.fields`, and an `#ItemRef` resolves against
it instead of `params`. Same `#Ref` machinery, different root.

---

## 7. Recommendation

1. **Reads (`get_*` lists)**: **D** — no SQL, best readability, strongest
   load-time checks. Covers the 80% case.
2. **Writes and anything with JOIN/aggregate**: raw `#QueryStep`/`#ExecStep`
   SQL **plus A's lint** on the strings now; move to **C fragments** per
   method when the runner grows an AST interpreter.
3. **B** only if string SQL must stay for long; if going to C, skip B.

Migration is per method and per step: `#Step: #SelectStep | #QueryStep |
#ExecStep | #EmitStep` — the runner dispatches on the step kind; a `sql`
field can be `string | [...#Fragment]` during the C transition.

**► Your comments**

> 

---

## 8. Open questions I could not settle alone

1. **Author ergonomics in C.** Is `#P & {path: "params.uid"}` acceptable, or
   do we want a shorter spelling? CUE cannot give us `:params.uid` sugar; the
   closest is a one-letter definition. Alternative: keep `string` fragments
   allowed to contain `:params.x` and *also* lint them with A's regex — mixed
   model, more to explain.
2. **DB-dependent checks stay in Go** (column exists in table, PK/identity
   skip, NOT NULL for insert). Should the CUE file carry a *declared* table
   schema too (so these move to CUE), or is introspection at startup the
   right boundary? V3 deliberately removed hand-typed models (§14).
3. **Export carries `type`/`static`/`out` on every fragment.** Fine for the
   runner; noisy for humans reading the JSON. Do we care about the JSON
   being readable, or only the `.cue`?
4. **`expand_order_by` default literal** (`"id asc"`) is free text today. In
   C it could be `default: [{col: or(keys), dir: "asc" | "desc"}]` — typed,
   but more to write. Worth it?
5. **Where do shared shapes live** (`#Clients` used by filters, search,
   columns, results)? C makes sharing natural (a definition), which reopens
   §13 "shared signature shapes" — probably in favour of a `shapes/` package.
