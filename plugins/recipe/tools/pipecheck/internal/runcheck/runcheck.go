// Package runcheck — 스펙 §9.2의 값 검증. 시드·회차 출력·경계 자리 공용.
// 판정 기준은 9.3의 값 표현 규약이다. json이 낀 조합과 빈 배열은 공허 통과.
package runcheck

import (
	"encoding/json"
	"fmt"
	"math"
	"math/big"
	"strings"
)

type Port struct {
	Shape    string   `json:"shape"`
	List     *int     `json:"list"`
	Required *bool    `json:"required"`
	Values   []string `json:"values"`
	Aligned  string   `json:"aligned"`
}

func (p Port) depth() int {
	if p.List == nil {
		return 0
	}
	return *p.List
}

func (p Port) required() bool {
	if p.Required == nil {
		return true
	}
	return *p.Required
}

type Result struct {
	Pass     bool              `json:"pass"`
	Failures []string          `json:"failures,omitempty"`
	Filled   map[string]string `json:"filled,omitempty"` // required:false 생략의 빈 배열 보충
}

// Check는 포트 선언과 주어진 값(raw JSON)을 대조한다.
// boundary=true면 경계 입력 규칙(짝 함께 생략)을 함께 본다.
func Check(ports map[string]Port, given map[string][]byte, boundary bool) (Result, error) {
	var fails []string
	fail := func(format string, a ...any) { fails = append(fails, fmt.Sprintf(format, a...)) }
	filled := map[string]string{}
	originally := map[string]bool{}
	for name := range given {
		originally[name] = true
	}

	for name, p := range ports {
		raw, has := given[name]
		if !has {
			if p.required() {
				fail("%s: required port has no value (9.2)", name)
			} else {
				filled[name] = "[]"        // 빈 배열 보충(3.2)
				given[name] = []byte("[]") // 보충값도 aligned 대조에 참여한다
			}
			continue
		}
		checkValue(name, p, raw, fail)
	}
	for name := range given {
		if _, ok := ports[name]; !ok {
			fail("%s: value for an undeclared port (9.2)", name)
		}
	}

	// aligned 길이 — 바깥 축부터 차례로
	for name, p := range ports {
		if p.Aligned == "" {
			continue
		}
		partner, ok := ports[p.Aligned]
		if !ok {
			continue
		}
		_ = partner
		ra, aok := given[name]
		rb, bok := given[p.Aligned]
		if boundary {
			if originally[name] != originally[p.Aligned] {
				fail("%s·%s: aligned pair must be given or omitted together (9.2 pair)", name, p.Aligned)
				continue
			}
		}
		if !aok || !bok {
			continue
		}
		var va, vb any
		if json.Unmarshal(ra, &va) != nil || json.Unmarshal(rb, &vb) != nil {
			continue
		}
		if msg := compareAxes(va, vb, p.depth()); msg != "" {
			fail("%s·%s: aligned lengths differ — %s (9.2)", name, p.Aligned, msg)
		}
	}

	return Result{Pass: len(fails) == 0, Failures: fails, Filled: filled}, nil
}

func checkValue(name string, p Port, raw []byte, fail func(string, ...any)) {
	dupMembers(raw, name, fail)
	var v any
	dec := json.NewDecoder(strings.NewReader(string(raw)))
	dec.UseNumber()
	if err := dec.Decode(&v); err != nil {
		fail("%s: value is not valid JSON: %v (9.3)", name, err)
		return
	}
	if dec.More() {
		fail("%s: trailing content after the JSON value (9.3)", name)
		return
	}
	walkValue(name, p, v, 0, fail)
}

func walkValue(name string, p Port, v any, depth int, fail func(string, ...any)) {
	if arr, ok := v.([]any); ok {
		if depth == p.depth() {
			if p.Shape == "json" {
				return // json은 값만으로 못 가린다 — 공허(9.3)
			}
			fail("%s: array at depth %d but declared depth is %d (9.2 depth)", name, depth, p.depth())
			return
		}
		for _, el := range arr {
			walkValue(name, p, el, depth+1, fail)
		}
		return
	}
	if depth != p.depth() {
		if p.Shape == "json" {
			return
		}
		fail("%s: leaf at depth %d but declared depth is %d (9.2 depth)", name, depth, p.depth())
		return
	}
	switch t := v.(type) {
	case string:
		if p.Shape != "text" && p.Shape != "json" {
			fail("%s: leaf is text but shape is %s (9.2 shape)", name, p.Shape)
		}
		if p.Shape == "text" && len(p.Values) > 0 {
			for _, allowed := range p.Values {
				if allowed == t {
					return
				}
			}
			fail("%s: %q is outside declared values (9.2)", name, t)
		}
	case json.Number:
		if p.Shape != "num" && p.Shape != "json" {
			fail("%s: leaf is num but shape is %s (9.2 shape)", name, p.Shape)
			return
		}
		checkNumber(name, t, fail)
	case bool:
		if p.Shape != "bool" && p.Shape != "json" {
			fail("%s: leaf is bool but shape is %s (9.2 shape)", name, p.Shape)
		}
	default: // map, nil
		if p.Shape != "json" {
			fail("%s: leaf is json but shape is %s (9.2 shape)", name, p.Shape)
		}
	}
}

func checkNumber(name string, n json.Number, fail func(string, ...any)) {
	f, err := n.Float64()
	if err != nil || math.IsInf(f, 0) || math.IsNaN(f) {
		fail("%s: num value is not finite (9.2)", name)
		return
	}
	// double로 정확히 표현되지 않는 정수는 표기와 무관하게 거부(9.3) —
	// 십진 원문을 정확히 읽어 double 반올림 결과와 대조한다.
	s := n.String()
	exact, ok := new(big.Rat).SetString(s)
	if ok && exact.IsInt() {
		rounded := new(big.Rat).SetFloat64(f)
		if rounded == nil || exact.Cmp(rounded) != 0 {
			fail("%s: integer %s is not exactly representable as double (9.3)", name, s)
		}
	}
}

// dupMembers — 값 JSON의 어느 객체에도 같은 멤버 이름이 두 번 나오지 않는다(9.3).
func dupMembers(raw []byte, name string, fail func(string, ...any)) {
	dec := json.NewDecoder(strings.NewReader(string(raw)))
	var walk func() error
	walk = func() error {
		t, err := dec.Token()
		if err != nil {
			return err
		}
		if d, ok := t.(json.Delim); ok {
			switch d {
			case '{':
				seen := map[string]bool{}
				for dec.More() {
					kt, err := dec.Token()
					if err != nil {
						return err
					}
					k := kt.(string)
					if seen[k] {
						fail("%s: duplicate member name %q (9.3)", name, k)
					}
					seen[k] = true
					if err := walk(); err != nil {
						return err
					}
				}
				_, err := dec.Token()
				return err
			case '[':
				for dec.More() {
					if err := walk(); err != nil {
						return err
					}
				}
				_, err := dec.Token()
				return err
			}
		}
		return nil
	}
	_ = walk()
}

// compareAxes — aligned 짝의 길이를 바깥 축부터 최심축까지 대조한다.
func compareAxes(a, b any, depth int) string {
	if depth == 0 {
		return ""
	}
	aa, aok := a.([]any)
	bb, bok := b.([]any)
	if !aok || !bok {
		return ""
	}
	if len(aa) != len(bb) {
		return fmt.Sprintf("axis length %d vs %d", len(aa), len(bb))
	}
	for i := range aa {
		if msg := compareAxes(aa[i], bb[i], depth-1); msg != "" {
			return msg
		}
	}
	return ""
}
