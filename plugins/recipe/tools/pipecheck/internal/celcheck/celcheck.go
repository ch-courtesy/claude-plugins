// celcheck — 스펙 §4의 CEL 호스트 환경으로 표현식 하나를 체크하는 CLI.
//
// 입력(stdin, JSON):
//
//	{"expr": "...", "in": {"포트명": {"shape": "text|num|bool|json", "list": 0}}}
//
// 출력(stdout, JSON):
//
//	{"ok": true,  "shape": "...", "list": n, "celType": "..."}
//	{"ok": false, "errors": ["..."]}
//
// 환경은 §4.3 그대로: 표준에서 형변환·시간·문자열 묶음을 빼고,
// flatten·join·zip·chunk·first_or를 호스트 등록한다. §8의 우리 층
// 트리 검사 중 리터럴 스캔(bytes 리터럴, 비문자열 키 맵 리터럴,
// 함수 인자 밖 빈 배열)과 §4.2 포트 결과 타입 표 폐쇄를 함께 본다.
//
// -selftest 는 §12의 CEL 바인딩 묶음(환경 시험) 배터리를 돌린다.
package celcheck

import (
	"fmt"

	"github.com/google/cel-go/cel"
	celast "github.com/google/cel-go/common/ast"
	celenv "github.com/google/cel-go/common/env"
	"github.com/google/cel-go/common/types"
	"github.com/google/cel-go/common/types/ref"
)

type PortDecl struct {
	Shape  string   `json:"shape"`
	List   int      `json:"list"`
	Values []string `json:"values,omitempty"`
}

type Request struct {
	Expr string              `json:"expr"`
	In   map[string]PortDecl `json:"in"`
}

type Response struct {
	OK      bool     `json:"ok"`
	Shape   string   `json:"shape,omitempty"`
	List    int      `json:"list,omitempty"`
	Values  []string `json:"values,omitempty"`
	CelType string   `json:"celType,omitempty"`
	Errors  []string `json:"errors,omitempty"`
}

// §4.3: 표준이 주지만 열거에 없는 함수 전부 — 형변환·시간·문자열 묶음.
var excludedFns = []string{
	"int", "uint", "double", "string", "bool", "bytes", "dyn", "type",
	"timestamp", "duration",
	"matches", "startsWith", "endsWith", "contains",
	"getDate", "getDayOfMonth", "getDayOfWeek", "getDayOfYear", "getFullYear",
	"getHours", "getMilliseconds", "getMinutes", "getMonth", "getSeconds",
}

func shapeToType(shape string, list int) (*cel.Type, error) {
	var t *cel.Type
	switch shape {
	case "text":
		t = cel.StringType
	case "num":
		t = cel.DoubleType
	case "bool":
		t = cel.BoolType
	case "json":
		t = cel.DynType
	default:
		return nil, fmt.Errorf("unknown shape %q", shape)
	}
	for i := 0; i < list; i++ {
		t = cel.ListType(t)
	}
	return t, nil
}

// §4.2 역방향: 추론 결과를 shape·깊이로 되읽는다. 표 밖 타입은 오류.
func typeToShape(t *cel.Type) (string, int, error) {
	depth := 0
	for t.Kind() == types.ListKind {
		params := t.Parameters()
		if len(params) != 1 {
			return "json", depth, nil
		}
		t = params[0]
		depth++
	}
	switch t.Kind() {
	case types.DoubleKind:
		return "num", depth, nil
	case types.StringKind:
		return "text", depth, nil
	case types.BoolKind:
		return "bool", depth, nil
	case types.DynKind, types.AnyKind, types.MapKind:
		return "json", depth, nil
	case types.TypeParamKind:
		// 원소 타입이 미정인 빈 컨텍스트 — json으로 승격하지 않고 거부.
		return "", 0, fmt.Errorf("unresolved type parameter %s", t)
	default:
		return "", 0, fmt.Errorf("type %s is outside the 4.2 mapping", t)
	}
}

