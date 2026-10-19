// patch-object-example.cue
// CUE translation of patch-object-example.md (TOML), same patterns as
// get-object-example.cue: closed #definitions, enum unions, step disjunction.
//
// New here vs get-object-example.cue:
//   - #ExecStep for insert/update/delete (exec + expect + on_zero + foreach + when)
//   - #IsObject / #IsArray for composite params/results AND for what a query
//     or an emit returns (kind encoded by the definition)
//   - `source`: on #Field = column name (only when it differs from the field
//     name); on #IsObject/#IsArray = rowset name (emit)
//   - #QueryStep.returns declares how rows are delivered: #IsObject (rows[0]
//     -> object) or #IsArray (all rows, min/max bounds)
//
// NOTE: no `package` clause on purpose, so this file stands alone.
// The reusable block below is duplicated from get-object-example.cue; it
// should eventually move to a shared package/file.

method:      "patch_invoice"
title:       "Patch an invoice"
description: "Header + lines + summary in one transaction (fixed order: header, lines, summary)"
version:     1

////////////////////////////////////////////////////////////////////////////////
//
// These are REUSABLE building blocks we may "import" into any method def
//
////////////////////////////////////////////////////////////////////////////////

// One scalar field / param / column constraint.
#Field: {
	type:      "uuid" | "integer" | "double" | "string" | "text"
	required?: bool   // params only
	default?:  _      // any concrete value; not cross-checked against `type`
	source?:   string // column name; omit when it equals the field name
	//                   e.g. invoiceId: #Field & {type: "integer", source: "id"}
}

// Composite shapes. The kind is encoded by the definition. `type` is a fixed
// constant you never write: it discriminates the #IsObject | #IsArray
// disjunction (optional-only differences cannot) and shows up in exports.
//
// Used in three places:
//   [params] / [results]  -> declares a shape (`fields`)
//   #QueryStep.returns    -> how rows are delivered (+ row shape via `fields`)
//   #EmitStep.returns     -> which rowset feeds a result field (`source`)
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

// A step is exactly one of three variants. Closed definitions make them
// exclusive: exec carries `exec`, query carries `query`, emit carries `emit`.
#Step: #ExecStep | #QueryStep | #EmitStep

// Write step (INSERT/UPDATE/DELETE). Runs `sql`, checks `expect`, no rowset.
#ExecStep: {
	exec:     string
	sql:      string
	expect?:  "one" | "some" | "any" // default any
	on_zero?: "NOT_FOUND" | "CONFLICT"
	foreach?: string                // array value ref; runs once per element, binds :item
	when?:    string                // skip step when value ref absent/null/empty
}

// Read step. SQL always yields 0..n rows; `returns` says how to deliver them:
//   #IsObject -> rows[0] as an object (>1 rows = INTERNAL, a SQL bug)
//   #IsArray  -> all rows, bounded by min/max
// `fields` is the row schema; `#Field.source` maps a field to a column with
// a different name (implicit when names match).
#QueryStep: {
	query:   string
	sql:     string
	returns: #IsObject | #IsArray
}

// Map step: each key is a [results] field; `source` names the rowset.
#EmitStep: {
	emit:    string
	returns: [string]: #IsObject | #IsArray
}

////////////////////////////////////////////////////////////////////////////////
//
// These are SPECIFIC to the JSONRPC method we want to describe
//
////////////////////////////////////////////////////////////////////////////////

// [params] — flat scalars + composite object/array params.
params: {
	uid: #Field & {type: "uuid", required: true}
	vrs: #Field & {type: "integer", required: true}

	invoice: #IsObject & {
		required: true
		fields: {
			id:          #Field & {type: "integer", required: true}
			client_name: #Field & {type: "string"}
			address:     #Field & {type: "string"}
			notes:       #Field & {type: "text"}
		}
	}

	items: #IsArray & {
		required: false // if not present we dont touch the items table
		min:      0
		max:      500
		fields: {
			id:          #Field & {type: "integer", required: true}
			description: #Field & {type: "string"}
			price:       #Field & {type: "double"}
			quantity:    #Field & {type: "integer"}
			total:       #Field & {type: "double"}
		}
	}

	summary: #IsObject & {
		required: true
		fields: {
			id:    #Field & {type: "integer", required: true}
			total: #Field & {type: "double"}
		}
	}
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

#ItemResult: {
	id:          #Field & {type: "integer"}
	description: #Field & {type: "string"}
	price:       #Field & {type: "double"}
	quantity:    #Field & {type: "integer"}
	total:       #Field & {type: "double"}
}

// [results] — the JSON-RPC output contract.
results: {
	invoice: #IsObject & {fields: #InvoiceResult}
	items:   #IsArray & {fields: #ItemResult}
}

// [errors]
errors: [string]: string
errors: {
	NOT_FOUND: "Invoice does not exist"
	CONFLICT:  "Invoice was modified by someone else"
}

// ---- steps ([[step]]) ---------------------------------------------------
// Mutation: all steps run in ONE transaction, in file order. Emit is last.

step: [...#Step]
step: [
	// 1. header (optimistic lock on vrs)
	#ExecStep & {
		exec:    "header"
		expect:  "one"
		on_zero: "CONFLICT"
		sql: """
			UPDATE invoice
			SET ${expand_set(:params.invoice, "invoice")}, vrs = vrs + 1
			WHERE uid = :params.uid AND vrs = :params.vrs
			"""
	},

	// 2. lines (per element of :params.items)
	#ExecStep & {
		exec:    "lines"
		foreach: ":params.items"
		expect:  "one"
		sql: """
			UPDATE details
			SET ${expand_set(:item, "details")}
			WHERE id = :item.id AND invoice_id = :params.invoice.id
			"""
	},

	// 3. summary (only when :params.summary is present)
	#ExecStep & {
		exec:   "summary"
		when:   ":params.summary"
		expect: "one"
		sql: """
			UPDATE summary
			SET ${expand_set(:params.summary, "summary")}
			WHERE invoice_id = :params.invoice.id AND id = :params.summary.id
			"""
	},

	// 4. re-read header -> rowset "_invoice", delivered as ONE object
	#QueryStep & {
		query:   "_invoice"
		returns: #IsObject & {required: true, fields: #InvoiceResult}
		sql: """
			SELECT *
			FROM invoice
			WHERE uid = :params.uid
			"""
	},

	// 5. re-read lines -> rowset "_items", delivered as an array (0..500)
	#QueryStep & {
		query:   "_items"
		returns: #IsArray & {min: 0, max: 500, fields: #ItemResult}
		sql: """
			SELECT *
			FROM details
			WHERE invoice_id = :params.invoice.id
			ORDER BY id
			"""
	},

	// 6. emit: feed each [results] field from its rowset
	#EmitStep & {
		emit: "results"
		returns: {
			invoice: #IsObject & {source: "_invoice"}
			items:   #IsArray & {source: "_items"}
		}
	},
]
