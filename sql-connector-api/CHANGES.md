# CHANGES.md - Session: scapi DRAFT.md spec (TOML method files, interpolation functions, transactions sketch)

## Date: 2026-10-15
## Branch: main

### Files Modified
1. **sql-connector-api/DRAFT.md** — spec iteration: TOML fixes, methods.enabled.toml
   registry, get_clients/patch_client method files, "Interpolation functions"
   section (7 funcs, typed signatures), TO BE DONE transactions sketch with
   bulk `(VALUES ...)` JOIN exec; co-edited with user.

### Files Created
1. **sql-connector-api/MEMO.md** — current session context
2. **sql-connector-api/docs/memos/HISTORY.md** — session archive
3. **sql-connector-api/CHANGES.md** — change log (this file)
4. **sql-connector-api/LEARNINGS.md** — durable learnings
5. **sql-connector-api/TODO.md** — pending tasks

### Commits
- (session files committed together in this session's closing commit)

---
# CHANGES.md - Session: config-language research — CUE examples, CUE-FUNCTIONS proposals, declarative TOML query

## Date: 2026-10-17
## Branch: main

### Files Modified
1. **sql-connector-api/MEMO.md** — rewritten with this session only (previous archived)
2. **sql-connector-api/docs/memos/HISTORY.md** — previous MEMO prepended via `cat`
3. **sql-connector-api/LEARNINGS.md** — CUE/TOML learnings appended
4. **sql-connector-api/TODO.md** — pending items appended

### Files Created
1. **sql-connector-api/QUESTIONS.md** — Q&A: JS as config lang, what is CUE, TOML→CUE mapping, `props` dropped
2. **sql-connector-api/CUE-FUNCTIONS.md** — interpolation functions in CUE: facts F1–F9, proposals A/B/C/D, perf note, recommendation, open questions; user comment blocks
3. **sql-connector-api/get-object-example.cue** — read method in CUE (co-edited with user)
4. **sql-connector-api/patch-object-example.cue** — mutation in CUE: `#ExecStep`, `#IsObject`/`#IsArray`, `source` (co-edited)
5. **sql-connector-api/query-example.cue** — declarative SELECT (Proposal D), imports `shared`
6. **sql-connector-api/shared/shared.cue** — reusable types package (`scapi.local/shared`)
7. **sql-connector-api/cue.mod/module.cue** — CUE module root (`module: "scapi.local"`)
8. **sql-connector-api/docs/cue-lab/** — README + 7 verified prototype packages (`01-fn-struct` … `07-declarative/perf_note.md`)
9. **sql-connector-api/query-example.toml** — declarative list method in TOML: `[type.X]`, `[params]`, `[result]` (invoices/total/count), `[errors]`, steps `select → count → emit` (co-edited; validated with tomli + go-toml/v2)

### Commits
- (session files committed together in this session's closing commit)

---
