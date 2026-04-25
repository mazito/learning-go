package main

import (
	"fmt"
	"os"

	"hello-world/asciiart"
)

func main() {
	text := "HELLO"
	if len(os.Args) > 1 {
		text = os.Args[1]
	}
	fmt.Printf("Input: %s\n\n", text)
	asciiart.Draw(os.Stdout, text)
}
