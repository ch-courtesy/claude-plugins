package graphcheck

// §8 배터리 조각 B1 — 재료 계약 로딩·포트 파생·배선 대조·상수·팬인·aligned.

import (
	"strings"
	"testing"
)

const reviewFileSkill = `---
name: review-file
description: 파일 하나를 리뷰한다
node:
  in:
    path: { shape: text }
    focus: { shape: text }
  out:
    findings: { shape: json, list: 1, required: false }
    messages: { shape: text, list: 1, required: false, aligned: findings }
    verdict: { shape: text, values: [clean, needs_fix] }
---

## 입력
- ` + "`path`" + ` — 대상
- ` + "`focus`" + ` — 관점

## 실행
리뷰한다.

## 출력
- ` + "`findings`" + ` — 발견
- ` + "`messages`" + ` — 메시지
- ` + "`verdict`" + ` — 판정
`

// 컨테이너·배선이 있는 유효 그래프.
const wiredGraph = `{
  "name": "audit-repo",
  "in":  { "dir": { "shape": "text" } },
  "out": { "verdicts": { "shape": "text", "list": 1 } },
  "nodes": [
    { "id": "scan", "kind": "node", "skill": "list-files" },
    { "id": "review", "kind": "container", "rule": "items", "skill": "review-file",
      "split": ["path"], "expose": ["verdict"],
      "const": { "focus": "security" } }
  ],
  "edges": [
    { "from": "graph.in.dir", "to": "scan.in.dir" },
    { "from": "scan.out.paths", "to": "review.in.path" },
    { "from": "review.out.verdict", "to": "graph.out.verdicts" }
  ],
  "materials": [
    { "name": "list-files", "scope": "project", "contract": "LF_C", "body": "LF_B" },
    { "name": "review-file", "scope": "project", "contract": "RF_C", "body": "RF_B" }
  ]
}`

func setupB(t *testing.T) (Options, string) {
	t.Helper()
	proj := t.TempDir()
	install(t, proj, "list-files", listFilesSkill, "")
	install(t, proj, "review-file", reviewFileSkill, "")
	lc, lb := skillHashes(t, listFilesSkill)
	rc, rb := skillHashes(t, reviewFileSkill)
	g := strings.NewReplacer("LF_C", lc, "LF_B", lb, "RF_C", rc, "RF_B", rb).Replace(wiredGraph)
	return Options{ProjectDir: proj, SelfName: "audit-repo", SelfScope: "project"}, g
}

func TestOverlayMaterial(t *testing.T) {
	// 승인 전 임시 위치의 신규 재료 — 설치본 없이 overlay만으로 검사 통과(7.5 원본 취급).
	proj := t.TempDir()
	overlay := t.TempDir()
	install(t, proj, "list-files", listFilesSkill, "")
	install(t, overlay, "review-file", reviewFileSkill, "")
	lc, lb := skillHashes(t, listFilesSkill)
	rc, rb := skillHashes(t, reviewFileSkill)
	g := strings.NewReplacer("LF_C", lc, "LF_B", lb, "RF_C", rc, "RF_B", rb).Replace(wiredGraph)
	opts := Options{ProjectDir: proj, SelfName: "audit-repo", SelfScope: "project", OverlayDir: overlay}
	r := checkA(t, opts, g)
	if !r.Pass {
		t.Fatalf("overlay material must resolve: %v", r.Failures)
	}
	// overlay 없으면 실재 실패
	opts.OverlayDir = ""
	r2 := checkA(t, opts, g)
	if r2.Pass {
		t.Fatal("missing material must fail without overlay")
	}
}

func TestWiredGraphPasses(t *testing.T) {
	opts, g := setupB(t)
	r := checkA(t, opts, g)
	if !r.Pass {
		t.Fatalf("wired graph failed: %v", r.Failures)
	}
}

func TestPortExistence(t *testing.T) {
	opts, g := setupB(t)
	// 없는 출력 포트 참조
	wantFailA(t, opts, strings.Replace(g, `"from": "scan.out.paths"`, `"from": "scan.out.ghost"`, 1), "port")
	// 없는 입력 포트 참조
	wantFailA(t, opts, strings.Replace(g, `"to": "review.in.path"`, `"to": "review.in.ghost"`, 1), "port")
}

func TestShapeDepthMatch(t *testing.T) {
	opts, g := setupB(t)
	// scan.out.paths는 text list:1 — review.in.path는 split로 깊이 +1 = list:1 → 일치.
	// graph.out.verdicts를 num으로 바꾸면 shape 불일치.
	wantFailA(t, opts, strings.Replace(g, `"verdicts": { "shape": "text", "list": 1 }`, `"verdicts": { "shape": "num", "list": 1 }`, 1), "shape")
	// 깊이 불일치: graph.in.dir(text,0) → review.in.path(파생 후 list:1)
	wantFailA(t, opts, strings.Replace(g, `"from": "scan.out.paths", "to": "review.in.path"`, `"from": "graph.in.dir", "to": "review.in.path"`, 1), "depth")
}

