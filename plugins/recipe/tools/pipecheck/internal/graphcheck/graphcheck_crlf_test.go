package graphcheck

import (
	"strings"
	"testing"
)

// CRLF로 체크아웃된 재료도 LF 원본으로 기록한 해시와 같게 판정한다(#666).
func TestCRLFMaterialPasses(t *testing.T) {
	proj := t.TempDir()
	install(t, proj, "list-files", strings.ReplaceAll(listFilesSkill, "\n", "\r\n"), "")
	c, b := skillHashes(t, listFilesSkill)
	g := strings.ReplaceAll(baseGraph, "CONTRACT", c)
	g = strings.ReplaceAll(g, "BODY", b)
	opts := Options{ProjectDir: proj, SelfName: "scan-repo", SelfScope: "project"}
	if r := checkA(t, opts, g); !r.Pass {
		t.Fatalf("CRLF material must pass: %v", r.Failures)
	}
}
