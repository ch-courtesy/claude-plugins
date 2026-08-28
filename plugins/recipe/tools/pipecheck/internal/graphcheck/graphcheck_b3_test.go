package graphcheck

// §8 배터리 조각 B3 — impl-r2 리뷰 반례 13건.

import (
	"strings"
	"testing"
)

func TestEdgeDirection(t *testing.T) {
	opts, g := setupA(t)
	wantFailA(t, opts, strings.Replace(g, `"from": "graph.in.dir"`, `"from": "graph.out.dir"`, 1), "direction")
	wantFailA(t, opts, strings.Replace(g, `"to": "scan.in.dir"`, `"to": "scan.out.dir"`, 1), "direction")
}

func TestEdgeFieldClosure(t *testing.T) {
	opts, g := setupA(t)
	wantFailA(t, opts, strings.Replace(g, `{ "from": "graph.in.dir", "to": "scan.in.dir" }`,
		`{ "from": "graph.in.dir", "to": "scan.in.dir", "expr": "true" }`, 1), "field")
}

func TestMaterialRequiredKeys(t *testing.T) {
	opts, g := setupA(t)
	noBody := strings.Replace(g, `, "body": "`, `, "was": "`, 1)
	wantFailA(t, opts, noBody, "body")
}

const alignedInnerSkill = `---
name: pairin
description: 짝 입력
node:
  in:
    a: { shape: text, list: 1, aligned: b }
    b: { shape: text, list: 1 }
  out:
    r: { shape: text }
---

## 입력
- ` + "`a`" + ` — 하나
- ` + "`b`" + ` — 둘

## 실행
e

## 출력
- ` + "`r`" + ` — 결과
`

func setupPair(t *testing.T) (Options, string, string) {
	t.Helper()
	proj := t.TempDir()
	install(t, proj, "pairin", alignedInnerSkill, "")
	c, b := skillHashes(t, alignedInnerSkill)
	return Options{ProjectDir: proj, SelfName: "w", SelfScope: "project"}, c, b
}

func TestAlignedSplitTogether(t *testing.T) {
	opts, c, b := setupPair(t)
	// 짝의 한쪽만 split — 거부
	g := `{
  "name": "w",
  "in": { "xa": { "shape": "text", "list": 2 }, "xb": { "shape": "text", "list": 1 } },
  "out": { "r": { "shape": "text", "list": 1 } },
  "nodes": [ { "id": "p", "kind": "container", "rule": "items", "skill": "pairin",
    "split": ["a"], "expose": ["r"] } ],
  "edges": [
    { "from": "graph.in.xa", "to": "p.in.a" },
    { "from": "graph.in.xb", "to": "p.in.b" },
    { "from": "p.out.r", "to": "graph.out.r" }
  ],
  "materials": [ { "name": "pairin", "scope": "project", "contract": "C", "body": "B" } ]
}`
	g = strings.NewReplacer("C", c, "B", b).Replace(g)
	wantFailA(t, opts, g, "split")
	// 둘 다 split인데 combine=product — 거부(zip만)
	g2 := strings.Replace(g, `"split": ["a"]`, `"split": ["a", "b"], "combine": "product"`, 1)
	g2 = strings.Replace(g2, `"xb": { "shape": "text", "list": 1 }`, `"xb": { "shape": "text", "list": 2 }`, 1)
	wantFailA(t, opts, g2, "zip")
}

func TestSplitKeepsRequired(t *testing.T) {
	// split 포트의 required는 물려받는다 — 선택 입력 미배선 통과.
	proj := t.TempDir()
	optIn := strings.Replace(listFilesSkill, "dir: { shape: text }", "dir: { shape: text, list: 1, required: false }", 1)
	install(t, proj, "list-files", optIn, "")
	c, b := skillHashes(t, optIn)
	g := `{
  "name": "w",
  "in": {},
  "out": { "paths": { "shape": "text", "list": 2 } },
  "nodes": [ { "id": "s", "kind": "container", "rule": "items", "skill": "list-files",
    "split": ["dir"], "expose": ["paths"] } ],
  "edges": [ { "from": "s.out.paths", "to": "graph.out.paths" } ],
  "materials": [ { "name": "list-files", "scope": "project", "contract": "C", "body": "B" } ]
}`
	g = strings.NewReplacer("C", c, "B", b).Replace(g)
	r := checkA(t, Options{ProjectDir: proj, SelfName: "w", SelfScope: "project"}, g)
	if !r.Pass {
		t.Fatalf("optional split input may stay unwired: %v", r.Failures)
	}
}

