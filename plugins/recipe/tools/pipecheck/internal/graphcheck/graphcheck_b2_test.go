package graphcheck

// §8 배터리 조각 B2 — transform 파생·표현식 연동·until·max·carry·values 포섭.

import (
	"strings"
	"testing"
)

// transform이 낀 유효 그래프: scan → pick(개수 문턱) → graph.out
const transformGraph = `{
  "name": "count-repo",
  "in":  { "dir": { "shape": "text" } },
  "out": { "few": { "shape": "bool" } },
  "nodes": [
    { "id": "scan", "kind": "node", "skill": "list-files" },
    { "id": "pick", "kind": "transform",
      "out": { "few": { "expr": "size(paths.filter(x, x != '')) == 0.0 || paths.flatten() == paths.flatten()" } } }
  ],
  "edges": [
    { "from": "graph.in.dir", "to": "scan.in.dir" },
    { "from": "scan.out.paths", "to": "pick.in.paths" },
    { "from": "pick.out.few", "to": "graph.out.few" }
  ],
  "materials": [
    { "name": "list-files", "scope": "project", "contract": "LF_C", "body": "LF_B" }
  ]
}`

func setupT(t *testing.T) (Options, string) {
	t.Helper()
	proj := t.TempDir()
	install(t, proj, "list-files", listFilesSkill, "")
	lc, lb := skillHashes(t, listFilesSkill)
	g := strings.NewReplacer("LF_C", lc, "LF_B", lb).Replace(transformGraph)
	return Options{ProjectDir: proj, SelfName: "count-repo", SelfScope: "project"}, g
}

func TestTransformGraphSimple(t *testing.T) {
	opts, _ := setupT(t)
	// paths.flatten()은 text list:1에 안 맞음(list(list) 필요) — 단순화한 유효식으로 교체해 기저 확인
	g := strings.Replace(transformGraphResolved(t, opts), `"expr": "size(paths.filter(x, x != '')) == 0.0 || paths.flatten() == paths.flatten()"`,
		`"expr": "size(paths.filter(x, x != '')) == 0"`, 1)
	r := checkA(t, opts, g)
	if !r.Pass {
		t.Fatalf("transform graph failed: %v", r.Failures)
	}
}

func transformGraphResolved(t *testing.T, opts Options) string {
	t.Helper()
	lc, lb := skillHashes(t, listFilesSkill)
	return strings.NewReplacer("LF_C", lc, "LF_B", lb).Replace(transformGraph)
}

func TestTransformExprRejections(t *testing.T) {
	opts, _ := setupT(t)
	base := strings.Replace(transformGraphResolved(t, opts), `"expr": "size(paths.filter(x, x != '')) == 0.0 || paths.flatten() == paths.flatten()"`,
		`"expr": "size(paths.filter(x, x != '')) == 0"`, 1)
	// 체커 거부(피연산자 타입) — text 포트와 수 비교
	wantFailA(t, opts, strings.Replace(base, `size(paths.filter(x, x != '')) == 0`, `paths == 1.0`, 1), "expr")
	// 형변환 미해소
	wantFailA(t, opts, strings.Replace(base, `size(paths.filter(x, x != '')) == 0`, `int(size(paths)) == 0`, 1), "expr")
	// 참조 이름에 엣지 없음
	noEdge := strings.Replace(base, `{ "from": "scan.out.paths", "to": "pick.in.paths" },`, "", 1)
	wantFailA(t, opts, noEdge, "wired")
	// 출력 이름을 식이 참조
	selfRef := strings.Replace(base, `"out": { "few": { "expr": "size(paths.filter(x, x != '')) == 0" } }`,
		`"out": { "few": { "expr": "size(paths) == 0" }, "echo": { "expr": "few" } }`, 1)
	wantFailA(t, opts, selfRef, "output")
	// 입력과 출력 이름 겹침 (§5.5 깊이만 벗기는 출력도 이름을 달리)
	overlap := strings.Replace(base, `"out": { "few": { "expr": "size(paths.filter(x, x != '')) == 0" } }`,
		`"out": { "paths": { "expr": "paths.filter(x, x != '')" } }`, 1)
	overlap = strings.Replace(overlap, `{ "from": "pick.out.few", "to": "graph.out.few" }`,
		`{ "from": "pick.out.paths", "to": "graph.out.few" }`, 1)
	wantFailA(t, opts, overlap, "name")
	// 추론 shape와 하류 불일치: bool 경계에 text 배열
	mism := strings.Replace(base, `"expr": "size(paths.filter(x, x != '')) == 0"`, `"expr": "paths.filter(x, x != '')"`, 1)
	wantFailA(t, opts, mism, "shape")
}

