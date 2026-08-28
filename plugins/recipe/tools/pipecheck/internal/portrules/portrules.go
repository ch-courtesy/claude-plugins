// Package portrules — §3의 포트·이름 규칙. skillcheck(§6.4)와 graphcheck(§8)가 공유한다.
package portrules

import (
	"fmt"
	"regexp"
)

type Port struct {
	Shape      string
	List       *int
	Required   *bool
	Values     []string
	Aligned    string
	ValuesSet  bool
	AlignedSet bool
}

func (p Port) Depth() int {
	if p.List == nil {
		return 0
	}
	return *p.List
}

func (p Port) IsRequired() bool {
	if p.Required == nil {
		return true
	}
	return *p.Required
}

var (
	// 스킬·워크플로 이름(§6.2)과 구성 요소 id(§5.1): 소문자·숫자·밑줄·하이픈, 숫자 시작 금지, 한 글자 이상.
	NameRe = regexp.MustCompile(`^[a-z_-][a-z0-9_-]*$`)
	// 포트 이름(§3.1): 하이픈 없음.
	PortNameRe = regexp.MustCompile(`^[a-z_][a-z0-9_]*$`)
)

// CheckSkillName은 §6.2 이름 규칙(문자·길이)을 판정한다.
func CheckSkillName(name string) error {
	if name == "" || !NameRe.MatchString(name) || len(name) > 255 {
		return fmt.Errorf("name %q violates the 6.2 name rule (non-empty, [a-z0-9_-], no leading digit, <=255)", name)
	}
	return nil
}

var ValidShapes = map[string]bool{"text": true, "num": true, "bool": true, "json": true}

// CheckContract는 한 방향(in 또는 out)의 포트 집합에 §3 규칙을 적용한다.
func CheckContract(dir string, ports map[string]Port) []string {
	var fails []string
	fail := func(format string, a ...any) { fails = append(fails, fmt.Sprintf(format, a...)) }
	for name, p := range ports {
		if !PortNameRe.MatchString(name) {
			fail("%s.%s: port name must be non-empty, [a-z0-9_], no leading digit", dir, name)
		}
		if !ValidShapes[p.Shape] {
			fail("%s.%s: shape %q is not one of text·num·bool·json", dir, name, p.Shape)
		}
		if p.List != nil && *p.List < 0 {
			fail("%s.%s: list must be >= 0", dir, name)
		}
		if p.Required != nil && !*p.Required && p.Depth() < 1 {
			fail("%s.%s: required:false is allowed only at depth >= 1", dir, name)
		}
		if p.ValuesSet && len(p.Values) == 0 {
			fail("%s.%s: values must have at least one element", dir, name)
		}
		if p.AlignedSet && p.Aligned == "" {
			fail("%s.%s: aligned must name an existing port", dir, name)
		}
		if len(p.Values) > 0 {
			if p.Shape != "text" {
				fail("%s.%s: values only on shape: text ports", dir, name)
			}
			seen := map[string]bool{}
			for _, v := range p.Values {
				if v == "" {
					fail("%s.%s: values elements must be non-empty", dir, name)
				}
				if seen[v] {
					fail("%s.%s: values elements must be distinct", dir, name)
				}
				seen[v] = true
			}
		}
		if p.Aligned != "" {
			if p.Depth() < 1 {
				fail("%s.%s: aligned only on depth >= 1 ports", dir, name)
			}
			partner, ok := ports[p.Aligned]
			if !ok {
				fail("%s.%s: aligned target %q must exist in the same direction", dir, name, p.Aligned)
				continue
			}
			if partner.IsRequired() != p.IsRequired() || partner.Depth() != p.Depth() {
				fail("%s.%s: aligned pair must share required and depth", dir, name)
			}
		}
	}
	for name, p := range ports {
		seenPath := map[string]bool{name: true}
		cur := p
		for cur.Aligned != "" {
			if seenPath[cur.Aligned] {
				fails = append(fails, fmt.Sprintf("%s.%s: aligned reference cycle", dir, name))
				break
			}
			seenPath[cur.Aligned] = true
			next, ok := ports[cur.Aligned]
			if !ok {
				break
			}
			cur = next
		}
	}
	return fails
}
