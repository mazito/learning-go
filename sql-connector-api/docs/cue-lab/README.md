# cue-lab — verified prototypes for CUE-FUNCTIONS.md

Each folder is one CUE package; every snippet quoted in `../../CUE-FUNCTIONS.md`
comes from here and was run with `cue v0.17.1`. The repo root has a CUE module
(`cue.mod/module.cue`, `module: "scapi.local"`) so method files can
`import "scapi.local/shared"`.

| dir | shows |
|---|---|
| `01-fn-struct` | function-as-struct idiom, default `source` via label alias, `\( )` call inside SQL |
| `02-lint-strings` | Proposal A: regex-lint of `${fn(...)}` and `:params.x` inside SQL strings |
| `03-fragments` | Proposal C: SQL as fragment list, `#Ref` with path check + type, `#Set` column map, dialect-aware `#Paging`, CUE-side preview |
| `04-allowlist-reuse-hybrid` | shape-bound allowlists (`or()`), reusable `_where` (`list.Concat`), hybrid `\( )`+`${ }` string, default-at-use `source` |
| `05-slim-export` | hidden inputs (`_of`) keep exports slim while checks stay in regular fields |
| `06-nested-where` | nested composition `#Where{parts: [#Conditions, #Search, "literal"]}`, text-like-only rule |
| `07-declarative` | Proposal D: pointer to `query-example.cue` + `shared/` (no copy); `perf_note.md` = the 25 s disjunction blow-up and the two rules that fixed it |

Run all:

```sh
for d in docs/cue-lab/*/; do printf '%-45s ' "$d"; cue vet -c "./$d" && echo OK; done
```

Inspect one value:

```sh
cue export ./docs/cue-lab/03-fragments -e preview
cue export ./docs/cue-lab/03-fragments -e 'update[1]'
```

Negative tests (should FAIL) — add a file to the package and vet:

```sh
printf 'package p3\nbad: #Ref & {path: "params.nope"}\n' > docs/cue-lab/03-fragments/zz_bad.cue
cue vet -c ./docs/cue-lab/03-fragments ; rm docs/cue-lab/03-fragments/zz_bad.cue
```

The `cue` binary used in this session lives at `/tmp/cuebin/cue` (not on PATH);
install permanently with `go install cuelang.org/go/cmd/cue@latest`.