func TestConstLeafAndMixedDepth(t *testing.T) {
	opts, g := setupB(t)
	proj := opts.ProjectDir
	enum := strings.Replace(reviewFileSkill, "focus: { shape: text }", "focus: { shape: text, list: 1, values: [security, style] }", 1)
	install(t, proj, "review-file", enum, "")
	rc, rb := skillHashes(t, enum)
	oc, ob := skillHashes(t, reviewFileSkill)
	g = strings.Replace(g, oc, rc, 1)
	g = strings.Replace(g, ob, rb, 1)
	// 혼합 깊이 배열 상수
	wantFailA(t, opts, strings.Replace(g, `"const": { "focus": "security" }`,
		`"const": { "focus": ["security", ["style"]] }`, 1), "depth")
	// 두 번째 리프가 열거 밖
	wantFailA(t, opts, strings.Replace(g, `"const": { "focus": "security" }`,
		`"const": { "focus": ["security", "speed"] }`, 1), "values")
	// text 포트에 객체 상수
	wantFailA(t, opts, strings.Replace(g, `"const": { "focus": "security" }`,
		`"const": { "focus": [{"x": 1}] }`, 1), "shape")
}

func TestAlignedBothConstLength(t *testing.T) {
	opts, c, b := setupPair(t)
	g := `{
  "name": "w",
  "in": {},
  "out": { "r": { "shape": "text" } },
  "nodes": [ { "id": "p", "kind": "node", "skill": "pairin",
    "const": { "a": ["x"], "b": ["x", "y"] } } ],
  "edges": [ { "from": "p.out.r", "to": "graph.out.r" } ],
  "materials": [ { "name": "pairin", "scope": "project", "contract": "C", "body": "B" } ]
}`
	g = strings.NewReplacer("C", c, "B", b).Replace(g)
	wantFailA(t, opts, g, "length")
}

const alignedOutSkill = `---
name: pairout
description: 짝 출력
node:
  in:
    x: { shape: text }
  out:
    a: { shape: text, list: 1, aligned: b }
    b: { shape: text, list: 1 }
---

## 입력
- ` + "`x`" + ` — 입력

## 실행
e

## 출력
- ` + "`a`" + ` — 하나
- ` + "`b`" + ` — 둘
`

func TestPairFanInToBoundary(t *testing.T) {
	proj := t.TempDir()
	install(t, proj, "pairout", alignedOutSkill, "")
	c, b := skillHashes(t, alignedOutSkill)
	g := `{
  "name": "w",
  "in": { "x": { "shape": "text" } },
  "out": { "m": { "shape": "text", "list": 1 } },
  "nodes": [ { "id": "p", "kind": "node", "skill": "pairout" } ],
  "edges": [
    { "from": "graph.in.x", "to": "p.in.x" },
    { "from": "p.out.a", "to": "graph.out.m" },
    { "from": "p.out.b", "to": "graph.out.m" }
  ],
  "materials": [ { "name": "pairout", "scope": "project", "contract": "C", "body": "B" } ]
}`
	g = strings.NewReplacer("C", c, "B", b).Replace(g)
	wantFailA(t, Options{ProjectDir: proj, SelfName: "w", SelfScope: "project"}, g, "fan-in")
}

func TestZipArgFanIn(t *testing.T) {
	opts, _ := setupT(t)
	base := strings.Replace(transformGraphResolved(t, opts),
		`"expr": "size(paths.filter(x, x != '')) == 0.0 || paths.flatten() == paths.flatten()"`,
		`"expr": "zip(paths, paths)"`, 1)
	base = strings.Replace(base, `"out": { "few": { "shape": "bool" } }`, `"out": { "few": { "shape": "json", "list": 1 } }`, 1)
	fan := strings.Replace(base, `{ "from": "scan.out.paths", "to": "pick.in.paths" }`,
		`{ "from": "scan.out.paths", "to": "pick.in.paths" },
    { "from": "scan.out.paths", "to": "pick.in.paths" }`, 1)
	wantFailA(t, opts, fan, "zip")
}

func TestCarryAlignedTogether(t *testing.T) {
	proj := t.TempDir()
	inner := `---
name: stepper
description: 회차
node:
  in:
    cur_a: { shape: text, list: 1, aligned: cur_b }
    cur_b: { shape: text, list: 1 }
  out:
    next_a: { shape: text, list: 1, aligned: next_b }
    next_b: { shape: text, list: 1 }
    done: { shape: bool }
---

## 입력
- ` + "`cur_a`" + ` — 하나
- ` + "`cur_b`" + ` — 둘

## 실행
e

## 출력
- ` + "`next_a`" + ` — 하나
- ` + "`next_b`" + ` — 둘
- ` + "`done`" + ` — 끝
`
	install(t, proj, "stepper", inner, "")
	c, b := skillHashes(t, inner)
	g := `{
  "name": "w",
  "in": {},
  "out": { "r": { "shape": "text", "list": 1 } },
  "nodes": [ { "id": "st", "kind": "container", "rule": "condition", "skill": "stepper",
    "expose": ["next_a", "next_b"],
    "const": { "cur_a": ["x"], "cur_b": ["y"] },
    "until": "done", "max": 3,
    "carry": { "next_a": "cur_a" } } ],
  "edges": [
    { "from": "st.out.next_a", "to": "graph.out.r" },
    { "from": "st.out.next_b", "to": "graph.out.rb" }
  ],
  "materials": [ { "name": "stepper", "scope": "project", "contract": "C", "body": "B" } ]
}`
	g = strings.Replace(g, `"out": { "r": { "shape": "text", "list": 1 } }`,
		`"out": { "r": { "shape": "text", "list": 1 }, "rb": { "shape": "text", "list": 1 } }`, 1)
	g = strings.NewReplacer("C", c, "B", b).Replace(g)
	wantFailA(t, Options{ProjectDir: proj, SelfName: "w", SelfScope: "project"}, g, "carry")
}

