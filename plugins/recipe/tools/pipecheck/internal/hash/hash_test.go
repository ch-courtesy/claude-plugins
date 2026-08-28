package hash

// §5.8 해시 정규형 테스트 — 스펙 본문의 정규형 예제 바이트열이 골든이다.

import (
	"strings"
	"testing"
)

// 스펙 §5.8 예제 그대로.
const specCanonical = `{"in":{"path":{"shape":"text","list":0,"required":true}},"out":{"verdict":{"shape":"text","list":0,"required":true,"values":["clean","needs_fix"]}}}`

const skillMD = `---
name: review-file
description: 파일 하나를 리뷰한다
node:
  in:
    path: { shape: text }
  out:
    verdict: { shape: text, values: [needs_fix, clean] }
---

## 입력
- ` + "`path`" + ` — 대상
## 실행
리뷰한다.
## 출력
- ` + "`verdict`" + ` — 판정
`

func TestCanonicalContract(t *testing.T) {
	got, err := CanonicalContract([]byte(skillMD))
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != specCanonical {
		t.Fatalf("canonical mismatch:\n got %s\nwant %s", got, specCanonical)
	}
}

func TestContractHashInvariantToReformat(t *testing.T) {
	// 키 순서·플로/블록 스타일·주석이 달라도 계약 해시는 같다(§12 재포매팅 불변).
	reformatted := strings.Replace(skillMD,
		"  out:\n    verdict: { shape: text, values: [needs_fix, clean] }",
		"  out:\n    verdict:\n      values: [clean, needs_fix]   # 열거\n      shape: text", 1)
	h1, _, err := SkillHashes([]byte(skillMD), nil)
	if err != nil {
		t.Fatal(err)
	}
	h2, _, err := SkillHashes([]byte(reformatted), nil)
	if err != nil {
		t.Fatal(err)
	}
	if h1 != h2 {
		t.Fatalf("contract hash changed on reformat: %s vs %s", h1, h2)
	}
}

func TestBodyHash(t *testing.T) {
	// 본문 해시 대상: node: 블록만 제거한 나머지 전체(프론트매터 포함),
	// 정규화는 줄 끝 공백 제거·파일 끝 개행 하나뿐.
	_, b1, err := SkillHashes([]byte(skillMD), nil)
	if err != nil {
		t.Fatal(err)
	}
	// description만 바꾸면 본문 해시가 바뀐다(계약 해시는 그대로).
	changed := strings.Replace(skillMD, "파일 하나를 리뷰한다", "다르게 설명한다", 1)
	c2, b2, err := SkillHashes([]byte(changed), nil)
	if err != nil {
		t.Fatal(err)
	}
	c1, _, _ := SkillHashes([]byte(skillMD), nil)
	if c1 != c2 {
		t.Fatal("contract hash must not change on description edit")
	}
	if b1 == b2 {
		t.Fatal("body hash must change on description edit")
	}
	// 줄 끝 공백·끝 개행 수는 본문 해시에 무영향.
	padded := strings.ReplaceAll(skillMD, "리뷰한다.", "리뷰한다.   ") + "\n\n"
	_, b3, err := SkillHashes([]byte(padded), nil)
	if err != nil {
		t.Fatal(err)
	}
	if b1 != b3 {
		t.Fatal("trailing spaces / final newlines must not affect body hash")
	}
}

func TestWorkflowBodyConcatOrder(t *testing.T) {
	// 재료가 워크플로면: 본문 결과 뒤에 graph.json — 순서 고정, 개행 하나로.
	g1 := []byte(`{"name":"w"}`)
	_, bA, err := SkillHashes([]byte(skillMD), g1)
	if err != nil {
		t.Fatal(err)
	}
	_, bB, _ := SkillHashes([]byte(skillMD), nil)
	if bA == bB {
		t.Fatal("graph.json must participate in workflow body hash")
	}
	// 순서 고정: 이어붙인 바이트열은 본문 뒤에 graph.json이다.
	joined, err := BodyBytes([]byte(skillMD), g1)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasSuffix(string(joined), string(g1)+"\n") {
		t.Fatal("graph.json must come last (body then graph)")
	}
	if !strings.HasPrefix(string(joined), "---\n") {
		t.Fatal("body (frontmatter remainder) must come first")
	}
}

func TestNonASCIIRawInCanonical(t *testing.T) {
	md := strings.Replace(skillMD, "values: [needs_fix, clean]", "values: [\" x\", clean]", 1)
	got, err := CanonicalContract([]byte(md))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(got), "\\u2028") {
		t.Fatalf("U+2028 must stay raw UTF-8, got %s", got)
	}
	if !strings.Contains(string(got), " ") {
		t.Fatalf("U+2028 bytes missing: %s", got)
	}
}

func TestNodeLineVariants(t *testing.T) {
	c1 := strings.Replace(skillMD, "node:", "node:   # contract", 1)
	if _, _, err := SkillHashes([]byte(c1), nil); err != nil {
		t.Fatalf("comment after node: must hash: %v", err)
	}
	inline := "---\nname: a\ndescription: d\nnode: { in: {}, out: { y: { shape: text } } }\n---\n\n## 입력\n\n## 실행\ne\n## 출력\n- `y` — o\n"
	if _, _, err := SkillHashes([]byte(inline), nil); err != nil {
		t.Fatalf("inline node mapping must hash: %v", err)
	}
}

func TestNodeBlockRemovalBoundary(t *testing.T) {
	// node: 뒤에 같은 들여쓰기의 다음 키(wraps)가 오면 거기까지 제거하고 wraps는 남긴다.
	md := "---\nname: a\nnode:\n  in:\n    x: { shape: text }\n  out:\n    y: { shape: text }\nwraps: { name: b, scope: project, contract: \"sha256:0\", body: \"sha256:0\" }\ndescription: d\n---\n\n## 입력\n- `x` — i\n## 실행\ne\n## 출력\n- `y` — o\n"
	_, body, err := SkillHashes([]byte(md), nil)
	if err != nil {
		t.Fatal(err)
	}
	stripped, err := BodyBytes([]byte(md), nil)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(stripped), "wraps:") {
		t.Fatal("wraps must survive node: block removal")
	}
	if strings.Contains(string(stripped), "shape: text") {
		t.Fatal("node: sub-block must be removed")
	}
	if body == "" {
		t.Fatal("empty body hash")
	}
}
