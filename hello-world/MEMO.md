# MEMO

## Last session: 2025-04-25

- Set up Go 1.26.2 toolchain (installed to `$HOME/.local/go`)
- Created hello-world module — flat layout (`go.mod` + `main.go` at root)
- Ran `go run .`, `go build`, `go vet`, `gofmt` — all passing
- Shell still picking up old Go 1.18.1 from `/usr/bin/go` — need `source ~/.bashrc`