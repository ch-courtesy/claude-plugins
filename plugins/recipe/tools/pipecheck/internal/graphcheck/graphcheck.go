// Package graphcheck — 스펙 §8 정적 검사. 조각 A: 파싱·스키마·재료·구조.
// 포트 파생·배선·표현식(조각 B)은 이 파일 뒤에 이어 붙는다.
package graphcheck

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/portrules"
	"gopkg.in/yaml.v3"
)

type Options struct {
	SelfName   string // 컴파일 대상 워크플로 이름(자기 재료 닫힘 판정)
	SelfScope  string
	ProjectDir string
	UserDir    string
	OverlayDir string // 승인 전 임시 위치 — 어느 scope에서든 설치본보다 먼저 찾는다(7.5)
}

type Result struct {
	Pass     bool     `json:"pass"`
	Failures []string `json:"failures,omitempty"`
	Warnings []string `json:"warnings,omitempty"`
}

type material struct {
	Name     string `json:"name"`
	Scope    string `json:"scope"`
	Contract string `json:"contract"`
	Body     string `json:"body"`
}

type edge struct {
	Kind string `json:"kind"`
	From string `json:"from"`
	To   string `json:"to"`
}

type component struct {
	ID    string `json:"id"`
	Kind  string `json:"kind"`
	Rule  string `json:"rule"`
	Skill string `json:"skill"`
	raw   map[string]json.RawMessage
}

type jsonPort struct {
	Shape    string   `json:"shape"`
	List     *int     `json:"list"`
	Required *bool    `json:"required"`
	Values   []string `json:"values"`
	Aligned  *string  `json:"aligned"`
}

func (jp jsonPort) shared(valuesSet bool) portrules.Port {
	p := portrules.Port{Shape: jp.Shape, List: jp.List, Required: jp.Required, Values: jp.Values, ValuesSet: valuesSet}
	if jp.Aligned != nil {
		p.Aligned = *jp.Aligned
		p.AlignedSet = true
	}
	return p
}

// ── JSON 중복 키 검사 (파서가 하나를 고르기 전에 원문에서) ──

func dupJSONKeys(raw []byte, fails *[]string) {
	dec := json.NewDecoder(strings.NewReader(string(raw)))
	dec.UseNumber()
	var walk func(path string) error
	walk = func(path string) error {
		t, err := dec.Token()
		if err != nil {
			return err
		}
		switch d := t.(type) {
		case json.Delim:
			switch d {
			case '{':
				seen := map[string]bool{}
				for dec.More() {
					kt, err := dec.Token()
					if err != nil {
						return err
					}
					key := kt.(string)
					if seen[key] {
						*fails = append(*fails, fmt.Sprintf("duplicate mapping key %q at %s (5.2)", key, path))
					}
					seen[key] = true
					if err := walk(path + "." + key); err != nil {
						return err
					}
				}
				_, err := dec.Token() // '}'
				return err
			case '[':
				i := 0
				for dec.More() {
					if err := walk(fmt.Sprintf("%s[%d]", path, i)); err != nil {
						return err
					}
					i++
				}
				_, err := dec.Token() // ']'
				return err
			}
		}
		return nil
	}
	_ = walk("$")
}

// ── 종별·재료 해소 ──

func rootFor(opts Options, scope string) string {
	if scope == "project" {
		return opts.ProjectDir
	}
	if scope == "user" {
		return opts.UserDir
	}
	return ""
}

type resolved struct {
	kind      string // skill | workflow | adapter | dual
	materials []material
	wraps     *material
}

func materialDir(opts Options, m material) (string, error) {
	if opts.OverlayDir != "" {
		d := filepath.Join(opts.OverlayDir, m.Name)
		if _, err := os.Stat(filepath.Join(d, "SKILL.md")); err == nil {
			return d, nil
		}
	}
	root := rootFor(opts, m.Scope)
	if root == "" {
		return "", fmt.Errorf("no %s skill directory configured", m.Scope)
	}
	return filepath.Join(root, m.Name), nil
}

