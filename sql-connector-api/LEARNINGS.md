# LEARNINGS.md

## 2026-10-15 — TOML: multi-line inline tables + inline trailing commas are 1.1-draft, not 1.0
Rule: avoid newlines inside inline tables and trailing commas there when targeting older/stricter parsers; tomli 2.4.1, BurntSushi v1.6.0 and go-toml v2.4.3 all accept, TOML 1.0 validators may not.
Why: DRAFT.md method files use multi-line inline tables (`filters = { ..., ... }`).

## 2026-10-15 — TOML: statements never end with a comma
Rule: `key = 'value',` (comma outside quotes) is a parse error; commas only inside inline tables/arrays. Also: TOML `'...'` literal strings do not process escapes; `'host\\instance'` decodes to two backslashes — MSSQL `host\instance` needs one.
Why: connection blocks in methods.enabled.toml had both bugs.

## 2026-10-15 — T-SQL paging: OFFSET/FETCH, not TOP
Rule: `TOP` cannot combine with `OFFSET ... FETCH`; paged queries require `ORDER BY` (hence a default order when none is given). Bulk multi-row patch: `UPDATE a SET a.c = v.c FROM t AS a JOIN (VALUES (?,?,...)) AS v(...) ON ...` — one statement, N bound rows.
Why: expand_limits/expand_value_rows design in DRAFT.md.

## 2026-10-15 — Validate TOML with at least two parsers during draft
Rule: quick-parse draft TOML blocks with a script (tomli + Go parsers) before baking them into a spec.
Why: caught missing `=`, trailing commas, backslash and copy-paste bugs the eye misses.


## 2026-10-17 — CUE: a disjunction inside a pattern constraint fans out exponentially
Rule: never put `#A | #B | #C` as the value of a pattern constraint (`[string]: #A | #B | #C`) when another disjunction or comprehension iterates that struct. Keep `fields: [string]: #Field` flat; declare a shape once and derive from it.
Why: `fields?: [string]: #Field | #IsObject | #IsArray` + `returns: #IsObject | #IsArray` made `cue vet` take > 25 s on a 7-field shape (2 × 3^7 disjuncts); flat version: 23 ms. Bisection in `docs/cue-lab/07-declarative/perf_note.md`.

## 2026-10-17 — CUE: errors in hidden fields do not fail `cue vet`
Rule: put every CHECK in a regular field; use hidden `_x` fields only for inputs. Also: hidden fields are package-private, so a shared definition takes cross-package inputs via a definition field (`#params`), never `_params`.
Why: a bad `#Ref` path hidden in `_root` passed vet silently; `shared.#SelectStep & {_params: params}` from another package is a different `_params`.

## 2026-10-17 — CUE: `#A | #B` needs a fixed constant to discriminate
Rule: every variant of a disjunction carries a required constant (`type: "object"`, `fn: "set"`). Optional-only differences cannot disambiguate: an optional field with a bottom value does not invalidate a struct.
Why: `#IsObject | #IsArray` differing only in optional `min?/max?` evaluated to an ambiguous "incomplete value".

## 2026-10-17 — CUE: `*a | S` lets the default bypass the set
Rule: to default INSIDE an allowed set write `(*a | string) & S`, not `*a | S`.
Why: `source: *"params.columns" | #ArrayParamPath` accepted `columns: {}` with no `params.columns` param.

## 2026-10-17 — CUE: multiline string indentation is the closing-quote indentation
Rule: every non-empty line inside `"""` must start with the exact whitespace that precedes the closing `"""`; mixing tabs and spaces → `non-matching whitespace for multiline strings`.
Why: hand-edited SQL in patch-object-example.cue broke vet twice.

## 2026-10-17 — TOML: comments are `#`, a table header may appear once, inline tables are multi-line in go-toml/v2
Rule: `//` is a parse error; a second `[type]` header is `table type already exists` (use `[type.X]` subtables or one header); multi-line `X = { … }` inline tables are accepted by go-toml/v2 v2.4.3 and tomli 2.4.1 (TOML 1.1 draft) — fine for the Go backend, not strict 1.0. Statements still never end with `,`.
Why: query-example.toml needed four passes; validated each with both parsers.

## 2026-10-17 — Spec design: make step outputs ordinary structs, not special references
Rule: when several features need "reuse something from an earlier step" (WHERE reuse, rowset→array coercion, row count), give each step a typed bag object with a fixed shape per kind and let later steps read fields by plain path (`_x.sql.where`, `_x.rows`, `_x.length`). One rule, compile-time checkable, extensible.
Why: the first design had three ad-hoc mechanisms (`where = "_x"`, implicit rowset coercion, a `.length` pseudo-field); the user's bag-object version replaced all three and made every `source` path type-checkable at startup.
