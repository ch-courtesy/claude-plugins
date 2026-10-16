package textnorm

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLF(t *testing.T) {
	if got := string(LF([]byte("---\r\nname: a\r\n---\r\n"))); got != "---\nname: a\n---\n" {
		t.Fatalf("CRLF not normalized: %q", got)
	}
	if got := string(LF([]byte("a\rb\n"))); got != "a\rb\n" {
		t.Fatalf("lone CR must stay: %q", got)
	}
}

func TestReadFile(t *testing.T) {
	p := filepath.Join(t.TempDir(), "SKILL.md")
	if err := os.WriteFile(p, []byte("x\r\ny\r\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	b, err := ReadFile(p)
	if err != nil {
		t.Fatal(err)
	}
	if string(b) != "x\ny\n" {
		t.Fatalf("got %q", b)
	}
	if _, err := ReadFile(filepath.Join(t.TempDir(), "missing")); !os.IsNotExist(err) {
		t.Fatalf("missing file must keep os.ReadFile error, got %v", err)
	}
}
