package graphcheck

// §8 조각 B1 — 재료 계약 로딩, 컨테이너 포트 파생, 배선 대조·상수·팬인·aligned.

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/celcheck"
	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/portrules"
	"gopkg.in/yaml.v3"
)

type yamlPort struct {
	Shape    string   `yaml:"shape"`
	List     *int     `yaml:"list"`
	Required *bool    `yaml:"required"`
	Values   []string `yaml:"values"`
	Aligned  string   `yaml:"aligned"`
}

func (yp yamlPort) shared() portrules.Port {
	return portrules.Port{Shape: yp.Shape, List: yp.List, Required: yp.Required,
		Values: yp.Values, Aligned: yp.Aligned}
}

// loadContract는 설치된 재료의 node: 계약을 읽는다.
func loadContract(opts Options, m material) (map[string]portrules.Port, map[string]portrules.Port, error) {
	dir, err := materialDir(opts, m)
	if err != nil {
		return nil, nil, err
	}
	md, err := os.ReadFile(filepath.Join(dir, "SKILL.md"))
	if err != nil {
		return nil, nil, fmt.Errorf("material %s(%s) does not exist", m.Name, m.Scope)
	}
	lines := strings.Split(string(md), "\n")
	fmEnd := -1
	for i := 1; i < len(lines); i++ {
		if strings.TrimRight(lines[i], " \t") == "---" {
			fmEnd = i
			break
		}
	}
	if fmEnd == -1 {
		return nil, nil, fmt.Errorf("material %s(%s): no frontmatter", m.Name, m.Scope)
	}
	var fmv struct {
		Node struct {
			In  map[string]yamlPort `yaml:"in"`
			Out map[string]yamlPort `yaml:"out"`
		} `yaml:"node"`
	}
	if err := yaml.Unmarshal([]byte(strings.Join(lines[1:fmEnd], "\n")), &fmv); err != nil {
		return nil, nil, fmt.Errorf("material %s(%s): %v", m.Name, m.Scope, err)
	}
	in := map[string]portrules.Port{}
	out := map[string]portrules.Port{}
	for n, p := range fmv.Node.In {
		in[n] = p.shared()
	}
	for n, p := range fmv.Node.Out {
		out[n] = p.shared()
	}
	return in, out, nil
}

func deepen(p portrules.Port, by int) portrules.Port {
	d := p.Depth() + by
	p.List = &d
	return p
}

func forceRequired(p portrules.Port) portrules.Port {
	req := true
	p.Required = &req
	return p
}

