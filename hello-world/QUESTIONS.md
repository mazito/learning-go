# QUESTIONS

## 1. Should we have a src/ folder for the source code?

**No.** In Go, `src/` is an anti-pattern. Convention is `go.mod` and `.go` files live in the same directory (the module root). The `src/` convention comes from Java/C++ and doesn't apply in Go.

Go projects are organized by package, not by file type. A simple program is flat:

```
hello-world/
├── go.mod
├── main.go
└── ...
```

Multi-package projects use meaningful subdirectory names (e.g., `cmd/`, `internal/`, `pkg/`), but never a generic `src/`.

## 2. What is go.mod? And what purpose does it serve?

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

## 3. Where does the compiler and builder put the binary files?

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

## 4. When creating a module used by the main code, where should I put it? As a subdir of the current main module? What are the naming conventions (for example, can I name it 'ascii-art'?)

**Put it in a subdirectory of the module.** A subdirectory becomes a sub-package — no separate `go.mod` needed. The import path is `module-name/package-name`:

```
hello-world/
├── go.mod           # module hello-world
├── main.go          # package main, imports "hello-world/asciiart"
└── asciiart/
    └── ascii.go     # package asciiart
```

**Naming rules:**
- No hyphens (`-`). Go import paths must be valid identifiers — `hello-world/ascii-art` is a parse error.
- No underscores (`_`) preferred, though they're technically valid. Convention is `alllowercase` with no separators.
- Short, lowercase, no punctuation — e.g. `asciiart`, `httputil`, `jsonrpc`.
- The package name (`package asciiart`) should match the directory name.
- Avoid `util`, `common`, `helpers` — too generic.

**When to use a separate module instead?** Only if the package is reusable across projects or has its own dependency lifecycle. For a learning repo, sub-packages under one module are simpler and correct.

## 5. Why the blank line between imports?

```go
import (
	"fmt"
	"os"

	"hello-world/asciiart"
)
```

Go convention groups imports into three categories, separated by blank lines:

1. **Standard library** — `fmt`, `os`, `io`
2. **Third-party packages** — `github.com/...`
3. **Local/project packages** — `hello-world/asciiart`

This is enforced by `gofmt` and `goimports`. If you remove the blank line, they'll put it back. It makes dependencies visually scannable: you can immediately see where each import comes from.

