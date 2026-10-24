package graphcheck

// wait 종류 — human(answer·approve·edit·task)·check 저작 규칙.

import (
	"strings"
	"testing"
)

const ciStatusSkill = `---
name: ci-status
description: CI 실행이 끝났는지 본다
node:
  in:
    run: { shape: text }
  out:
    done: { shape: bool }
    url: { shape: text }
---

## 입력
- ` + "`run`" + ` — 실행 id

## 실행
상태를 조회한다.

## 출력
- ` + "`done`" + ` — 끝났는지
- ` + "`url`" + ` — 결과 주소
`

// scan → gate(사람 승인) → graph.out
const humanGraph = `{
  "name": "gated-scan",
  "in":  { "dir": { "shape": "text" } },
  "out": { "ok": { "shape": "bool" }, "note": { "shape": "text" } },
  "nodes": [
    { "id": "scan", "kind": "node", "skill": "list-files" },
    { "id": "gate", "kind": "wait", "by": "human", "mode": "approve", "prompt": "이 목록으로 진행할까요?" }
  ],
  "edges": [
    { "from": "graph.in.dir", "to": "scan.in.dir" },
    { "from": "scan.out.paths", "to": "gate.in.paths" },
    { "from": "gate.out.approved", "to": "graph.out.ok" },
    { "from": "gate.out.note", "to": "graph.out.note" }
  ],
  "materials": [
    { "name": "list-files", "scope": "project", "contract": "LF_C", "body": "LF_B" }
  ]
}`

func setupW(t *testing.T) (Options, string) {
	t.Helper()
	proj := t.TempDir()
	install(t, proj, "list-files", listFilesSkill, "")
	install(t, proj, "ci-status", ciStatusSkill, "")
	lc, lb := skillHashes(t, listFilesSkill)
	g := strings.NewReplacer("LF_C", lc, "LF_B", lb).Replace(humanGraph)
	return Options{ProjectDir: proj, SelfName: "gated-scan", SelfScope: "project"}, g
}

func TestHumanApprovePasses(t *testing.T) {
	opts, g := setupW(t)
	if r := checkA(t, opts, g); !r.Pass {
		t.Fatalf("approve wait failed: %v", r.Failures)
	}
}

func TestHumanAnswerPasses(t *testing.T) {
	opts, g := setupW(t)
	g = strings.Replace(g, `"mode": "approve", "prompt": "이 목록으로 진행할까요?"`,
		`"mode": "answer", "prompt": "어느 쪽으로?", "answer": { "shape": "text", "values": ["fast", "full"] }`, 1)
	g = strings.Replace(g, `"out": { "ok": { "shape": "bool" }, "note": { "shape": "text" } }`,
		`"out": { "pick": { "shape": "text", "values": ["fast", "full"] } }`, 1)
	g = strings.Replace(g, `{ "from": "gate.out.approved", "to": "graph.out.ok" },
    { "from": "gate.out.note", "to": "graph.out.note" }`, `{ "from": "gate.out.answer", "to": "graph.out.pick" }`, 1)
	if r := checkA(t, opts, g); !r.Pass {
		t.Fatalf("answer wait failed: %v", r.Failures)
	}
	// answer 선언이 없으면 불통과
	wantFailA(t, opts, strings.Replace(g, `, "answer": { "shape": "text", "values": ["fast", "full"] }`, "", 1), "needs answer")
	// answer 선언의 허용 밖 필드
	wantFailA(t, opts, strings.Replace(g, `"answer": { "shape": "text", "values": ["fast", "full"] }`, `"answer": { "shape": "text", "values": ["fast", "full"], "aligned": "x" }`, 1), "not allowed")
	// answer 선언도 §3 포트 규칙을 따른다
	wantFailA(t, opts, strings.Replace(g, `"answer": { "shape": "text", "values": ["fast", "full"] }`, `"answer": { "shape": "date" }`, 1), "shape")
	// values 밖 값을 받는 경계 출력이면 포섭 불통과
	wantFailA(t, opts, strings.Replace(g, `"pick": { "shape": "text", "values": ["fast", "full"] }`, `"pick": { "shape": "text", "values": ["fast"] }`, 1), "subsumed")
}

func TestHumanEditPasses(t *testing.T) {
	opts, g := setupW(t)
	g = strings.Replace(g, `"mode": "approve"`, `"mode": "edit"`, 1)
	g = strings.Replace(g, `"out": { "ok": { "shape": "bool" }, "note": { "shape": "text" } }`,
		`"out": { "paths": { "shape": "text", "list": 1 } }`, 1)
	g = strings.Replace(g, `{ "from": "gate.out.approved", "to": "graph.out.ok" },
    { "from": "gate.out.note", "to": "graph.out.note" }`, `{ "from": "gate.out.edited", "to": "graph.out.paths" }`, 1)
	if r := checkA(t, opts, g); !r.Pass {
		t.Fatalf("edit wait failed: %v", r.Failures)
	}
	// 입력이 둘이면 불통과
	two := strings.Replace(g, `{ "from": "scan.out.paths", "to": "gate.in.paths" }`,
		`{ "from": "scan.out.paths", "to": "gate.in.paths" },
    { "from": "graph.in.dir", "to": "gate.in.dir" }`, 1)
	wantFailA(t, opts, two, "exactly one wired input")
	// 출력 깊이는 입력을 따른다 — 깊이 0 경계로 보내면 불통과
	wantFailA(t, opts, strings.Replace(g, `"paths": { "shape": "text", "list": 1 }`, `"paths": { "shape": "text" }`, 1), "depth")
}

