package celcheck

// §4.4 zip 추출 특례와 §8의 리터럴 런타임 조건 검사 — 우리 층의 트리 순회.

import (
	"fmt"
	"math"

	celast "github.com/google/cel-go/common/ast"
	"github.com/google/cel-go/common/types"
)

// ── §8: 4.5 조건이 리터럴만으로 정해지는 자리는 컴파일에서 거부 ──

func scanLiteralRuntime(e celast.Expr, mcs map[int64]celast.Expr, errs *[]string) {
	if mc, ok := mcs[e.ID()]; ok {
		e = mc
	}
	switch e.Kind() {
	case celast.CallKind:
		c := e.AsCall()
		switch c.FunctionName() {
		case "chunk":
			if len(c.Args()) == 2 {
				if d, ok := evalLiteralDouble(c.Args()[1], mcs); ok {
					if d < 1 || d != math.Trunc(d) {
						*errs = append(*errs, fmt.Sprintf("chunk size literal %v must be an integer >= 1 (4.5/8)", d))
					}
				}
			}
		case "zip":
			if len(c.Args()) == 2 && c.Args()[0].Kind() == celast.ListKind && c.Args()[1].Kind() == celast.ListKind {
				a, b := c.Args()[0].AsList().Size(), c.Args()[1].AsList().Size()
				if a != b {
					*errs = append(*errs, fmt.Sprintf("zip literal list lengths differ: %d vs %d (4.5/8)", a, b))
				}
			}
		case "_/_":
			if len(c.Args()) == 2 {
				if d, ok := evalLiteralDouble(c.Args()[1], mcs); ok && d == 0 {
					*errs = append(*errs, "literal division by zero yields a non-finite num (4.5/8)")
				}
			}
		case "_[_]":
			if len(c.Args()) == 2 {
				checkMapLiteralKey(c.Args()[0], c.Args()[1], mcs, errs)
			}
		}
		if c.IsMemberFunction() {
			scanLiteralRuntime(c.Target(), mcs, errs)
		}
		for _, a := range c.Args() {
			scanLiteralRuntime(a, mcs, errs)
		}
	case celast.SelectKind:
		s := e.AsSelect()
		checkMapLiteralField(s.Operand(), s.FieldName(), mcs, errs)
		scanLiteralRuntime(s.Operand(), mcs, errs)
	default:
		for _, ch := range children(e) {
			scanLiteralRuntime(ch, mcs, errs)
		}
	}
}

func mapLiteralKeys(e celast.Expr) ([]string, bool) {
	if e.Kind() != celast.MapKind {
		return nil, false
	}
	var keys []string
	for _, en := range e.AsMap().Entries() {
		k := en.AsMapEntry().Key()
		if k.Kind() != celast.LiteralKind {
			return nil, false
		}
		sv, ok := k.AsLiteral().Value().(string)
		if !ok {
			return nil, false
		}
		keys = append(keys, sv)
	}
	return keys, true
}

func checkMapLiteralField(operand celast.Expr, field string, mcs map[int64]celast.Expr, errs *[]string) {
	if mc, ok := mcs[operand.ID()]; ok {
		operand = mc
	}
	keys, ok := mapLiteralKeys(operand)
	if !ok {
		return
	}
	for _, k := range keys {
		if k == field {
			return
		}
	}
	*errs = append(*errs, fmt.Sprintf("map literal has no key %q (4.5/8)", field))
}

func checkMapLiteralKey(operand, keyExpr celast.Expr, mcs map[int64]celast.Expr, errs *[]string) {
	if keyExpr.Kind() != celast.LiteralKind {
		return
	}
	sv, ok := keyExpr.AsLiteral().Value().(string)
	if !ok {
		return
	}
	checkMapLiteralField(operand, sv, mcs, errs)
}

// ── §4.4: shape 추론 — zip 추출 특례 포함 ──

type shapeInfo struct {
	kind   string   // scalar | list | pair
	shape  string   // scalar일 때 text|num|bool|json
	values []string // §8 전파 목록을 따라 흐르는 열거(text 스칼라)
	elem   *shapeInfo
	a, b   *shapeInfo
}

func (s *shapeInfo) flat() (string, int, bool) {
	depth := 0
	cur := s
	for cur.kind == "list" {
		depth++
		cur = cur.elem
	}
	if cur.kind == "scalar" {
		return cur.shape, depth, true
	}
	// pair가 값으로 남으면 맵이므로 json이다(§4.3 zip 결과).
	return "json", depth, true
}

func (s *shapeInfo) leafValues() []string {
	cur := s
	for cur != nil && cur.kind == "list" {
		cur = cur.elem
	}
	if cur != nil && cur.kind == "scalar" {
		return cur.values
	}
	return nil
}

func cloneWithLeafValues(s *shapeInfo, values []string) *shapeInfo {
	if s == nil {
		return nil
	}
	c := *s
	if c.kind == "list" {
		c.elem = cloneWithLeafValues(c.elem, values)
	} else if c.kind == "scalar" {
		c.values = values
	}
	return &c
}

