# SQL-connector-API (scapi) — config-language research: CUE vs TOML, declarative steps
Branch: main
Date: 2026-10-17

## What was done
- Researched alternatives to TOML for method files (JS, HCL, CUE, Starlark, …).
  Conclusion: JS not for a Go backend; CUE is the cheapest "features over TOML"
  (pure Go). Logged in `QUESTIONS.md`.
- Built and `cue vet`-verified three CUE method examples (cue v0.17.1, binary
  at `/tmp/cuebin/cue`, not on PATH):
  - `get-object-example.cue` — read, 4 queries + emit; `#Returns`/`#Mapping`
    (older pattern, standalone).
  - `patch-object-example.cue` — mutation; `#ExecStep` (expect/on_zero/foreach/
    when), `#IsObject`/`#IsArray` (kind by definition, fixed `type` const as
    discriminator), `source` = column name on `#Field`, rowset on emit.
  - `query-example.cue` — Proposal D, declarative SELECT, no SQL; imports
    `shared/shared.cue` (`import "scapi.local/shared"`, module in `cue.mod/`).
- `CUE-FUNCTIONS.md` (~700 lines): how interpolation functions can be done in
  CUE. Proposals A (regex lint of `${}` strings), B (hybrid `\( )`+`${}`),
  C (SQL as typed fragment list → JSON AST for Go), D (declarative step, from
  user's sketch). Every snippet verified; sources in `docs/cue-lab/01..07`.
  Recommendation: D for reads, raw SQL + A-lint for writes now, C later.
- Then pivoted back to **TOML for readability**: `query-example.toml` =
  declarative list method (`[type.X]` shapes, `[params]`, `[result]`,
  `[errors]`, steps `select → count → emit`, every binding `{source = ...}`).
  Validated with tomli 2.4.1 and go-toml/v2 v2.4.3 (checker in `/tmp/gotoml`,
  rebuild if needed).

## Current state
- All `.cue` files and `shared/`, `docs/cue-lab/0[1-6]` vet clean (`cue vet -c`).
- `query-example.toml` parses in both parsers; semantics reviewed, see below.
- The `.cue` files are experiments; `query-example.toml` is the current
  direction for the real spec.

## Key decisions
- `source` = "where the data comes from", one meaning per place: column
  (`#Field`/type field), rowset (emit), param path (step bindings). No `param`
  keyword.
- Types are DATA SHAPES only; binding config (`source/allow/over/default`)
  lives in the step. Reference a type only via `type = "X"`.
- `default`/`max` live on the param, never on the step; `returns.min/max`
  dropped (`limit.max` is the cap).
- Result shape has priority: `columns` param (with alias) dropped.
- Emit explicit (no implicit result binding). `[result]` = shape only.
- New step kind `count = "_total"` (COUNT(*) over the same filters/search);
  emit `count = {source = "_invoices.length"}` (rowset pseudo-field) — both
  invented this session, to confirm in the spec.
- TOML 1.1-style multi-line inline tables accepted (go-toml/v2 + tomli ok);
  strict 1.0 not required.
- `[type.X]` (map) not `[[type]]` (array) so `type = "X"` is an index lookup.

## Next steps
- Confirm `count` step + `_invoices.length`; decide WHERE reuse between
  `select` and `count` (`where = "_invoices"`?).
- Write the startup-check list for the TOML runner (the "bill" vs CUE): param
  paths exist, `allow ⊆` result fields, `over` text-like, `limit`+`offset` ⇒
  `order_by`, unknown keys rejected, `source` stripped from discovery.
- Port patch (mutation) example to the new TOML style.
- See `TODO.md`.

## Key files
- Created: `CUE-FUNCTIONS.md`, `QUESTIONS.md`, `query-example.toml`,
  `get-object-example.cue`, `patch-object-example.cue`, `query-example.cue`,
  `shared/shared.cue`, `cue.mod/module.cue`, `docs/cue-lab/` (README, 01–07,
  `07-declarative/perf_note.md`).
- User-authored (not committed by me): `get-object-example.md`,
  `patch-object-example.md`, `DRAFT-V2.md`, `DRAFT-V3.md`, `../AGENTS.md` edit.

## Known issues / blockers
- `cue` binary only in `/tmp/cuebin` (lost on reboot); install with
  `go install cuelang.org/go/cmd/cue@latest`.
- get/patch `.cue` examples still use the older `#Returns`/`#Mapping` pattern
  and are standalone (not importing `shared/`).
