// Package hash — 스펙 §5.8의 계약·본문 해시 정규형.
//
// 계약: 프론트매터 node: 블록을 UTF-8 JSON 정규형으로 재직렬화해 SHA-256.
// 본문: node: 키와 그 하위 블록만 제거한 나머지 전체를 원문 바이트로 두고,
// 줄 끝 공백 제거·파일 끝 개행 하나 — 두 정규화만 적용해 SHA-256.
// 재료가 워크플로면 그 결과 뒤에 같은 정규화를 거친 graph.json을 잇는다(순서 고정).
package hash

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"regexp"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
)

type port struct {
	Shape    string   `yaml:"shape"`
	List     *int     `yaml:"list"`
	Required *bool    `yaml:"required"`
	Values   []string `yaml:"values"`
	Aligned  string   `yaml:"aligned"`
}

type nodeBlock struct {
	In  map[string]port `yaml:"in"`
	Out map[string]port `yaml:"out"`
}

var nodeLine = regexp.MustCompile(`^node:(\s|$)`)
var topKey = regexp.MustCompile(`^[^\s#-]`)

// splitFrontmatter는 (프론트매터 내부 줄들, 전체 줄들, 프론트매터 범위)를 돌려준다.
func splitLines(md []byte) ([]string, int, int, error) {
	lines := strings.Split(string(md), "\n")
	if len(lines) == 0 || strings.TrimRight(lines[0], " \t") != "---" {
		return nil, 0, 0, fmt.Errorf("no frontmatter opening ---")
	}
	for i := 1; i < len(lines); i++ {
		if strings.TrimRight(lines[i], " \t") == "---" {
			return lines, 1, i, nil // 내부는 [1, i)
		}
	}
	return nil, 0, 0, fmt.Errorf("no frontmatter closing ---")
}

// nodeRange는 프론트매터 안 node: 블록의 [시작, 끝) 줄 범위를 찾는다.
// 제거 범위: node: 줄부터 같은 들여쓰기 수준(최상위)의 다음 키 또는 종료 구분선 직전까지.
func nodeRange(lines []string, fmStart, fmEnd int) (int, int, error) {
	start := -1
	for i := fmStart; i < fmEnd; i++ {
		if nodeLine.MatchString(lines[i]) {
			start = i
			break
		}
	}
	if start == -1 {
		return 0, 0, fmt.Errorf("no node: block in frontmatter")
	}
	end := fmEnd
	for i := start + 1; i < fmEnd; i++ {
		if topKey.MatchString(lines[i]) {
			end = i
			break
		}
	}
	return start, end, nil
}

// CanonicalContract는 §5.8 정규형 JSON 바이트열을 낸다.
func CanonicalContract(md []byte) ([]byte, error) {
	lines, fmStart, fmEnd, err := splitLines(md)
	if err != nil {
		return nil, err
	}
	s, e, err := nodeRange(lines, fmStart, fmEnd)
	if err != nil {
		return nil, err
	}
	block := strings.Join(lines[s:e], "\n")
	var wrapper struct {
		Node nodeBlock `yaml:"node"`
	}
	if err := yaml.Unmarshal([]byte(block), &wrapper); err != nil {
		return nil, fmt.Errorf("node: yaml: %w", err)
	}
	var buf bytes.Buffer
	buf.WriteString(`{"in":`)
	writePorts(&buf, wrapper.Node.In)
	buf.WriteString(`,"out":`)
	writePorts(&buf, wrapper.Node.Out)
	buf.WriteString("}")
	return buf.Bytes(), nil
}

func jstr(s string) string {
	var b bytes.Buffer
	enc := json.NewEncoder(&b)
	enc.SetEscapeHTML(false)
	_ = enc.Encode(s) // 개행 하나가 붙는다
	out := strings.TrimRight(b.String(), "\n")
	// Go 인코더는 U+2028·U+2029를 이스케이프한다 — 비ASCII는 원문 그대로(5.8).
	out = strings.ReplaceAll(out, "\\u2028", " ")
	out = strings.ReplaceAll(out, "\\u2029", " ")
	return out
}

func writePorts(buf *bytes.Buffer, ports map[string]port) {
	names := make([]string, 0, len(ports))
	for n := range ports {
		names = append(names, n)
	}
	sort.Strings(names) // 유니코드 코드포인트 순
	buf.WriteString("{")
	for i, n := range names {
		if i > 0 {
			buf.WriteString(",")
		}
		p := ports[n]
		list := 0
		if p.List != nil {
			list = *p.List
		}
		required := true
		if p.Required != nil {
			required = *p.Required
		}
		buf.WriteString(jstr(n))
		buf.WriteString(`:{"shape":`)
		buf.WriteString(jstr(p.Shape))
		fmt.Fprintf(buf, `,"list":%d,"required":%t`, list, required)
		if len(p.Values) > 0 {
			vals := append([]string(nil), p.Values...)
			sort.Strings(vals)
			buf.WriteString(`,"values":[`)
			for j, v := range vals {
				if j > 0 {
					buf.WriteString(",")
				}
				buf.WriteString(jstr(v))
			}
			buf.WriteString("]")
		}
		if p.Aligned != "" {
			buf.WriteString(`,"aligned":`)
			buf.WriteString(jstr(p.Aligned))
		}
		buf.WriteString("}")
	}
	buf.WriteString("}")
}

// normalize: 줄 끝 공백 제거, 파일 끝 개행 하나.
func normalize(b []byte) []byte {
	lines := strings.Split(string(b), "\n")
	for i := range lines {
		lines[i] = strings.TrimRight(lines[i], " \t")
	}
	out := strings.Join(lines, "\n")
	out = strings.TrimRight(out, "\n") + "\n"
	return []byte(out)
}

// BodyBytes는 본문 해시의 대상 바이트열(정규화 적용 후)을 낸다.
// graphJSON이 nil이 아니면 워크플로 재료 — 정규화한 graph.json을 뒤에 잇는다.
func BodyBytes(md []byte, graphJSON []byte) ([]byte, error) {
	lines, fmStart, fmEnd, err := splitLines(md)
	if err != nil {
		return nil, err
	}
	s, e, err := nodeRange(lines, fmStart, fmEnd)
	if err == nil {
		lines = append(append([]string{}, lines[:s]...), lines[e:]...)
	}
	_ = fmStart
	body := normalize([]byte(strings.Join(lines, "\n")))
	if graphJSON != nil {
		body = append(body, normalize(graphJSON)...)
	}
	return body, nil
}

func sha(b []byte) string {
	return fmt.Sprintf("sha256:%x", sha256.Sum256(b))
}

// SkillHashes는 (계약 해시, 본문 해시)를 "sha256:<hex>"로 낸다.
func SkillHashes(md []byte, graphJSON []byte) (string, string, error) {
	c, err := CanonicalContract(md)
	if err != nil {
		return "", "", err
	}
	b, err := BodyBytes(md, graphJSON)
	if err != nil {
		return "", "", err
	}
	return sha(c), sha(b), nil
}
