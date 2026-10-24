package runstate

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"
	"testing"
)

const graph = `{"name": "gated-scan", "nodes": []}`

func refused(t *testing.T, err error, substr string) {
	t.Helper()
	var r Refusal
	if !errors.As(err, &r) {
		t.Fatalf("expected refusal containing %q, got %v", substr, err)
	}
	if !strings.Contains(r.Msg, substr) {
		t.Fatalf("refusal %q does not mention %q", r.Msg, substr)
	}
}

func compact(raw json.RawMessage) string {
	b, _ := json.Marshal(raw)
	return string(b)
}

func must(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
}

func TestLifecycle(t *testing.T) {
	dir := t.TempDir()
	m, err := Init(dir, []byte(graph), json.RawMessage(`{"dir": "/a"}`))
	must(t, err)
	if !strings.HasPrefix(m.Run, "gated-scan-") || m.Status != "running" {
		t.Fatalf("bad meta %+v", m)
	}
	must(t, Start(dir, m.Run, "scan"))
	must(t, Record(dir, m.Run, "scan", json.RawMessage(`{"paths": ["a"]}`)))
	must(t, Wait(dir, m.Run, "gate", json.RawMessage(`{"by": "human", "mode": "approve", "prompt": "?"}`)))
	must(t, Start(dir, m.Run, "sub/inner#2"))
	must(t, End(dir, m.Run, "waiting"))

	s, err := Status(dir, m.Run, "")
	must(t, err)
	if s[0].Status != "waiting" || len(s[0].Waiting) != 1 || len(s[0].Started) != 1 || s[0].Started[0] != "sub/inner#2" {
		t.Fatalf("bad status %+v", s[0])
	}

	st, err := Show(dir, m.Run)
	must(t, err)
	if st.Status != "waiting" || len(st.Done) != 1 {
		t.Fatalf("show must read without changing status: %+v", st)
	}
	rep, err := Resume(dir, m.Run, []byte(graph))
	must(t, err)
	if rep.Status != "running" || rep.GraphChanged || compact(rep.Inputs) != `{"dir":"/a"}` || compact(rep.Done["scan"]) != `{"paths":["a"]}` {
		t.Fatalf("bad resume %+v", rep)
	}
	if _, ok := rep.Waiting["gate"]; !ok || len(rep.Interrupted) != 1 {
		t.Fatalf("bad resume %+v", rep)
	}
	// 대기의 답은 record로 적는다
	must(t, Record(dir, m.Run, "gate", json.RawMessage(`{"approved": true, "note": ""}`)))
	// 끝난 구성 요소는 다시 시작·기록하지 않는다
	refused(t, Start(dir, m.Run, "scan"), "already done")
	refused(t, Record(dir, m.Run, "gate", json.RawMessage(`{}`)), "already done")
	must(t, End(dir, m.Run, "done"))
	// 끝난 실행은 재개·쓰기·취소하지 않는다
	_, err = Resume(dir, m.Run, []byte(graph))
	refused(t, err, "is done")
	refused(t, Start(dir, m.Run, "other"), "is done")
	refused(t, Cancel(dir, m.Run), "is done")
}

func TestResumeDetectsChangeAndOwner(t *testing.T) {
	dir := t.TempDir()
	m, err := Init(dir, []byte(graph), json.RawMessage(`{}`))
	must(t, err)
	rep, err := Resume(dir, m.Run, []byte(`{"name": "gated-scan", "nodes": [1]}`))
	must(t, err)
	if !rep.GraphChanged {
		t.Fatal("graph change not detected")
	}
	_, err = Resume(dir, m.Run, []byte(`{"name": "other-flow"}`))
	refused(t, err, "belongs to workflow gated-scan")
	_, err = Resume(dir, "ghost-run", []byte(graph))
	refused(t, err, "does not exist")
}

func TestCancel(t *testing.T) {
	dir := t.TempDir()
	m, err := Init(dir, []byte(graph), json.RawMessage(`{}`))
	must(t, err)
	must(t, Wait(dir, m.Run, "gate", json.RawMessage(`{"by": "check"}`)))
	must(t, End(dir, m.Run, "waiting"))
	must(t, Cancel(dir, m.Run))
	_, err = Resume(dir, m.Run, []byte(graph))
	refused(t, err, "is cancelled")
}

func TestStatusList(t *testing.T) {
	dir := t.TempDir()
	if s, err := Status(dir+"/none", "", ""); err != nil || len(s) != 0 {
		t.Fatalf("missing dir must list nothing: %v %v", s, err)
	}
	a, _ := Init(dir, []byte(graph), json.RawMessage(`{}`))
	b, _ := Init(dir, []byte(`{"name": "other-flow"}`), json.RawMessage(`{}`))
	all, err := Status(dir, "", "")
	must(t, err)
	if len(all) != 2 {
		t.Fatalf("want 2 runs, got %d", len(all))
	}
	one, err := Status(dir, "", "other-flow")
	must(t, err)
	if len(one) != 1 || one[0].Run != b.Run {
		t.Fatalf("workflow filter failed: %+v", one)
	}
	_ = a
}

func TestInputValidation(t *testing.T) {
	dir := t.TempDir()
	if _, err := Init(dir, []byte(`{"name": "Bad Name"}`), json.RawMessage(`{}`)); err == nil {
		t.Fatal("invalid workflow name must fail")
	}
	if _, err := Init(dir, []byte(graph), json.RawMessage(`[1]`)); err == nil {
		t.Fatal("non-object inputs must fail")
	}
	m, _ := Init(dir, []byte(graph), json.RawMessage(`{}`))
	for _, id := range []string{"", "../x", "a//b", "a#", "a/#1", "A"} {
		if err := Start(dir, m.Run, id); err == nil {
			t.Fatalf("id %q must be rejected", id)
		}
	}
	if err := Start(dir, "../escape", "a"); err == nil {
		t.Fatal("run id with path must be rejected")
	}
	if err := Record(dir, m.Run, "a", json.RawMessage(`"x"`)); err == nil {
		t.Fatal("non-object outputs must fail")
	}
	if err := End(dir, m.Run, "paused"); err == nil {
		t.Fatal("unknown end status must fail")
	}
}

func TestConcurrentItems(t *testing.T) {
	// 하위 워크플로를 맡은 서브에이전트와 최상위 런너가 동시에 적어도 잃지 않는다.
	dir := t.TempDir()
	m, _ := Init(dir, []byte(graph), json.RawMessage(`{}`))
	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			if err := Record(dir, m.Run, fmt.Sprintf("review#%d", i), json.RawMessage(`{"v": 1}`)); err != nil {
				t.Error(err)
			}
		}(i)
	}
	wg.Wait()
	rep, err := Resume(dir, m.Run, []byte(graph))
	must(t, err)
	if len(rep.Done) != 20 {
		t.Fatalf("want 20 done, got %d", len(rep.Done))
	}
}
