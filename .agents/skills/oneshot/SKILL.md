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
  output: {type: string, description: 에이전트 최종 출력 전문}
  log_path: {type: string}
  workdir: {type: string}
  meta_dir: {type: string, description: 로그·신호가 놓인 디렉토리}
  commits: {type: array, description: 이번 실행이 만든 커밋 해시}
  dirty: {type: boolean, description: 커밋되지 않은 변경 유무}
  signals: {type: array, description: meta_dir/signals 에 남은 파일명}
run:
  command: "bash ${ONESHOT_SH:-$HOME/.claude/plugins/cache/courtesy-claude-plugins/recipe/current/skills/oneshot/references/oneshot.sh}"
  input: stdin-json
  output: stdout-json
allowed-tools:
  - Bash(bash * oneshot.sh)
---

# oneshot (typed)

외부 에이전트를 격리 환경에서 1회 실행한다. recipe 플러그인의 `skills/oneshot/references/oneshot.sh` 본체를 호출하는 typed 래퍼다.

## 실행

1. inputs 스키마대로 입력 객체를 만든다 — `prompt`는 필수, 나머지는 기본값 사용.
2. `run.command`를 stdin-json 으로 실행한다. 스크립트 경로는 환경 변수 `ONESHOT_SH`로 덮어쓸 수 있다(플러그인 설치 위치가 다르거나 저장소 사본을 쓸 때).
3. stdout 의 JSON 을 outputs 스키마와 대조해 그대로 보고한다. 종료 여부는 판정하지 않는다 — `signals`·`commits`·`exit_code`는 호출자가 해석한다.
