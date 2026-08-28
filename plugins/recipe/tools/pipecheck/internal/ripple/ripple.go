// Package ripple — 스펙 §5.8의 파급 보고.
// 설치된 워크플로의 graph.json materials와 어댑터의 wraps를 역참조로 훑어,
// 대상을 재료로 쓰는 소비자를 전이적으로 모은다. materials·wraps 경유가
// 각 1층, 경로가 여럿이면 최단 층수. 버킷은 직접 소비자의 기록 해시 대조.
package ripple

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
)

type Target struct {
	Name     string
	Scope    string
	Contract string // 현재(새) 계약 해시
	Body     string // 현재(새) 본문 해시
}

type Options struct {
	ProjectDir string
	UserDir    string
}

type Consumer struct {
	Name          string `json:"name"`
	Scope         string `json:"scope"`
	Kind          string `json:"kind"` // workflow | adapter
	Layers        int    `json:"layers"`
	ContractStale bool   `json:"contractStale,omitempty"` // 직접 소비자만 의미
	BodyStale     bool   `json:"bodyStale,omitempty"`
	Recorded      string `json:"recorded,omitempty"` // 직접 소비자의 기록 "contract body"
}

type Report struct {
	Consumers []Consumer `json:"consumers"`
	Errors    []string   `json:"errors,omitempty"`
}

type matRef struct {
	Name     string `json:"name"`
	Scope    string `json:"scope"`
	Contract string `json:"contract"`
	Body     string `json:"body"`
}

type graphFile struct {
	Materials []matRef `json:"materials"`
}

type entry struct {
	name, scope string
	kind        string   // workflow | adapter | skill | dual
	refs        []matRef // 이 산출물이 가리키는 재료들(materials 또는 wraps 한 개)
}

func key(name, scope string) string { return name + "+" + scope }

// scan은 두 설치 디렉터리의 산출물 전부를 종별과 함께 읽는다.
func scan(opts Options) (map[string]entry, []string, error) {
	out := map[string]entry{}
	var errs []string
	for scope, root := range map[string]string{"project": opts.ProjectDir, "user": opts.UserDir} {
		if root == "" {
			continue
		}
		dirs, err := os.ReadDir(root)
		if err != nil {
			if os.IsNotExist(err) {
				continue
			}
			return nil, nil, err
		}
		for _, d := range dirs {
			if !d.IsDir() {
				continue
			}
			name := d.Name()
			mdPath := filepath.Join(root, name, "SKILL.md")
			md, err := os.ReadFile(mdPath)
			if err != nil {
				continue // SKILL.md 없는 디렉터리는 산출물이 아니다
			}
			hasGraph := false
			var g graphFile
			if _, err := os.Stat(filepath.Join(root, name, "graph.json")); err != nil && !os.IsNotExist(err) {
				errs = append(errs, fmt.Sprintf("%s(%s): graph.json unreadable: %v", name, scope, err))
				continue
			}
			if gb, err := os.ReadFile(filepath.Join(root, name, "graph.json")); err == nil {
				hasGraph = true
				if err := json.Unmarshal(gb, &g); err != nil {
					errs = append(errs, fmt.Sprintf("%s(%s): graph.json: %v", name, scope, err))
					continue
				}
			}
			w, hasWraps, err := wrapsOf(md)
			if err != nil {
				errs = append(errs, fmt.Sprintf("%s(%s): %v", name, scope, err))
				continue
			}
			e := entry{name: name, scope: scope}
			switch {
			case hasGraph && hasWraps:
				// 종별을 가를 수 없다 — 가지를 중단하고 오류 항목으로.
				e.kind = "dual"
				errs = append(errs, fmt.Sprintf("%s(%s): has both graph.json and wraps — kind undecidable (5.8)", name, scope))
			case hasGraph:
				e.kind = "workflow"
				e.refs = g.Materials
			case hasWraps:
				e.kind = "adapter"
				e.refs = []matRef{w}
			default:
				e.kind = "skill"
			}
			out[key(name, scope)] = e
		}
	}
	return out, errs, nil
}

func wrapsOf(md []byte) (matRef, bool, error) {
	lines := strings.Split(string(md), "\n")
	fmEnd := -1
	for i := 1; i < len(lines); i++ {
		if strings.TrimRight(lines[i], " \t") == "---" {
			fmEnd = i
			break
		}
	}
	if fmEnd == -1 {
		return matRef{}, false, fmt.Errorf("no frontmatter")
	}
	var fmv struct {
		Wraps *matRef `yaml:"wraps"`
	}
	if err := yaml.Unmarshal([]byte(strings.Join(lines[1:fmEnd], "\n")), &fmv); err != nil {
		return matRef{}, false, err
	}
	if fmv.Wraps == nil {
		return matRef{}, false, nil
	}
	return *fmv.Wraps, true, nil
}

// Compute는 대상의 소비자 전이 폐포를 BFS로 모은다 — 층수가 곧 BFS 레벨(최단).
func Compute(t Target, opts Options) (Report, error) {
	entries, errs, err := scan(opts)
	if err != nil {
		return Report{}, err
	}

	// 역참조 인덱스: 재료 key → 그것을 직접 가리키는 산출물들
	reverse := map[string][]entry{}
	directRec := map[string]matRef{} // 소비자key+대상key → 기록
	for _, e := range entries {
		if e.kind == "dual" {
			continue // 가지 중단
		}
		for _, r := range e.refs {
			rk := key(r.Name, r.Scope)
			reverse[rk] = append(reverse[rk], e)
			directRec[key(e.name, e.scope)+"→"+rk] = r
		}
	}

	start := key(t.Name, t.Scope)
	visited := map[string]int{start: 0}
	queue := []string{start}
	var consumers []Consumer
	for len(queue) > 0 {
		cur := queue[0]
		queue = queue[1:]
		for _, e := range reverse[cur] {
			ck := key(e.name, e.scope)
			if _, seen := visited[ck]; seen {
				continue // 방문 집합이 순환을 끊는다
			}
			visited[ck] = visited[cur] + 1
			queue = append(queue, ck)
			c := Consumer{Name: e.name, Scope: e.scope, Kind: e.kind, Layers: visited[ck]}
			if rec, ok := directRec[ck+"→"+start]; ok && visited[ck] == 1 {
				c.ContractStale = rec.Contract != t.Contract
				c.BodyStale = rec.Body != t.Body
				c.Recorded = rec.Contract + " " + rec.Body
			}
			consumers = append(consumers, c)
		}
	}
	sort.Slice(consumers, func(i, j int) bool {
		if consumers[i].Layers != consumers[j].Layers {
			return consumers[i].Layers < consumers[j].Layers
		}
		return consumers[i].Name < consumers[j].Name
	})
	return Report{Consumers: consumers, Errors: errs}, nil
}
