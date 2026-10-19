# TODO.md

- [ ] Transactions spec: ordered `[[exec]]` in ONE transaction; first error → rollback all + defined JSON-RPC error mapping; fixed table order (header → details → summary) to avoid deadlocks; savepoint vs full rollback decision.
- [ ] Decide SET-join form: new `expand_set_join(target, values)` vs a mode of `expand_set_values` (column-to-column `d.c = v.c` vs `?`-bound).
- [ ] Models: `models/Invoice.v1.toml` shared row schemas + import rule (currently client schema duplicated in 2 method files).
- [ ] `vrs` optimistic locking: `WHERE uid = ? AND vrs = ?` + bump policy — still unused in patch_client.
- [ ] Go entry point: method-file loader + TOML validation + placeholder static check (refs exist, types match).
- [ ] Define `[[exec]]` extra fields (`name` for logs/errors, `iterate` if per-row mode chosen) and `[exec]` vs `[[exec]]` unification.
- [ ] query-example.toml semantics: confirm `count = "_total"` step kind and `_invoices.length` rowset pseudo-field; decide WHERE reuse between `select` and `count` (`where = "_invoices"`?).
- [ ] Write the TOML runner startup-check list (what CUE did for free): `source` param paths exist and have the right kind; `allow ⊆` result fields; `over` only text-like; `limit`+`offset` ⇒ `order_by`; unknown step keys rejected; `source` stripped from JSON-RPC discovery output.
- [ ] Port the mutation example (patch-object) to the new declarative TOML style (`[type.X]`, `source` bindings, explicit emit).
- [ ] CUE-FUNCTIONS.md: answer the user comment blocks (► Your comments) and §8 open questions, or close the CUE track if TOML wins.
- [ ] get/patch `.cue` examples: migrate to `shared/` import and `#IsObject`/`#IsArray`, or mark as legacy experiments.
- [ ] Bag-object model: fix the bag shape per step kind in the spec (`select` → `{rows, sql.where, length}`, `count` → `{count, sql.where}`; add `sql.order_by`? `exec` → `{affected}`?) and whether bag paths may address `params.*` with the same syntax.
- [ ] Spec: `sql.where` reuse = predicate plan + binds (never text); `count` runs with the select's binds.
- [ ] Write the compile-pass check list (aspects doc C1) and the run-file format (C2) into the spec.