func NewEnv(ports map[string]PortDecl) (*cel.Env, error) {
	ex := make([]*celenv.Function, 0, len(excludedFns))
	for _, name := range excludedFns {
		ex = append(ex, celenv.NewFunction(name))
	}
	subset := celenv.NewLibrarySubset().AddExcludedFunctions(ex...).
		AddExcludedMacros("exists_one", "has") // §4.3 허용 매크로는 filter·map·exists·all뿐

	opts := []cel.EnvOption{
		cel.StdLib(cel.StdLibSubset(subset)),
		cel.EnableMacroCallTracking(),
		cel.Function("flatten",
			cel.MemberOverload("list_list_flatten",
				[]*cel.Type{cel.ListType(cel.ListType(cel.TypeParamType("T")))},
				cel.ListType(cel.TypeParamType("T")))),
		cel.Function("join",
			cel.MemberOverload("list_string_join_string",
				[]*cel.Type{cel.ListType(cel.StringType), cel.StringType},
				cel.StringType)),
		cel.Function("zip",
			cel.Overload("zip_list_list",
				[]*cel.Type{cel.ListType(cel.TypeParamType("A")), cel.ListType(cel.TypeParamType("B"))},
				cel.ListType(cel.DynType))),
		cel.Function("chunk",
			cel.Overload("chunk_list_double",
				[]*cel.Type{cel.ListType(cel.TypeParamType("T")), cel.DoubleType},
				cel.ListType(cel.ListType(cel.TypeParamType("T"))))),
		cel.Function("first_or",
			cel.Overload("first_or_list_elem",
				[]*cel.Type{cel.ListType(cel.TypeParamType("T")), cel.TypeParamType("T")},
				cel.TypeParamType("T"))),
	}
	for name, p := range ports {
		t, err := shapeToType(p.Shape, p.List)
		if err != nil {
			return nil, fmt.Errorf("port %s: %w", name, err)
		}
		opts = append(opts, cel.Variable(name, t))
	}
	return cel.NewCustomEnv(opts...)
}

// 매크로 전 형태의 트리 스캔 — bytes 리터럴, 함수 인자 밖 빈 배열.
// mcs: 매크로 호출 추적 맵 — 전개 자리를 원 호출 형태로 치환해 훑는다(§12-222).
func scanParsed(e celast.Expr, parentIsCallArg bool, mcs map[int64]celast.Expr, errs *[]string) {
	if mc, ok := mcs[e.ID()]; ok {
		e = mc
	}
	switch e.Kind() {
	case celast.LiteralKind:
		if _, isBytes := e.AsLiteral().(interface{ ConvertToType(ref.Type) ref.Val }); isBytes {
			if types.Bytes(nil).Type() == e.AsLiteral().Type() {
				*errs = append(*errs, "bytes literal is not allowed (4.3)")
			}
		}
	case celast.ListKind:
		l := e.AsList()
		if l.Size() == 0 && !parentIsCallArg {
			*errs = append(*errs, "empty list literal outside function arguments (4.2)")
		}
		for _, el := range l.Elements() {
			scanParsed(el, false, mcs, errs)
		}
		return
	case celast.CallKind:
		c := e.AsCall()
		if c.IsMemberFunction() {
			scanParsed(c.Target(), false, mcs, errs)
		}
		for _, a := range c.Args() {
			scanParsed(a, true, mcs, errs)
		}
		return
	case celast.MapKind:
		for _, en := range e.AsMap().Entries() {
			me := en.AsMapEntry()
			scanParsed(me.Key(), false, mcs, errs)
			scanParsed(me.Value(), false, mcs, errs)
		}
		return
	case celast.SelectKind:
		scanParsed(e.AsSelect().Operand(), false, mcs, errs)
		return
	case celast.ComprehensionKind:
		co := e.AsComprehension()
		scanParsed(co.IterRange(), false, mcs, errs)
		scanParsed(co.AccuInit(), false, mcs, errs)
		scanParsed(co.LoopCondition(), false, mcs, errs)
		scanParsed(co.LoopStep(), false, mcs, errs)
		scanParsed(co.Result(), false, mcs, errs)
		return
	case celast.StructKind:
		for _, f := range e.AsStruct().Fields() {
			scanParsed(f.AsStructField().Value(), false, mcs, errs)
		}
		return
	}
}