func TestHumanTaskPasses(t *testing.T) {
	opts, g := setupW(t)
	g = strings.Replace(g, `"mode": "approve"`, `"mode": "task"`, 1)
	g = strings.Replace(g, `"out": { "ok": { "shape": "bool" }, "note": { "shape": "text" } }`, `"out": { "note": { "shape": "text" } }`, 1)
	g = strings.Replace(g, `{ "from": "gate.out.approved", "to": "graph.out.ok" },
    `, "", 1)
	if r := checkA(t, opts, g); !r.Pass {
		t.Fatalf("task wait failed: %v", r.Failures)
	}
}

func TestHumanWaitRejections(t *testing.T) {
	opts, g := setupW(t)
	wantFailA(t, opts, strings.Replace(g, `"by": "human"`, `"by": "robot"`, 1), "human|check")
	wantFailA(t, opts, strings.Replace(g, `"mode": "approve"`, `"mode": "vote"`, 1), "answer|approve|edit|task")
	wantFailA(t, opts, strings.Replace(g, `"prompt": "이 목록으로 진행할까요?"`, `"prompt": ""`, 1), "prompt")
	wantFailA(t, opts, strings.Replace(g, `, "prompt": "이 목록으로 진행할까요?"`, "", 1), "prompt")
	wantFailA(t, opts, strings.Replace(g, `"prompt": "이 목록으로 진행할까요?"`, `"prompt": "?", "answer": { "shape": "text" }`, 1), "only for mode: answer")
	// human에는 skill·const가 없다
	wantFailA(t, opts, strings.Replace(g, `"prompt": "이 목록으로 진행할까요?"`, `"prompt": "?", "const": { "x": "y" }`, 1), `field "const" is not allowed`)
	// 없는 출력 포트
	wantFailA(t, opts, strings.Replace(g, `"from": "gate.out.note"`, `"from": "gate.out.answer"`, 1), "port")
	// 입력과 출력 이름 충돌
	wantFailA(t, opts, strings.Replace(g, `"to": "gate.in.paths"`, `"to": "gate.in.note"`, 1), "share the name")
	// kind 오류 메시지가 wait을 안내한다
	wantFailA(t, opts, strings.Replace(g, `"kind": "wait"`, `"kind": "pause"`, 1), "node·transform·container·wait")
}

// scan과 나란히 CI를 기다린다: ci(check) → graph.out
func checkGraph(t *testing.T, opts Options) string {
	t.Helper()
	cc, cb := skillHashes(t, ciStatusSkill)
	return `{
  "name": "wait-ci",
  "in":  { "run": { "shape": "text" } },
  "out": { "url": { "shape": "text" } },
  "nodes": [
    { "id": "ci", "kind": "wait", "by": "check", "skill": "ci-status" }
  ],
  "edges": [
    { "from": "graph.in.run", "to": "ci.in.run" },
    { "from": "ci.out.url", "to": "graph.out.url" }
  ],
  "materials": [
    { "name": "ci-status", "scope": "project", "contract": "` + cc + `", "body": "` + cb + `" }
  ]
}`
}

func TestCheckWait(t *testing.T) {
	opts, _ := setupW(t)
	opts.SelfName = "wait-ci"
	g := checkGraph(t, opts)
	if r := checkA(t, opts, g); !r.Pass {
		t.Fatalf("check wait failed: %v", r.Failures)
	}
	// 재료는 materials에 있어야 한다
	wantFailA(t, opts, strings.Replace(g, `"skill": "ci-status"`, `"skill": "ghost"`, 1), "not in materials")
	// 상수는 노드와 같은 규칙
	constG := strings.Replace(g, `"skill": "ci-status" }`, `"skill": "ci-status", "const": { "run": "r1" } }`, 1)
	constG = strings.Replace(constG, `"in":  { "run": { "shape": "text" } }`, `"in":  {}`, 1)
	constG = strings.Replace(constG, `{ "from": "graph.in.run", "to": "ci.in.run" },
    `, "", 1)
	if r := checkA(t, opts, constG); !r.Pass {
		t.Fatalf("check wait with const failed: %v", r.Failures)
	}
	// check에는 prompt·mode가 없다
	wantFailA(t, opts, strings.Replace(g, `"skill": "ci-status" }`, `"skill": "ci-status", "prompt": "?" }`, 1), `field "prompt" is not allowed`)
	// done(bool)을 내지 않는 재료는 불통과
	lc, lb := skillHashes(t, listFilesSkill)
	cc, cb := skillHashes(t, ciStatusSkill)
	noDone := strings.NewReplacer(`"skill": "ci-status"`, `"skill": "list-files"`, `"name": "ci-status"`, `"name": "list-files"`,
		cc, lc, cb, lb, "ci.in.run", "ci.in.dir", "ci.out.url", "ci.out.paths",
		`"url": { "shape": "text" }`, `"url": { "shape": "text", "list": 1 }`).Replace(g)
	wantFailA(t, opts, noDone, "must output done")
}
