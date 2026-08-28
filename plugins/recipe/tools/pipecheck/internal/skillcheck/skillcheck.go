// Package skillcheck — 스펙 §6.4의 스킬 구조 검증.
// 실행하지 않는다. 항목 하나하나가 §12 G2의 검사다.
package skillcheck

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/hash"
	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/portrules"
	"gopkg.in/yaml.v3"
)

type Options struct {
	SelfScope  string // 후보의 설치 예정 scope(project|user) — wraps 자기 순환 판정에 쓴다
	ProjectDir string // scope: project 스킬 루트(각 스킬은 <dir>/<name>/SKILL.md)
	UserDir    string // scope: user 스킬 루트
	OverlayDir string // 승인 전 임시 위치 — 어느 scope에서든 설치본보다 먼저 찾는다(7.5)
}

type Result struct {
	Pass     bool     `json:"pass"`
	Failures []string `json:"failures,omitempty"`
	Warnings []string `json:"warnings,omitempty"`
}

type port struct {
	ValuesSet  bool     `yaml:"-"`
	AlignedSet bool     `yaml:"-"`
	Shape      string   `yaml:"shape"`
	List       *int     `yaml:"list"`
	Required   *bool    `yaml:"required"`
	Values     []string `yaml:"values"`
	Aligned    string   `yaml:"aligned"`
}

func (p port) depth() int {
	if p.List == nil {
		return 0
	}
	return *p.List
}

func (p port) required() bool {
	if p.Required == nil {
		return true
	}
	return *p.Required
}

type wrapsRef struct {
	Name     string `yaml:"name"`
	Scope    string `yaml:"scope"`
	Contract string `yaml:"contract"`
	Body     string `yaml:"body"`
}

var portItemRe = regexp.MustCompile("^-\\s*`([^`]*)`(.*)$")

// hashesFor는 테스트·wraps 대조가 쓰는 §5.8 해시다.
func hashesFor(md []byte) (string, string, error) {
	return hash.SkillHashes(md, nil)
}

func Check(md []byte, opts Options) (Result, error) {
	var fails, warns []string
	fail := func(format string, a ...any) { fails = append(fails, fmt.Sprintf(format, a...)) }

	text := string(md)
	lines := strings.Split(text, "\n")
	if len(lines) == 0 || strings.TrimRight(lines[0], " \t") != "---" {
		return Result{}, fmt.Errorf("no frontmatter")
	}
	fmEnd := -1
	for i := 1; i < len(lines); i++ {
		if strings.TrimRight(lines[i], " \t") == "---" {
			fmEnd = i
			break
		}
	}
	if fmEnd == -1 {
		return Result{}, fmt.Errorf("unclosed frontmatter")
	}
	fmText := strings.Join(lines[1:fmEnd], "\n")
	body := lines[fmEnd+1:]

	// ── 프론트매터: YAML 파싱 + 중복 키 + 폐쇄 ──
	var root yaml.Node
	if err := yaml.Unmarshal([]byte(fmText), &root); err != nil {
		fail("frontmatter yaml parse: %v", err)
		return done(fails, warns), nil
	}
	if len(root.Content) == 0 || root.Content[0].Kind != yaml.MappingNode {
		fail("frontmatter is not a mapping")
		return done(fails, warns), nil
	}
	top := root.Content[0]
	checkDupKeys(top, "frontmatter", &fails)

	allowedTop := map[string]bool{"name": true, "description": true, "node": true, "wraps": true}
	var name, description string
	var nodeNode, wrapsNode *yaml.Node
	for i := 0; i+1 < len(top.Content); i += 2 {
		k, v := top.Content[i], top.Content[i+1]
		if !allowedTop[k.Value] {
			fail("frontmatter key %q is not allowed (name·description·node·wraps only)", k.Value)
			continue
		}
		switch k.Value {
		case "name":
			name = v.Value
		case "description":
			description = v.Value
		case "node":
			nodeNode = v
		case "wraps":
			wrapsNode = v
		}
	}

	// name — §6.2 이름 규칙
	if err := portrules.CheckSkillName(name); err != nil {
		fail("%v", err)
	}
	if strings.TrimSpace(description) == "" {
		fail("description is empty")
	}

	// ── node: 블록 ──
	in := map[string]port{}
	out := map[string]port{}
	if nodeNode == nil {
		fail("node key missing: no contract block")
		return done(fails, warns), nil
	}
	if nodeNode.Kind != yaml.MappingNode {
		fail("node key: block must be a mapping (yaml parse / in·out mapping)")
		return done(fails, warns), nil
	}
	checkDupKeys(nodeNode, "node", &fails)
	hasIn, hasOut := false, false
	for i := 0; i+1 < len(nodeNode.Content); i += 2 {
		k, v := nodeNode.Content[i], nodeNode.Content[i+1]
		switch k.Value {
		case "in":
			hasIn = true
			parsePorts(v, "in", in, &fails)
		case "out":
			hasOut = true
			parsePorts(v, "out", out, &fails)
		default:
			fail("node key %q is not allowed (in·out only)", k.Value)
		}
	}

	if !hasIn || !hasOut {
		fail("node: must have both in and out mappings")
	}
	checkContract("in", in, &fails)
	checkContract("out", out, &fails)

	// 출력 전부 required:false → 주의
	if len(out) > 0 {
		all := true
		for _, p := range out {
			if p.required() {
				all = false
			}
		}
		if all {
			warns = append(warns, "all output ports are required:false (7.5 주의 항목)")
		}
	}

	// ── 본문 세 절 (원시 `## ` 줄 대조) ──
	var heads []string
	var headIdx []int
	for i, l := range body {
		if strings.HasPrefix(l, "## ") {
			heads = append(heads, strings.TrimRight(l, " \t"))
			headIdx = append(headIdx, i)
		}
	}
	if len(heads) != 3 || heads[0] != "## 입력" || heads[1] != "## 실행" || heads[2] != "## 출력" {
		fail("sections: raw '## ' heading list must be exactly [## 입력, ## 실행, ## 출력], got %v", heads)
	} else {
		checkSection(body[headIdx[0]+1:headIdx[1]], "input section", in, &fails)
		checkSection(body[headIdx[2]+1:], "output section", out, &fails)
	}

	// ── wraps 체인 ──
	if wrapsNode != nil {
		checkWraps(wrapsNode, name, opts, &fails)
	}

	return done(fails, warns), nil
}