func TestConditionContainer(t *testing.T) {
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
      "until": "verdict == 'clean'",
      "max": 5,
      "carry": { "draft": "draft" } }
  ],
  "edges": [
    { "from": "graph.in.spec", "to": "fix.in.spec" },
    { "from": "fix.out.draft", "to": "graph.out.final" }
  ],
  "materials": [
    { "name": "fix-draft", "scope": "project", "contract": "FC", "body": "FB" }
  ]
}`
	g = strings.NewReplacer("FC", fc, "FB", fb).Replace(g)
	sopts := opts
	sopts.SelfName = "fix-loop"
	r := checkA(t, sopts, g)
	if !r.Pass {
		t.Fatalf("condition container graph failed: %v", r.Failures)
	}
	// until이 bool이 아님
	wantFailA(t, sopts, strings.Replace(g, `"until": "verdict == 'clean'"`, `"until": "verdict"`, 1), "until")
	// until이 내부 출력 밖 이름 참조
	wantFailA(t, sopts, strings.Replace(g, `"until": "verdict == 'clean'"`, `"until": "ghost == 'x'"`, 1), "until")
	// max 0
	wantFailA(t, sopts, strings.Replace(g, `"max": 5`, `"max": 0`, 1), "max")
	// carry 키가 출력에 없음
	wantFailA(t, sopts, strings.Replace(g, `"carry": { "draft": "draft" }`, `"carry": { "ghost": "draft" }`, 1), "carry")
	// carry 값이 입력에 없음
	wantFailA(t, sopts, strings.Replace(g, `"carry": { "draft": "draft" }`, `"carry": { "draft": "ghost" }`, 1), "carry")
	// carry 값 중복 — verdict도 draft로 이월
	wantFailA(t, sopts, strings.Replace(g, `"carry": { "draft": "draft" }`, `"carry": { "draft": "draft", "verdict": "draft" }`, 1), "carry")
}

func TestValuesSubsumption(t *testing.T) {
	opts, g := setupB(t)
	// review.out.verdict(values: clean·needs_fix) → 경계 출력이 좁은 열거 선언 — 포섭 위반
	narrow := strings.Replace(g, `"verdicts": { "shape": "text", "list": 1 }`,
		`"verdicts": { "shape": "text", "list": 1, "values": ["clean"] }`, 1)
	wantFailA(t, opts, narrow, "values")
	// 넓은 열거 선언은 통과
	wide := strings.Replace(g, `"verdicts": { "shape": "text", "list": 1 }`,
		`"verdicts": { "shape": "text", "list": 1, "values": ["clean", "needs_fix", "skip"] }`, 1)
	r := checkA(t, opts, wide)
	if !r.Pass {
		t.Fatalf("wider values must pass: %v", r.Failures)
	}
	// from에 values 없는데 to가 선언
	bare := strings.Replace(g, `"out": { "verdicts": { "shape": "text", "list": 1 } }`,
		`"out": { "verdicts": { "shape": "text", "list": 1 }, "names": { "shape": "text", "list": 1, "values": ["a"] } }`, 1)
	bare = strings.Replace(bare, `{ "from": "review.out.verdict", "to": "graph.out.verdicts" }`,
		`{ "from": "review.out.verdict", "to": "graph.out.verdicts" },
    { "from": "scan.out.paths", "to": "graph.out.names" }`, 1)
	wantFailA(t, opts, bare, "values")
}
