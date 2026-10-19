package p1

import "strings"

// --- idiom: "function as struct". No lambdas in CUE; a definition with
// input fields and an `out` field is the function; (#Fn & {in}).out is the call.

#Field: {
	type:    "uuid" | "integer" | "double" | "string" | "text"
	source?: string
}

// Row shape with the default-source trick: label alias K gives each field
// its own name as default `source`.
#Shape: [K=string]: #Field & {source: *K | string}

#InvoiceResult: #Shape & {
	id:     {type: "integer"}
	uid:    {type: "uuid"}
	client: {type: "string", source: "client_name"}
	notes:  {type: "text"}
}

// expand_columns("table", @results.x [, alias]) as a pure CUE "function"
#Columns: {
	of:     #Shape
	alias?: string
	let pre = [if alias != _|_ {alias + "."}, ""][0]
	out: strings.Join([for k, f in of {"\(pre)\(f.source) AS \(k)"}], ", ")
}

cols:    (#Columns & {of: #InvoiceResult}).out
colsAli: (#Columns & {of: #InvoiceResult, alias: "i"}).out

// use inside a SQL string via \( ) interpolation
sql: "SELECT \((#Columns & {of: #InvoiceResult, alias: "i"}).out) FROM invoice i WHERE uid = :params.uid"
