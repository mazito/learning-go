package p2

import (
	"regexp"
)

// Registry of known interpolation functions (names only, for this test).
#FnName: "expand_columns" | "expand_where" | "expand_conditions" | "expand_search" |
	"expand_order_by" | "expand_paging" | "expand_set" | "expand_insert" | "expand_in"

params: {
	uid:     {type: "uuid"}
	vrs:     {type: "integer"}
	invoice: {type: "object", fields: {id: {type: "integer"}, notes: {type: "text"}}}
}

// A SQL template with the three token kinds from DRAFT-V3 §7.
sql: """
	UPDATE invoice
	SET ${expand_set(:params.invoice, "invoice")}, vrs = vrs + 1
	WHERE uid = :params.uid AND vrs = :params.vrs
	"""

// 1. extract ${fn(  -> function names
_fnCalls: regexp.FindAllSubmatch(#"\$\{([a-z_]+)\("#, sql, -1)
fnNames: [for m in _fnCalls {m[1]}]

// each extracted name must be a known function -> unification against the enum
fnCheck: [for n in fnNames {n & #FnName}]

// 2. extract :params.a.b value refs
_refs: regexp.FindAllSubmatch(#":params\.([a-zA-Z_][a-zA-Z0-9_]*)(?:\.([a-zA-Z_][a-zA-Z0-9_]*))?"#, sql, -1)
refs: [for m in _refs {m[0]}]

// each first segment must be a key of params; second (if any) a key of fields
refCheck: [for m in _refs {
	let s1 = m[1]
	let s2 = m[2]
	seg1: s1 & or([for k, _ in params {k}])
	if s2 != "" {
		seg2: s2 & or([for k, _ in params[s1].fields {k}])
	}
}]
