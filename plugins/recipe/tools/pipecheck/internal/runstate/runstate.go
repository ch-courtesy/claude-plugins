// Package runstate — 워크플로 실행 상태(.pipelines/runs/<run-id>/)를 읽고 쓴다.
//
// run.json에 실행 머리(워크플로·상태·graph 해시·경계 입력)를, items/에 구성 요소마다
// 파일 하나를 둔다. 구성 요소 파일이 따로라서 하위 워크플로를 맡은 서브에이전트
// 런너와 최상위 런너가 같은 실행에 동시에 적어도 서로 덮어쓰지 않는다. 쓰기는 같은
// 디렉터리의 임시 파일에 쓴 뒤 이름을 바꿔 한 번에 바뀐다.
package runstate

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

// Refusal은 요청이 실행 상태와 맞지 않아 거부한 경우다 — 호출 오류가 아니라 불통과다.
type Refusal struct{ Msg string }

func (r Refusal) Error() string { return r.Msg }

func refuse(format string, a ...any) error { return Refusal{fmt.Sprintf(format, a...)} }

type Meta struct {
	Run      string          `json:"run"`
	Workflow string          `json:"workflow"`
	Status   string          `json:"status"` // running | waiting | done | failed | cancelled
	Graph    string          `json:"graph"`  // 시작 시점 graph.json 해시
	Inputs   json.RawMessage `json:"inputs"`
	Created  string          `json:"created"`
	Updated  string          `json:"updated"`
}

type Item struct {
	ID      string          `json:"id"`
	State   string          `json:"state"` // started | waiting | done
	Out     json.RawMessage `json:"out,omitempty"`
	Wait    json.RawMessage `json:"wait,omitempty"`
	Updated string          `json:"updated"`
}

var (
	runRe = regexp.MustCompile(`^[a-z_-][a-z0-9_-]*$`)
	seg   = `[a-z_-][a-z0-9_-]*(#[0-9]+)?`
	// 구성 요소 경로 id: 하위 워크플로는 /로 잇고, 컨테이너 회차는 #n(0부터)을 붙인다.
	idRe = regexp.MustCompile(`^` + seg + `(/` + seg + `)*$`)
)

func terminal(s string) bool { return s == "done" || s == "failed" || s == "cancelled" }

func now() string { return time.Now().UTC().Format(time.RFC3339) }

func graphHash(graph []byte) string { return fmt.Sprintf("sha256:%x", sha256.Sum256(graph)) }

func graphName(graph []byte) (string, error) {
	var g struct {
		Name string `json:"name"`
	}
	if err := json.Unmarshal(graph, &g); err != nil || g.Name == "" || !runRe.MatchString(g.Name) {
		return "", fmt.Errorf("graph.json: name missing or invalid")
	}
	return g.Name, nil
}

func runDir(dir, run string) (string, error) {
	if !runRe.MatchString(run) {
		return "", fmt.Errorf("run id %q is invalid", run)
	}
	return filepath.Join(dir, run), nil
}

// itemFile은 경로 id를 파일 이름으로 바꾼다 — id 문자에 없는 . 과 @ 로 / 와 # 를 대신해 되돌릴 수 있다.
func itemFile(rd, id string) string {
	return filepath.Join(rd, "items", strings.NewReplacer("/", ".", "#", "@").Replace(id)+".json")
}

func writeJSON(path string, v any) error {
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".tmp-*")
	if err != nil {
		return err
	}
	if _, err := tmp.Write(append(b, '\n')); err != nil {
		tmp.Close()
		os.Remove(tmp.Name())
		return err
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmp.Name())
		return err
	}
	return os.Rename(tmp.Name(), path)
}

func readJSON(path string, v any) error {
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, v)
}

func loadMeta(dir, run string) (string, Meta, error) {
	rd, err := runDir(dir, run)
	if err != nil {
		return "", Meta{}, err
	}
	var m Meta
	if err := readJSON(filepath.Join(rd, "run.json"), &m); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return "", Meta{}, refuse("run %s does not exist in %s", run, dir)
		}
		return "", Meta{}, err
	}
	return rd, m, nil
}

func saveMeta(rd string, m Meta) error {
	m.Updated = now()
	return writeJSON(filepath.Join(rd, "run.json"), m)
}

func isObject(raw json.RawMessage) bool {
	var o map[string]json.RawMessage
	return json.Unmarshal(raw, &o) == nil && o != nil
}

