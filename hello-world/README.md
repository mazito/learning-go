# hello-world

First Go program with an `asciiart` sub-package. Renders text as figlet-style ASCII block letters.

## Run

```sh
go run .
go run . HELLO
go run . WORLD
```

## Build

```sh
go build -o hello-world .
./hello-world HELLO
```

## Test

```sh
go test ./... -v
```

## Project layout

```
hello-world/
├── go.mod                  # module "hello-world"
├── main.go                 # package main — uses asciiart
├── asciiart/
│   ├── asciiart.go         # package asciiart — Draw(w, s)
│   └── asciiart_test.go    # tests
├── README.md
├── LEARNINGS.md
├── MEMO.md
├── QUESTIONS.md
├── TODO.md
└── CHANGES.md
```