func unionValues(a, b []string) []string {
	if len(a) == 0 || len(b) == 0 {
		return nil // 한쪽이라도 없으면 버린다(§8 — 팬인·삼항과 같은 규칙)
	}
	seen := map[string]bool{}
	var out []string
	for _, v := range append(append([]string{}, a...), b...) {
		if !seen[v] {
			seen[v] = true
			out = append(out, v)
		}
	}
	return out
}

func scalarInfo(shape string, depth int) *shapeInfo {
	cur := &shapeInfo{kind: "scalar", shape: shape}
	for i := 0; i < depth; i++ {
		cur = &shapeInfo{kind: "list", elem: cur}
	}
	return cur
}

type inferCtx struct {
	ports   map[string]PortDecl
	typeMap map[int64]*types.Type
	mcs     map[int64]celast.Expr
	binds   map[string]*shapeInfo
}

func (cx *inferCtx) fallback(e celast.Expr) *shapeInfo {
	t, ok := cx.typeMap[e.ID()]
	if !ok {
		return nil
	}
	shape, depth, err := typeToShape(t)
	if err != nil {
		return nil
	}
	return scalarInfo(shape, depth)
}

func elemOf(s *shapeInfo) *shapeInfo {
	if s == nil {
		return nil
	}
	if s.kind == "list" {
		return s.elem
	}
	if s.kind == "scalar" && s.shape == "json" {
		return s // dyn의 원소도 dyn
	}
	return nil
}

func (cx *inferCtx) infer(e celast.Expr) *shapeInfo {
	if mc, ok := cx.mcs[e.ID()]; ok {
		e = mc
	}
	switch e.Kind() {
	case celast.IdentKind:
		name := e.AsIdent()
		if b, ok := cx.binds[name]; ok {
			return b
		}
		if p, ok := cx.ports[name]; ok {
			si := scalarInfo(p.Shape, p.List)
			leaf := si
			for leaf.kind == "list" {
				leaf = leaf.elem
			}
			leaf.values = p.Values
			return si
		}
	case celast.SelectKind:
		s := e.AsSelect()
		op := cx.infer(s.Operand())
		if op != nil && op.kind == "pair" {
			if s.FieldName() == "a" {
				return op.a
			}
			if s.FieldName() == "b" {
				return op.b
			}
		}
	case celast.CallKind:
		c := e.AsCall()
		switch c.FunctionName() {
		case "_?_:_":
			if len(c.Args()) == 3 {
				x, y := cx.infer(c.Args()[1]), cx.infer(c.Args()[2])
				if x != nil && y != nil {
					return cloneWithLeafValues(x, unionValues(x.leafValues(), y.leafValues()))
				}
			}
		case "zip":
			if len(c.Args()) == 2 {
				ea, eb := elemOf(cx.infer(c.Args()[0])), elemOf(cx.infer(c.Args()[1]))
				if ea != nil && eb != nil {
					return &shapeInfo{kind: "list", elem: &shapeInfo{kind: "pair", a: ea, b: eb}}
				}
			}
		case "flatten":
			t := cx.infer(c.Target())
			if t != nil && t.kind == "list" {
				return t.elem // list(list(X)) → list(X): 바깥을 벗기면 elem이 list(X)
			}
		case "chunk":
			if len(c.Args()) == 2 {
				t := cx.infer(c.Args()[0])
				if t != nil {
					return &shapeInfo{kind: "list", elem: t}
				}
			}
		case "first_or":
			if len(c.Args()) == 2 {
				el := elemOf(cx.infer(c.Args()[0]))
				if el == nil {
					return nil
				}
				if c.Args()[1].Kind() == celast.LiteralKind {
					return el // 리터럴 대체값은 열거 안 검사(리터럴 대조)가 따로 본다
				}
				fb := cx.infer(c.Args()[1])
				var fv []string
				if fb != nil {
					fv = fb.leafValues()
				}
				return cloneWithLeafValues(el, unionValues(el.leafValues(), fv))
			}
		case "filter":
			if c.IsMemberFunction() && len(c.Args()) == 2 {
				return cx.infer(c.Target())
			}
		case "map":
			if c.IsMemberFunction() && len(c.Args()) == 2 && c.Args()[0].Kind() == celast.IdentKind {
				rng := cx.infer(c.Target())
				el := elemOf(rng)
				if el != nil {
					old, had := cx.binds[c.Args()[0].AsIdent()]
					cx.binds[c.Args()[0].AsIdent()] = el
					body := cx.infer(c.Args()[1])
					if had {
						cx.binds[c.Args()[0].AsIdent()] = old
					} else {
						delete(cx.binds, c.Args()[0].AsIdent())
					}
					if body != nil {
						return &shapeInfo{kind: "list", elem: body}
					}
				}
			}
		}
	}
	return cx.fallback(e)
}
