// get-object-example.cue
// CUE translation of get-object-example.md (TOML).
//
// Shape mapping TOML -> CUE:
//   key = value                  ->  key: value
//   [a.b]                        ->  a: b: { ... }
//   [[step]]                     ->  step: [ ... ]
//   { type = "x", ... }          ->  #Field & {type: "x", ...}
//   schema = "result.schema.hdr" ->  schema: #Header   (a real reference)
//
// What CUE adds over TOML here:
//   - #definitions are closed -> typo/extra fields are errors, not silent data
//   - `type` is an enum (union) -> invalid type = compile error
//   - steps are a disjunction of #QueryStep | #EmitStep -> per-variant schema
//   - defaults (*x) instead of ad-hoc `default = ...` handling
//   - mapping `schema` points at the schema value, never a string path
//
// NOTE: no `package` clause on purpose, so this file stands alone.

////////////////////////////////////////////////////////////////////////////////
//
// These are REUSABLE building blocks we may "import" into any method def
// 
////////////////////////////////////////////////////////////////////////////////

// One field / param / column constraint.
#Field: {
	type:      "uuid" | "integer" | "double" | "string" | "text"
	required?: bool // params only
	default?:  _    // any concrete value; not cross-checked against `type`
}

#Returns: {
	type:    "object" | "array"
	single?: bool
	min?:    int
	max?:    int
	count?:  int

	// Named output parts (header, client, details, summary, ...).
	// Method-specific keys, each mapping a query bag to a schema.
	// Shared by both steps; #QueryStep permits them but does not use them.
	// NOTE: grow this exclusion list if the envelope above grows.
	[string & !="type" & !="single" & !="min" & !="max" & !="count"]: #Mapping
}

// Pairs a query result with the schema it must satisfy.
// `schema` is a genuine value reference, not the string "result.schema.x".
#Mapping: {
	from:   string
	schema: _ // #Header | #Client | [...#Item] | #Summary
}

// A step is exactly one of two variants. Closed definitions make them
// exclusive: a query step cannot carry `emit`, the emit step cannot carry
// `sql`, and CUE resolves which variant a literal is.
#Step: #QueryStep | #EmitStep

#QueryStep: {
	query:   string
	returns: #Returns
	sql:     string
}

#EmitStep: {
	emit:    string
	returns: #Returns
}

////////////////////////////////////////////////////////////////////////////////
//
// These are SPECIFIC to the JSONRPC method we want to describe
//
////////////////////////////////////////////////////////////////////////////////

method:      "get_invoice"
title:       "Get a particular invoice by its uid"
description: "Full invoice with header, client, items and summary"
version:     1

//-- JSONRPC Params definitions --//

// [params.schema]
params: schema: {
	uid: #Field & {type: "uuid", required: true}
	vrs: #Field & {type: "integer", default: 1}
}

//-- JSONRPC Results definitions --//

// Partial result schemas: #Header, #Client, #Item, #Summary 
#Header: {
	uid:   #Field & {type: "uuid"}
	id:    #Field & {type: "integer"}
	vrs:   #Field & {type: "integer", default: 1}
	num:   #Field & {type: "string"}
	notes: #Field & {type: "text"}
}

#Client: {
	id:        #Field & {type: "integer"}
	full_name: #Field & {type: "string"}
	address:   #Field & {type: "string"}
	notes:     #Field & {type: "text"}
}

#Item: {
	id:          #Field & {type: "integer"}
	description: #Field & {type: "string"}
	quantity:    #Field & {type: "integer"}
	price:       #Field & {type: "double"}
	subtotal:    #Field & {type: "double"}
}

#Summary: {
	id:    #Field & {type: "integer"}
	total: #Field & {type: "string"}
}

// Full result schema
result: schema: {
	count:   #Field & {type: "integer"}
	header:  #Header
	client:  #Client
	details: [...#Item]
	summary: #Summary
}

//-- JSONRPC Error definitions --//

// [errors]
errors: [string]: string
errors: {
	NOT_FOUND:   "Invoice :params.uid not found"
	BAD_REQUEST: "Bad params for request"
}

////////////////////////////////////////////////////////////////////////////////
//
// The execution STEPS we need to run in order to get the desired result
// JSONRPC(params) -> [steps] -> result
//
////////////////////////////////////////////////////////////////////////////////

step: [...#Step]
step: [
	// 1. header -> bag "_invoice"
	#QueryStep & {
		query:   "_invoice"
		returns: {type: "object", single: true}
		sql: """
			SELECT *
			FROM invoices
			WHERE uid = :params.uid
			"""
	},

	// 2. client -> bag "_client"
	#QueryStep & {
		query:   "_client"
		returns: {type: "object", single: true}
		sql: """
			SELECT *
			FROM client
			WHERE id = :invoice_obj.client_id
			"""
	},

	// 3. items -> bag "_items"
	#QueryStep & {
		query:   "_items"
		returns: {type: "array", min: 0, max: 500}
		sql: """
			SELECT uid, id, description, quantity, price, subtotal, invoice_id
			FROM invoice_items
			WHERE invoice_id = :invoice_obj.id
			"""
	},

	// 4. summary -> bag "_summary"
	#QueryStep & {
		query:   "_summary"
		returns: {type: "object", single: true}
		sql: """
			SELECT *
			FROM invoice_totals
			WHERE invoice_id = :invoice_obj.id
			"""
	},

	// 5. emit: map each bag to the constrained result schema
	#EmitStep & {
		emit: "result"
		returns: {
			type:   "object"
			single: true
			count:  1
			header:  {from: "_invoice", schema: #Header}
			client:  {from: "_client", schema: #Client}
			details: {from: "_items", schema: [...#Item]}
			summary: {from: "_summary", schema: #Summary}
		}
	},
]
