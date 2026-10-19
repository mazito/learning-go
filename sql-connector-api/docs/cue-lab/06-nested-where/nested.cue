package p6

#Field: {type: string, source?: string}
#Shape: [K=string]: #Field & {source: *K | string}
#Clients: #Shape & {id: {type: "integer"}, full_name: {type: "string", source: "FullName"}, notes: {type: "text"}}

#Conditions: {
	fn: "conditions", ref: string, _of: #Shape
	cols: [...or([for k, _ in _of {k}])]
	columns: {for c in cols {(c): _of[c].source}}
	static: false
}
#Search: {
	fn: "search", ref: string, _of: #Shape
	cols: [...or([for k, f in _of if f.type == "string" || f.type == "text" {k}])] // text-like only (§7.4)
	columns: {for c in cols {(c): _of[c].source}}
	static: false
}
// expand_where(frag, frag, ...): parts are predicates or literal SQL
#Where: {
	fn:     "where"
	parts:  [...(#Conditions | #Search | string)]
	static: false
}

w: #Where & {parts: [
	#Conditions & {ref: "params.filters", _of: #Clients, cols: ["id", "full_name"]},
	#Search & {ref: "params.q", _of: #Clients, cols: ["full_name", "notes"]},
	"deleted = 0",
]}