// 체크된 트리에서 맵 리터럴 키의 추론 타입이 string인지 본다(§8).
func scanMapKeys(e celast.Expr, typeMap map[int64]*types.Type, errs *[]string) {
	if e.Kind() == celast.MapKind {
		for _, en := range e.AsMap().Entries() {
			me := en.AsMapEntry()
			kt, ok := typeMap[me.Key().ID()]
			if !ok || kt.Kind() != types.StringKind {
				*errs = append(*errs, "map literal key must be string-typed (4.3)")
			}
		}
	}
	for _, ch := range children(e) {
		scanMapKeys(ch, typeMap, errs)
	}
}

func children(e celast.Expr) []celast.Expr {
	switch e.Kind() {
	case celast.CallKind:
		c := e.AsCall()
		out := []celast.Expr{}
		if c.IsMemberFunction() {
			out = append(out, c.Target())
		}
		return append(out, c.Args()...)
	case celast.ListKind:
		return e.AsList().Elements()
	case celast.MapKind:
		out := []celast.Expr{}
		for _, en := range e.AsMap().Entries() {
			me := en.AsMapEntry()
			out = append(out, me.Key(), me.Value())
		}
		return out
	case celast.SelectKind:
		return []celast.Expr{e.AsSelect().Operand()}
	case celast.ComprehensionKind:
		co := e.AsComprehension()
		return []celast.Expr{co.IterRange(), co.AccuInit(), co.LoopCondition(), co.LoopStep(), co.Result()}
	case celast.StructKind:
		out := []celast.Expr{}
		for _, f := range e.AsStruct().Fields() {
			out = append(out, f.AsStructField().Value())
		}
		return out
	}
	return nil
}

func Run(req Request) Response {
	env, err := NewEnv(req.In)
	if err != nil {
		return Response{Errors: []string{err.Error()}}
	}

	var errs []string

	// 1) 매크로 전 형태 스캔 (§8: 리터럴을 읽는 항목들)
	parsed, iss := env.Parse(req.Expr)
	if iss != nil && iss.Err() != nil {
		return Response{Errors: []string{"parse: " + iss.Err().Error()}}
	}
	scanParsed(parsed.NativeRep().Expr(), false, parsed.NativeRep().SourceInfo().MacroCalls(), &errs)
	scanLiteralRuntime(parsed.NativeRep().Expr(), parsed.NativeRep().SourceInfo().MacroCalls(), &errs)
	scanValuesLiterals(parsed.NativeRep().Expr(), parsed.NativeRep().SourceInfo().MacroCalls(), req.In, &errs)

	// 2) CEL 체크 단계
	checked, iss := env.Check(parsed)
	if iss != nil && iss.Err() != nil {
		errs = append(errs, "check: "+iss.Err().Error())
		return Response{Errors: errs}
	}

	// 3) 맵 리터럴 키 타입 (§8)
	scanMapKeys(checked.NativeRep().Expr(), checked.NativeRep().TypeMap(), &errs)

	// 4) §4.4 shape 추론(zip 추출 특례 포함) — 실패하면 §4.2 표 폐쇄 판정으로.
	var shape string
	var depth int
	var outValues []string
	cx := &inferCtx{
		ports:   req.In,
		typeMap: checked.NativeRep().TypeMap(),
		mcs:     checked.NativeRep().SourceInfo().MacroCalls(),
		binds:   map[string]*shapeInfo{},
	}
	if si := cx.infer(checked.NativeRep().Expr()); si != nil {
		shape, depth, _ = si.flat()
		outValues = si.leafValues()
	} else {
		var err error
		shape, depth, err = typeToShape(checked.OutputType())
		if err != nil {
			errs = append(errs, err.Error())
		}
	}

	if len(errs) > 0 {
		return Response{Errors: errs}
	}
	return Response{OK: true, Shape: shape, List: depth, Values: outValues, CelType: checked.OutputType().String()}
}