// Init은 새 실행을 만든다. inputs는 검증을 마친 경계 입력 JSON 객체다.
func Init(dir string, graph []byte, inputs json.RawMessage) (Meta, error) {
	name, err := graphName(graph)
	if err != nil {
		return Meta{}, err
	}
	if !isObject(inputs) {
		return Meta{}, fmt.Errorf("inputs must be a JSON object")
	}
	r := make([]byte, 3)
	if _, err := rand.Read(r); err != nil {
		return Meta{}, err
	}
	t := now()
	run := fmt.Sprintf("%s-%s-%s", name, strings.ToLower(strings.NewReplacer("-", "", ":", "").Replace(t)), hex.EncodeToString(r))
	rd, _ := runDir(dir, run)
	if err := os.MkdirAll(filepath.Join(rd, "items"), 0o755); err != nil {
		return Meta{}, err
	}
	m := Meta{Run: run, Workflow: name, Status: "running", Graph: graphHash(graph), Inputs: inputs, Created: t}
	return m, saveMeta(rd, m)
}

func loadItem(rd, id string) (Item, bool, error) {
	var it Item
	err := readJSON(itemFile(rd, id), &it)
	if errors.Is(err, os.ErrNotExist) {
		return Item{ID: id}, false, nil
	}
	return it, err == nil, err
}

// setItem은 끝나지 않은 실행의 끝나지 않은 구성 요소 상태를 바꾼다.
func setItem(dir, run, id string, f func(*Item) error) error {
	if !idRe.MatchString(id) {
		return fmt.Errorf("component path id %q is invalid", id)
	}
	rd, m, err := loadMeta(dir, run)
	if err != nil {
		return err
	}
	if terminal(m.Status) {
		return refuse("run %s is %s", run, m.Status)
	}
	it, _, err := loadItem(rd, id)
	if err != nil {
		return err
	}
	if it.State == "done" {
		return refuse("%s is already done in run %s — 끝난 구성 요소는 다시 돌리지 않는다", id, run)
	}
	if err := f(&it); err != nil {
		return err
	}
	it.Updated = now()
	return writeJSON(itemFile(rd, id), it)
}

// Start는 구성 요소 실행 시작을 적는다 — 결과 없이 남으면 재개 때 끊긴 것으로 본다.
func Start(dir, run, id string) error {
	return setItem(dir, run, id, func(it *Item) error {
		it.State = "started"
		return nil
	})
}

// Wait는 구성 요소를 대기로 적는다. info는 대기 내용(by·mode·prompt·보일 값 등) JSON 객체다.
func Wait(dir, run, id string, info json.RawMessage) error {
	if !isObject(info) {
		return fmt.Errorf("wait info must be a JSON object")
	}
	return setItem(dir, run, id, func(it *Item) error {
		it.State, it.Wait = "waiting", info
		return nil
	})
}

// Record는 구성 요소 출력을 적어 끝낸다. out은 {"포트": 값} JSON 객체다.
func Record(dir, run, id string, out json.RawMessage) error {
	if !isObject(out) {
		return fmt.Errorf("outputs must be a JSON object")
	}
	return setItem(dir, run, id, func(it *Item) error {
		it.State, it.Out = "done", out
		return nil
	})
}

// End는 런너가 실행을 마칠 때 상태를 적는다 — waiting은 재개할 수 있다.
func End(dir, run, status string) error {
	if status != "waiting" && status != "done" && status != "failed" {
		return fmt.Errorf("status %q is not waiting|done|failed", status)
	}
	rd, m, err := loadMeta(dir, run)
	if err != nil {
		return err
	}
	if terminal(m.Status) {
		return refuse("run %s is %s", run, m.Status)
	}
	m.Status = status
	return saveMeta(rd, m)
}

// Cancel은 끝나지 않은 실행을 취소한다.
func Cancel(dir, run string) error {
	rd, m, err := loadMeta(dir, run)
	if err != nil {
		return err
	}
	if terminal(m.Status) {
		return refuse("run %s is %s", run, m.Status)
	}
	m.Status = "cancelled"
	return saveMeta(rd, m)
}

func loadItems(rd string) ([]Item, error) {
	ents, err := os.ReadDir(filepath.Join(rd, "items"))
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	var items []Item
	for _, e := range ents {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".json") {
			continue
		}
		var it Item
		if err := readJSON(filepath.Join(rd, "items", e.Name()), &it); err != nil {
			return nil, err
		}
		items = append(items, it)
	}
	sort.Slice(items, func(i, j int) bool { return items[i].ID < items[j].ID })
	return items, nil
}