func TestUntilValuesLiteral(t *testing.T) {
	opts, _ := setupB(t)
	proj := opts.ProjectDir
	fixDraft := `---
name: fix-draft
description: 고친다
node:
  in:
    spec: { shape: text }
    draft: { shape: text }
  out:
    draft: { shape: text }
    verdict: { shape: text, values: [clean, needs_fix] }
---

## 입력
- ` + "`spec`" + ` — 지시
- ` + "`draft`" + ` — 이전 초안

## 실행
고친다.

## 출력
- ` + "`draft`" + ` — 새 초안
- ` + "`verdict`" + ` — 판정
`
	install(t, proj, "fix-draft", fixDraft, "")
	fc, fb := skillHashes(t, fixDraft)
	g := `{
  "name": "fix-loop",
  "in":  { "spec": { "shape": "text" } },
  "out": { "final": { "shape": "text" } },
  "nodes": [
    { "id": "fix", "kind": "container", "rule": "condition", "skill": "fix-draft",
      "expose": ["draft"],
      "const": { "draft": "" },
      "until": "verdict == 'bogus'",
      "max": 5,
      "carry": { "draft": "draft" } }
  ],
  "edges": [
    { "from": "graph.in.spec", "to": "fix.in.spec" },
    { "from": "fix.out.draft", "to": "graph.out.final" }
  ],
  "materials": [ { "name": "fix-draft", "scope": "project", "contract": "FC", "body": "FB" } ]
}`
	g = strings.NewReplacer("FC", fc, "FB", fb).Replace(g)
	sopts := opts
	sopts.SelfName = "fix-loop"
	wantFailA(t, sopts, g, "values")
}

func TestChunkFoldedLiteral(t *testing.T) {
	opts, _ := setupT(t)
	base := strings.Replace(transformGraphResolved(t, opts),
		`"expr": "size(paths.filter(x, x != '')) == 0.0 || paths.flatten() == paths.flatten()"`,
		`"expr": "chunk(paths, 1.0 - 1.0)"`, 1)
	base = strings.Replace(base, `"out": { "few": { "shape": "bool" } }`, `"out": { "few": { "shape": "text", "list": 2 } }`, 1)
	wantFailA(t, opts, base, "chunk")
}

func TestTransformInputPortName(t *testing.T) {
	opts, _ := setupT(t)
	base := strings.Replace(transformGraphResolved(t, opts),
		`"expr": "size(paths.filter(x, x != '')) == 0.0 || paths.flatten() == paths.flatten()"`,
		`"expr": "size(Bad) == 0"`, 1)
	base = strings.Replace(base, `"to": "pick.in.paths"`, `"to": "pick.in.Bad"`, 1)
	wantFailA(t, opts, base, "port name")
}

func TestTransformValuesPropagation(t *testing.T) {
	opts, _ := setupB(t)
	// review.out.verdict(values)를 transform이 그대로 통과 — 하류 좁은 열거는 거부, 넓은 열거는 통과.
	g := transformValuesGraph(t, opts)
	r := checkA(t, opts, g)
	if !r.Pass {
		t.Fatalf("passthrough values graph must pass: %v", r.Failures)
	}
	narrow := strings.Replace(g, `"values": ["clean", "needs_fix", "skip"]`, `"values": ["clean"]`, 1)
	wantFailA(t, opts, narrow, "values")
}

func transformValuesGraph(t *testing.T, opts Options) string {
	t.Helper()
	lc, lb := skillHashes(t, listFilesSkill)
	rc, rb := skillHashes(t, reviewFileSkill)
	g := `{
  "name": "audit-repo",
  "in":  { "dir": { "shape": "text" } },
  "out": { "vs": { "shape": "text", "list": 1, "values": ["clean", "needs_fix", "skip"] } },
  "nodes": [
    { "id": "scan", "kind": "node", "skill": "list-files" },
    { "id": "review", "kind": "container", "rule": "items", "skill": "review-file",
      "split": ["path"], "expose": ["verdict"], "const": { "focus": "security" } },
    { "id": "keep", "kind": "transform",
      "out": { "kept": { "expr": "vs_in.filter(v, v != '')" } } }
  ],
  "edges": [
    { "from": "graph.in.dir", "to": "scan.in.dir" },
    { "from": "scan.out.paths", "to": "review.in.path" },
    { "from": "review.out.verdict", "to": "keep.in.vs_in" },
    { "from": "keep.out.kept", "to": "graph.out.vs" }
  ],
  "materials": [
    { "name": "list-files", "scope": "project", "contract": "LF_C", "body": "LF_B" },
    { "name": "review-file", "scope": "project", "contract": "RF_C", "body": "RF_B" }
  ]
}`
	return strings.NewReplacer("LF_C", lc, "LF_B", lb, "RF_C", rc, "RF_B", rb).Replace(g)
}
