// pipecheck — /skill·/pipeline의 결정적 검사 코어.
//
//	pipecheck check-expr  < {"expr": "...", "in": {...}}      §4 표현식 체크
//	pipecheck check-skill -file SKILL.md [-project DIR] [-user DIR]   §6.4 스킬 검증
//	pipecheck hash        -file SKILL.md [-graph graph.json]  §5.8 계약·본문 해시
//	pipecheck run <init|start|wait|record|end|show|resume|cancel|status> -dir RUNS ...  실행 상태
//
// 출력은 전부 stdout 한 줄 JSON. 검사 불통과는 exit 1, 사용 오류는 exit 2.
package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"

	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/celcheck"
	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/graphcheck"
	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/hash"
	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/ripple"
	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/runcheck"
	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/runstate"
	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/skillcheck"
	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/textnorm"
	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/verify"
)

func usage() {
	fmt.Fprintln(os.Stderr, "usage: pipecheck <check-expr|check-skill|check-graph|check-values|verify-materials|hash|ripple|run> [flags]")
	os.Exit(2)
}

func emit(v any, ok bool) {
	enc := json.NewEncoder(os.Stdout)
	enc.SetEscapeHTML(false)
	_ = enc.Encode(v)
	if !ok {
		os.Exit(1)
	}
}

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	switch os.Args[1] {
	case "check-expr":
		var req celcheck.Request
		if err := json.NewDecoder(os.Stdin).Decode(&req); err != nil {
			fmt.Fprintln(os.Stderr, "input:", err)
			os.Exit(2)
		}
		resp := celcheck.Run(req)
		emit(resp, resp.OK)

	case "check-skill":
		fs := flag.NewFlagSet("check-skill", flag.ExitOnError)
		file := fs.String("file", "", "SKILL.md path")
		project := fs.String("project", "", "project skills root")
		user := fs.String("user", "", "user skills root")
		selfScope := fs.String("self-scope", "", "candidate install scope (project|user) for wraps self-cycle check")
		overlay := fs.String("overlay", "", "temp dir searched before installed roots (pre-approval materials)")
		_ = fs.Parse(os.Args[2:])
		if *file == "" {
			usage()
		}
		md, err := textnorm.ReadFile(*file)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		r, err := skillcheck.Check(md, skillcheck.Options{ProjectDir: *project, UserDir: *user, SelfScope: *selfScope, OverlayDir: *overlay})
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		emit(r, r.Pass)

	case "hash":
		fs := flag.NewFlagSet("hash", flag.ExitOnError)
		file := fs.String("file", "", "SKILL.md path")
		graph := fs.String("graph", "", "graph.json path (workflow material)")
		_ = fs.Parse(os.Args[2:])
		if *file == "" {
			usage()
		}
		md, err := textnorm.ReadFile(*file)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		var g []byte
		if *graph != "" {
			g, err = textnorm.ReadFile(*graph)
			if err != nil {
				fmt.Fprintln(os.Stderr, err)
				os.Exit(2)
			}
		}
		c, b, err := hash.SkillHashes(md, g)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		emit(map[string]string{"contract": c, "body": b}, true)

	case "check-graph":
		fs := flag.NewFlagSet("check-graph", flag.ExitOnError)
		file := fs.String("file", "", "graph.json path")
		project := fs.String("project", "", "project skills root")
		user := fs.String("user", "", "user skills root")
		selfName := fs.String("self-name", "", "workflow name being compiled")
		selfScope := fs.String("self-scope", "", "workflow install scope")
		overlay := fs.String("overlay", "", "temp dir searched before installed roots (pre-approval materials)")
		_ = fs.Parse(os.Args[2:])
		if *file == "" {
			usage()
		}
		raw, err := textnorm.ReadFile(*file)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		r, err := graphcheck.Check(raw, graphcheck.Options{
			ProjectDir: *project, UserDir: *user, SelfName: *selfName, SelfScope: *selfScope, OverlayDir: *overlay})
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		emit(r, r.Pass)

	case "check-values":
		// stdin: {"ports": {...}, "given": {"name": <JSON 값>}, "boundary": bool}
		var req struct {
			Ports    map[string]runcheck.Port   `json:"ports"`
			Given    map[string]json.RawMessage `json:"given"`
			Boundary bool                       `json:"boundary"`
		}
		if err := json.NewDecoder(os.Stdin).Decode(&req); err != nil {
			fmt.Fprintln(os.Stderr, "input:", err)
			os.Exit(2)
		}
		given := map[string][]byte{}
		for k, v := range req.Given {
			given[k] = []byte(v)
		}
		r, err := runcheck.Check(req.Ports, given, req.Boundary)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		emit(r, r.Pass)

	case "verify-materials":
		fs := flag.NewFlagSet("verify-materials", flag.ExitOnError)
		file := fs.String("file", "", "graph.json path")
		project := fs.String("project", "", "project skills root")
		user := fs.String("user", "", "user skills root")
		_ = fs.Parse(os.Args[2:])
		if *file == "" {
			usage()
		}
		raw, err := textnorm.ReadFile(*file)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		r, err := verify.Run(raw, verify.Options{ProjectDir: *project, UserDir: *user})
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		emit(r, r.Pass)

	case "ripple":
		fs := flag.NewFlagSet("ripple", flag.ExitOnError)
		name := fs.String("name", "", "target skill name")
		scope := fs.String("scope", "", "target scope (project|user)")
		contract := fs.String("contract", "", "current contract hash")
		body := fs.String("body", "", "current body hash")
		project := fs.String("project", "", "project skills root")
		user := fs.String("user", "", "user skills root")
		_ = fs.Parse(os.Args[2:])
		if *name == "" || *scope == "" {
			usage()
		}
		rep, err := ripple.Compute(
			ripple.Target{Name: *name, Scope: *scope, Contract: *contract, Body: *body},
			ripple.Options{ProjectDir: *project, UserDir: *user})
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		emit(rep, true)

	case "run":
		runCmd(os.Args[2:])

	default:
		usage()
	}
}

