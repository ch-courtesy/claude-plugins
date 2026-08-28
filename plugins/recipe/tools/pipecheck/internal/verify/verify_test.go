package verify

// §9.1-1 실행 전 재귀 대조 배터리 — 등장마다 대조·경로 보고·종별 오류.

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/hash"
)

const plain = `---
name: NAME
description: d
node:
  in:
    x: { shape: text }
  out:
    y: { shape: text }
---

## 입력
- ` + "`x`" + ` — i

## 실행
e

## 출력
- ` + "`y`" + ` — o
`

func put(t *testing.T, root, name, md, graph string) (string, string) {
	t.Helper()
	dir := filepath.Join(root, name)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "SKILL.md"), []byte(md), 0o644); err != nil {
		t.Fatal(err)
	}
	var g []byte
	if graph != "" {
		g = []byte(graph)
		if err := os.WriteFile(filepath.Join(dir, "graph.json"), g, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	c, b, err := hash.SkillHashes([]byte(md), g)
	if err != nil {
		t.Fatal(err)
	}
	return c, b
}

func skill(name string) string { return strings.Replace(plain, "NAME", name, 1) }

func graphWith(name, mats string) string {
	return `{"name":"` + name + `","in":{},"out":{},"nodes":[],"edges":[],"materials":[` + mats + `]}`
}

func mat(name, scope, c, b string) string {
	return `{"name":"` + name + `","scope":"` + scope + `","contract":"` + c + `","body":"` + b + `"}`
}

func TestFreshMaterialsPass(t *testing.T) {
	proj := t.TempDir()
	c, b := put(t, proj, "leaf", skill("leaf"), "")
	g := graphWith("top", mat("leaf", "project", c, b))
	r, err := Run([]byte(g), Options{ProjectDir: proj})
	if err != nil {
		t.Fatal(err)
	}
	if !r.Pass {
		t.Fatalf("fresh materials must pass: %v", r.Failures)
	}
}

func TestStaleContractWithPath(t *testing.T) {
	proj := t.TempDir()
	c, b := put(t, proj, "leaf", skill("leaf"), "")
	// 하위 워크플로 sub가 leaf를 낡은 해시로 기록
	subGraph := graphWith("sub", mat("leaf", "project", "sha256:old", b))
	sc, sb := put(t, proj, "sub", skill("sub"), subGraph)
	_ = c
	g := graphWith("top", mat("sub", "project", sc, sb))
	r, err := Run([]byte(g), Options{ProjectDir: proj})
	if err != nil {
		t.Fatal(err)
	}
	if r.Pass {
		t.Fatal("stale sub-material must fail")
	}
	joined := strings.Join(r.Failures, " | ")
	if !strings.Contains(joined, "top") || !strings.Contains(joined, "sub") || !strings.Contains(joined, "leaf") {
		t.Fatalf("failure must carry the path from top: %v", r.Failures)
	}
}

func TestOccurrencePerAppearance(t *testing.T) {
	proj := t.TempDir()
	_, b := put(t, proj, "leaf", skill("leaf"), "")
	// 두 하위가 각각 leaf를 낡게 기록 — 등장 각각 보고
	s1 := graphWith("s1", mat("leaf", "project", "sha256:o1", b))
	s2 := graphWith("s2", mat("leaf", "project", "sha256:o2", b))
	c1, b1 := put(t, proj, "s1", skill("s1"), s1)
	c2, b2 := put(t, proj, "s2", skill("s2"), s2)
	g := graphWith("top", mat("s1", "project", c1, b1)+","+mat("s2", "project", c2, b2))
	r, err := Run([]byte(g), Options{ProjectDir: proj})
	if err != nil {
		t.Fatal(err)
	}
	count := 0
	for _, f := range r.Failures {
		if strings.Contains(f, "leaf") {
			count++
		}
	}
	if count != 2 {
		t.Fatalf("stale leaf must be reported per appearance (2), got %d: %v", count, r.Failures)
	}
}

func TestCycleTerminates(t *testing.T) {
	proj := t.TempDir()
	// 손 편집 상호순환 — 대조는 등장마다, 하위 재귀는 방문 집합이 끊음
	aC, aB := put(t, proj, "a", skill("a"), graphWith("a", mat("b", "project", "x", "y")))
	bG := graphWith("b", mat("a", "project", aC, aB))
	bC, bB := put(t, proj, "b", skill("b"), bG)
	// a의 graph를 b 기록으로 갱신
	put(t, proj, "a", skill("a"), graphWith("a", mat("b", "project", bC, bB)))
	g := graphWith("top", mat("a", "project", "sha256:stale", "sha256:stale"))
	r, err := Run([]byte(g), Options{ProjectDir: proj})
	if err != nil {
		t.Fatal(err)
	}
	if r.Pass {
		t.Fatal("stale a must fail; and the run must terminate despite the cycle")
	}
}

func TestDualKindError(t *testing.T) {
	proj := t.TempDir()
	md := strings.Replace(skill("dual"), "description: d",
		"description: d\nwraps: { name: leaf, scope: project, contract: \"c\", body: \"b\" }", 1)
	put(t, proj, "leaf", skill("leaf"), "")
	dir := filepath.Join(proj, "dual")
	_ = os.MkdirAll(dir, 0o755)
	_ = os.WriteFile(filepath.Join(dir, "SKILL.md"), []byte(md), 0o644)
	_ = os.WriteFile(filepath.Join(dir, "graph.json"), []byte(graphWith("dual", "")), 0o644)
	g := graphWith("top", mat("dual", "project", "sha256:x", "sha256:y"))
	r, err := Run([]byte(g), Options{ProjectDir: proj})
	if err != nil {
		t.Fatal(err)
	}
	if r.Pass {
		t.Fatal("dual-kind material must fail")
	}
	if !strings.Contains(strings.Join(r.Failures, " "), "undecidable") {
		t.Fatalf("dual-kind must be named: %v", r.Failures)
	}
}

func TestBlockScalarDelimiterNotConfused(t *testing.T) {
	proj := t.TempDir()
	put(t, proj, "leaf", skill("leaf"), "")
	// description 블록 스칼라 안 "  ---"는 프론트매터 종료가 아니다 — wraps를 읽어야 한다.
	md := strings.Replace(skill("adapter"), "description: d",
		"description: |\n  ---\n  줄", 1)
	md = strings.Replace(md, "node:",
		"wraps: { name: leaf, scope: project, contract: \"sha256:stale\", body: \"b\" }\nnode:", 1)
	dir := filepath.Join(proj, "adapter")
	_ = os.MkdirAll(dir, 0o755)
	_ = os.WriteFile(filepath.Join(dir, "SKILL.md"), []byte(md), 0o644)
	c, b, err := hash.SkillHashes([]byte(md), nil)
	if err != nil {
		t.Fatal(err)
	}
	g := graphWith("top", mat("adapter", "project", c, b))
	r, err := Run([]byte(g), Options{ProjectDir: proj})
	if err != nil {
		t.Fatal(err)
	}
	if r.Pass {
		t.Fatal("stale wraps behind a block-scalar --- must be detected")
	}
}
