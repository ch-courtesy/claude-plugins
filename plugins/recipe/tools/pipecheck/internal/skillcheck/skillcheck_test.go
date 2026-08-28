package skillcheck

// §6.4 검증 배터리 — 항목마다 그 항목만 어기는 최소 스킬(§12 G2의 픽스처).
// 유효 기저는 스펙 §6.2의 review-file 예제를 축약한 것.

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const valid = `---
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
- ` + "`path`" + ` — 대상 파일
- ` + "`focus`" + ` — 관점

## 실행
파일을 읽어 리뷰한다.

## 출력
- ` + "`findings`" + ` — 발견 배열
- ` + "`messages`" + ` — 메시지 배열
- ` + "`verdict`" + ` — 판정
`

func mustCheck(t *testing.T, md string) Result {
	t.Helper()
	r, err := Check([]byte(md), Options{})
	if err != nil {
		t.Fatal(err)
	}
	return r
}

func wantFail(t *testing.T, md, substr string) {
	t.Helper()
	r := mustCheck(t, md)
	if r.Pass {
		t.Fatalf("expected failure containing %q, got pass", substr)
	}
	joined := strings.Join(r.Failures, " | ")
	if !strings.Contains(joined, substr) {
		t.Fatalf("failures %v do not mention %q", r.Failures, substr)
	}
}

func TestValidPasses(t *testing.T) {
	r := mustCheck(t, valid)
	if !r.Pass {
		t.Fatalf("valid skill failed: %v", r.Failures)
	}
	if len(r.Warnings) != 0 {
		t.Fatalf("unexpected warnings: %v", r.Warnings)
	}
}

// 세 절 규약 — 원시 `## ` 줄 목록 대조
func TestSectionHeadings(t *testing.T) {
	wantFail(t, strings.Replace(valid, "## 실행", "### 실행", 1), "sections")
	wantFail(t, strings.Replace(valid, "## 출력", "## 결과", 1), "sections")
	wantFail(t, valid+"\n## 비고\n없음\n", "sections")
	// 코드 펜스 안 ## 줄도 원시 대조에 걸린다(§6.3 — raw 판정이 정본)
	wantFail(t, strings.Replace(valid, "파일을 읽어 리뷰한다.",
		"파일을 읽어 리뷰한다.\n```text\n## 결과\n```", 1), "sections")
}

// 절의 포트 나열
func TestPortListing(t *testing.T) {
	wantFail(t, strings.Replace(valid, "- `focus` — 관점\n", "", 1), "input section")
	wantFail(t, strings.Replace(valid, "- `verdict` — 판정\n", "", 1), "output section")
	// 계약에 없는 포트 나열
	wantFail(t, strings.Replace(valid, "- `focus` — 관점",
		"- `focus` — 관점\n- `ghost` — 없음", 1), "not in contract")
	// 설명 비어 있음
	wantFail(t, strings.Replace(valid, "- `focus` — 관점", "- `focus` —", 1), "empty description")
}

// 계약 §3 규칙
func TestContractRules(t *testing.T) {
	wantFail(t, strings.Replace(valid, "focus: { shape: text }", "focus: { shape: file }", 1), "shape")
	wantFail(t, strings.Replace(valid, "list: 1, required: false, aligned: findings", "list: -1, required: false, aligned: findings", 1), "list")
	wantFail(t, strings.Replace(valid, "path: { shape: text }", "9path: { shape: text }", 1), "port name")
	wantFail(t, strings.Replace(valid, "path: { shape: text }", "\"\": { shape: text }", 1), "port name")
	// required:false 깊이 0
	wantFail(t, strings.Replace(valid, "focus: { shape: text }", "focus: { shape: text, required: false }", 1), "required")
	// values는 text 포트만
	wantFail(t, strings.Replace(valid, "findings: { shape: json, list: 1, required: false }",
		"findings: { shape: json, list: 1, required: false, values: [a] }", 1), "values")
	// values 원소 중복
	wantFail(t, strings.Replace(valid, "values: [clean, needs_fix]", "values: [clean, clean]", 1), "values")
	// aligned 깊이 0
	wantFail(t, strings.Replace(valid, "verdict: { shape: text, values: [clean, needs_fix] }",
		"verdict: { shape: text, values: [clean, needs_fix], aligned: findings }", 1), "aligned")
	// aligned 미실재 대상
	wantFail(t, strings.Replace(valid, "aligned: findings", "aligned: nothing", 1), "aligned")
	// aligned 다른 방향(출력이 입력을 가리킴)
	wantFail(t, strings.Replace(valid, "aligned: findings", "aligned: path", 1), "aligned")
	// aligned 짝 required 불일치
	wantFail(t, strings.Replace(valid, "findings: { shape: json, list: 1, required: false }",
		"findings: { shape: json, list: 1 }", 1), "aligned")
}