func done(fails, warns []string) Result {
	return Result{Pass: len(fails) == 0, Failures: fails, Warnings: warns}
}

func checkDupKeys(m *yaml.Node, where string, fails *[]string) {
	if m.Kind != yaml.MappingNode {
		for _, c := range m.Content {
			checkDupKeys(c, where, fails)
		}
		return
	}
	seen := map[string]bool{}
	for i := 0; i+1 < len(m.Content); i += 2 {
		k := m.Content[i]
		if seen[k.Value] {
			*fails = append(*fails, fmt.Sprintf("%s: duplicate mapping key %q", where, k.Value))
		}
		seen[k.Value] = true
		checkDupKeys(m.Content[i+1], where, fails)
	}
}

var allowedPortFields = map[string]bool{"shape": true, "list": true, "required": true, "values": true, "aligned": true}

func parsePorts(v *yaml.Node, dir string, dst map[string]port, fails *[]string) {
	if v.Kind != yaml.MappingNode {
		*fails = append(*fails, fmt.Sprintf("node %s: must be a mapping (yaml parse / in·out mapping)", dir))
		return
	}
	for i := 0; i+1 < len(v.Content); i += 2 {
		k, pv := v.Content[i], v.Content[i+1]
		if pv.Kind != yaml.MappingNode {
			*fails = append(*fails, fmt.Sprintf("node %s.%s: port must be a mapping", dir, k.Value))
			continue
		}
		for j := 0; j+1 < len(pv.Content); j += 2 {
			fk, fv := pv.Content[j], pv.Content[j+1]
			if !allowedPortFields[fk.Value] {
				*fails = append(*fails, fmt.Sprintf("node %s.%s: port field %q is not allowed", dir, k.Value, fk.Value))
			}
			if fk.Value == "required" && fv.Tag != "!!bool" {
				*fails = append(*fails, fmt.Sprintf("node %s.%s: required must be boolean", dir, k.Value))
			}
			if fk.Value == "list" && fv.Tag != "!!int" {
				*fails = append(*fails, fmt.Sprintf("node %s.%s: list must be an integer", dir, k.Value))
			}
		}
		var p port
		for j := 0; j+1 < len(pv.Content); j += 2 {
			switch pv.Content[j].Value {
			case "values":
				p.ValuesSet = true
			case "aligned":
				p.AlignedSet = true
			}
		}
		if err := pv.Decode(&p); err != nil {
			*fails = append(*fails, fmt.Sprintf("node %s.%s: %v", dir, k.Value, err))
			continue
		}
		dst[k.Value] = p
	}
}