func resolveMaterial(opts Options, m material) (resolved, error) {
	dir, err := materialDir(opts, m)
	if err != nil {
		return resolved{}, err
	}
	md, err := os.ReadFile(filepath.Join(dir, "SKILL.md"))
	if err != nil {
		return resolved{}, fmt.Errorf("material %s(%s) does not exist", m.Name, m.Scope)
	}
	r := resolved{kind: "skill"}
	if _, err := os.Stat(filepath.Join(dir, "graph.json")); err != nil && !os.IsNotExist(err) {
		return resolved{}, fmt.Errorf("material %s(%s): graph.json unreadable: %v", m.Name, m.Scope, err)
	}
	if gb, err := os.ReadFile(filepath.Join(dir, "graph.json")); err == nil {
		var g struct {
			Materials []material `json:"materials"`
		}
		if err := json.Unmarshal(gb, &g); err != nil {
			return resolved{}, fmt.Errorf("material %s(%s): graph.json: %v", m.Name, m.Scope, err)
		}
		r.kind = "workflow"
		r.materials = g.Materials
	}
	if w, ok, err := wrapsOf(md); err != nil {
		return resolved{}, fmt.Errorf("material %s(%s): %v", m.Name, m.Scope, err)
	} else if ok {
		if r.kind == "workflow" {
			return resolved{}, fmt.Errorf("material %s(%s) has both graph.json and wraps — kind undecidable (5.8)", m.Name, m.Scope)
		}
		r.kind = "adapter"
		r.wraps = &w
	}
	return r, nil
}

func wrapsOf(md []byte) (material, bool, error) {
	lines := strings.Split(string(md), "\n")
	fmEnd := -1
	for i := 1; i < len(lines); i++ {
		if strings.TrimRight(lines[i], " \t") == "---" {
			fmEnd = i
			break
		}
	}
	if fmEnd == -1 {
		return material{}, false, fmt.Errorf("no frontmatter")
	}
	var fmv struct {
		Wraps *material `yaml:"wraps"`
	}
	if err := yaml.Unmarshal([]byte(strings.Join(lines[1:fmEnd], "\n")), &fmv); err != nil {
		return material{}, false, err
	}
	if fmv.Wraps == nil {
		return material{}, false, nil
	}
	return *fmv.Wraps, true, nil
}

// ── 본검사 ──

var topKeys = []string{"name", "in", "out", "nodes", "edges", "materials"}

var fieldClosure = map[string]map[string]bool{
	"node":      {"id": true, "kind": true, "skill": true, "const": true},
	"transform": {"id": true, "kind": true, "out": true},
	"items":     {"id": true, "kind": true, "rule": true, "skill": true, "split": true, "expose": true, "combine": true, "const": true},
	"condition": {"id": true, "kind": true, "rule": true, "skill": true, "expose": true, "until": true, "max": true, "carry": true, "const": true},
}

