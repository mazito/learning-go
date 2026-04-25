# LEARNINGS

## Go compile and run

Three ways to execute a Go program:

| Command | What it does | When to use |
|---------|-------------|-------------|
| `go run .` | Compiles to temp dir, runs, cleans up. No binary left behind. | Quick iteration during dev |
| `go build -o hello-world .` | Compiles to named binary in current dir. Must run manually after. | When you need a deployable binary |
| `go install .` | Compiles and installs to `$GOPATH/bin/`. Available globally. | When you want the tool on your PATH |

**Key points**:
- `go run` hides the compile step — great for dev, not for deployment.
- `go build` output defaults to the package name unless `-o` overrides it.
- `go install` puts the binary in `$GOPATH/bin` (must be on PATH).
- All three accept `./...` to target all packages in the module.
- The `.` targets the current package — idiomatic Go.

## Go project layout

- `go.mod` and `.go` files live in the same directory (module root).
- No `src/` folder — that's an anti-pattern in Go, inherited from Java/C++.
- Build artifacts (compiled binary) sit in the module root.
- Compiled binary should be gitignored (add to `.gitignore`).

## Go sub-packages

- A subdirectory in a Go module is a sub-package. `hello-world/asciiart/` → `package asciiart`, imported as `hello-world/asciiart`.
- Import path = module name + `/` + directory name.
- `main.go` imports the sub-package simply by name: `import "hello-world/asciiart"`.
- `go test ./...` runs tests for all packages in the module.
- `go vet ./...` and `gofmt -l .` work across the whole module too.

## Go naming conventions

- Package/directory names: `lowercasenoseparator` (e.g., `asciiart`, not `ascii-art` or `ascii_art`).
- Hyphens are illegal in import paths — `hello-world/ascii-art` is a parse error.
- Underscores work but go against convention.
- Package name must match directory name: directory `asciiart/` → `package asciiart`.

## Go formatting

- `gofmt -l .` lists files needing formatting. `gofmt -w .` fixes them in-place.
- Always run `gofmt -w .` and `go vet ./...` before committing.

## Adding a sub-package to a module

No extra `go.mod` needed. Steps:

1. Create a directory under the module root: `mkdir asciiart`
2. Add `.go` files with `package asciiart` declaration
3. Import from `main.go` as `"hello-world/asciiart"` (module name + `/` + dir name)
4. Run `go test ./...` to verify everything compiles and tests pass

That's it. No `go mod tidy` needed unless you add external dependencies. The Go toolchain discovers sub-packages automatically from the directory structure.

**Checklist before committing a new sub-package:**
- `go test ./... -v` — all tests pass
- `go vet ./...` — no issues
- `gofmt -w .` — formatting clean
- `go build .` — binary builds without errors