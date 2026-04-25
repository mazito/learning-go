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