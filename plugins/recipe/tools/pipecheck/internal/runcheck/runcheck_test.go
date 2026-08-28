package runcheck

// §9.2 값 검증 배터리 — 시드·회차·경계 자리의 판정을 한 도구로.

import (
	"strings"
	"testing"
)

func decls() map[string]Port {
	one := 1
	f := false
	return map[string]Port{
		"path":     {Shape: "text"},
		"n":        {Shape: "num"},
		"j":        {Shape: "json"},
		"items":    {Shape: "text", List: &one},
		"opt":      {Shape: "text", List: &one, Required: &f},
		"verdict":  {Shape: "text", Values: []string{"clean", "needs_fix"}},
		"findings": {Shape: "json", List: &one, Required: &f},
		"messages": {Shape: "text", List: &one, Required: &f, Aligned: "findings"},
	}
}

func run(t *testing.T, given map[string]string, boundary bool) Result {
	t.Helper()
	g := map[string][]byte{}
	for k, v := range given {
		g[k] = []byte(v)
	}
	r, err := Check(decls(), g, boundary)
	if err != nil {
		t.Fatal(err)
	}
	return r
}

func wantFail(t *testing.T, r Result, substr string) {
	t.Helper()
	if r.Pass {
		t.Fatalf("expected failure containing %q, got pass", substr)
	}
	if !strings.Contains(strings.Join(r.Failures, " | "), substr) {
		t.Fatalf("failures %v lack %q", r.Failures, substr)
	}
}

var full = map[string]string{
	"path": `"a.py"`, "n": `1.5`, "j": `{"k": 1}`, "items": `["x"]`,
	"verdict": `"clean"`, "findings": `[{"s": 1}]`, "messages": `["m"]`,
}

func TestValidValuesPass(t *testing.T) {
	r := run(t, full, false)
	if !r.Pass {
		t.Fatalf("valid values failed: %v", r.Failures)
	}
}

func TestRequiredMissing(t *testing.T) {
	g := map[string]string{}
	for k, v := range full {
		if k != "path" {
			g[k] = v
		}
	}
	wantFail(t, run(t, g, false), "required")
}

func TestOptionalFilled(t *testing.T) {
	g := map[string]string{}
	for k, v := range full {
		if k != "opt" && k != "findings" && k != "messages" {
			g[k] = v
		}
	}
	r := run(t, g, false)
	if !r.Pass {
		t.Fatalf("optional omission must pass with fill: %v", r.Failures)
	}
	if r.Filled["opt"] != "[]" {
		t.Fatalf("opt must be filled with []: %v", r.Filled)
	}
}

func TestShapeDepth(t *testing.T) {
	g := clone(full)
	g["path"] = `[]` // 깊이 0 비-json에 배열
	wantFail(t, run(t, g, false), "depth")
	g = clone(full)
	g["n"] = `"x"`
	wantFail(t, run(t, g, false), "shape")
	g = clone(full)
	g["items"] = `["x", ["y"]]` // 혼합 깊이
	wantFail(t, run(t, g, false), "depth")
}

func TestNumRules(t *testing.T) {
	g := clone(full)
	g["n"] = `9007199254740993` // 2^53+1
	wantFail(t, run(t, g, false), "double")
	// -0은 0과 같다 — 통과
	g = clone(full)
	g["n"] = `-0`
	if r := run(t, g, false); !r.Pass {
		t.Fatalf("-0 must pass: %v", r.Failures)
	}
}

func TestDuplicateMembers(t *testing.T) {
	g := clone(full)
	g["j"] = `{"a": 1, "a": 2}`
	wantFail(t, run(t, g, false), "duplicate")
}

func TestValuesLeaves(t *testing.T) {
	g := clone(full)
	g["verdict"] = `"bogus"`
	wantFail(t, run(t, g, false), "values")
}

func TestAlignedLengths(t *testing.T) {
	g := clone(full)
	g["messages"] = `["m", "m2"]` // findings 길이 1과 불일치
	wantFail(t, run(t, g, false), "aligned")
	// 바깥 축 불일치(깊이 2)
	two := 2
	ports := map[string]Port{
		"a": {Shape: "text", List: &two},
		"b": {Shape: "bool", List: &two, Aligned: "a"},
	}
	r, err := Check(ports, map[string][]byte{"a": []byte(`[["x"],["y"]]`), "b": []byte(`[[true]]`)}, false)
	if err != nil {
		t.Fatal(err)
	}
	wantFail(t, r, "aligned")
}

func TestBoundaryPairOmission(t *testing.T) {
	// 경계: 짝은 함께 생략하거나 함께 준다
	g := clone(full)
	delete(g, "findings") // messages만 제공
	wantFail(t, run(t, g, true), "pair")
	// 함께 생략은 통과(둘 다 required:false)
	g2 := clone(full)
	delete(g2, "findings")
	delete(g2, "messages")
	if r := run(t, g2, true); !r.Pass {
		t.Fatalf("pair omitted together must pass: %v", r.Failures)
	}
}

func clone(m map[string]string) map[string]string {
	out := map[string]string{}
	for k, v := range m {
		out[k] = v
	}
	return out
}

// impl-r3 반례들
func TestFilledJoinsAlignedComparison(t *testing.T) {
	// 선택 짝의 한쪽만 제공(비경계) — 보충된 []가 짝 대조에 참여해 길이 불일치.
	g := clone(full)
	delete(g, "findings") // messages=["m"] 남음
	wantFail(t, run(t, g, false), "aligned")
}

func TestScientificIntegerRejected(t *testing.T) {
	g := clone(full)
	g["n"] = `9007199254740993.0`
	wantFail(t, run(t, g, false), "double")
	g["n"] = `9.007199254740993e15`
	wantFail(t, run(t, g, false), "double")
	// 2^53 자체는 표기와 무관하게 통과
	g["n"] = `9.007199254740992e15`
	if r := run(t, g, false); !r.Pass {
		t.Fatalf("2^53 in e-notation must pass: %v", r.Failures)
	}
}

func TestTrailingJSONRejected(t *testing.T) {
	g := clone(full)
	g["j"] = `{} []`
	wantFail(t, run(t, g, false), "trailing")
}

// impl-r4 반례 — 임의 정밀 정수 판정(big.Rat)
func TestHugeIntegerExactness(t *testing.T) {
	g := clone(full)
	// 2^200 + 1 — double로 정확히 표현 불가한 정수 → 거부
	g["n"] = `1606938044258990275541962092341162602522202993782792835301377`
	wantFail(t, run(t, g, false), "double")
	// 2^200 + 1.5 — 비정수 → 반올림 감수, 통과
	g["n"] = `1606938044258990275541962092341162602522202993782792835301377.5`
	if r := run(t, g, false); !r.Pass {
		t.Fatalf("non-integer decimal must pass: %v", r.Failures)
	}
}
