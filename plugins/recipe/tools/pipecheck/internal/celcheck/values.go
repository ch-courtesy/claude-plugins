package celcheck

// §8: values가 선언된 포트와 맞대는 리터럴의 열거 대조, 리터럴 폴딩, zip 팬인 인자.

import (
	"fmt"

	celast "github.com/google/cel-go/common/ast"
)

// evalLiteralDouble — 리터럴만으로 정해지는 double 부분식을 접는다(§8 "리터럴만으로").
func evalLiteralDouble(e celast.Expr, mcs map[int64]celast.Expr) (float64, bool) {
	if mc, ok := mcs[e.ID()]; ok {
		e = mc
	}
	switch e.Kind() {
	case celast.LiteralKind:
		d, ok := e.AsLiteral().Value().(float64)
		return d, ok
	case celast.CallKind:
		c := e.AsCall()
		if len(c.Args()) != 2 {
			return 0, false
		}
		a, aok := evalLiteralDouble(c.Args()[0], mcs)
		b, bok := evalLiteralDouble(c.Args()[1], mcs)
		if !aok || !bok {
			return 0, false
		}
		switch c.FunctionName() {
		case "_+_":
			return a + b, true
		case "_-_":
			return a - b, true
		case "_*_":
			return a * b, true
		case "_/_":
			if b == 0 {
				return 0, false // 0 나눗셈은 별도 항목이 거부한다
			}
			return a / b, true
		}
	}
	return 0, false
}

// scanValuesLiterals — 비교(==·!=)·in·first_or에서 values 포트와 맞대는 문자열
// 리터럴이 열거 안인지 본다. ports는 이름→선언.
func scanValuesLiterals(e celast.Expr, mcs map[int64]celast.Expr, ports map[string]PortDecl, errs *[]string) {
	if mc, ok := mcs[e.ID()]; ok {
		e = mc
	}
	if e.Kind() == celast.CallKind {
		c := e.AsCall()
		args := c.Args()
		check := func(identExpr, litExpr celast.Expr) {
			ident := identOf(identExpr, mcs)
			if ident == "" {
				return
			}
			p, ok := ports[ident]
			if !ok || len(p.Values) == 0 {
				return
			}
			lit, ok := literalString(litExpr, mcs)
			if !ok {
				return
			}
			for _, v := range p.Values {
				if v == lit {
					return
				}
			}
			*errs = append(*errs, fmt.Sprintf("literal %q is outside the declared values of %q (§8)", lit, ident))
		}
		switch c.FunctionName() {
		case "_==_", "_!=_":
			if len(args) == 2 {
				check(args[0], args[1])
				check(args[1], args[0])
			}
		case "@in":
			if len(args) == 2 {
				check(args[1], args[0])
			}
		case "first_or":
			if len(args) == 2 {
				check(args[0], args[1])
			}
		}
	}
	for _, ch := range children(e) {
		scanValuesLiterals(ch, mcs, ports, errs)
	}
	if e.Kind() == celast.CallKind && e.AsCall().IsMemberFunction() {
		scanValuesLiterals(e.AsCall().Target(), mcs, ports, errs)
	}
}

func identOf(e celast.Expr, mcs map[int64]celast.Expr) string {
	if mc, ok := mcs[e.ID()]; ok {
		e = mc
	}
	if e.Kind() == celast.IdentKind {
		return e.AsIdent()
	}
	return ""
}

func literalString(e celast.Expr, mcs map[int64]celast.Expr) (string, bool) {
	if mc, ok := mcs[e.ID()]; ok {
		e = mc
	}
	if e.Kind() != celast.LiteralKind {
		return "", false
	}
	s, ok := e.AsLiteral().Value().(string)
	return s, ok
}

// FanInZipViolations — 팬인된 포트 이름이 zip 인자로 직접 쓰이면 그 이름들을 낸다(§8).
func FanInZipViolations(expr string, fanned map[string]bool) ([]string, error) {
	env, err := NewEnv(nil)
	if err != nil {
		return nil, err
	}
	parsed, iss := env.Parse(expr)
	if iss != nil && iss.Err() != nil {
		return nil, iss.Err()
	}
	mcs := parsed.NativeRep().SourceInfo().MacroCalls()
	var out []string
	var walk func(e celast.Expr)
	walk = func(e celast.Expr) {
		if mc, ok := mcs[e.ID()]; ok {
			e = mc
		}
		if e.Kind() == celast.CallKind {
			c := e.AsCall()
			if c.FunctionName() == "zip" {
				for _, a := range c.Args() {
					if n := identOf(a, mcs); n != "" && fanned[n] {
						out = append(out, n)
					}
				}
			}
			if c.IsMemberFunction() {
				walk(c.Target())
			}
			for _, a := range c.Args() {
				walk(a)
			}
			return
		}
		for _, ch := range children(e) {
			walk(ch)
		}
	}
	walk(parsed.NativeRep().Expr())
	return out, nil
}