func Check(raw []byte, opts Options) (Result, error) {
	var fails, warns []string
	fail := func(format string, a ...any) { fails = append(fails, fmt.Sprintf(format, a...)) }

	dupJSONKeys(raw, &fails)

	var top map[string]json.RawMessage
	if err := json.Unmarshal(raw, &top); err != nil {
		fail("graph.json parse: %v", err)
		return done(fails, warns), nil
	}

	// 최상위 폐쇄·타입 (5.2)
	known := map[string]bool{}
	for _, k := range topKeys {
		known[k] = true
		if _, ok := top[k]; !ok {
			fail("top-level key %q missing (5.2)", k)
		}
	}
	for k := range top {
		if !known[k] {
			fail("top-level key %q is not allowed (5.2)", k)
		}
	}

	var name string
	if err := json.Unmarshal(top["name"], &name); err != nil {
		fail("name must be a string (5.2)")
	} else if err := portrules.CheckSkillName(name); err != nil {
		fail("name: %v", err)
	}

	inPorts := parseBoundary(top["in"], "in", &fails)
	outPorts := parseBoundary(top["out"], "out", &fails)

	var rawNodes []map[string]json.RawMessage
	if err := json.Unmarshal(top["nodes"], &rawNodes); err != nil {
		fail("nodes must be an array of component objects (5.2)")
	}
	var edges []edge
	if err := json.Unmarshal(top["edges"], &edges); err != nil {
		fail("edges must be an array (5.2)")
	}
	var mats []material
	if err := json.Unmarshal(top["materials"], &mats); err != nil {
		fail("materials must be an array (5.2)")
	}
	var rawMats []map[string]json.RawMessage
	_ = json.Unmarshal(top["materials"], &rawMats)
	var rawEdges []map[string]json.RawMessage
	_ = json.Unmarshal(top["edges"], &rawEdges)
	edgeKeys := map[string]bool{"from": true, "to": true, "kind": true}
	for i, re := range rawEdges {
		for k := range re {
			if !edgeKeys[k] {
				fail("edges[%d]: field %q is not allowed (from·to·kind only, §8)", i, k)
			}
		}
	}

	// materials 항목 폐쇄·타입·이름·scope (5.2)
	matKeys := map[string]bool{"name": true, "scope": true, "contract": true, "body": true}
	for i, rm := range rawMats {
		for k := range rm {
			if !matKeys[k] {
				fail("materials[%d]: key %q is not allowed (5.2)", i, k)
			}
		}
		for k := range matKeys {
			if _, ok := rm[k]; !ok {
				fail("materials[%d]: key %q missing (5.2)", i, k)
			}
		}
	}
	seenMat := map[string]bool{}
	for i, m := range mats {
		if err := portrules.CheckSkillName(m.Name); err != nil {
			fail("materials[%d]: %v", i, err)
		}
		if m.Scope != "project" && m.Scope != "user" {
			fail("materials[%d]: scope %q is not project|user (5.2/7.5)", i, m.Scope)
		}
		if seenMat[m.Name] {
			fail("materials: name %q is not unique (5.2)", m.Name)
		}
		seenMat[m.Name] = true
	}

	// 구성 요소 (5.1·5.2·§8 재료 블록)
	comps := map[string]*component{}
	var order []string
	for i, rn := range rawNodes {
		c := &component{raw: rn}
		b, _ := json.Marshal(rn)
		_ = json.Unmarshal(b, c)
		if c.ID == "graph" || portrules.NameRe.FindString(c.ID) != c.ID || c.ID == "" {
			fail("nodes[%d]: id %q violates the 5.1 id rule", i, c.ID)
		}
		if _, dup := comps[c.ID]; dup {
			fail("nodes[%d]: id %q is not unique", i, c.ID)
		}
		closureKey := c.Kind
		if c.Kind == "container" {
			if c.Rule != "items" && c.Rule != "condition" {
				fail("nodes[%d]: rule %q is not items|condition", i, c.Rule)
				closureKey = ""
			} else {
				closureKey = c.Rule
			}
		} else if c.Kind != "node" && c.Kind != "transform" {
			fail("nodes[%d]: kind %q is not node·transform·container", i, c.Kind)
			closureKey = ""
		}
		if allowed, ok := fieldClosure[closureKey]; ok {
			for k := range rn {
				if !allowed[k] {
					fail("nodes[%d] (%s): field %q is not allowed for this kind", i, c.ID, k)
				}
			}
		}
		comps[c.ID] = c
		order = append(order, c.ID)
	}

	// skill ↔ materials 대응 (§8 재료)
	used := map[string]bool{}
	for _, id := range order {
		c := comps[id]
		if c.Kind == "node" || c.Kind == "container" {
			if c.Skill == "" {
				fail("%s: skill reference missing", id)
				continue
			}
			if !seenMat[c.Skill] {
				fail("%s: skill %q is not in materials", id, c.Skill)
			}
			used[c.Skill] = true
		}
	}
	for _, m := range mats {
		if !used[m.Name] {
			fail("materials: %q is unused — 안 쓰는 재료를 등재하지 않는다 (5.2)", m.Name)
		}
	}

	// 재료 실재 + 자기 전이 닫힘 (§8 재료)
	checkMaterialClosure(opts, mats, &fails)

	// 엣지 참조·구조 (§8 구조 조각)
	checkStructure(name, comps, order, edges, inPorts, outPorts, &fails, &warns)

	// 재료 계약 로딩 → 포트 파생 → 배선 대조 (조각 B1)
	contracts := map[string][2]map[string]portrules.Port{}
	for _, m := range mats {
		if ci, co, err := loadContract(opts, m); err == nil {
			contracts[m.Name] = [2]map[string]portrules.Port{ci, co}
		}
	}
	checkWiring(comps, order, edges, inPorts, outPorts, contracts, &fails)

	// 경계 포트 §3 규칙
	fails = append(fails, portrules.CheckContract("graph.in", inPorts)...)
	fails = append(fails, portrules.CheckContract("graph.out", outPorts)...)

	return done(fails, warns), nil
}

