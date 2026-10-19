package p5

#Field: {type: string, source?: string}
#Shape: [K=string]: #Field & {source: *K | string}
#Clients: #Shape & {id: {type: "integer"}, full_name: {type: "string", source: "FullName"}}

#Conditions: {
	fn:   "conditions"
	ref:  string
	_of:  #Shape                           // hidden input: not exported
	cols: [...or([for k, _ in _of {k}])]   // regular: errors DO fail vet
	columns: {for c in cols {(c): _of[c].source}}
	static: false
}
ok: #Conditions & {ref: "params.filters", _of: #Clients, cols: ["id", "full_name"]}