// derive는 구성 요소의 실효 입출력 포트를 계산한다. transform은 B2에서.
func derive(c *component, in, out map[string]portrules.Port, fails *[]string) (map[string]portrules.Port, map[string]portrules.Port) {
	fail := func(format string, a ...any) { *fails = append(*fails, fmt.Sprintf(format, a...)) }
	if c.Kind == "node" {
		return in, out
	}
	// container
	var split, expose []string
	var combine string
	if raw, ok := c.raw["split"]; ok {
		_ = json.Unmarshal(raw, &split)
	}
	if raw, ok := c.raw["expose"]; ok {
		_ = json.Unmarshal(raw, &expose)
	}
	if raw, ok := c.raw["combine"]; ok {
		_ = json.Unmarshal(raw, &combine)
	}

	dIn := map[string]portrules.Port{}
	dOut := map[string]portrules.Port{}

	if c.Rule == "items" {
		seen := map[string]bool{}
		for _, s := range split {
			if seen[s] {
				fail("%s: split name %q is not unique", c.ID, s)
			}
			seen[s] = true
			if _, ok := in[s]; !ok {
				fail("%s: split name %q is not an input of the inner skill", c.ID, s)
			}
		}
		if len(split) == 0 {
			fail("%s: items container needs at least one split input", c.ID)
		}
		if len(split) >= 2 && combine == "" {
			fail("%s: split has %d names — combine is required (5.7)", c.ID, len(split))
		}
		if len(split) == 1 && combine != "" {
			fail("%s: combine must be omitted when split has one name (5.7)", c.ID)
		}
		if combine != "" && combine != "zip" && combine != "product" && combine != "nested" {
			fail("%s: combine %q is not zip|product|nested", c.ID, combine)
		}
		for n, p := range in {
			partner := p.Aligned
			if partner == "" {
				partner = reverseAligned(in, n)
			}
			if partner == "" {
				continue
			}
			if seen[n] != seen[partner] {
				fail("%s: aligned pair %s·%s must join split together or stay out together (§8)", c.ID, n, partner)
			}
			if seen[n] && seen[partner] && combine != "zip" && len(split) >= 2 {
				fail("%s: aligned pair in split requires combine: zip (§8)", c.ID)
			}
		}
		for n, p := range in {
			if seen[n] {
				dIn[n] = deepen(p, 1)
			} else {
				dIn[n] = p
			}
		}
		outDepth := 1
		if combine == "nested" {
			outDepth = len(split)
		}
		exposeSet := map[string]bool{}
		for _, e := range expose {
			if exposeSet[e] {
				fail("%s: expose name %q is not unique", c.ID, e)
			}
			exposeSet[e] = true
			p, ok := out[e]
			if !ok {
				fail("%s: expose name %q is not an output of the inner skill", c.ID, e)
				continue
			}
			np := forceRequired(deepen(p, outDepth))
			if p.Aligned != "" {
				partnerExposed := false
				for _, other := range expose {
					if other == p.Aligned {
						partnerExposed = true
					}
				}
				if !partnerExposed {
					np.Aligned = "" // 짝의 상대가 노출되지 않으면 떼어진다(5.7)
				}
			}
			dOut[e] = np
		}
	} else { // condition
		if _, hasSplit := c.raw["split"]; hasSplit {
			fail("%s: condition container has no split", c.ID)
		}
		for n, p := range in {
			dIn[n] = p
		}
		exposeSet := map[string]bool{}
		for _, e := range expose {
			if exposeSet[e] {
				fail("%s: expose name %q is not unique", c.ID, e)
			}
			exposeSet[e] = true
			p, ok := out[e]
			if !ok {
				fail("%s: expose name %q is not an output of the inner skill", c.ID, e)
				continue
			}
			np := forceRequired(deepen(p, 0))
			if p.Aligned != "" && !contains(expose, p.Aligned) {
				np.Aligned = ""
			}
			dOut[e] = np
		}
	}
	return dIn, dOut
}

func contains(xs []string, s string) bool {
	for _, x := range xs {
		if x == s {
			return true
		}
	}
	return false
}

// constInfo는 JSON 상수 값의 리프를 전부 연다 — 깊이 집합·shape 집합·문자열 리프.
type constInfo struct {
	depths map[int]bool
	shapes map[string]bool
	leaves []string
	arrays []int // 최상위 배열 길이(-1이면 스칼라)
}

func constWalk(v any, depth int, ci *constInfo) {
	if arr, ok := v.([]any); ok {
		if len(arr) == 0 {
			ci.depths[depth+1] = true
			return
		}
		for _, el := range arr {
			constWalk(el, depth+1, ci)
		}
		return
	}
	ci.depths[depth] = true
	switch t := v.(type) {
	case string:
		ci.shapes["text"] = true
		ci.leaves = append(ci.leaves, t)
	case float64:
		ci.shapes["num"] = true
	case bool:
		ci.shapes["bool"] = true
	default:
		ci.shapes["json"] = true
	}
}

func constScan(raw json.RawMessage) (*constInfo, error) {
	var v any
	if err := json.Unmarshal(raw, &v); err != nil {
		return nil, err
	}
	ci := &constInfo{depths: map[int]bool{}, shapes: map[string]bool{}}
	if arr, ok := v.([]any); ok {
		ci.arrays = append(ci.arrays, len(arr))
	} else {
		ci.arrays = append(ci.arrays, -1)
	}
	constWalk(v, 0, ci)
	return ci, nil
}

