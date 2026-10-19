package p4

import (
	"strings"
	"list"
)

#Field: {type: "uuid" | "integer" | "double" | "string" | "text", source?: string}
#Shape: [K=string]: #Field & {source: *K | string}
#Clients: #Shape & {id: {type: "integer"}, full_name: {type: "string", source: "FullName"}, address: {type: "string"}, notes: {type: "text"}}

// (1) allowlist bound to a shape: every entry must be a field of `of`
#Conditions: {
	fn:   "conditions"
	ref:  string // ":params.filters" (object/array check omitted here)
	of:   #Shape
	cols: [...or([for k, _ in of {k}])]
	// field -> column map the runner needs (never inferred at runtime)
	columns: {for c in cols {(c): of[c].source}}
	static: false
}
okConds: #Conditions & {ref: "params.filters", of: #Clients, cols: ["id", "full_name"]}

// (2) reusable fragment (DRAFT-V3 §13: share WHERE between list and count)
_where: [" WHERE ", #Conditions & {ref: "params.filters", of: #Clients, cols: ["id", "full_name", "address"]}]
listSQL:  list.Concat([["SELECT id, FullName AS full_name FROM clients"], _where, [" ORDER BY id"]])
countSQL: list.Concat([["SELECT COUNT(*) AS n FROM clients"], _where])

// (3) hybrid string: CUE `\( )` folds static parts now; runner `${ }` stays verbatim
#Columns: {of: #Shape, out: strings.Join([for k, f in of {"\(f.source) AS \(k)"}], ", ")}
hybrid: """
	SELECT \((#Columns & {of: #Clients}).out)
	FROM clients
	${expand_where(expand_conditions(:params.filters, ["id","full_name"]))}
	"""

// (4) default-at-use alternative: keep `source?` optional, resolve when used
#FieldOpt: {type: string, source?: string}
#ShapeOpt: [string]: #FieldOpt
#ColumnsOpt: {
	of:  #ShapeOpt
	out: strings.Join([for k, f in of {
		let col = [if f.source != _|_ {f.source}, k][0]
		"\(col) AS \(k)"
	}], ", ")
}
optOut: (#ColumnsOpt & {of: {id: {type: "integer"}, full_name: {type: "string", source: "FullName"}}}).out
