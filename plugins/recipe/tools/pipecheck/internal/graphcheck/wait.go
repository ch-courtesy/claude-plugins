package graphcheck

// wait — 사람의 응답(by: human)이나 바깥 완료(by: check)를 기다리는 구성 요소.
// human은 들어오는 엣지에서 입력 포트를 파생하고 출력은 mode가 정한다.
// check는 노드처럼 재료 계약을 쓰고, 그 계약은 done(bool)을 내야 한다.

import (
	"encoding/json"
	"fmt"

	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/portrules"
)

var waitModes = map[string]bool{"answer": true, "approve": true, "edit": true, "task": true}

func boolPort() portrules.Port { return portrules.Port{Shape: "bool"} }
func textPort() portrules.Port { return portrules.Port{Shape: "text"} }

// humanWaitPorts는 human wait의 필드를 검사하고 출력 포트를 낸다. in은 엣지에서 파생한 입력이다.
func humanWaitPorts(c *component, in map[string]portrules.Port, fails *[]string) map[string]portrules.Port {
	fail := func(format string, a ...any) { *fails = append(*fails, fmt.Sprintf(format, a...)) }
	var prompt string
	if raw, ok := c.raw["prompt"]; !ok || json.Unmarshal(raw, &prompt) != nil || prompt == "" {
		fail("%s: human wait needs prompt (non-empty string)", c.ID)
	}
	if !waitModes[c.Mode] {
		fail("%s: mode %q is not answer|approve|edit|task", c.ID, c.Mode)
		return nil
	}
	_, hasAnswer := c.raw["answer"]
	if hasAnswer && c.Mode != "answer" {
		fail("%s: answer is only for mode: answer", c.ID)
	}
	out := map[string]portrules.Port{}
	switch c.Mode {
	case "answer":
		if !hasAnswer {
			fail("%s: mode answer needs answer (port declaration)", c.ID)
			return out
		}
		var fields map[string]json.RawMessage
		if err := json.Unmarshal(c.raw["answer"], &fields); err != nil {
			fail("%s: answer must be a port declaration object", c.ID)
			return out
		}
		for k := range fields {
			if k != "shape" && k != "list" && k != "required" && k != "values" {
				fail("%s.answer: port field %q is not allowed (shape·list·required·values)", c.ID, k)
			}
		}
		var jp jsonPort
		if err := json.Unmarshal(c.raw["answer"], &jp); err != nil {
			fail("%s.answer: %v", c.ID, err)
			return out
		}
		_, valuesSet := fields["values"]
		out["answer"] = jp.shared(valuesSet)
		*fails = append(*fails, portrules.CheckContract(c.ID+".answer", out)...)
	case "approve":
		out["approved"] = boolPort()
		out["note"] = textPort()
	case "edit":
		if len(in) != 1 {
			fail("%s: mode edit needs exactly one wired input (the value to edit), got %d", c.ID, len(in))
			return out
		}
		for _, p := range in {
			p.Aligned, p.AlignedSet = "", false
			out["edited"] = p
		}
	case "task":
		out["note"] = textPort()
	}
	for name := range in {
		if _, clash := out[name]; clash {
			fail("%s: input and output share the name %q", c.ID, name)
		}
	}
	return out
}

// checkWaitContract는 by: check 재료가 done(bool, 깊이 0, 필수)을 내는지 본다.
func checkWaitContract(c *component, out map[string]portrules.Port, fails *[]string) {
	p, ok := out["done"]
	if !ok || p.Shape != "bool" || p.Depth() != 0 || !p.IsRequired() {
		*fails = append(*fails, fmt.Sprintf("%s: check material %q must output done (bool, depth 0, required)", c.ID, c.Skill))
	}
}
