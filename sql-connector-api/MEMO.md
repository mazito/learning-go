# SQL-connector-API (scapi) — DRAFT.md spec iteration
Branch: main

## What was done
- Iterated the scapi spec in `DRAFT.md` (TOML-defined JSON-RPC 2.0 methods for
  local SQL engines, outbound-only to Treme.io connectors).
- TOML validity passes: fixed missing `=`, trailing commas in TOML statements,
  `port` as integer, literal-string backslashes (`'host\instance'` for MSSQL),
  `$ENV:` secret refs, inline-table syntax. Verified with tomli 2.4.1,
  BurntSushi/toml v1.6.0 and go-toml v2.4.3.
- `methods.enabled.toml`: `[[connection]]` pools + `[[method]]` registry;
  `[connection]` removed from method files (pool binding = single source).
- Method files: `get_clients` (query) + `patch_client` (exec).
- Placeholder names unified and signatures moved to inner args:
  `expand_columns(:results.clients)`, `expand_conditions(:params.filters.conditions)`,
  `expand_search(:params.q, 'full_name,address,notes')`,
  `expand_order_by(:params.orders.by)`, `expand_set_values(:params.client)`,
  `expand_limits(:params.limit, :params.start)`.
- "Interpolation functions" section: 7 functions with `###` headings and typed
  signatures (`row_schema`, `condition[]`, `order_by[]`, `patch_object`, `row[]`).
- Rules written in: two placeholder styles (`${fn(...)}` fragment vs `:params.x`
  bound value), whitelist inlining for structural tokens, multi-WHERE `AND`-join
  rule, paging requires ORDER BY (default `ORDER BY id ASC`).
- "TO BE DONE": multi-table transaction sketch (Invoice.v1) with `[[exec]]`
  per table; bulk details patch via T-SQL `UPDATE ... FROM (VALUES ...) JOIN`;
  new function `expand_value_rows(values: row[])` defined.

## Key decisions
- Pool binding only in methods.enabled.toml; validate at load.
- Functions receive exact fragment inputs; structural tokens whitelist-validated,
  never inferred.
- MSSQL dialect: OFFSET/FETCH (not TOP) for paging; `(VALUES ...) JOIN` for
  bulk patch; all values bound, literals never inlined.

## Next steps
- See `TODO.md`.

## Key files
- `sql-connector-api/DRAFT.md` (co-edited with user)
- `sql-connector-api/MEMO.md`, `docs/memos/HISTORY.md`, `CHANGES.md`,
  `LEARNINGS.md`, `TODO.md` (created this session)

## Blockers
- None; spec decisions pending (see TODO.md).
