# QUESTIONS

## Should we have a src/ folder for the source code?

**No.** In Go, `src/` is an anti-pattern. Convention is `go.mod` and `.go` files live in the same directory (the module root). The `src/` convention comes from Java/C++ and doesn't apply in Go.

Go projects are organized by package, not by file type. A simple program is flat:

```
hello-world/
├── go.mod
├── main.go
└── ...
```

Multi-package projects use meaningful subdirectory names (e.g., `cmd/`, `internal/`, `pkg/`), but never a generic `src/`.

## What is go.mod? And what purpose does it serve?

`go.mod` is the **module definition file**. It serves three purposes:

1. **Declares the module path** — the identity of the module (e.g., `module hello-world`). This becomes the import prefix for all packages in the module.

2. **Sets the Go version** — `go 1.26.2` tells the toolchain which minimum Go version is required. Also enables `GOTOOLCHAIN=auto` to download a newer toolchain if needed.

3. **Tracks dependencies** — `require` directives list external modules and their versions. `go mod tidy` adds/removes entries as code imports change.

Example:

```
module hello-world

go 1.26.2

require (
    github.com/some/lib v1.2.3
)
```

Without `go.mod`, Go operates in legacy GOPATH mode. With it, you get **modules** — reproducible builds, versioned dependencies, and no need for a specific directory layout.

## Where does the compiler and builder put the binary files?

Depends on the command:

| Command | Binary location | Stays after run? |
|---------|----------------|-----------------|
| `go run .` | Temp dir (`/tmp` or OS cache) | No — deleted after execution |
| `go build .` | Current working directory (named after the module) | Yes |
| `go build -o name .` | Current working directory (custom name via `-o`) | Yes |
| `go install .` | `$GOPATH/bin/` | Yes |

**Details**:
- `go build` without `-o` names the binary after the module path's last segment (e.g., `module hello-world` → binary `hello-world`).
- `go build` for non-main packages compiles to the **build cache** (`$GOPATH/pkg/` or `$GOCACHE`) — no binary written to cwd.
- `go install` for non-main packages writes `.a` archive files to `$GOPATH/pkg/`.
- Build cache is at `$(go env GOCACHE)` (typically `~/.cache/go-build`). Clean with `go clean -cache`.