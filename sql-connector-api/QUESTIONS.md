# QUESTIONS

## 1. Can JavaScript be used as the configuration language instead of TOML (TOML-like structure plus extra features)? Is it a good idea?

**Possible: yes. Good idea: depends.** Config-as-code is proven (ESLint, Vite, Tailwind, webpack all use JS config). The catch here is that the `scapi` backend is Go, so running JS needs an embedded engine (goja, otto, v8go, quickjs): extra dependency, extra attack surface, slower load, worse errors.

Power/analysis trade-off ladder:

| Form | Power | Statically analyzable | Cost in Go |
|---|---|---|---|
| TOML | data | yes | trivial |
| JSON5/JSONC | +comments, trailing commas | yes | easy |
| HCL | +expressions, functions, blocks | mostly | parser exists |
| CUE | +types, constraints | yes (not Turing-complete) | pure-Go, no engine |
| Jsonnet/Dhall | programmable, pure | hard | heavy |
| Starlark | Python-like, hermetic, no I/O | partial | parser exists |
| **JS** | Turing-complete | no | engine needed |

Where JS tempts us: the spec already has a mini-DSL (`${expand_columns(...)}`, `:params.x`, 7 interpolation functions). In JS those become real functions, dropping the string-parsing placeholder layer.

Why it bites: not statically checkable (kills the planned static placeholder validator), non-determinism (env/time/require), arbitrary code at load, no schema validation, noisier diffs, permanent JS-runtime lock-in for a Go project, and SQL-template building in code drifts toward injection unless bindings stay strict.

**Rule of thumb:** want features -> HCL/CUE first. Want a language -> Starlark. Want JS habits -> JS, but pay the Go tax.

## 2. What is CUE, and is it Go-native?

**CUE** (*Configure, Unify, Execute*) is a config/schema language by Marcel van Lohuizen (ex-Google Go team). Its idea is data + types + constraints in one language; values unify with `&`. It is **not Turing-complete** (no loops, no side effects), so it stays analyzable. It reads/writes JSON, YAML, TOML, XML, OpenAPI, Protobuf and JSON Schema.

```cue
port: int | *8080        // type | default
name: string & =~"^[a-z]+$"
host: "db-\(env)"        // interpolation
```

**Go-native: yes.**
- Implemented in Go; core API `cuelang.org/go/cue`, plus `cue/cuecontext`, `cue/load`.
- `cue get go <pkg>` generates CUE definitions from Go types; `gocodec` validates/completes Go structs.
- Install: `go install cuelang.org/go/cmd/cue@latest` (needs a recent Go).

So for a Go backend it is the cheapest "features over TOML" jump: pure-Go dependency, no JS engine, no CGO.

Links: https://cuelang.org | spec https://cuelang.org/docs/reference/spec/ | Go integration https://cuelang.org/docs/integration/go/ | API https://pkg.go.dev/cuelang.org/go | repo https://github.com/cue-lang/cue | tour https://cuelang.org/docs/tour/

## 3. How does the `get_invoice` example map from TOML to CUE?

Files: `get-object-example.md` (TOML) -> `get-object-example.cue` (CUE). Validated with `cue v0.17.1` (`cue vet` OK, `cue export` gives clean JSON).

Shape mapping:

| TOML | CUE |
|---|---|
| `key = v` | `key: v` |
| `[a.b]` | `a: b: { ... }` |
| `[[step]]` | `step: [ ... ]` |
| `{ type = "x", ... }` | `#Field & {type: "x", ...}` |
| `details = [{...}]` | `details: [...#Item]` |
| `schema = "result.schema.header"` | `schema: #Header` (a real value reference) |

What CUE adds over TOML here:
- `#definitions` are **closed** -> typos/extra fields are errors, not silent data.
- `type` is an **enum union** -> an invalid type is a compile error.
- Steps are a **disjunction** `#Step: #QueryStep | #EmitStep` -> per-variant schema.
- Defaults via the `*x` idiom and optional-field constraints (`required?: bool`).
- Mapping `schema` points at the schema **value**, never a string path.
- Row schemas (`#Header`, `#Client`, `#Item`, `#Summary`) are defined once and reused.

Design decisions taken while translating:
- **`#Returns` is shared** by both step variants: envelope (`type`, `single?`, `min?`, `max?`, `count?`) plus a dynamic pattern `[string & !="type" & ...]: #Mapping` for the method-specific named output parts (`header`, `client`, `details`, `summary`, ...).
- Consequence: `#QueryStep` also *permits* those parts but does not use them. (The alternative, an emit-only `#EmitReturns`, was considered and rejected in favor of the shared definition.)
- The pattern must **exclude the envelope keys** (`!="type" & !="single" & ...`), otherwise they would be unified with `#Mapping`. Caveat: this exclusion list must grow whenever the envelope grows.

Caveats (not hidden):
- Still no *query* semantics: `:params.uid`, bag names like `_invoice`, `${...}` and `:params.x` are just strings to CUE. CUE validates **shape**, not the interpolation mini-DSL.
- SQL lives in `"""` multiline strings; CUE strips the indentation of the closing quote (verified: output has no leading spaces).
- `default` on `#Field` is not cross-checked against `type` (type is a string enum, default is a raw value).

## 4. Did `#Returns` need a `props` property?

**No.** It was added on request, but nothing in the example or the drafts uses it (`grep` found only unrelated prose). Since it was optional it changed nothing at runtime, but it was a dead line and forced `!="props"` into the exclusion list. Decision: **drop it**; add it back only when a method actually needs extra per-return metadata.
