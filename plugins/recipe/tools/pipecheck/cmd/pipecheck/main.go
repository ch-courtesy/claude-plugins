// pipecheck — /skill·/pipeline의 결정적 검사 코어.
//
//	pipecheck check-expr  < {"expr": "...", "in": {...}}      §4 표현식 체크
//	pipecheck check-skill -file SKILL.md [-project DIR] [-user DIR]   §6.4 스킬 검증
//	pipecheck hash        -file SKILL.md [-graph graph.json]  §5.8 계약·본문 해시
//
// 출력은 전부 stdout 한 줄 JSON. 검사 불통과는 exit 1, 사용 오류는 exit 2.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/celcheck"
	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/graphcheck"
	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/hash"
	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/ripple"
	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/runcheck"
	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/skillcheck"
	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/verify"
)

func usage() {
	fmt.Fprintln(os.Stderr, "usage: pipecheck <check-expr|check-skill|check-graph|check-values|verify-materials|hash|ripple> [flags]")
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
		md, err := os.ReadFile(*file)
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
		md, err := os.ReadFile(*file)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		var g []byte
		if *graph != "" {
			g, err = os.ReadFile(*graph)
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
		raw, err := os.ReadFile(*file)
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
		raw, err := os.ReadFile(*file)
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

	default:
		usage()
	}
}