func done(fails, warns []string) Result {
	return Result{Pass: len(fails) == 0, Failures: fails, Warnings: warns}
}

func parseBoundary(raw json.RawMessage, dir string, fails *[]string) map[string]portrules.Port {
	out := map[string]portrules.Port{}
	if raw == nil {
		return out
	}
	var m map[string]json.RawMessage
	if err := json.Unmarshal(raw, &m); err != nil {
		*fails = append(*fails, fmt.Sprintf("%s must be an object (5.2)", dir))
		return out
	}
	for pname, praw := range m {
		var jp jsonPort
		var fields map[string]json.RawMessage
		if err := json.Unmarshal(praw, &fields); err != nil {
			*fails = append(*fails, fmt.Sprintf("%s.%s must be a port declaration object (5.2)", dir, pname))
			continue
		}
		allowed := map[string]bool{"shape": true, "list": true, "required": true, "values": true, "aligned": true}
		for k := range fields {
			if !allowed[k] {
				*fails = append(*fails, fmt.Sprintf("%s.%s: port field %q is not allowed", dir, pname, k))
			}
		}
		if err := json.Unmarshal(praw, &jp); err != nil {
			*fails = append(*fails, fmt.Sprintf("%s.%s: %v", dir, pname, err))
			continue
		}
		_, valuesSet := fields["values"]
		out[pname] = jp.shared(valuesSet)
	}
	return out
}

func checkMaterialClosure(opts Options, mats []material, fails *[]string) {
	selfKey := opts.SelfName + "+" + opts.SelfScope
	visited := map[string]bool{}
	var visit func(m material) bool
	visit = func(m material) bool {
		key := m.Name + "+" + m.Scope
		if key == selfKey {
			*fails = append(*fails, fmt.Sprintf("materials closure reaches self %s — 자기 재료 거부 (5.2)", key))
			return false
		}
		if visited[key] {
			return true
		}
		visited[key] = true
		r, err := resolveMaterial(opts, m)
		if err != nil {
			*fails = append(*fails, err.Error())
			return false
		}
		for _, sub := range r.materials {
			visit(sub)
		}
		if r.wraps != nil {
			visit(*r.wraps)
		}
		return true
	}
	for _, m := range mats {
		visit(m)
	}
}

type portRef struct {
	comp, dir, port string
}

func parsePortRef(s string) (portRef, bool) {
	parts := strings.Split(s, ".")
	if len(parts) != 3 || (parts[1] != "in" && parts[1] != "out") {
		return portRef{}, false
	}
	return portRef{comp: parts[0], dir: parts[1], port: parts[2]}, true
}

