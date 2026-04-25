// Package asciiart renders text as figlet-style ASCII block letters.
package asciiart

import (
	"io"
	"strings"
)

// Each character is 5 lines tall. Unknown runes are skipped.
var chars = map[rune][]string{
	'A': {
		"  ___  ",
		" / _ \\ ",
		"| | | |",
		"| |_| |",
		"|_| |_|",
	},
	'B': {
		" ____  ",
		"|  _ \\ ",
		"| |_) |",
		"|  _ < ",
		"|_| \\_\\",
	},
	'C': {
		" ____  ",
		"/ ___| ",
		"| |    ",
		"| |___ ",
		" \\____|",
	},
	'D': {
		" ____  ",
		"|  _ \\ ",
		"| | | |",
		"| |_| |",
		"|____/ ",
	},
	'E': {
		" _____ ",
		"|  ___|",
		"| |__  ",
		"|  __| ",
		"|_____|",
	},
	'H': {
		" _   _ ",
		"| | | |",
		"| |_| |",
		"|  _  |",
		"|_| |_|",
	},
	'I': {
		" _____ ",
		"|_   _|",
		"  | |  ",
		"  | |  ",
		"  |_|  ",
	},
	'L': {
		" _     ",
		"| |    ",
		"| |    ",
		"| |___ ",
		"|_____|",
	},
	'O': {
		" ____  ",
		"/ _ \\ ",
		"| | | |",
		"| |_| |",
		" \\____|",
	},
	'R': {
		" ____  ",
		"|  _ \\ ",
		"| |_) |",
		"|  _ < ",
		"|_| \\_\\",
	},
	'W': {
		" _      _ ",
		"| |    | |",
		"| |    | |",
		"| | /\\ | |",
		"|_|/  \\__|",
	},
	' ': {
		"   ",
		"   ",
		"   ",
		"   ",
		"   ",
	},
	'!': {
		" _ ",
		"| |",
		"| |",
		"  ",
		" _ ",
	},
}

// height is the number of lines per character.
const height = 5

// Draw writes s as figlet-style ASCII art to w.
// Lowercase letters are converted to uppercase.
// Unknown characters are skipped.
func Draw(w io.Writer, s string) {
	upper := strings.ToUpper(s)
	runes := []rune(upper)

	// Filter to only supported characters
	var supported []rune
	for _, r := range runes {
		if _, ok := chars[r]; ok {
			supported = append(supported, r)
		}
	}
	if len(supported) == 0 {
		return
	}

	// Render line by line
	for line := 0; line < height; line++ {
		for _, r := range supported {
			pattern := chars[r]
			io.WriteString(w, pattern[line])
		}
		io.WriteString(w, "\n")
	}
}
