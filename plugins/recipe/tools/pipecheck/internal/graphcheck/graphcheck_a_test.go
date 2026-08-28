package graphcheck

// §8 배터리 조각 A — 파싱·스키마·재료·구조. 각 케이스는 §12 G1의 최소 그래프.

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// 유효 기저 그래프: scan(list-files) → graph.out. 재료는 설치 디렉터리에 실재.
const baseGraph = `{
  "name": "scan-repo",
  "in":  { "dir": { "shape": "text" } },
  "out": { "paths": { "shape": "text", "list": 1 } },
  "nodes": [
    { "id": "scan", "kind": "node", "skill": "list-files" }
  ],
  "edges": [
    { "from": "graph.in.dir", "to": "scan.in.dir" },
    { "from": "scan.out.paths", "to": "graph.out.paths" }
  ],
  "materials": [
    { "name": "list-files", "scope": "project", "contract": "CONTRACT", "body": "BODY" }
  ]
}`

const listFilesSkill = `---
name: list-files
description: 디렉터리의 파일 목록을 낸다
node:
  in:
    dir: { shape: text }
  out:
    paths: { shape: text, list: 1 }
---

## 입력
- ` + "`dir`" + ` — 대상

## 실행
ls를 돌린다.

## 출력
- ` + "`paths`" + ` — 목록
`

