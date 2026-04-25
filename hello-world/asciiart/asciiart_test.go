package asciiart

import (
	"bytes"
	"testing"
)

func TestDrawHello(t *testing.T) {
	var buf bytes.Buffer
	Draw(&buf, "HELLO")

	got := buf.String()
	// Should have 5 lines
	lines := bytes.Count([]byte(got), []byte("\n"))
	if lines != 5 {
		t.Errorf("expected 5 lines, got %d", lines)
	}
}

func TestDrawLowercase(t *testing.T) {
	var buf bytes.Buffer
	Draw(&buf, "hello")

	got := buf.String()
	// Lowercase should be converted to uppercase, so output matches "HELLO"
	var buf2 bytes.Buffer
	Draw(&buf2, "HELLO")
	if got != buf2.String() {
		t.Error("lowercase input should produce same output as uppercase")
	}
}

func TestDrawUnknownChars(t *testing.T) {
	var buf bytes.Buffer
	Draw(&buf, "H3LL0")

	var buf2 bytes.Buffer
	Draw(&buf2, "HLL")

	// Unknown chars (digits) should be skipped, so "H3LL0" renders same as "HLL"
	if got, want := buf.String(), buf2.String(); got != want {
		t.Errorf("expected unknown chars to be skipped, got:\n%s\nwant:\n%s", got, want)
	}
}

func TestDrawEmpty(t *testing.T) {
	var buf bytes.Buffer
	Draw(&buf, "")
	if buf.String() != "" {
		t.Errorf("expected empty output for empty input, got: %q", buf.String())
	}
}

func TestDrawExclamation(t *testing.T) {
	var buf bytes.Buffer
	Draw(&buf, "A!")

	got := buf.String()
	if len(got) == 0 {
		t.Error("expected non-empty output for 'A!'")
	}
}
