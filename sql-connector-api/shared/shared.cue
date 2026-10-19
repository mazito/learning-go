// shared/shared.cue — reusable types for scapi method files.
//
// Import with:   import "scapi.local/shared"      (module root: ../cue.mod)
// Then:          shared.#Field, shared.#IsArray, shared.#Step, ...
//
// Rules we learned (see CUE-FUNCTIONS.md §6.5):
//   - `fields` holds SCALARS only. A `#Field | #IsObject | #IsArray`
//     disjunction inside a pattern constraint made `cue vet` take 25 s.
//   - Every disjunction variant carries a fixed constant (`type`, `fn`) so
//     CUE can discriminate; optional-only differences cannot.
//   - Checks live in regular fields: errors in hidden fields (`_x`) do NOT
//     fail `cue vet`. Hidden fields are fine for inputs.
package shared

////////////////////////////////////////////////////////////////////////////////
// Shapes
////////////////////////////////////////////////////////////////////////////////

// One scalar field / param / column constraint.
#Field: {
	type:      "uuid" | "integer" | "double" | "string" | "text" | "boolean" | "json"
	required?: bool       // params only
	default?:  _          // any concrete value; not cross-checked against `type`
	enum?:     [...string] // allowed literal values
	max?:      int        // max length (string/text) or max value (numbers)
	source?:   string     // column name; omit when it equals the field name
}

// Composite shapes. The kind is encoded by the definition; `type` is a fixed
// constant you never write (it discriminates `#IsObject | #IsArray` and shows
// up in exports, matching the TOML `type = "object"`).
//
// Used in three places:
//   [params] / [results]   -> declares a shape (`fields`)
//   #QueryStep/#SelectStep -> how rows are delivered (+ row shape via `fields`)
//   #EmitStep              -> which rowset feeds a result field (`source`)
#IsObject: {
	type:      "object"
	required?: bool             // query: 0 rows -> NOT_FOUND if true, null if false
	default?:  _
	source?:   string           // emit: rowset name
	fields?:   [string]: #Field // keys not declared are rejected
}

#IsArray: {
	type:      "array"
	required?: bool
	default?:  _
	min?:      int              // min items / rows
	max?:      int              // max items / rows
	source?:   string           // emit: rowset name
	fields?:   [string]: #Field // shape of ONE element
}

////////////////////////////////////////////////////////////////////////////////
// Standard PARAM shapes (what the JSON-RPC client sends)
////////////////////////////////////////////////////////////////////////////////

#Operator: "EQ" | "NEQ" | "GT" | "GTE" | "LT" | "LTE" | "IN" | "NOT_IN" |
	"LIKE" | "IS_NULL" | "IS_NOT_NULL" | "BETWEEN"

// filters: [{column, operator, value}]  (DRAFT-V3 §5.3 Condition[], flat)
#FiltersParam: #IsArray & {
	required: bool | *false
	fields: {
		column: #Field & {type: "string", required: true}
		// enum entries are checked against #Operator: a typo here is a vet error
		operator: #Field & {type: "string", required: true,
			enum: [...#Operator] & ["EQ", "NEQ", "GT", "GTE", "LT", "LTE", "IN", "NOT_IN", "LIKE", "IS_NULL", "IS_NOT_NULL", "BETWEEN"]}
		value: #Field & {type: "json"} // 0 for IS_*, 1 scalar, N for IN, 2 for BETWEEN
	}
}

// order_by: [{column, dir}]
#OrderByParam: #IsArray & {
	required: bool | *false
	fields: {
		column: #Field & {type: "string", required: true}
		dir:    #Field & {type: "string", default: "asc", enum: ["asc", "desc"]}
	}
}

// columns: [{name}] — client picks a subset of the result fields
#ColumnsParam: #IsArray & {
	required: bool | *false
	fields: {name: #Field & {type: "string", required: true}}
}

#SearchParam: #Field & {type: "string", required: bool | *false}
#LimitParam:  #Field & {type: "integer", default: 1000}
#OffsetParam: #Field & {type: "integer", default: 0}

////////////////////////////////////////////////////////////////////////////////
// Steps
////////////////////////////////////////////////////////////////////////////////

// Write step (INSERT/UPDATE/DELETE). Runs `sql`, checks `expect`, no rowset.
#ExecStep: {
	exec:     string
	sql:      string
	expect?:  "one" | "some" | "any" // default any
	on_zero?: "NOT_FOUND" | "CONFLICT"
	foreach?: string // array value ref; runs once per element, binds :item
	when?:    string // skip step when value ref absent/null/empty
}

// Raw-SQL read step. SQL always yields 0..n rows; `returns` says how to
// deliver them: #IsObject -> rows[0] as an object (>1 rows = INTERNAL);
// #IsArray -> all rows, bounded by min/max.
#QueryStep: {
	query:   string
	sql:     string
	returns: #IsObject | #IsArray
}

// Declarative SELECT. No SQL: the runner builds
//   SELECT <columns> FROM <from> WHERE <filters AND search> ORDER BY <order_by> <paging>
//
// `#params` is the method's [params] (a method binds it once:
//   #Select: shared.#SelectStep & {#params: params}
// ). It is a definition field, so it is not exported.
//
// Bindings: `source` = where the data comes from (a param path). It must be
// an existing param of the right kind and defaults to the same-named param,
// so `columns: {}` means "params.columns". `allow` = result fields the client
// may name; defaults to ALL fields of `returns` (a method never exposes more
// than it returns); write a list only to narrow. `search.over` is explicit
// and limited to text-like fields. `map` (field -> column) is for the runner.
#SelectStep: {
	#params: [string]: {type: string, ...}

	select:  string // rowset name
	from:    string // table (existence checked by the runner against the DB)
	returns: #IsObject | #IsArray

	_shape: returns.fields
	_keys:  [for k, _ in _shape {k}]
	_text:  [for k, f in _shape if f.type == "string" || f.type == "text" {k}]

	_arrayPath:   or([for k, f in #params if f.type == "array" {"params.\(k)"}])
	_stringPath:  or([for k, f in #params if f.type == "string" {"params.\(k)"}])
	_integerPath: or([for k, f in #params if f.type == "integer" {"params.\(k)"}])

	columns?: {
		source: (*"params.columns" | string) & _arrayPath
		allow:  [...or(_keys)] | *_keys
		map:    {for f in allow {(f): *_shape[f].source | f}}
	}
	filters?: {
		source: (*"params.filters" | string) & _arrayPath
		allow:  [...or(_keys)] | *_keys
		map:    {for f in allow {(f): *_shape[f].source | f}}
	}
	search?: {
		source: (*"params.q" | string) & _stringPath
		over:   [...or(_text)]
		map:    {for f in over {(f): *_shape[f].source | f}}
	}
	order_by?: {
		source:  (*"params.order_by" | string) & _arrayPath
		allow:   [...or(_keys)] | *_keys
		map:     {for f in allow {(f): *_shape[f].source | f}}
		default: [...{column: or(_keys), dir: "asc" | "desc"}] // paging needs a deterministic order
	}
	paging?: {
		limit:  (*"params.limit" | string) & _integerPath
		offset: (*"params.offset" | string) & _integerPath
	}
}

// Map step: each key is a [results] field; `source` names the rowset.
#EmitStep: {
	emit:    string
	returns: [string]: #IsObject | #IsArray
}

// A step is exactly one of four variants. Closed definitions make them
// exclusive: exec / query / select / emit.
#Step: #ExecStep | #QueryStep | #SelectStep | #EmitStep
