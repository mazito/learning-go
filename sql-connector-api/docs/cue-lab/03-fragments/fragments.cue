package p3

import "strings"

driver: "mssql" | "postgres" | "mysql" | "sqlite"

#Field: {type: "uuid" | "integer" | "double" | "string" | "text", source?: string}
#Shape: [K=string]: #Field & {source: *K | string}

params: {
	uid:     {type: "uuid"}
	offset:  {type: "integer"}
	limit:   {type: "integer", max: 500}
	invoice: {type: "object", fields: #Shape & {id: {type: "integer"}, notes: {type: "text"}}}
}
#InvoiceResult: #Shape & {id: {type: "integer"}, uid: {type: "uuid"}, client: {type: "string", source: "client_name"}}

// ---- fragment kinds ------------------------------------------------------
// Every non-literal fragment is a closed struct with a fixed `fn` discriminator.
// `static: true`  -> CUE renders `out` now (pure function of the schema)
// `static: false` -> runner evaluates at request time; CUE only validates args

// value ref: ":params.uid" -> one bound placeholder (runtime), path checked now
#Ref: {
	fn:   "ref"
	path: string
	let segs = strings.Split(path, ".")
	// resolve the referenced param; a bad path is an error HERE (regular field,
	// not hidden: errors in hidden fields do not fail `cue vet`). A root other
	// than "params" leaves the list empty -> index error.
	type: [
		if segs[0] == "params" && len(segs) == 2 {params[segs[1]].type},
		if segs[0] == "params" && len(segs) == 3 {params[segs[1]].fields[segs[2]].type},
	][0]
	static: false
}
// §7: a bare ref in SQL must be a scalar; functions take object/array refs.
#ScalarRef: #Ref & {type: !="object" & !="array"}
#ObjectRef: #Ref & {type: "object"}
#ArrayRef:  #Ref & {type: "array"}

#Columns: {
	fn:     "columns"
	of:     #Shape
	alias:  string | *""
	static: true
	let pre = [if alias != "" {alias + "."}, ""][0]
	out: strings.Join([for k, f in of {"\(pre)\(f.source) AS \(k)"}], ", ")
}

// expand_set(:params.obj, "table"): keys present at runtime -> "col = ?" list.
// CUE cannot know which keys arrive, but it CAN fix the allowed column map.
#Set: {
	fn:    "set"
	ref:   #ObjectRef                 // must be an object param
	table: string
	// allowlist derived from the param's shape: field -> column
	columns: {for k, f in params[strings.Split(ref.path, ".")[1]].fields {(k): f.source}}
	static: false
}

#Paging: {
	fn:     "paging"
	offset: #Ref
	limit:  #Ref
	static: true // text is static per dialect; values are bound at runtime
	out: {
		mssql:    "OFFSET ? ROWS FETCH NEXT ? ROWS ONLY"
		postgres: "LIMIT ? OFFSET ?"
		mysql:    "LIMIT ? OFFSET ?"
		sqlite:   "LIMIT ? OFFSET ?"
	}[driver]
}

#Fragment: string | #ScalarRef | #Columns | #Set | #Paging

// ---- a template as a fragment list ---------------------------------------
sql: [...#Fragment]
sql: [
	"SELECT ", #Columns & {of: #InvoiceResult, alias: "i"},
	" FROM invoice i WHERE uid = ", #ScalarRef & {path: "params.uid"},
	" ORDER BY id ", #Paging & {offset: {path: "params.offset"}, limit: {path: "params.limit"}},
]

// preview: what the runner would receive after CUE folds static parts.
// Disjunction-as-dispatch: exactly one variant unifies with each fragment.
#Render: {in: string, out: in} |
	{in: {static: true, out: string, ...}, out: in.out} |
	{in: {static: false, fn: string, ...}, out: "<\(in.fn)>"}

preview: strings.Join([for f in sql {(#Render & {in: f}).out}], "")

update: [...#Fragment]
update: ["UPDATE invoice SET ", #Set & {ref: {path: "params.invoice"}, table: "invoice"}, ", vrs = vrs + 1 WHERE uid = ", #ScalarRef & {path: "params.uid"}]
