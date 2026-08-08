---
name: oneshot
description: "외부 에이전트를 격리 환경에서 1회 실행하고 결과를 구조화해 받을 때 사용. 파이프라인 노드로 쓰면 while 과 조합해 반복 실행이 된다."
kind: script
inputs:
  prompt: {type: string, required: true, description: 에이전트에 줄 지시}
  system_prompt_file: {type: string, description: 지침 파일 경로 — 규율은 호출자가 주입}
  isolation: {type: string, default: worktree, description: "worktree | cwd | tmpdir"}
  repo: {type: string, description: 대상 git 저장소 (기본 cwd)}
  vendor: {type: string, default: claude, description: "claude | codex"}
  workdir_name: {type: string, default: oneshot, description: 작업 공간·lock 이름}
outputs:
  exit_code: {type: number}
  output: {type: string, description: 에이전트 로그 꼬리(stdout+stderr 합본, 최대 ONESHOT_OUTPUT_BYTES)}
  log_path: {type: string}
  workdir: {type: string}
  commits: {type: array, description: 이번 실행이 만든 커밋 해시}
  dirty: {type: boolean, description: 커밋되지 않은 변경 유무}
  error: {type: string, description: 실패 시에만 — 실패도 stdout 은 JSON 하나다}
run:
  command: "bash ${ONESHOT_SH:?ONESHOT_SH 에 oneshot.sh 절대 경로 필요}"
  input: stdin-json
  output: stdout-json
allowed-tools:
  - Bash(bash *oneshot.sh:*)
---

# oneshot (typed)

외부 에이전트를 격리 환경에서 1회 실행한다. recipe 플러그인의 `skills/oneshot/references/oneshot.sh` 본체를 호출하는 typed 래퍼다.

## 실행

1. inputs 스키마대로 입력 객체를 만든다 — `prompt`는 필수, 나머지는 기본값 사용.
2. `run.command`를 stdin-json 으로 실행한다. **스크립트 경로는 환경 변수 `ONESHOT_SH`로 준다** — 플러그인 설치 위치는 런타임·마켓플레이스마다 달라서 이 파일에 박지 않는다(예: `ONESHOT_SH=$(ls -d ~/.claude/plugins/cache/*/recipe/*/skills/oneshot/references/oneshot.sh | tail -1)`).
3. stdout 의 JSON 을 outputs 스키마와 대조해 그대로 보고한다. 실패해도 stdout 은 JSON 이므로(`error` 필드) 파싱은 언제나 성공한다. 종료 여부는 판정하지 않는다 — `output`·`commits`·`exit_code`는 호출자가 해석한다(종료 표지 규약은 프롬프트에서 정한다).
