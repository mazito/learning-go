# Perf note — the 25-second `cue vet`

First version of `#IsObject`/`#IsArray` had
`fields?: [string]: #Field | #IsObject | #IsArray` (to allow nested params) and
`#SelectStep.returns: #IsObject | #IsArray` with `_shape: returns.fields`
feeding five comprehensions.

| variant | `cue vet -c` |
|---|---|
| as above (full file) | **timeout > 25 s** |
| `returns: #IsArray` only (t8) | 0.02 s |
| shape given once, outer disjunction kept, inner 3-way kept (t9) | timeout |
| shape given once, inner `[string]: #Field` only (t10) | **0.023 s** |

Cause: 2 (outer) x 3^7 (one 3-way disjunct per field of a 7-field shape) is
fanned out through every comprehension that touches the shape.

Rules adopted:
1. `fields` holds scalars only. Nesting a composite inside `fields` is not
   supported (DRAFT-V3 §5.3 `Condition[]` is flat anyway).
2. Declare the row shape ONCE (`shape`) and derive `returns.fields` from it,
   so no comprehension iterates an unresolved disjunction.
