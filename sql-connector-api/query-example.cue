// query-example.cue
// Proposal D — DECLARATIVE query step. The author writes NO SQL for the
// list/search case: the step declares a table and which standard params feed
// it; the runner generates the SELECT. CUE validates the declaration
// (param paths, column allowlists bound to the result shape, enums).
//
// Reusable types come from ./shared (module root: ./cue.mod). Only what is
// specific to this method lives here.
//
// `source` = where the data comes from, one meaning per place:
//   #Field.source                 -> column name (only when != field name)
//   #IsObject/#IsArray.source     -> rowset name (emit)
//   #SelectStep bindings .source  -> param path ("params.x"), defaults to the
//                                    same-named param

import "scapi.local/shared"

method:      "get_invoices"
title:       "List invoices"
description: "Invoice list with column pick, filters, search, order and paging"
version:     1

////////////////////////////////////////////////////////////////////////////////
//
// SPECIFIC to this method
//
////////////////////////////////////////////////////////////////////////////////

params: {
	columns:  shared.#ColumnsParam
	filters:  shared.#FiltersParam
	q:        shared.#SearchParam
	order_by: shared.#OrderByParam
	limit:    shared.#LimitParam & {max: 5000}
	offset:   shared.#OffsetParam
}

// `source` only where the column name differs from the field name (`client`).
#InvoiceResult: {
	id:      shared.#Field & {type: "integer"}
	uid:     shared.#Field & {type: "uuid"}
	vrs:     shared.#Field & {type: "integer"}
	client:  shared.#Field & {type: "string", source: "client_name"}
	address: shared.#Field & {type: "string"}
	notes:   shared.#Field & {type: "text"}
	total:   shared.#Field & {type: "double"}
}

result: {
	invoices: shared.#IsArray & {fields: #InvoiceResult}
}

error: [string]: string
errors: {
	BAD_REQUEST: "Bad params for request"
}

// Bind the declarative step to this method's params, once.
#Select: shared.#SelectStep & {#params: params}

step: [...shared.#Step]
step: [
	// 1. the whole list query, declared — no SQL
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

	// 2. emit
	shared.#EmitStep & {
		emit: "results"
		returns: {
			invoices: shared.#IsArray & {source: "_invoices"}
		}
	},
]