// State는 실행 하나의 이어 갈 상태다.
type State struct {
	Pass        bool                       `json:"pass"`
	Run         string                     `json:"run"`
	Workflow    string                     `json:"workflow"`
	Status      string                     `json:"status"`
	Inputs      json.RawMessage            `json:"inputs"`
	Done        map[string]json.RawMessage `json:"done"`
	Waiting     map[string]json.RawMessage `json:"waiting"`
	Interrupted []string                   `json:"interrupted"` // 시작했지만 결과가 기록되지 않은 구성 요소
}

type ResumeReport struct {
	State
	GraphChanged bool `json:"graph_changed"`
}

func load(dir, run string) (string, Meta, State, error) {
	rd, m, err := loadMeta(dir, run)
	if err != nil {
		return "", Meta{}, State{}, err
	}
	items, err := loadItems(rd)
	if err != nil {
		return "", Meta{}, State{}, err
	}
	st := State{Pass: true, Run: run, Workflow: m.Workflow, Status: m.Status, Inputs: m.Inputs,
		Done: map[string]json.RawMessage{}, Waiting: map[string]json.RawMessage{}, Interrupted: []string{}}
	for _, it := range items {
		switch it.State {
		case "done":
			st.Done[it.ID] = it.Out
		case "waiting":
			st.Waiting[it.ID] = it.Wait
		case "started":
			st.Interrupted = append(st.Interrupted, it.ID)
		}
	}
	return rd, m, st, nil
}

// Show는 실행 상태를 바꾸지 않고 읽는다 — 하위 실행이 최상위 run에서 자기 접두 아래를 찾을 때 쓴다.
func Show(dir, run string) (State, error) {
	_, _, st, err := load(dir, run)
	return st, err
}

// Resume은 끝나지 않은 실행을 다시 running으로 두고, 이어 가는 데 필요한 상태를 낸다.
func Resume(dir, run string, graph []byte) (ResumeReport, error) {
	name, err := graphName(graph)
	if err != nil {
		return ResumeReport{}, err
	}
	rd, m, st, err := load(dir, run)
	if err != nil {
		return ResumeReport{}, err
	}
	if m.Workflow != name {
		return ResumeReport{}, refuse("run %s belongs to workflow %s, not %s", run, m.Workflow, name)
	}
	if terminal(m.Status) {
		return ResumeReport{}, refuse("run %s is %s — 끝난 실행은 재개하지 않는다", run, m.Status)
	}
	m.Status, st.Status = "running", "running"
	return ResumeReport{State: st, GraphChanged: m.Graph != graphHash(graph)}, saveMeta(rd, m)
}

type Summary struct {
	Run      string                     `json:"run"`
	Workflow string                     `json:"workflow"`
	Status   string                     `json:"status"`
	Created  string                     `json:"created"`
	Updated  string                     `json:"updated"`
	Waiting  map[string]json.RawMessage `json:"waiting"`
	Started  []string                   `json:"started"`
}

func summarize(rd string, m Meta) (Summary, error) {
	items, err := loadItems(rd)
	if err != nil {
		return Summary{}, err
	}
	s := Summary{Run: m.Run, Workflow: m.Workflow, Status: m.Status, Created: m.Created, Updated: m.Updated,
		Waiting: map[string]json.RawMessage{}, Started: []string{}}
	for _, it := range items {
		if it.State == "waiting" {
			s.Waiting[it.ID] = it.Wait
		} else if it.State == "started" {
			s.Started = append(s.Started, it.ID)
		}
	}
	return s, nil
}

// Status는 run이 주어지면 그 실행 하나를, 아니면 dir의 실행 전부(workflow가 주어지면 그 워크플로만)를 만든 순서로 낸다.
func Status(dir, run, workflow string) ([]Summary, error) {
	if run != "" {
		rd, m, err := loadMeta(dir, run)
		if err != nil {
			return nil, err
		}
		s, err := summarize(rd, m)
		return []Summary{s}, err
	}
	ents, err := os.ReadDir(dir)
	if errors.Is(err, os.ErrNotExist) {
		return []Summary{}, nil
	}
	if err != nil {
		return nil, err
	}
	out := []Summary{}
	for _, e := range ents {
		if !e.IsDir() || !runRe.MatchString(e.Name()) {
			continue
		}
		rd, m, err := loadMeta(dir, e.Name())
		if err != nil {
			var r Refusal
			if errors.As(err, &r) {
				continue // run.json 없는 디렉터리는 실행이 아니다
			}
			return nil, err
		}
		if workflow != "" && m.Workflow != workflow {
			continue
		}
		s, err := summarize(rd, m)
		if err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Created+out[i].Run < out[j].Created+out[j].Run })
	return out, nil
}