func TestAlignedCycle(t *testing.T) {
	md := strings.Replace(valid,
		"findings: { shape: json, list: 1, required: false }",
		"findings: { shape: json, list: 1, required: false, aligned: messages }", 1)
	wantFail(t, md, "aligned")
}

// 프론트매터 규칙
func TestFrontmatter(t *testing.T) {
	wantFail(t, strings.Replace(valid, "description: 파일 하나를 리뷰한다", "description: \"\"", 1), "description")
	wantFail(t, strings.Replace(valid, "name: review-file", "name: Review-File", 1), "name")
	wantFail(t, strings.Replace(valid, "name: review-file", "name: \"\"", 1), "name")
	wantFail(t, strings.Replace(valid, "name: review-file", "name: "+strings.Repeat("a", 256), 1), "name")
	// 폐쇄: 허용 밖 키
	wantFail(t, strings.Replace(valid, "description: 파일 하나를 리뷰한다",
		"description: 파일 하나를 리뷰한다\nkind: adapter", 1), "frontmatter key")
	// 포트 객체 폐쇄
	wantFail(t, strings.Replace(valid, "focus: { shape: text }", "focus: { shape: text, note: x }", 1), "port field")
	// node: 폐쇄
	wantFail(t, strings.Replace(valid, "  out:", "  meta: {}\n  out:", 1), "node key")
	// required 불리언
	wantFail(t, strings.Replace(valid, "required: false, aligned: findings", "required: 0, aligned: findings", 1), "required")
	// 중복 키
	wantFail(t, strings.Replace(valid, "    focus: { shape: text }",
		"    focus: { shape: text }\n    focus: { shape: text }", 1), "duplicate")
}

// impl-r1 반례들
func TestImplReviewCounterexamples(t *testing.T) {
	// node: {} — in·out 누락 거부
	md := strings.Replace(valid,
		"node:\n  in:\n    path: { shape: text }\n    focus: { shape: text }\n  out:\n    findings: { shape: json, list: 1, required: false }\n    messages: { shape: text, list: 1, required: false, aligned: findings }\n    verdict: { shape: text, values: [clean, needs_fix] }",
		"node: {}", 1)
	md = strings.NewReplacer("- `path` — 대상 파일\n", "", "- `focus` — 관점\n", "",
		"- `findings` — 발견 배열\n", "", "- `messages` — 메시지 배열\n", "", "- `verdict` — 판정\n", "").Replace(md)
	wantFail(t, md, "in")
	// values: [] 거부
	wantFail(t, strings.Replace(valid, "values: [clean, needs_fix]", "values: []", 1), "values")
	// aligned: "" 거부
	wantFail(t, strings.Replace(valid, "aligned: findings", "aligned: \"\"", 1), "aligned")
	// 하이픈 시작 이름은 적법
	r := mustCheck(t, strings.Replace(valid, "name: review-file", "name: -review", 1))
	if !r.Pass {
		t.Fatalf("hyphen-leading name must pass: %v", r.Failures)
	}
}

func TestWrapsSelfCycle(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "review-file"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "review-file", "SKILL.md"), []byte(valid), 0o644); err != nil {
		t.Fatal(err)
	}
	ch, _ := contractHashOf(t, valid)
	// 수정 후보가 자기 자신(설치본)을 wraps — 설치되면 자기 순환
	selfWrap := strings.Replace(valid, "description: 파일 하나를 리뷰한다",
		"description: 파일 하나를 리뷰한다\nwraps: { name: review-file, scope: project, contract: \""+ch+"\", body: \"sha256:0\" }", 1)
	r, err := Check([]byte(selfWrap), Options{ProjectDir: dir, SelfScope: "project"})
	if err != nil {
		t.Fatal(err)
	}
	if r.Pass {
		t.Fatal("self-wrapping candidate must fail as a cycle")
	}
}

// 출력 전부 required:false → 주의(불통과 아님)
func TestAllOptionalOutputsWarns(t *testing.T) {
	md := strings.Replace(valid, "verdict: { shape: text, values: [clean, needs_fix] }",
		"verdict: { shape: text, required: false, list: 1 }", 1)
	r := mustCheck(t, md)
	if !r.Pass {
		t.Fatalf("all-optional outputs must pass with warning, got %v", r.Failures)
	}
	if len(r.Warnings) == 0 {
		t.Fatal("expected warning for all-optional outputs")
	}
}

