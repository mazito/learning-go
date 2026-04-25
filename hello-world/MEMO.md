# MEMO

## Session 2: 2025-04-25 — ASCII Art Package

- Created `asciiart` sub-package with `Draw(w io.Writer, s string)` function
- Figlet-style block letters, 5 lines tall
- Supported chars: A, B, C, D, E, H, I, L, O, R, W, space, `!`
- Lowercase → uppercase. Unknown chars skipped silently.
- `main.go` accepts CLI arg (default: "HELLO")
- 5 tests passing. Vet and fmt clean.
- Added Q5 (import grouping) to QUESTIONS.md
- Key learnings: sub-package creation, naming conventions, import grouping

## Session 1: 2025-04-25 — Toolchain Setup

- Set up Go 1.26.2 at `$HOME/.local/go`
- Created hello-world module
- Flat layout (no `src/`), `go.mod` + `main.go` at module root
- Shell needs `source ~/.bashrc` for new Go