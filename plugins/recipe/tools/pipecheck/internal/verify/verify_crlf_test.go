package verify

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// CRLF로 체크아웃된 재료·하위 워크플로(SKILL.md·graph.json)도 LF 원본으로
// 기록한 해시와 대조해 통과한다(#666).
func TestCRLFCheckoutPasses(t *testing.T) {
	proj := t.TempDir()
	lc, lb := put(t, proj, "leaf", skill("leaf"), "")
	subGraph := "{\n  \"name\": \"sub\",\n  \"in\": {}, \"out\": {}, \"nodes\": [], \"edges\": [],\n  \"materials\": [" + mat("leaf", "project", lc, lb) + "]\n}\n"
	sc, sb := put(t, proj, "sub", skill("sub"), subGraph)

	crlf := func(rel string) {
		p := filepath.Join(proj, rel)
		b, err := os.ReadFile(p)
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(strings.ReplaceAll(string(b), "\n", "\r\n")), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	crlf(filepath.Join("leaf", "SKILL.md"))
	crlf(filepath.Join("sub", "SKILL.md"))
	crlf(filepath.Join("sub", "graph.json"))

	g := graphWith("top", mat("sub", "project", sc, sb))
	r, err := Run([]byte(strings.ReplaceAll(g, "\n", "\r\n")), Options{ProjectDir: proj})
	if err != nil {
		t.Fatal(err)
	}
	if !r.Pass {
		t.Fatalf("CRLF checkout must pass: %v", r.Failures)
	}
}