func toShared(ports map[string]port) map[string]portrules.Port {
	out := make(map[string]portrules.Port, len(ports))
	for n, p := range ports {
		out[n] = portrules.Port{Shape: p.Shape, List: p.List, Required: p.Required,
			Values: p.Values, Aligned: p.Aligned, ValuesSet: p.ValuesSet, AlignedSet: p.AlignedSet}
	}
	return out
}

func checkContract(dir string, ports map[string]port, fails *[]string) {
	*fails = append(*fails, portrules.CheckContract(dir, toShared(ports))...)
}

func checkSection(lines []string, label string, ports map[string]port, fails *[]string) {
	fail := func(format string, a ...any) { *fails = append(*fails, fmt.Sprintf(format, a...)) }
	listed := map[string]bool{}
	for _, l := range lines {
		m := portItemRe.FindStringSubmatch(strings.TrimRight(l, " \t"))
		if m == nil {
			continue
		}
		name, rest := m[1], m[2]
		listed[name] = true
		if _, ok := ports[name]; !ok {
			fail("%s: port %q is not in contract", label, name)
		}
		desc := strings.TrimLeft(rest, " \t—–-")
		if strings.TrimSpace(desc) == "" {
			fail("%s: port %q has empty description", label, name)
		}
	}
	for name := range ports {
		if !listed[name] {
			fail("%s: missing port %q", label, name)
		}
	}
}

func checkWraps(v *yaml.Node, selfName string, opts Options, fails *[]string) {
	fail := func(format string, a ...any) { *fails = append(*fails, fmt.Sprintf(format, a...)) }
	var w wrapsRef
	if err := v.Decode(&w); err != nil {
		fail("wraps: %v", err)
		return
	}
	visited := map[string]bool{}
	if opts.SelfScope != "" {
		visited[selfName+"+"+opts.SelfScope] = true
	}
	cur := w
	for {
		key := cur.Name + "+" + cur.Scope
		if visited[key] {
			fail("wraps: chain cycles at %s", key)
			return
		}
		visited[key] = true
		if cur.Body == "" {
			fail("wraps: body hash missing for %s", key)
		}
		if cur.Scope != "project" && cur.Scope != "user" {
			fail("wraps: scope %q is not project|user", cur.Scope)
			return
		}
		target := ""
		if opts.OverlayDir != "" {
			p := filepath.Join(opts.OverlayDir, cur.Name, "SKILL.md")
			if _, err := os.Stat(p); err == nil {
				target = p
			}
		}
		if target == "" {
			var rootDir string
			if cur.Scope == "project" {
				rootDir = opts.ProjectDir
			} else {
				rootDir = opts.UserDir
			}
			if rootDir == "" {
				fail("wraps: no %s skill directory configured to resolve %s", cur.Scope, cur.Name)
				return
			}
			target = filepath.Join(rootDir, cur.Name, "SKILL.md")
		}
		md, err := os.ReadFile(target)
		if err != nil {
			fail("wraps: target %s does not exist", key)
			return
		}
		contract, _, err := hashesFor(md)
		if err != nil {
			fail("wraps: target %s: %v", key, err)
			return
		}
		if contract != cur.Contract {
			fail("wraps: contract hash of %s changed (recorded %s, current %s)", key, cur.Contract, contract)
		}
		// 대상이 또 어댑터면 체인을 따라간다
		next, hasNext, err := wrapsOf(md)
		if err != nil {
			fail("wraps: target %s frontmatter: %v", key, err)
			return
		}
		if !hasNext {
			return // 순환이 없으면 마지막은 wraps 없는 스킬
		}
		cur = next
	}
}

func wrapsOf(md []byte) (wrapsRef, bool, error) {
	text := string(md)
	lines := strings.Split(text, "\n")
	fmEnd := -1
	for i := 1; i < len(lines); i++ {
		if strings.TrimRight(lines[i], " \t") == "---" {
			fmEnd = i
			break
		}
	}
	if fmEnd == -1 {
		return wrapsRef{}, false, fmt.Errorf("no frontmatter")
	}
	var fmv struct {
		Wraps *wrapsRef `yaml:"wraps"`
	}
	if err := yaml.Unmarshal([]byte(strings.Join(lines[1:fmEnd], "\n")), &fmv); err != nil {
		return wrapsRef{}, false, err
	}
	if fmv.Wraps == nil {
		return wrapsRef{}, false, nil
	}
	return *fmv.Wraps, true, nil
}