// ── 조각 B2: transform 파생·표현식 연동 ──

type outSpec struct {
	Expr    string
	Aligned string
}

func transformSpecs(c *component, fails *[]string) map[string]outSpec {
	specs := map[string]outSpec{}
	raw, ok := c.raw["out"]
	if !ok {
		*fails = append(*fails, fmt.Sprintf("%s: transform needs out", c.ID))
		return specs
	}
	var outs map[string]map[string]json.RawMessage
	if err := json.Unmarshal(raw, &outs); err != nil {
		*fails = append(*fails, fmt.Sprintf("%s: transform out must be an object", c.ID))
		return specs
	}
	for name, fields := range outs {
		for k := range fields {
			if k != "expr" && k != "aligned" {
				*fails = append(*fails, fmt.Sprintf("%s.out.%s: field %q is not allowed (expr·aligned only, §8)", c.ID, name, k))
			}
		}
		var sp outSpec
		_ = json.Unmarshal(fields["expr"], &sp.Expr)
		_ = json.Unmarshal(fields["aligned"], &sp.Aligned)
		if sp.Expr == "" {
			*fails = append(*fails, fmt.Sprintf("%s.out.%s: expr missing", c.ID, name))
		}
		specs[name] = sp
	}
	return specs
}

// checkWiring — 파생 포트 계산(위상 순서로 transform 포함) 후 배선·상수·팬인·
// aligned·values 포섭·컨테이너 세부(until·max·carry)를 대조한다.
func checkWiring(comps map[string]*component, order []string, edges []edge,
	inPorts, outPorts map[string]portrules.Port,
	contracts map[string][2]map[string]portrules.Port, fails *[]string) {
	fail := func(format string, a ...any) { *fails = append(*fails, fmt.Sprintf(format, a...)) }

	compIn := map[string]map[string]portrules.Port{}
	compOut := map[string]map[string]portrules.Port{}
	for _, id := range order {
		c := comps[id]
		if c.Kind == "node" || c.Kind == "container" {
			if ct, ok := contracts[c.Skill]; ok {
				ci, co := derive(c, ct[0], ct[1], fails)
				compIn[id], compOut[id] = ci, co
			}
		}
	}

	// 수신 인덱스
	inboundRefs := map[string][]portRef{}
	for _, e := range edges {
		if e.Kind == "order" {
			continue
		}
		f, fok := parsePortRef(e.From)
		t, tok := parsePortRef(e.To)
		if fok && tok {
			inboundRefs[t.comp+".in."+t.port] = append(inboundRefs[t.comp+".in."+t.port], f)
		}
	}

	resolveFrom := func(r portRef) (portrules.Port, bool) {
		if r.comp == "graph" {
			p, ok := inPorts[r.port]
			return p, ok
		}
		if m := compOut[r.comp]; m != nil {
			p, ok := m[r.port]
			return p, ok
		}
		return portrules.Port{}, false
	}
	resolveTo := func(r portRef) (portrules.Port, bool) {
		if r.comp == "graph" {
			p, ok := outPorts[r.port]
			return p, ok
		}
		if m := compIn[r.comp]; m != nil {
			p, ok := m[r.port]
			return p, ok
		}
		return portrules.Port{}, false
	}

	// 위상 순서(데이터 엣지)로 transform 파생 — 상류 shape가 먼저 정해진다.
	indeg := map[string]int{}
	succ := map[string][]string{}
	for _, id := range order {
		indeg[id] = 0
	}
	for _, e := range edges {
		if e.Kind == "order" {
			continue
		}
		f, fok := parsePortRef(e.From)
		t, tok := parsePortRef(e.To)
		if fok && tok && f.comp != "graph" && t.comp != "graph" {
			if _, ok := comps[f.comp]; ok {
				if _, ok := comps[t.comp]; ok {
					succ[f.comp] = append(succ[f.comp], t.comp)
					indeg[t.comp]++
				}
			}
		}
	}
	var queue []string
	for _, id := range order {
		if indeg[id] == 0 {
			queue = append(queue, id)
		}
	}
	var topo []string
	for len(queue) > 0 {
		id := queue[0]
		queue = queue[1:]
		topo = append(topo, id)
		for _, n := range succ[id] {
			indeg[n]--
			if indeg[n] == 0 {
				queue = append(queue, n)
			}
		}
	}

	for _, id := range topo {
		c := comps[id]
		if c.Kind != "transform" {
			continue
		}
		specs := transformSpecs(c, fails)
		outNames := map[string]bool{}
		for n := range specs {
			outNames[n] = true
		}
		inDecl := map[string]celcheck.PortDecl{}
		inMap := map[string]portrules.Port{}
		for outName, sp := range specs {
			frees, err := celcheck.FreeNames(sp.Expr)
			if err != nil {
				fail("%s.out.%s: expr parse: %v", id, outName, err)
				continue
			}
			for _, fn := range frees {
				if outNames[fn] {
					fail("%s.out.%s: expr references output name %q (§12)", id, outName, fn)
					continue
				}
				if _, seen := inDecl[fn]; seen {
					continue
				}
				refs := inboundRefs[id+".in."+fn]
				if len(refs) == 0 {
					fail("%s.in.%s: transform input is not wired (§12-66)", id, fn)
					continue
				}
				fp, ok := resolveFrom(refs[0])
				if !ok {
					fail("%s.in.%s: upstream port %s.%s does not exist", id, fn, refs[0].comp, refs[0].port)
					continue
				}
				d := fp.Depth()
				inDecl[fn] = celcheck.PortDecl{Shape: fp.Shape, List: d, Values: fp.Values}
				dd := d
				inMap[fn] = portrules.Port{Shape: fp.Shape, List: &dd}
			}
		}
		for name := range inDecl {
			if outNames[name] {
				fail("%s: input and output share the name %q (5.5)", id, name)
			}
			if !portrules.PortNameRe.MatchString(name) {
				fail("%s.in.%s: port name must be non-empty, [a-z0-9_], no leading digit (3.1)", id, name)
			}
		}
		fanned := map[string]bool{}
		for name := range inDecl {
			if len(inboundRefs[id+".in."+name]) > 1 {
				fanned[name] = true
			}
		}
		if len(fanned) > 0 {
			for outName, sp := range specs {
				if v, err := celcheck.FanInZipViolations(sp.Expr, fanned); err == nil {
					for _, n := range v {
						fail("%s.out.%s: zip argument %q comes from a fanned-in port (§8)", id, outName, n)
					}
				}
			}
		}
		outMap := map[string]portrules.Port{}
		for outName, sp := range specs {
			resp := celcheck.Run(celcheck.Request{Expr: sp.Expr, In: inDecl})
			if !resp.OK {
				for _, e := range resp.Errors {
					fail("%s.out.%s: expr: %s", id, outName, e)
				}
				continue
			}
			d := resp.List
			p := portrules.Port{Shape: resp.Shape, List: &d, Values: resp.Values}
			if sp.Aligned != "" {
				p.Aligned = sp.Aligned
				p.AlignedSet = true
			}
			outMap[outName] = p
		}
		*fails = append(*fails, portrules.CheckContract(id+".out", outMap)...)
		compIn[id], compOut[id] = inMap, outMap
	}

	// ── 엣지 전수 대조 (shape·깊이·values 포섭) ──
	for i, e := range edges {
		if e.Kind == "order" {
			continue
		}
		f, fok := parsePortRef(e.From)
		t, tok := parsePortRef(e.To)
		if !fok || !tok {
			continue
		}
		fp, fOK := resolveFrom(f)
		tp, tOK := resolveTo(t)
		if !fOK {
			if _, exists := comps[f.comp]; exists && compOut[f.comp] != nil {
				fail("edges[%d]: port %s.out.%s does not exist", i, f.comp, f.port)
			}
			continue
		}
		if !tOK {
			if t.comp == "graph" {
				continue // 구조 검사에서 이미
			}
			if _, exists := comps[t.comp]; exists && compIn[t.comp] != nil {
				fail("edges[%d]: port %s.in.%s does not exist", i, t.comp, t.port)
			}
			continue
		}
		if fp.Shape != tp.Shape {
			fail("edges[%d]: shape mismatch %s(%s) → %s(%s)", i, e.From, fp.Shape, e.To, tp.Shape)
		}
		if fp.Depth() != tp.Depth() {
			fail("edges[%d]: depth mismatch %s(%d) → %s(%d)", i, e.From, fp.Depth(), e.To, tp.Depth())
		}
		if tp.ValuesSet || len(tp.Values) > 0 {
			if len(fp.Values) == 0 {
				fail("edges[%d]: %s declares values but %s has none (§8)", i, e.To, e.From)
			} else {
				for _, v := range fp.Values {
					if !contains(tp.Values, v) {
						fail("edges[%d]: values of %s are not subsumed by %s (§8)", i, e.From, e.To)
						break
					}
				}
			}
		}
	}

	// 팬인
	for key, froms := range inboundRefs {
		if len(froms) < 2 {
			continue
		}
		parts := strings.SplitN(key, ".in.", 2)
		r := portRef{comp: parts[0], dir: "in", port: parts[1]}
		tp, ok := resolveTo(r)
		if !ok {
			continue
		}
		if tp.Depth() < 1 {
			fail("fan-in into %s requires depth >= 1 (5.4)", key)
		}
		if tp.Aligned != "" || alignedPartnerIn(r, compIn, outPorts) != "" {
			fail("fan-in into %s: aligned pair ports cannot fan in (5.4)", key)
		}
		for _, fr := range froms {
			var fouts map[string]portrules.Port
			if fr.comp == "graph" {
				fouts = inPorts
			} else {
				fouts = compOut[fr.comp]
			}
			if fouts == nil {
				continue
			}
			fp, ok := fouts[fr.port]
			if !ok {
				continue
			}
			if fp.Aligned != "" || reverseAligned(fouts, fr.port) != "" {
				fail("fan-in into %s: upstream %s.%s is half of an aligned pair — inherited pair cannot fan in (§8)", key, fr.comp, fr.port)
				break
			}
		}
	}

	// 상수
	for _, id := range order {
		c := comps[id]
		raw, has := c.raw["const"]
		if !has {
			continue
		}
		var consts map[string]json.RawMessage
		if err := json.Unmarshal(raw, &consts); err != nil {
			fail("%s: const must be an object", id)
			continue
		}
		for pname, pval := range consts {
			var tp portrules.Port
			ok := false
			if m := compIn[id]; m != nil {
				tp, ok = m[pname]
			}
			if !ok {
				fail("%s: const target port %q is not in the contract (§12)", id, pname)
				continue
			}
			if len(inboundRefs[id+".in."+pname]) > 0 {
				fail("%s.in.%s: const and data edge on the same port (5.4)", id, pname)
			}
			ci, err := constScan(pval)
			if err != nil {
				fail("%s.in.%s: const value: %v", id, pname, err)
				continue
			}
			for d := range ci.depths {
				if d != tp.Depth() {
					fail("%s.in.%s: const depth %d does not match %d (모든 리프 대조)", id, pname, d, tp.Depth())
					break
				}
			}
			if tp.Shape != "json" {
				for sh := range ci.shapes {
					if sh != tp.Shape {
						fail("%s.in.%s: const leaf shape %s does not match %s", id, pname, sh, tp.Shape)
						break
					}
				}
			}
			if len(tp.Values) > 0 {
				for _, leaf := range ci.leaves {
					if !contains(tp.Values, leaf) {
						fail("%s.in.%s: const %q is outside declared values (§8)", id, pname, leaf)
					}
				}
			}
		}
	}

	// aligned 짝 둘 다 상수 — 최상위 배열 길이 대조 (§8)
	for _, id := range order {
		c := comps[id]
		raw, has := c.raw["const"]
		if !has {
			continue
		}
		var consts map[string]json.RawMessage
		if json.Unmarshal(raw, &consts) != nil {
			continue
		}
		m := compIn[id]
		if m == nil {
			continue
		}
		for pname, p := range m {
			partner := p.Aligned
			if partner == "" {
				partner = reverseAligned(m, pname)
			}
			if partner == "" || pname > partner {
				continue
			}
			ra, aok := consts[pname]
			rb, bok := consts[partner]
			if !aok || !bok {
				continue
			}
			ca, ea := constScan(ra)
			cb, eb := constScan(rb)
			if ea != nil || eb != nil {
				continue
			}
			if len(ca.arrays) > 0 && len(cb.arrays) > 0 && ca.arrays[0] >= 0 && cb.arrays[0] >= 0 && ca.arrays[0] != cb.arrays[0] {
				fail("%s: aligned pair %s·%s const lengths differ (%d vs %d) (§8 length)", id, pname, partner, ca.arrays[0], cb.arrays[0])
			}
		}
	}

	// 필수 입력 배선
	for _, id := range order {
		m := compIn[id]
		if m == nil {
			continue
		}
		c := comps[id]
		var consts map[string]json.RawMessage
		if raw, has := c.raw["const"]; has {
			_ = json.Unmarshal(raw, &consts)
		}
		for pname, p := range m {
			if !p.IsRequired() {
				continue
			}
			if len(inboundRefs[id+".in."+pname]) == 0 {
				if _, viaConst := consts[pname]; !viaConst {
					fail("%s.in.%s: required input is neither wired nor const (§8)", id, pname)
				}
			}
		}
	}

	// aligned 배선 대칭
	targetsOf := func(fromComp, fromPort string) map[string]int {
		out := map[string]int{}
		for _, e := range edges {
			if e.Kind == "order" {
				continue
			}
			f, fok := parsePortRef(e.From)
			t, tok := parsePortRef(e.To)
			if fok && tok && f.comp == fromComp && f.port == fromPort {
				out[t.comp]++
			}
		}
		return out
	}
	for _, id := range append([]string{"graph"}, order...) {
		var outs map[string]portrules.Port
		if id == "graph" {
			outs = inPorts
		} else {
			outs = compOut[id]
		}
		for pname, p := range outs {
			partner := p.Aligned
			if partner == "" {
				partner = reverseAligned(outs, pname)
			}
			if partner == "" {
				continue
			}
			myTargets := targetsOf(id, pname)
			partnerTargets := targetsOf(id, partner)
			for comp, n := range myTargets {
				if n > 1 {
					fail("%s.%s: aligned pair sends two edges into %s — pair mapping not unique (5.4)", id, pname, comp)
				}
				if partnerTargets[comp] == 0 {
					fail("%s.%s: aligned partner %q is not wired into %s (§8)", id, pname, partner, comp)
				}
			}
		}
	}

	// ── 조건 컨테이너 세부: until·max·carry ──
	for _, id := range order {
		c := comps[id]
		if c.Kind != "container" || c.Rule != "condition" {
			continue
		}
		ct, ok := contracts[c.Skill]
		if !ok {
			continue
		}
		innerIn, innerOut := ct[0], ct[1]

		var until string
		if raw, has := c.raw["until"]; has {
			_ = json.Unmarshal(raw, &until)
		}
		if until == "" {
			fail("%s: condition container needs until (5.7)", id)
		} else {
			decl := map[string]celcheck.PortDecl{}
			for n, p := range innerOut {
				decl[n] = celcheck.PortDecl{Shape: p.Shape, List: p.Depth(), Values: p.Values}
			}
			resp := celcheck.Run(celcheck.Request{Expr: until, In: decl})
			if !resp.OK {
				for _, e := range resp.Errors {
					fail("%s: until: %s", id, e)
				}
			} else if resp.Shape != "bool" || resp.List != 0 {
				fail("%s: until must yield bool, got %s list:%d (5.7)", id, resp.Shape, resp.List)
			}
		}

		if raw, has := c.raw["max"]; has {
			var m float64
			if err := json.Unmarshal(raw, &m); err != nil || m < 1 || m != float64(int(m)) {
				fail("%s: max must be an integer >= 1 (5.7)", id)
			}
		} else {
			fail("%s: condition container needs max (5.7)", id)
		}

		if raw, has := c.raw["carry"]; has {
			var carry map[string]string
			if err := json.Unmarshal(raw, &carry); err != nil {
				fail("%s: carry must be an object of output→input (5.7)", id)
			} else {
				usedIn := map[string]string{}
				for outName, inName := range carry {
					op, ok := innerOut[outName]
					if !ok {
						fail("%s: carry key %q is not an inner output (5.7)", id, outName)
						continue
					}
					ip, ok := innerIn[inName]
					if !ok {
						fail("%s: carry value %q is not an inner input (5.7)", id, inName)
						continue
					}
					if prev, dup := usedIn[inName]; dup {
						fail("%s: carry values %q and %q both target input %q — not unique (5.7)", id, prev, outName, inName)
					}
					usedIn[inName] = outName
					if op.Shape != ip.Shape || op.Depth() != ip.Depth() {
						fail("%s: carry %s→%s shape/depth mismatch (§8)", id, outName, inName)
					}
					if len(ip.Values) > 0 {
						if len(op.Values) == 0 {
							fail("%s: carry %s→%s: input declares values but output has none (§8)", id, outName, inName)
						} else {
							for _, v := range op.Values {
								if !contains(ip.Values, v) {
									fail("%s: carry %s→%s: values not subsumed (§8)", id, outName, inName)
									break
								}
							}
						}
					}
				}
				for outName := range carry {
					op, ok := innerOut[outName]
					if !ok {
						continue
					}
					partner := op.Aligned
					if partner == "" {
						partner = reverseAligned(innerOut, outName)
					}
					if partner != "" {
						if _, carried := carry[partner]; !carried {
							fail("%s: carry moves only one half of aligned pair %s·%s (§8)", id, outName, partner)
						}
					}
					inName := carry[outName]
					ip, ok := innerIn[inName]
					if !ok {
						continue
					}
					ipartner := ip.Aligned
					if ipartner == "" {
						ipartner = reverseAligned(innerIn, inName)
					}
					if ipartner != "" {
						found := false
						for _, tgt := range carry {
							if tgt == ipartner {
								found = true
							}
						}
						if !found {
							fail("%s: carry targets only one half of aligned input pair %s·%s (§8)", id, inName, ipartner)
						}
					}
				}
			}
		}
	}
}

func alignedPartnerIn(r portRef, compIn map[string]map[string]portrules.Port, _ map[string]portrules.Port) string {
	m := compIn[r.comp]
	if m == nil {
		return ""
	}
	p, ok := m[r.port]
	if !ok {
		return ""
	}
	if p.Aligned != "" {
		return p.Aligned
	}
	return reverseAligned(m, r.port)
}

func reverseAligned(ports map[string]portrules.Port, name string) string {
	for other, op := range ports {
		if op.Aligned == name {
			return other
		}
	}
	return ""
}
