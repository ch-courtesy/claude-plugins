package celcheck

// §12 CEL 바인딩 묶음(환경 시험) 배터리 — celcheck -selftest에서 이식.
// 스펙 §4.3 환경 구성·§8 트리 검사·§4.2 포트 타입 폐쇄의 실행 계약이다.

import "testing"

func TestSpecBattery(t *testing.T) {
	ports := map[string]PortDecl{
		"n":     {Shape: "num"},
		"one":   {Shape: "text"},
		"items": {Shape: "text", List: 1},
		"nest":  {Shape: "text", List: 2},
		"rest":  {Shape: "json", List: 1},
	}
	cases := []struct {
		name   string
		expr   string
		wantOK bool
	}{
		// §12 환경 시험 — 제거가 걸렸는가
		{"conversion_int_excluded", "int(n)", false},
		{"timestamp_excluded", "timestamp('2026-01-01T00:00:00Z')", false},
		{"duration_excluded", "duration('1h')", false},
		{"matches_excluded", "one.matches('a')", false},
		{"sort_not_registered", "items.sort()", false},
		{"slice_not_registered", "items.slice(0, 1)", false},
		// 호스트 등록 생존
		{"flatten_ok", "nest.flatten()", true},
		{"join_ok", "items.join(',')", true},
		{"zip_ok", "zip(items, items)", true},
		{"chunk_ok", "chunk(items, 2.0)", true},
		{"first_or_ok", "first_or(items, 'x')", true},
		// 표준 생존
		{"arith_ok", "n + 1.0", true},
		{"size_cmp_ok", "size(rest) == 0", true},
		{"filter_macro_ok", "items.filter(x, x != '')", true},
		{"exists_one_macro_excluded", "items.exists_one(x, x == 'a')", false},
		{"has_macro_excluded", "has(rest.foo)", false},
		// 우리 층 트리 검사 (§8 — 매크로 전 형태)
		{"bytes_literal_rejected", "{'payload': b'abc'}", false},
		{"bool_map_key_rejected", "{true: 'x'}", false},
		{"int_map_key_rejected", "{1: 'x'}", false},
		{"string_map_key_ok", "{'k': 'v'}", true},
		{"empty_list_bare_rejected", "[]", false},
		{"empty_list_as_arg_ok", "first_or([], 'x')", true},
		// §4.2 포트 결과 타입 폐쇄
		{"uint_result_rejected", "1u", false},
		{"int_result_rejected", "size(items)", false},
		{"null_result_rejected", "null", false},
		{"double_ok", "1.5", true},
		// 체커 소관 — 피연산자 타입
		{"int_plus_double_rejected", "1 + 1.0", false},
		// 정본 예제(§5.2 pick)
		{"spec_pick_expr_ok", "zip(rest.flatten(), rest.flatten()).filter(p, p.b == 'x').map(p, p.a)", true},
		// §8: 4.5 조건이 리터럴만으로 정해지는 자리는 컴파일 거부
		{"chunk_literal_zero_rejected", "chunk(items, 0.0)", false},
		{"chunk_literal_fraction_rejected", "chunk(items, 1.5)", false},
		{"chunk_port_size_ok", "chunk(items, n)", true},
		{"zip_literal_len_mismatch_rejected", "zip(['a', 'b'], ['x', 'y', 'z'])", false},
		{"zip_literal_len_match_ok", "zip(['a'], ['x'])", true},
		{"literal_div_zero_rejected", "1.0 / 0.0", false},
		{"map_literal_missing_key_rejected", "{'a': 'x'}.b", false},
		{"map_literal_missing_key_index_rejected", "{'a': 'x'}['b']", false},
		{"map_literal_present_key_ok", "{'a': 'x'}.a", true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := Run(Request{Expr: c.expr, In: ports})
			if got.OK != c.wantOK {
				t.Fatalf("expr %q: ok=%v want=%v errors=%v", c.expr, got.OK, c.wantOK, got.Errors)
			}
		})
	}
}

// §4.4 zip 추출 특례 — .a·.b는 원 인자의 원소 shape, 중첩 zip은 재귀.
func TestZipExtraction(t *testing.T) {
	ports := map[string]PortDecl{
		"paths": {Shape: "text", List: 1},
		"flags": {Shape: "bool", List: 1},
	}
	cases := []struct {
		expr  string
		shape string
		list  int
	}{
		{"zip(paths, flags).map(p, p.a)", "text", 1},
		{"zip(paths, flags).map(p, p.b)", "bool", 1},
		{"zip(paths, zip(flags, paths)).map(p, p.b.a)", "bool", 1},
		{"zip(paths, flags).filter(p, p.b).map(p, p.a)", "text", 1},
	}
	for _, c := range cases {
		t.Run(c.expr, func(t *testing.T) {
			got := Run(Request{Expr: c.expr, In: ports})
			if !got.OK {
				t.Fatalf("errors=%v", got.Errors)
			}
			if got.Shape != c.shape || got.List != c.list {
				t.Fatalf("got %s/%d want %s/%d (celType=%s)", got.Shape, got.List, c.shape, c.list, got.CelType)
			}
		})
	}
}