// 출력 0개 계약은 적법
func TestZeroOutputContract(t *testing.T) {
	md := strings.Replace(valid,
		"  out:\n    findings: { shape: json, list: 1, required: false }\n    messages: { shape: text, list: 1, required: false, aligned: findings }\n    verdict: { shape: text, values: [clean, needs_fix] }",
		"  out: {}", 1)
	md = strings.Replace(md, "\n## 출력\n- `findings` — 발견 배열\n- `messages` — 메시지 배열\n- `verdict` — 판정\n", "\n## 출력\n", 1)
	r := mustCheck(t, md)
	if !r.Pass {
		t.Fatalf("zero-output contract must be legal: %v", r.Failures)
	}
}

// wraps 체인 — 실재·계약 해시 대조·body 기록·비순환
func TestWrapsChain(t *testing.T) {
	dir := t.TempDir()
	// 원본 스킬 설치
	orig := valid
	if err := os.MkdirAll(filepath.Join(dir, "review-file"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "review-file", "SKILL.md"), []byte(orig), 0o644); err != nil {
		t.Fatal(err)
	}
	ch, _ := contractHashOf(t, orig)

	adapter := `---
name: quick-review
description: 감싼다
node:
  in:
    file: { shape: text }
  out:
    verdict: { shape: text }
wraps: { name: review-file, scope: project, contract: "` + ch + `", body: "sha256:0" }
---

## 입력
- ` + "`file`" + ` — 대상

## 실행
file을 path로 옮겨 원본을 수행한다.

## 출력
- ` + "`verdict`" + ` — 판정
`
	r, err := Check([]byte(adapter), Options{ProjectDir: dir})
	if err != nil {
		t.Fatal(err)
	}
	if !r.Pass {
		t.Fatalf("valid adapter failed: %v", r.Failures)
	}
	// 계약 해시 불일치
	bad := strings.Replace(adapter, ch, "sha256:dead", 1)
	r2, _ := Check([]byte(bad), Options{ProjectDir: dir})
	if r2.Pass {
		t.Fatal("stale wraps contract must fail")
	}
	// 대상 미실재
	missing := strings.Replace(adapter, "name: review-file, scope: project", "name: nobody, scope: project", 1)
	r3, _ := Check([]byte(missing), Options{ProjectDir: dir})
	if r3.Pass {
		t.Fatal("missing wraps target must fail")
	}
	// body 누락
	nobody := strings.Replace(adapter, `, body: "sha256:0"`, "", 1)
	r4, _ := Check([]byte(nobody), Options{ProjectDir: dir})
	if r4.Pass {
		t.Fatal("missing wraps body must fail")
	}
}

func contractHashOf(t *testing.T, md string) (string, string) {
	t.Helper()
	c, b, err := hashesFor([]byte(md))
	if err != nil {
		t.Fatal(err)
	}
	return c, b
}

func TestOverlayWraps(t *testing.T) {
	proj := t.TempDir()
	overlay := t.TempDir()
	// 설치본은 없고 임시 위치에만 대상이 있다 — 같은 실행의 신규·수정 재료
	if err := os.MkdirAll(filepath.Join(overlay, "review-file"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(overlay, "review-file", "SKILL.md"), []byte(valid), 0o644); err != nil {
		t.Fatal(err)
	}
	ch, _ := contractHashOf(t, valid)

	adapter := `---
name: quick-review
description: 감싼다
node:
  in:
    file: { shape: text }
  out:
    verdict: { shape: text }
wraps: { name: review-file, scope: project, contract: "` + ch + `", body: "sha256:0" }
---

## 입력
- ` + "`file`" + ` — 대상

## 실행
file을 path로 옮겨 원본을 수행한다.

## 출력
- ` + "`verdict`" + ` — 판정
`
	r, err := Check([]byte(adapter), Options{ProjectDir: proj, OverlayDir: overlay})
	if err != nil {
		t.Fatal(err)
	}
	if !r.Pass {
		t.Fatalf("overlay wraps should resolve: %v", r.Failures)
	}
	r, err = Check([]byte(adapter), Options{ProjectDir: proj})
	if err != nil {
		t.Fatal(err)
	}
	if r.Pass {
		t.Fatal("without overlay the target must not resolve")
	}
}
