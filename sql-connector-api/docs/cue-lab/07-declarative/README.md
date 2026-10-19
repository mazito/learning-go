# 07 — declarative SELECT (Proposal D)

No lab copy any more: the live example is `../../../query-example.cue`, which
imports the shared types from `../../../shared/shared.cue` (module root
`../../../cue.mod`).

```sh
cue vet -c ./query-example.cue
cue export -e 'step[0]' ./query-example.cue
```

`perf_note.md` documents the 25-second `cue vet` and the two rules that fixed it.