func install(t *testing.T, root, name, md string, graph string) {
	t.Helper()
	dir := filepath.Join(root, name)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "SKILL.md"), []byte(md), 0o644); err != nil {
		t.Fatal(err)
	}
	if graph != "" {
		if err := os.WriteFile(filepath.Join(dir, "graph.json"), []byte(graph), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

// setupA는 list-files가 설치된 project 루트와, 해시가 채워진 유효 그래프를 돌려준다.
func setupA(t *testing.T) (Options, string) {
	t.Helper()
	proj := t.TempDir()
	install(t, proj, "list-files", listFilesSkill, "")
	c, b := skillHashes(t, listFilesSkill)
	g := strings.ReplaceAll(baseGraph, "CONTRACT", c)
	g = strings.ReplaceAll(g, "BODY", b)
	return Options{ProjectDir: proj, SelfName: "scan-repo", SelfScope: "project"}, g
}

func checkA(t *testing.T, opts Options, graph string) Result {
	t.Helper()
	r, err := Check([]byte(graph), opts)
	if err != nil {
		t.Fatal(err)
	}
	return r
}

func wantFailA(t *testing.T, opts Options, graph, substr string) {
	t.Helper()
	r := checkA(t, opts, graph)
	if r.Pass {
		t.Fatalf("expected failure containing %q, got pass", substr)
	}
	if !strings.Contains(strings.Join(r.Failures, " | "), substr) {
		t.Fatalf("failures %v do not mention %q", r.Failures, substr)
	}
}

func TestValidGraphPasses(t *testing.T) {
	opts, g := setupA(t)
	r := checkA(t, opts, g)
	if !r.Pass {
		t.Fatalf("valid graph failed: %v", r.Failures)
	}
}

func TestTopLevelSchema(t *testing.T) {
	opts, g := setupA(t)
	wantFailA(t, opts, strings.Replace(g, `"name": "scan-repo"`, `"name": "scan-repo", "extra": 1`, 1), "key")
	wantFailA(t, opts, strings.Replace(g, `"name": "scan-repo"`, `"name": ""`, 1), "name")
	wantFailA(t, opts, strings.Replace(g, `"nodes": [`, `"nodes": "x", "was": [`, 1), "nodes")
	// 중복 키
	wantFailA(t, opts, strings.Replace(g, `"name": "scan-repo",`, `"name": "scan-repo", "name": "twice",`, 1), "duplicate")
	// materials 항목 폐쇄·scope 열거
	wantFailA(t, opts, strings.Replace(g, `"scope": "project"`, `"scope": "../../x"`, 1), "scope")
	wantFailA(t, opts, strings.Replace(g, `"contract": "`, `"note": 1, "contract": "`, 1), "key")
}

func TestComponentRules(t *testing.T) {
	opts, g := setupA(t)
	// id 규칙·유일·graph 금지
	wantFailA(t, opts, strings.Replace(g, `"id": "scan"`, `"id": "graph"`, 1), "id")
	wantFailA(t, opts, strings.Replace(g, `"id": "scan"`, `"id": "9scan"`, 1), "id")
	// kind 열거
	wantFailA(t, opts, strings.Replace(g, `"kind": "node"`, `"kind": "widget"`, 1), "kind")
	// 필드 폐쇄: 노드에 expr
	wantFailA(t, opts, strings.Replace(g, `"kind": "node", "skill": "list-files"`, `"kind": "node", "skill": "list-files", "until": "x"`, 1), "field")
}

func TestMaterialRules(t *testing.T) {
	opts, g := setupA(t)
	// 미등재 skill 참조
	wantFailA(t, opts, strings.Replace(g, `"skill": "list-files"`, `"skill": "ghost"`, 1), "materials")
	// 안 쓰는 재료 등재(역성립)
	extra := strings.Replace(g, `{ "name": "list-files", "scope": "project", "contract": "`,
		`{ "name": "unused", "scope": "project", "contract": "x", "body": "y" },
    { "name": "list-files", "scope": "project", "contract": "`, 1)
	wantFailA(t, opts, extra, "unused")
	// 재료 미실재
	opts2 := opts
	opts2.ProjectDir = filepath.Join(opts.ProjectDir, "empty")
	wantFailA(t, opts2, g, "exist")
	// 자기 재료(직접): scan-repo가 자기 자신을 재료로
	self := strings.ReplaceAll(g, "list-files", "scan-repo")
	wantFailA(t, opts, self, "self")
}

func TestStructureRules(t *testing.T) {
	opts, g := setupA(t)
	// 아무 데도 안 닿는 구성 요소(둘 이상일 때)
	orphan := strings.Replace(g, `{ "id": "scan", "kind": "node", "skill": "list-files" }`,
		`{ "id": "scan", "kind": "node", "skill": "list-files" },
    { "id": "dead", "kind": "node", "skill": "list-files" }`, 1)
	orphan = strings.Replace(orphan, `{ "from": "graph.in.dir", "to": "scan.in.dir" }`,
		`{ "from": "graph.in.dir", "to": "scan.in.dir" },
    { "from": "graph.in.dir", "to": "dead.in.dir" }`, 1)
	wantFailA(t, opts, orphan, "reach")
	// 유일 구성 요소 예외 — 경계 출력 없어도 하나뿐이면 통과
	sole := `{
  "name": "clean-repo",
  "in":  { "dir": { "shape": "text" } },
  "out": {},
  "nodes": [ { "id": "c", "kind": "node", "skill": "list-files" } ],
  "edges": [ { "from": "graph.in.dir", "to": "c.in.dir" } ],
  "materials": [ { "name": "list-files", "scope": "project", "contract": "CONTRACT", "body": "BODY" } ]
}`
	c, b := skillHashes(t, listFilesSkill)
	sole = strings.ReplaceAll(sole, "CONTRACT", c)
	sole = strings.ReplaceAll(sole, "BODY", b)
	soleOpts := opts
	soleOpts.SelfName = "clean-repo"
	r := checkA(t, soleOpts, sole)
	if !r.Pass {
		t.Fatalf("sole component graph must pass: %v", r.Failures)
	}
	// order 사이클
	cyc := strings.Replace(orphan, `{ "from": "graph.in.dir", "to": "dead.in.dir" }`,
		`{ "from": "graph.in.dir", "to": "dead.in.dir" },
    { "kind": "order", "from": "scan", "to": "dead" },
    { "kind": "order", "from": "dead", "to": "scan" }`, 1)
	wantFailA(t, opts, cyc, "cycle")
	// 미소비 경계 입력
	unused := strings.Replace(g, `"in":  { "dir": { "shape": "text" } }`,
		`"in":  { "dir": { "shape": "text" }, "ghost": { "shape": "text" } }`, 1)
	wantFailA(t, opts, unused, "boundary input")
}
