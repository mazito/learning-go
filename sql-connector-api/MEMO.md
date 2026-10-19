# SQL-connector-API (scapi) — query-example.toml: bag-object model + aspects doc
Branch: main
Date: 2026-10-17 (second close of the day; research session archived in HISTORY)

## What was done
- Closed the research session (`d7ee551`), committed user drafts (`306d468`).
- Wrote `query-example-toml-aspects.md`: aspects to improve the TOML example
  under a two-phase runtime (compile pass at startup → "almost executable"
  run file → run steps). Sections: readability, stricter definition, compile
  checks (C1), run-file contents (C2), run-step rules (C3), open points (C4).
- User refined `query-example.toml` to the **bag-object model**: each step
  puts a typed object in the bag (`select` → `{rows, sql.where, length}`,
  `count` → `{count, sql.where}`); `count` reuses the select's WHERE via
  `where = "_invoices.sql.where"`; emit reads bag paths (`_invoices.rows`,
  `_total.count`, `_invoices.length`). Validated with tomli + go-toml/v2.
- Aspects doc updated with §0 "bag-object model (adopted)"; A1/A2/D1/D2 done.

## Current state
- `query-example.toml` = current direction for the real spec (declarative
  list method, 3 steps `select → count → emit`, every binding `{source=…}`).
- `.cue` files, `shared/`, `docs/cue-lab/`, `CUE-FUNCTIONS.md` = experiments,
  all vet clean; CUE track parked unless TOML falls short.
- Tree clean, `main` in sync with `origin/main` after this close.

## Key decisions
- Bag object per step, shape fixed per kind; later steps read fields with
  plain paths. One rule replaces WHERE-reuse, rowset coercion and `.length`
  special cases.
- `sql.where` is a compiled predicate plan **with binds**, not text; `count`
  runs with the same binds as `select`.
- Compile pass type-checks every `source` bag path at startup.
- (From research session) `source` = "where data comes from": column / param
  path / bag path. Types are data shapes only. `[result]` = shape only, emit
  explicit. `limit.max` is the only row cap.

## Next steps
- Confirm bag shapes per kind (`select` also `sql.order_by`? `exec` →
  `affected`?); whether bag paths may address `params.*` with the same syntax.
- Confirm `count` as a step kind.
- Write the compile-pass check list into the spec (aspects doc C1) and the
  run-file format (C2).
- Port the mutation example (patch-object) to the TOML bag-object style.
- See `TODO.md`.

## Key files
- Modified: `query-example.toml` (user, bag-object model),
  `query-example-toml-aspects.md` (created then updated).
- Session files: `MEMO.md`, `docs/memos/HISTORY.md`, `CHANGES.md`,
  `LEARNINGS.md`, `TODO.md`.

## Known issues / blockers
- `cue` binary only in `/tmp/cuebin`, go-toml checker in `/tmp/gotoml` — both
  lost on reboot; `go install cuelang.org/go/cmd/cue@latest` to restore cue.
- get/patch `.cue` examples still on the older `#Returns`/`#Mapping` pattern.
