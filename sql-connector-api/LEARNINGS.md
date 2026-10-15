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