func TestConstRules(t *testing.T) {
	opts, g := setupB(t)
	// 계약에 없는 포트로 const
	wantFailA(t, opts, strings.Replace(g, `"const": { "focus": "security" }`, `"const": { "ghost": "x" }`, 1), "const")
	// 상수와 엣지 동시
	both := strings.Replace(g, `{ "from": "scan.out.paths", "to": "review.in.path" }`,
		`{ "from": "scan.out.paths", "to": "review.in.path" },
    { "from": "graph.in.dir", "to": "review.in.focus" }`, 1)
	wantFailA(t, opts, both, "const")
	// values 있는 포트에 열거 밖 상수 — verdict 재료를 소비하는 노드가 없으니 review-file의 focus에 values를 더한 변형으로 본다
	proj2 := opts.ProjectDir
	install(t, proj2, "review-file", strings.Replace(reviewFileSkill, "focus: { shape: text }", "focus: { shape: text, values: [security, style] }", 1), "")
	rc, rb := skillHashes(t, strings.Replace(reviewFileSkill, "focus: { shape: text }", "focus: { shape: text, values: [security, style] }", 1))
	g2 := g
	// 재료 해시 갱신
	oldC, oldB := skillHashes(t, reviewFileSkill)
	g2 = strings.Replace(g2, oldC, rc, 1)
	g2 = strings.Replace(g2, oldB, rb, 1)
	ok := strings.Replace(g2, `"const": { "focus": "security" }`, `"const": { "focus": "style" }`, 1)
	r := checkA(t, opts, ok)
	if !r.Pass {
		t.Fatalf("in-enum const must pass: %v", r.Failures)
	}
	bad := strings.Replace(g2, `"const": { "focus": "security" }`, `"const": { "focus": "speed" }`, 1)
	wantFailA(t, opts, bad, "values")
}

func TestRequiredInputsWired(t *testing.T) {
	opts, g := setupB(t)
	// focus 상수 제거 — 필수 입력 미배선
	wantFailA(t, opts, strings.Replace(g, `,
      "const": { "focus": "security" }`, "", 1), "required")
}

func TestFanIn(t *testing.T) {
	opts, g := setupB(t)
	// 깊이 0 포트에 팬인 — scan.in.dir에 엣지 둘
	fan := strings.Replace(g, `{ "from": "graph.in.dir", "to": "scan.in.dir" }`,
		`{ "from": "graph.in.dir", "to": "scan.in.dir" },
    { "from": "graph.in.dir", "to": "scan.in.dir" }`, 1)
	wantFailA(t, opts, fan, "fan-in")
}

func TestAlignedWiring(t *testing.T) {
	opts, g := setupB(t)
	// findings·messages(aligned 짝)를 노출하고 한쪽만 하류로 — 짝 규칙 위반.
	half := strings.Replace(g, `"expose": ["verdict"]`, `"expose": ["verdict", "findings", "messages"]`, 1)
	half = strings.Replace(half, `{ "from": "review.out.verdict", "to": "graph.out.verdicts" }`,
		`{ "from": "review.out.verdict", "to": "graph.out.verdicts" },
    { "from": "review.out.findings", "to": "graph.out.found" }`, 1)
	half = strings.Replace(half, `"out": { "verdicts": { "shape": "text", "list": 1 } }`,
		`"out": { "verdicts": { "shape": "text", "list": 1 }, "found": { "shape": "json", "list": 2, "required": false } }`, 1)
	wantFailA(t, opts, half, "aligned")
}

func TestContainerDerivation(t *testing.T) {
	opts, g := setupB(t)
	// split 이름이 내부 계약에 없음
	wantFailA(t, opts, strings.Replace(g, `"split": ["path"]`, `"split": ["ghost"]`, 1), "split")
	// expose 이름이 내부 출력에 없음
	wantFailA(t, opts, strings.Replace(g, `"expose": ["verdict"]`, `"expose": ["ghost"]`, 1), "expose")
	// split 둘인데 combine 없음
	two := strings.Replace(g, `"split": ["path"]`, `"split": ["path", "focus"]`, 1)
	two = strings.Replace(two, `,
      "const": { "focus": "security" }`, "", 1)
	two = strings.Replace(two, `{ "from": "scan.out.paths", "to": "review.in.path" }`,
		`{ "from": "scan.out.paths", "to": "review.in.path" },
    { "from": "scan.out.paths", "to": "review.in.focus" }`, 1)
	wantFailA(t, opts, two, "combine")
	// split 하나인데 combine 명시
	one := strings.Replace(g, `"split": ["path"]`, `"split": ["path"], "combine": "zip"`, 1)
	wantFailA(t, opts, one, "combine")
}