func checkStructure(graphName string, comps map[string]*component, order []string, edges []edge,
	inPorts, outPorts map[string]portrules.Port, fails *[]string, warns *[]string) {
	fail := func(format string, a ...any) { *fails = append(*fails, fmt.Sprintf(format, a...)) }

	// 인접(구성 요소 수준): data는 from 구성 요소 → to 구성 요소, order는 그대로.
	adj := map[string][]string{}
	rev := map[string][]string{}
	contributes := map[string]bool{} // 경계 출력으로의 도달 시드
	hasOrder := map[string]bool{}
	hasData := map[string]bool{}
	consumedBoundary := map[string]bool{}

	for i, e := range edges {
		kind := e.Kind
		if kind == "" {
			kind = "data"
		}
		switch kind {
		case "data":
			f, fok := parsePortRef(e.From)
			t, tok := parsePortRef(e.To)
			if !fok || !tok {
				fail("edges[%d]: data edge endpoints must be <id>.in|out.<port>", i)
				continue
			}
			wantFromDir := "out"
			if f.comp == "graph" {
				wantFromDir = "in"
			}
			wantToDir := "in"
			if t.comp == "graph" {
				wantToDir = "out"
			}
			if f.dir != wantFromDir || t.dir != wantToDir {
				fail("edges[%d]: wrong endpoint direction — from must be an output (graph.in), to an input (graph.out) (5.4)", i)
				continue
			}
			if f.comp == "graph" {
				if _, ok := inPorts[f.port]; !ok {
					fail("edges[%d]: graph.in.%s does not exist", i, f.port)
				}
				consumedBoundary[f.port] = true
			} else if _, ok := comps[f.comp]; !ok {
				fail("edges[%d]: component %q does not exist", i, f.comp)
			}
			if t.comp == "graph" {
				if _, ok := outPorts[t.port]; !ok {
					fail("edges[%d]: graph.out.%s does not exist", i, t.port)
				}
				if f.comp != "graph" {
					contributes[f.comp] = true
				}
			} else if _, ok := comps[t.comp]; !ok {
				fail("edges[%d]: component %q does not exist", i, t.comp)
			}
			if f.comp != "graph" && t.comp != "graph" {
				adj[f.comp] = append(adj[f.comp], t.comp)
				rev[t.comp] = append(rev[t.comp], f.comp)
			}
			if f.comp != "graph" {
				hasData[f.comp] = true
			}
			if t.comp != "graph" {
				hasData[t.comp] = true
			}
		case "order":
			if _, ok := comps[e.From]; !ok {
				fail("edges[%d]: order edge component %q does not exist", i, e.From)
			}
			if _, ok := comps[e.To]; !ok {
				fail("edges[%d]: order edge component %q does not exist", i, e.To)
			}
			adj[e.From] = append(adj[e.From], e.To)
			hasOrder[e.From] = true
			hasOrder[e.To] = true
		default:
			fail("edges[%d]: kind %q is not data|order", i, kind)
		}
	}

	// 미소비 경계 입력 (5.3)
	for pname := range inPorts {
		if !consumedBoundary[pname] {
			fail("boundary input %q has no outgoing data edge (5.3)", pname)
		}
	}

	// 사이클 (data+order 합산)
	state := map[string]int{}
	var dfs func(id string) bool
	dfs = func(id string) bool {
		state[id] = 1
		for _, n := range adj[id] {
			if state[n] == 1 {
				return false
			}
			if state[n] == 0 && !dfs(n) {
				return false
			}
		}
		state[id] = 2
		return true
	}
	for _, id := range order {
		if state[id] == 0 && !dfs(id) {
			fail("data+order edges form a cycle (§8 구조)")
			break
		}
	}

	// 경계 출력 기여(역도달) 또는 order 연결 — 유일 구성 요소 예외
	if len(order) > 1 {
		reach := map[string]bool{}
		var back func(id string)
		back = func(id string) {
			if reach[id] {
				return
			}
			reach[id] = true
			for _, p := range rev[id] {
				back(p)
			}
		}
		for id := range contributes {
			back(id)
		}
		for _, id := range order {
			if !reach[id] && !hasOrder[id] {
				fail("component %q neither reaches a boundary output nor joins an order edge (§8 구조)", id)
			}
		}
	}

	// order로만 매달린 구성 요소 — 주의
	for _, id := range order {
		if hasOrder[id] && !hasData[id] && !contributes[id] {
			*warns = append(*warns, fmt.Sprintf("component %q hangs on order edges only (7.5 주의)", id))
		}
	}

	// 필수 경계 출력 기여 존재
	for pname, p := range outPorts {
		found := false
		for _, e := range edges {
			if e.Kind == "" || e.Kind == "data" {
				if t, ok := parsePortRef(e.To); ok && t.comp == "graph" && t.port == pname {
					found = true
				}
			}
		}
		if !found && p.IsRequired() {
			fail("required boundary output %q has no incoming data edge", pname)
		}
	}
	_ = graphName
}
