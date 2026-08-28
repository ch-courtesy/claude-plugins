package celcheck

// FreeNames — 식이 참조하는 자유 이름(§4.1: transform의 입력 포트가 된다).

import (
	celast "github.com/google/cel-go/common/ast"
)

func FreeNames(expr string) ([]string, error) {
	env, err := NewEnv(nil)
	if err != nil {
		return nil, err
	}
	parsed, iss := env.Parse(expr)
	if iss != nil && iss.Err() != nil {
		return nil, iss.Err()
	}
	mcs := parsed.NativeRep().SourceInfo().MacroCalls()
	seen := map[string]bool{}
	var names []string
	var walk func(e celast.Expr, bound map[string]bool)
	walk = func(e celast.Expr, bound map[string]bool) {
		if mc, ok := mcs[e.ID()]; ok {
			e = mc
		}
		switch e.Kind() {
		case celast.IdentKind:
			n := e.AsIdent()
			if !bound[n] && !seen[n] {
				seen[n] = true
				names = append(names, n)
			}
		case celast.CallKind:
			c := e.AsCall()
			fn := c.FunctionName()
			if c.IsMemberFunction() && (fn == "filter" || fn == "map" || fn == "exists" || fn == "all") &&
				len(c.Args()) == 2 && c.Args()[0].Kind() == celast.IdentKind {
				walk(c.Target(), bound)
				inner := map[string]bool{}
				for k := range bound {
					inner[k] = true
				}
				inner[c.Args()[0].AsIdent()] = true
				walk(c.Args()[1], inner)
				return
			}
			if c.IsMemberFunction() {
				walk(c.Target(), bound)
			}
			for _, a := range c.Args() {
				walk(a, bound)
			}
		default:
			for _, ch := range children(e) {
				walk(ch, bound)
			}
		}
	}
	walk(parsed.NativeRep().Expr(), map[string]bool{})
	return names, nil
}
