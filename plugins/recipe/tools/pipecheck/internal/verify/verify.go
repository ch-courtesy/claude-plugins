// Package verify — 스펙 §9.1-1의 실행 전 재귀 대조.
// 이 그래프의 materials를 먼저 전부 확인한 뒤 하위로 내려간다. 방문 집합은
// 하위 재귀만 막고, 대조는 재료가 등장할 때마다 한다. 보고는 이름·설치 위치·
// 최상위로부터의 경로·기록/현재 해시다.
package verify

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/hash"
	"gopkg.in/yaml.v3"
)

type Options struct {
	ProjectDir string
	UserDir    string
}

type Result struct {
	Pass     bool     `json:"pass"`
	Failures []string `json:"failures,omitempty"`
}

type material struct {
	Name     string `json:"name" yaml:"name"`
	Scope    string `json:"scope" yaml:"scope"`
	Contract string `json:"contract" yaml:"contract"`
	Body     string `json:"body" yaml:"body"`
}

type graphFile struct {
	Materials []material `json:"materials"`
}

func rootFor(o Options, scope string) string {
	switch scope {
	case "project":
		return o.ProjectDir
	case "user":
		return o.UserDir
	}
	return ""
}

// Run은 최상위 graph.json에서 시작해 재료 폐포를 대조한다.
func Run(topGraph []byte, opts Options) (Result, error) {
	var fails []string
	fail := func(format string, a ...any) { fails = append(fails, fmt.Sprintf(format, a...)) }

	var top graphFile
	if err := json.Unmarshal(topGraph, &top); err != nil {
		return Result{}, fmt.Errorf("graph.json: %w", err)
	}

	visited := map[string]bool{}

	// 대조: 이 층의 재료 전부 → 그다음 하위로(§9.1-1 순서).
	var level func(path []string, mats []material)
	level = func(path []string, mats []material) {
		type sub struct {
			m    material
			mats []material
			w    *material
		}
		var next []sub
		for _, m := range mats {
			key := m.Name + "+" + m.Scope
			p := strings.Join(append(append([]string{}, path...), m.Name), " → ")
			root := rootFor(opts, m.Scope)
			if root == "" {
				fail("%s(%s): no %s directory configured — 경로 %s", m.Name, m.Scope, m.Scope, p)
				continue
			}
			dir := filepath.Join(root, m.Name)
			md, err := os.ReadFile(filepath.Join(dir, "SKILL.md"))
			if err != nil {
				fail("%s(%s): material does not exist — 경로 %s", m.Name, m.Scope, p)
				continue
			}
			var g []byte
			hasGraph := false
			if gb, err := os.ReadFile(filepath.Join(dir, "graph.json")); err == nil {
				g = gb
				hasGraph = true
			} else if !os.IsNotExist(err) {
				fail("%s(%s): graph.json unreadable: %v — 경로 %s", m.Name, m.Scope, err, p)
				continue
			}
			w, hasWraps, err := wrapsOf(md)
			if err != nil {
				fail("%s(%s): %v — 경로 %s", m.Name, m.Scope, err, p)
				continue
			}
			if hasGraph && hasWraps {
				fail("%s(%s): has both graph.json and wraps — kind undecidable (5.8) — 경로 %s", m.Name, m.Scope, p)
				continue
			}
			cur, _, err := hash.SkillHashes(md, g)
			if err != nil {
				fail("%s(%s): %v — 경로 %s", m.Name, m.Scope, err, p)
				continue
			}
			if cur != m.Contract {
				fail("%s(%s): contract changed — 경로 %s, 기록 %s ≠ 현재 %s (9.1-1)", m.Name, m.Scope, p, m.Contract, cur)
			}
			if visited[key] {
				continue // 하위 재귀만 막는다 — 대조는 위에서 이미 했다
			}
			visited[key] = true
			s := sub{m: m}
			if hasGraph {
				var gf graphFile
				if err := json.Unmarshal(g, &gf); err != nil {
					fail("%s(%s): graph.json: %v — 경로 %s", m.Name, m.Scope, err, p)
					continue
				}
				s.mats = gf.Materials
			}
			if hasWraps {
				s.w = &w
			}
			next = append(next, s)
		}
		for _, s := range next {
			childPath := append(append([]string{}, path...), s.m.Name)
			if len(s.mats) > 0 {
				level(childPath, s.mats)
			}
			if s.w != nil {
				level(childPath, []material{*s.w})
			}
		}
	}
	level([]string{"top"}, top.Materials)

	return Result{Pass: len(fails) == 0, Failures: fails}, nil
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
