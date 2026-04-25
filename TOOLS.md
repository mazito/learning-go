# Tools

This repo uses the following tools for development, AI-assisted coding, and learning.

## PI (Coding Agent)

**Version**: 0.68.1 (`@mariozechner/pi-coding-agent`)  
**Binary**: `$HOME/.nvm/versions/node/v24.6.0/bin/pi`  
**Config**: `$HOME/.pi/agent/`

PI is the primary AI coding agent used in this project. It runs in the terminal and provides read, bash, edit, and write tools for autonomous or semi-autonomous code manipulation.

**Why?** 

I have found it to be much lighter and to the point than Claude Code. I feel quite confortable using it, and it does not interrump asking for irrelevant permissions while working. 

Only problem I found so far (not PI fault anyway) is that Anthropic does not allow to use the Max suscription with other assistants other than Claude Code, so i need to use API tokens from the extra usage which are more expensive.

**Current setup**:

- Default model: `glm-5.1:cloud` (reasoning model via Ollama)
- Default provider: Ollama
- Default thinking level: medium
- Installed extensions: `@ollama/pi-web-search` (web search and fetch capabilities)

**Available models** (via Ollama provider):

| Model | Context Window | Input | Reasoning |
|-------|---------------|-------|-----------|
| glm-5.1:cloud | 202K | text | yes |
| qwen3.5:cloud | 256K | text, image | yes |
| kimi-k2.6:cloud | 256K | text, image | yes |
| gemma4:31b-cloud | 256K | text, image | yes |
| deepseek-v3.2:cloud | 256K | text | yes |

**Bundled tools**: `fd` (find), `rg` (ripgrep) — available at `$HOME/.pi/agent/bin/`

## Ollama

**Version**: 0.20.2  
**Binary**: `/usr/local/bin/ollama`  
**Service**: systemd (`ollama.service`), enabled, running  
**API**: `http://127.0.0.1:11434` (OpenAI-compatible at `/v1`)

Ollama serves as the local LLM inference platform. It runs as a system service and provides an OpenAI-compatible API that PI (and other tools) connect to.

**Pulled models**:

| Model | Notes |
|-------|-------|
| minimax-m2.5:cloud | 2 months old |
| deepseek-v3.2:cloud | 2 months old |
| glm-5:cloud | 2 months old |
| kimi-k2.5:cloud | 2 months old |

**Useful commands**:
```sh
ollama list              # List pulled models
ollama run <model>       # Interactive chat with a model
ollama serve             # Start the server (runs as systemd service)
```

## Claude Code & Anthropic Max

In addition to the local toolchain above, [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (Anthropic's CLI coding agent) is used under an **Anthropic Max** subscription.

**What it provides**:

- Claude Code: terminal-based AI coding agent (similar role to PI but backed by Claude models)
- Anthropic Max: subscription plan that includes higher usage limits for Claude Code and access to the latest Claude models
- Useful as a second opinion / cross-check against PI's output, and for tasks where Claude's strengths (large context, strong reasoning) are beneficial

**Typical usage in this repo**:

- Running alongside PI for comparative coding sessions
- Asking architecture or design questions that benefit from a different model's perspective
- Code review and suggestion generation

## Go Toolchain

**Version**: 1.26.2 (linux/amd64)  
**Date installed**: 2025-04-25

### Installation Steps

The Go toolchain was installed using the official binary tarball from [go.dev/dl](https://go.dev/dl/).

**1. Download and verify the tarball**

```sh
cd /tmp
curl -LO https://go.dev/dl/go1.26.2.linux-amd64.tar.gz
echo "990e6b4bbba816dc3ee129eaeaf4b42f17c2800b88a2166c265ac1a200262282  go1.26.2.linux-amd64.tar.gz" | sha256sum -c
```

> The SHA-256 hash was obtained from the [Go downloads page JSON](https://go.dev/dl/?mode=json).

**2. Extract to user-local directory**

```sh
mkdir -p $HOME/.local
tar -C $HOME/.local -xzf /tmp/go1.26.2.linux-amd64.tar.gz
```

This installs the Go SDK to `$HOME/.local/go`. User-local path was chosen because `sudo` was not available for a system-wide install to `/usr/local/go`. Works equally well.

**3. Set environment variables**

Added to `~/.bashrc`:

```sh
#-- Go Toolchain --
export GOROOT="$HOME/.local/go"
export GOPATH="$HOME/go"
export PATH="$GOROOT/bin:$GOPATH/bin:$PATH"
```

Then reload: `source ~/.bashrc`

**4. Verify**

```sh
go version          # go version go1.26.2 linux/amd64
go env GOROOT       # /home/mzito/.local/go
go env GOPATH       # /home/mzito/go
```

**5. Create workspace directory structure**

```sh
mkdir -p $HOME/go/{bin,src,pkg}
```

**6. Clean up**

```sh
rm /tmp/go1.26.2.linux-amd64.tar.gz
```

### Environment Reference

| Variable | Value | Purpose |
|----------|-------|---------|
| `GOROOT` | `$HOME/.local/go` | Location of the Go SDK installation |
| `GOPATH` | `$HOME/go` | Go workspace (binaries, source, packages) |
| `PATH` | Includes `$GOROOT/bin` and `$GOPATH/bin` | Makes `go`, `gofmt`, and installed tools available |

### What was installed before

The system previously had **Go 1.18.1** installed via `apt` (package `golang-go`) at `/usr/bin/go`. That older version is still on disk but is now shadowed by the newer `$HOME/.local/go/bin/go` which appears earlier in `PATH`.

To fully remove the old system Go (optional):

```sh
sudo apt remove golang-go golang-1.18-go golang-src golang-1.18-src
```

### Included Tools

| Tool | Description |
|------|-------------|
| `go` | Main Go command (build, test, run, mod, etc.) |
| `gofmt` | Code formatter |
| `goimports` | Not included by default; install with `go install golang.org/x/tools/cmd/goimports@latest` |

### Upgrading

```sh
cd /tmp
curl -LO https://go.dev/dl/go<VERSION>.linux-amd64.tar.gz
# Verify the hash from https://go.dev/dl/?mode=json
rm -rf $HOME/.local/go
tar -C $HOME/.local -xzf /tmp/go<VERSION>.linux-amd64.tar.gz
rm /tmp/go<VERSION>.linux-amd64.tar.gz
```

No need to change environment variables — `GOROOT` still points to `$HOME/.local/go`.

