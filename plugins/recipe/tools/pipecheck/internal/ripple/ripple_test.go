package ripple

// §5.8 파급 보고 배터리 — 역참조 전이 탐색·층수(각 1층·최단)·버킷·동시 보유 오류.

import (
	"os"
	"path/filepath"
	"testing"
)

func writeSkill(t *testing.T, root, name, md string, graph string) {
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

func plainSkill(name string) string {
	return "---\nname: " + name + "\ndescription: d\nnode:\n  in:\n    x: { shape: text }\n  out:\n    y: { shape: text }\n---\n\n## 입력\n- `x` — i\n\n## 실행\ne\n\n## 출력\n- `y` — o\n"
}

func workflowGraph(materials string) string {
	return `{"name":"w","in":{},"out":{},"nodes":[],"edges":[],"materials":[` + materials + `]}`
}

func mat(name, scope, contract, body string) string {
	return `{"name":"` + name + `","scope":"` + scope + `","contract":"` + contract + `","body":"` + body + `"}`
}

func setup(t *testing.T) (string, string) {
	proj := t.TempDir()
	user := t.TempDir()

	// 대상: review-file(project). 현재 해시는 아래 Report 호출에 new-c·new-b로 준다.
	writeSkill(t, proj, "review-file", plainSkill("review-file"), "")

	// 직접 소비자들 — 기록 해시가 버킷을 가른다.
	writeSkill(t, proj, "fix-all", plainSkill("fix-all"),
		workflowGraph(mat("review-file", "project", "old-c", "old-b")))
	writeSkill(t, user, "nightly-scan", plainSkill("nightly-scan"),
		workflowGraph(mat("review-file", "project", "new-c", "old-b")))

	// 어댑터 직접 소비자(wraps 경유 1층).
	writeSkill(t, proj, "quick-review",
		"---\nname: quick-review\ndescription: d\nnode:\n  in:\n    x: { shape: text }\n  out:\n    y: { shape: text }\nwraps: { name: review-file, scope: project, contract: \"old-c\", body: \"old-b\" }\n---\n\n## 입력\n- `x` — i\n\n## 실행\ne\n\n## 출력\n- `y` — o\n", "")

	// 간접 소비자: weekly-audit → fix-all → review-file (2층).
	writeSkill(t, proj, "weekly-audit", plainSkill("weekly-audit"),
		workflowGraph(mat("fix-all", "project", "c", "b")))

	return proj, user
}

func find(rep Report, name string) *Consumer {
	for i := range rep.Consumers {
		if rep.Consumers[i].Name == name {
			return &rep.Consumers[i]
		}
	}
	return nil
}

func TestDirectConsumersAndBuckets(t *testing.T) {
	proj, user := setup(t)
	rep, err := Compute(Target{Name: "review-file", Scope: "project", Contract: "new-c", Body: "new-b"},
		Options{ProjectDir: proj, UserDir: user})
	if err != nil {
		t.Fatal(err)
	}
	fa := find(rep, "fix-all")
	if fa == nil || fa.Layers != 1 || fa.Kind != "workflow" {
		t.Fatalf("fix-all: %+v", fa)
	}
	// 계약·본문 둘 다 낡음 → 양쪽 버킷
	if !fa.ContractStale || !fa.BodyStale {
		t.Fatalf("fix-all buckets: %+v", fa)
	}
	ns := find(rep, "nightly-scan")
	if ns == nil || ns.Scope != "user" || ns.ContractStale || !ns.BodyStale {
		t.Fatalf("nightly-scan: %+v", ns)
	}
	qr := find(rep, "quick-review")
	if qr == nil || qr.Kind != "adapter" || qr.Layers != 1 || !qr.ContractStale || !qr.BodyStale {
		t.Fatalf("quick-review: %+v", qr)
	}
}

func TestIndirectLayers(t *testing.T) {
	proj, user := setup(t)
	rep, err := Compute(Target{Name: "review-file", Scope: "project", Contract: "new-c", Body: "new-b"},
		Options{ProjectDir: proj, UserDir: user})
	if err != nil {
		t.Fatal(err)
	}
	wa := find(rep, "weekly-audit")
	if wa == nil || wa.Layers != 2 {
		t.Fatalf("weekly-audit must be layer 2: %+v", wa)
	}
}

func TestMultiPathShortest(t *testing.T) {
	proj, user := setup(t)
	// weekly-audit이 review-file을 직접도 기록 — 경로 둘, 최단 1층.
	writeSkill(t, proj, "weekly-audit", plainSkill("weekly-audit"),
		workflowGraph(mat("fix-all", "project", "c", "b")+","+mat("review-file", "project", "old-c", "old-b")))
	rep, err := Compute(Target{Name: "review-file", Scope: "project", Contract: "new-c", Body: "new-b"},
		Options{ProjectDir: proj, UserDir: user})
	if err != nil {
		t.Fatal(err)
	}
	wa := find(rep, "weekly-audit")
	if wa == nil || wa.Layers != 1 {
		t.Fatalf("multi-path must report shortest layer 1: %+v", wa)
	}
}

func TestCycleTermination(t *testing.T) {
	proj, user := setup(t)
	// 손 편집 잔재 상호순환: loop-a ⇄ loop-b, loop-a가 대상도 소비.
	writeSkill(t, proj, "loop-a", plainSkill("loop-a"),
		workflowGraph(mat("review-file", "project", "old-c", "old-b")+","+mat("loop-b", "project", "c", "b")))
	writeSkill(t, proj, "loop-b", plainSkill("loop-b"),
		workflowGraph(mat("loop-a", "project", "c", "b")))
	rep, err := Compute(Target{Name: "review-file", Scope: "project", Contract: "new-c", Body: "new-b"},
		Options{ProjectDir: proj, UserDir: user})
	if err != nil {
		t.Fatal(err)
	}
	if find(rep, "loop-a") == nil || find(rep, "loop-b") == nil {
		t.Fatalf("cycle members must be reported once each: %+v", rep.Consumers)
	}
	for _, c := range rep.Consumers {
		if c.Name == "loop-a" && c.Layers != 1 {
			t.Fatalf("loop-a layer: %+v", c)
		}
		if c.Name == "loop-b" && c.Layers != 2 {
			t.Fatalf("loop-b layer: %+v", c)
		}
	}
}

func TestDualKindError(t *testing.T) {
	proj, user := setup(t)
	// graph.json과 wraps 동시 보유 — 가지 중단 + 오류 항목.
	writeSkill(t, proj, "broken",
		"---\nname: broken\ndescription: d\nnode:\n  in: {}\n  out: {}\nwraps: { name: review-file, scope: project, contract: \"old-c\", body: \"old-b\" }\n---\n\n## 입력\n\n## 실행\ne\n\n## 출력\n",
		workflowGraph(mat("review-file", "project", "old-c", "old-b")))
	rep, err := Compute(Target{Name: "review-file", Scope: "project", Contract: "new-c", Body: "new-b"},
		Options{ProjectDir: proj, UserDir: user})
	if err != nil {
		t.Fatal(err)
	}
	if len(rep.Errors) == 0 {
		t.Fatal("dual-kind material must surface an error item")
	}
	if find(rep, "broken") != nil {
		t.Fatalf("dual-kind consumer branch must be cut: %+v", rep.Consumers)
	}
}

func TestEmptyInstallPasses(t *testing.T) {
	rep, err := Compute(Target{Name: "x", Scope: "project", Contract: "c", Body: "b"},
		Options{ProjectDir: t.TempDir(), UserDir: t.TempDir()})
	if err != nil {
		t.Fatal(err)
	}
	if len(rep.Consumers) != 0 || len(rep.Errors) != 0 {
		t.Fatalf("empty install must yield empty report: %+v", rep)
	}
}
