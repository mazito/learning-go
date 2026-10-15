# TODO.md

- [ ] Transactions spec: ordered `[[exec]]` in ONE transaction; first error → rollback all + defined JSON-RPC error mapping; fixed table order (header → details → summary) to avoid deadlocks; savepoint vs full rollback decision.
- [ ] Decide SET-join form: new `expand_set_join(target, values)` vs a mode of `expand_set_values` (column-to-column `d.c = v.c` vs `?`-bound).
- [ ] Models: `models/Invoice.v1.toml` shared row schemas + import rule (currently client schema duplicated in 2 method files).
- [ ] `vrs` optimistic locking: `WHERE uid = ? AND vrs = ?` + bump policy — still unused in patch_client.
- [ ] Go entry point: method-file loader + TOML validation + placeholder static check (refs exist, types match).
- [ ] Define `[[exec]]` extra fields (`name` for logs/errors, `iterate` if per-row mode chosen) and `[exec]` vs `[[exec]]` unification.