// runCmd — 실행 상태 하위 명령. 상태와 맞지 않는 요청(없는 run, 끝난 run, 끝난 구성 요소)은
// 불통과(exit 1)로 {"pass":false,"failures":[...]}를 낸다.
func runCmd(args []string) {
	if len(args) < 1 {
		usage()
	}
	sub := args[0]
	fs := flag.NewFlagSet("run "+sub, flag.ExitOnError)
	dir := fs.String("dir", "", "runs directory (.pipelines/runs)")
	run := fs.String("run", "", "run id")
	id := fs.String("id", "", "component path id")
	graph := fs.String("graph", "", "graph.json path")
	status := fs.String("status", "", "end status (waiting|done|failed)")
	workflow := fs.String("workflow", "", "status filter: workflow name")
	_ = fs.Parse(args[1:])
	if *dir == "" {
		usage()
	}
	readGraph := func() []byte {
		if *graph == "" {
			usage()
		}
		g, err := textnorm.ReadFile(*graph)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		return g
	}
	readStdin := func() json.RawMessage {
		var v json.RawMessage
		if err := json.NewDecoder(os.Stdin).Decode(&v); err != nil {
			fmt.Fprintln(os.Stderr, "input:", err)
			os.Exit(2)
		}
		return v
	}
	need := func(vals ...string) {
		for _, v := range vals {
			if v == "" {
				usage()
			}
		}
	}
	finish := func(v any, err error) {
		var r runstate.Refusal
		if errors.As(err, &r) {
			emit(map[string]any{"pass": false, "failures": []string{r.Msg}}, false)
			return
		}
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		emit(v, true)
	}
	ok := map[string]bool{"pass": true}
	switch sub {
	case "init":
		m, err := runstate.Init(*dir, readGraph(), readStdin())
		finish(map[string]any{"pass": true, "run": m.Run}, err)
	case "start":
		need(*run, *id)
		finish(ok, runstate.Start(*dir, *run, *id))
	case "wait":
		need(*run, *id)
		finish(ok, runstate.Wait(*dir, *run, *id, readStdin()))
	case "record":
		need(*run, *id)
		finish(ok, runstate.Record(*dir, *run, *id, readStdin()))
	case "end":
		need(*run, *status)
		finish(ok, runstate.End(*dir, *run, *status))
	case "show":
		need(*run)
		st, err := runstate.Show(*dir, *run)
		finish(st, err)
	case "resume":
		need(*run)
		rep, err := runstate.Resume(*dir, *run, readGraph())
		finish(rep, err)
	case "cancel":
		need(*run)
		finish(ok, runstate.Cancel(*dir, *run))
	case "status":
		runs, err := runstate.Status(*dir, *run, *workflow)
		finish(map[string]any{"pass": true, "runs": runs}, err)
	default:
		usage()
	}
}
