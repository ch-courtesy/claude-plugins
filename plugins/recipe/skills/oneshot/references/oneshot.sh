#!/usr/bin/env bash
# usage: oneshot.sh [--mode read|write] [--schema <f>] [--model <m>] [--effort low|medium|high]
#                   [--prompt-file <f> | --stdin] [--raw] <agent> ["<prompt>"]
#
# 벤더 중립 facade: 모든 파라미터를 벤더 플래그로 매핑. passthrough 없음.
#
# 프롬프트 소스: positional "<prompt>" | --prompt-file <f> | --stdin 중 "정확히 하나"(0개·2개는 오류).
#   래퍼가 소스를 읽어 전체를 벤더 stdin으로 전달(스트리밍 아님, EOF까지 버퍼링). 후행 개행은 정규화됨.
# --mode: read(기본)=읽기전용 안전. write=권한·샌드박스 "완전해제" — "호출자가 이미 격리했다"는 선언. 단순 쓰기추가 아님.
#   write 매핑: claude=--dangerously-skip-permissions | agy=--mode accept-edits --dangerously-skip-permissions
#     (agy는 권한 자동승인과 실행 모드가 별개 축이라 둘 다 명시 — 안 하면 저장된 agentMode(plan일 수 있음)에 좌우됨)
#     | codex=--dangerously-bypass-approvals-and-sandbox (승인 정책까지 해제. sandbox_mode=danger-full-access만으로는
#     호출자 config의 approval_policy가 남아 비대화형 실행이 승인 대기로 죽을 수 있음).
#   read 매핑: claude=--allowedTools/--disallowedTools(denylist) | codex=-c sandbox_mode=read-only(샌드박스)
#     | agy=--mode plan(실행 모드).
#   read 주의: 어느 것도 hermetic 아님. claude는 열거된 4개 도구만 차단하므로 호출 환경 설정이 MCP 도구를
#     allow하면 read 모드에서도 부작용 가능하고 WebFetch/WebSearch는 미차단. codex 샌드박스와 agy plan 모드는
#     각 벤더 구현에 의존하며 이 래퍼가 보증하지 않는다.
# --schema <f>: 구조화 출력. codex(--output-schema)·agy(--output-format json --json-schema)는 네이티브 강제,
#   claude는 프롬프트 주입+사후검증. 주의: agy 분기는 --schema를 줄 때만 --output-format json을 함께 켠다 —
#   이 래퍼가 agy 출력 형식을 건드리는 유일한 경로다(--json-schema가 그 형식을 요구).
#   사후검증(claude 전용)은 jq well-formed(단일 문서)만 — 스키마 미강제라 항상 강등(exit 3). --raw와 상호배타.
# --model <m>: 벤더에 그대로 전달(claude·codex·agy 모두 --model). 유효값 검증은 벤더 몫 — 잘못된 값은 벤더 rc로 드러난다.
# --effort low|medium|high: claude·agy는 --effort <v>, codex만 -c model_reasoning_effort=<v>(config 오버라이드)로 번역.
# --raw: 출력 정규화 끄기 — 사실상 codex 전용(claude/agy는 기본 출력이 이미 최종만이라 no-op).
#
# 출력 채널(캡처 경로 = claude --schema 또는 codex 정규화): 성공/강등 결과 → stdout, 실패 시 벤더 출력·진단 → stderr.
#   codex 세션로그는 성공·실패 무관 항상 stderr — stderr가 비어 있음을 성공 판정에 쓰면 안 된다(rc로 판정).
#   (stdout은 "사용 가능한 최종 결과"만 담는 깨끗한 채널 — 파이프 조합용.)
#   예외: exec 경로(--raw, claude에서 --schema 없음, agy 전부 — read/write 무관)는 벤더 stdout/stderr를 네이티브 그대로 통과 —
#   실패해도 벤더 stdout이 stdout에 남음(성능·스트리밍 위해 캡처 안 함). 실패 격리는 캡처 경로(claude --schema, codex 비-raw)에서만 제공.
# exit code: 0=성공(codex·agy --schema는 네이티브 검증 통과) | 1=출력 사용불가(비JSON·다중 문서·빈출력 — 빈출력 승격은 캡처 경로 한정, agy는 미적용) | 2=usage/인자/환경 오류
#   | 3=강등(well-formed지만 스키마 미강제, 출력은 usable — claude --schema의 성공 케이스) | 그 외=벤더 CLI의 rc 그대로 전달.
#   (주의: 벤더가 우연히 1/2/3을 쓰면 겹칠 수 있고, emit 전달실패(디스크풀 등) 시 cat rc도 1/2/3과 겹칠 수 있음.
#    well-formed 판정은 jq 수용 기준 — RFC보다 관대: NaN/Infinity 외 01·+1·1. 같은 숫자 리터럴도 통과.)
set -euo pipefail
# 호출자가 export한 동명 변수의 export 속성 상속 차단 — 대형 프롬프트/스키마가 벤더 env에도 실려 execve E2BIG 나는 것 방지
unset -v prompt sch jq_bin

usage() {
  echo "usage: oneshot.sh [--mode read|write] [--schema <f>] [--model <m>] [--effort low|medium|high] [--prompt-file <f>|--stdin] [--raw] <claude|codex|agy> [\"<prompt>\"]" >&2
}

need_val() {  # $1=flag $2=value ; 값이 없거나 -*면 거부(후속 플래그 흡수 방지)
  case "${2-}" in
    "" ) echo "$1 needs a value" >&2; exit 2 ;;
    -* ) echo "$1 value looks like a flag: $2 (values must not start with '-')" >&2; exit 2 ;;
  esac
}
mode=read schema="" model="" effort="" prompt_file="" use_stdin=0 raw=0
while [ $# -gt 0 ]; do
  case "$1" in
    --mode)        need_val "$1" "${2-}"; mode="$2"; shift 2 ;;
    --schema)      need_val "$1" "${2-}"; schema="$2"; shift 2 ;;
    --model)       need_val "$1" "${2-}"; model="$2"; shift 2 ;;
    --effort)      need_val "$1" "${2-}"; effort="$2"; shift 2 ;;
    --prompt-file) need_val "$1" "${2-}"; prompt_file="$2"; shift 2 ;;
    --stdin)       use_stdin=1; shift ;;
    --raw)         raw=1; shift ;;
    -*)            echo "unknown option: $1" >&2; usage; exit 2 ;;
    *)             break ;;
  esac
done

case "$mode" in read|write) ;; *) echo "invalid --mode: $mode (read|write)" >&2; exit 2 ;; esac
[ -z "$effort" ] || case "$effort" in low|medium|high) ;; *) echo "invalid --effort: $effort (low|medium|high)" >&2; exit 2 ;; esac
[ -z "$schema" ] || { [ -f "$schema" ] && [ -r "$schema" ]; } || { echo "schema must be a readable regular file: $schema" >&2; exit 2; }
# --raw는 원본 출력, --schema는 정규화된 출력 검증 — 모순 조합
[ "$raw" -eq 0 ] || [ -z "$schema" ] || { echo "--raw and --schema are mutually exclusive" >&2; exit 2; }

[ $# -ge 1 ] || { usage; exit 2; }
agent="$1"; shift
# agent 검증을 프롬프트 소비 앞으로 — 오타 + 비종료 --stdin 조합의 무한 대기 방지(fail-fast)
case "$agent" in claude|codex|agy) ;; *) echo "unknown agent: $agent (claude|codex|agy)" >&2; exit 2 ;; esac
# 벤더 CLI 실경로 사전 해소 — 부재 시 stdin 소비 후 127 대신 즉시 환경 오류(계약상 2).
# type -P: PATH의 실행파일만 인정(셸 함수·alias 제외) — exported 함수가 검증을 속이거나 캡처 경로에서 대신 실행되는 것 차단.
agent_bin=$(type -P "$agent") || { echo "vendor CLI not found in PATH: $agent" >&2; exit 2; }

# 프롬프트 소스 정확히 하나: positional | --prompt-file | --stdin
src=0
[ -n "$prompt_file" ] && src=$((src+1))
[ "$use_stdin" -eq 1 ] && src=$((src+1))
[ $# -ge 1 ] && src=$((src+1))
[ "$src" -eq 1 ] || { echo "exactly one prompt source required (positional | --prompt-file | --stdin), got $src" >&2; exit 2; }

# --- 리소스/시그널 생명주기 (프롬프트 읽기 전에 설치 — --stdin 버퍼링 중 시그널도 커버) ---
stin=""; out=""
cleanup() { [ -n "$stin" ] && rm -f -- "$stin"; [ -n "$out" ] && rm -f -- "$out"; return 0; }
kill_tree() {  # $1=루트 PID. 시그널 시점에 존재하는 서브트리를 children-first 재귀 TERM.
  # 한계(이식적 userspace tree-kill의 근본): pgrep -P는 노드당 1회 스냅샷이라, teardown 중
  #   부모가 새로 fork한 자식은 열거에서 빠져 reparent 후 살아남을 수 있음. 완전 봉쇄는
  #   프로세스그룹/cgroup이 필요하나 macOS엔 setsid가 없어 불가 → best-effort. write 모드에서
  #   외부 TERM과 벤더의 능동 fork가 겹치면 고아가 남을 수 있음.
  # pgrep 없으면 자식 열거 실패해 루트만 kill(무해 degrade). PPID 그래프는 스냅샷상 비순환이라 무한재귀 없음.
  local p="$1" c
  for c in $(pgrep -P "$p" 2>/dev/null); do kill_tree "$c"; done
  kill -TERM "$p" 2>/dev/null || :
}
on_signal() {  # $1=시그널명. 시그널 시점의 살아있는 자식 트리 kill → temp 정리 → 시그널 재전파.
  # 저장 PID 대신 pgrep -P $$ 라이브 열거 — spawn~$! 할당 사이 시그널 창과 reap된 stale PID
  # (재사용 시 무관 프로세스) kill 위험을 동시에 제거. pgrep 부재 시 자식 미종료(무해 degrade).
  local c
  for c in $(pgrep -P $$ 2>/dev/null); do kill_tree "$c"; done
  cleanup
  trap - INT TERM HUP EXIT
  kill -"$1" "$$"
}
trap cleanup EXIT
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM
trap 'on_signal HUP' HUP

require_no_nul() {  # $1=file $2=진단 라벨. $(cat)이 NUL을 조용히 제거해 프롬프트가 절단되므로 거부.
  # 검사 도구 실패(tr/wc)는 NUL 오진 대신 fail-loud — $( ) 대입의 rc(pipefail 포함)를 ||로 포착.
  local n
  n=$(LC_ALL=C tr -dc '\000' < "$1" | wc -c) || { echo "NUL check failed on $2" >&2; exit 2; }
  [ "$n" -eq 0 ] || { echo "$2 contains NUL bytes (binary?)" >&2; exit 2; }
}

# schema 사전검증(주입 경로 전용) — 확정된 입력 오류는 프롬프트 소비(특히 --stdin 버퍼링) 전에 fail-fast.
# NUL은 $(cat)이 조용히 제거해 스키마를 변형시키므로 거부, 빈 파일도 무의미 주입이라 거부. codex·agy는 파일 네이티브 전달이라 면제.
if [ -n "$schema" ] && [ "$agent" = claude ]; then
  require_no_nul "$schema" "schema file $schema"
  [ -s "$schema" ] || { echo "schema file is empty: $schema" >&2; exit 2; }
  # jq도 이 경로의 확정 의존성 — 벤더 완주(write 모드면 부작용까지) 후 exit 2 대신 사전 fail-fast.
  # type -P: 벤더 CLI와 동일 방어 — exported 셸 함수(`jq(){ printf 1; }`)가 검증 결과를 위조해
  # 비JSON 출력을 well-formed로 통과시키는 것을 차단한다.
  jq_bin=$(type -P jq) || { echo "jq required for --schema with $agent (not found in PATH)" >&2; exit 2; }
  # schema 자체가 깨진 JSON이면 주입해봤자 원인(schema 불량)·증상(출력 rc 1)이 뒤섞임 — 단일 well-formed 문서 사전 확인
  n=$("$jq_bin" -s 'length' < "$schema" 2>/dev/null) && [ "$n" -eq 1 ] || { echo "schema file is not a single well-formed JSON document: $schema" >&2; exit 2; }
fi

if [ -n "$prompt_file" ]; then
  # 정규파일만 — /dev/zero 등 특수·무한 장치로 인한 무한 읽기(hang) 차단.
  # 파이프·process-substitution(<(...))은 정규파일 아님 → --stdin으로 넣을 것.
  [ -f "$prompt_file" ] && [ -r "$prompt_file" ] || { echo "prompt file must be a readable regular file: $prompt_file (for pipes/<(...) use --stdin)" >&2; exit 2; }
  # 검사↔읽기 비원자(best-effort 스냅샷) — 검사 후 파일 교체(TOCTOU)까지는 방어하지 않음(동일 사용자 위협모델 밖).
  require_no_nul "$prompt_file" "prompt file $prompt_file"
  prompt=$(cat -- "$prompt_file") || { echo "prompt file read failed: $prompt_file" >&2; exit 2; }  # 환경 오류(계약상 2)
elif [ "$use_stdin" -eq 1 ]; then
  # stdin은 스트림이라 한 번만 읽힘 → temp로 버퍼 후 NUL 검사(--prompt-file과 동일 계약).
  # stin 정리는 통합 cleanup(EXIT/시그널)이 담당.
  # cat을 백그라운드+wait로 — 전경 외부명령 중엔 bash가 trap을 보류해 비종료 stdin+단일 PID TERM 시 hang.
  # wait(빌트인)은 인터럽트 가능 → on_signal이 cat 자식 kill·정리·재전파.
  # <&0: 비대화형 bash는 'cmd &' stdin을 /dev/null로 돌리므로 스크립트 stdin(fd0)을 명시 연결.
  # 시그널은 on_signal이 재전파(스크립트 종료)하므로 여기 도달하는 실패는 순수 cat 실패 → fail-loud.
  stin=$(mktemp) || { echo "mktemp failed for stdin buffer" >&2; exit 2; }  # 환경 오류(계약상 2)
  cat <&0 > "$stin" &
  if wait "$!"; then scrc=0; else scrc=$?; fi
  [ "$scrc" -eq 0 ] || { echo "stdin read failed (rc=$scrc)" >&2; exit 2; }  # 입력오류 계열(계약상 2)
  require_no_nul "$stin" "stdin"
  prompt=$(cat -- "$stin") || { echo "stdin buffer read failed" >&2; exit 2; }  # 환경 오류(계약상 2)
  rm -f -- "$stin"; stin=""
else
  # positional 프롬프트가 -로 시작 = 오배치된 래퍼 플래그일 가능성. dash 프롬프트는 --prompt-file/--stdin으로.
  case "$1" in -*) echo "prompt starts with '-' (put wrapper flags before <agent>, or use --prompt-file/--stdin)" >&2; exit 2 ;; esac
  prompt=$(printf '%s' "$1"); shift  # $( )가 후행 개행 제거 — file/stdin 경로와 동일 정규화(herestring이 1개 추가)
fi
[ $# -eq 0 ] || { echo "unexpected extra args: $*" >&2; exit 2; }
# 공백-전용 프롬프트도 거부 — 출력측 blank 거부(아래 rc=1 승격)와 대칭
case "$prompt" in *[![:space:]]*) ;; *) echo "empty/blank prompt (source produced no usable content)" >&2; exit 2 ;; esac

# schema 주입(claude 전용): 네이티브 미지원 벤더는 프롬프트에 스키마 주입 + 사후검증(사전검증은 위에서 완료)
if [ -n "$schema" ] && [ "$agent" = claude ]; then
  sch=$(cat -- "$schema") || { echo "schema file read failed: $schema" >&2; exit 2; }  # 환경 오류(계약상 2)
  prompt="$prompt

[출력 요구] 아래 JSON 스키마를 정확히 따르는 단일 JSON 문서만 출력하라. 산문·코드펜스 없이 JSON만.
스키마:
$sch"
fi

# JSON 사후검증(jq): well-formed + 단일 문서만 — 스키마 강제 없음, 통과해도 항상 강등(3).
# 주의: jq는 RFC보다 관대 — NaN→null, Infinity→max double 외에 01·+1·1. 같은 숫자 리터럴도 수용.
validate_json() {  # $1=data_file
  # 실행파일만 인정(type -P) — 셸 함수가 검증을 대신하면 판정 자체가 위조된다
  [ -n "${jq_bin:-}" ] && [ -x "$jq_bin" ] || jq_bin=$(type -P jq) \
    || { echo "schema validation: jq not found (required for --schema with $agent)" >&2; return 2; }  # 환경 오류(계약상 2)
  local n
  if ! n=$("$jq_bin" -s 'length' < "$1" 2>&1); then
    echo "schema validation: output is not valid JSON: $n" >&2; return 1
  fi
  [ "$n" -eq 1 ] || { echo "schema validation: expected single JSON document, got $n" >&2; return 1; }
  echo "schema validation DEGRADED: checked well-formed JSON only (schema NOT enforced)" >&2
  return 3  # 강등: well-formed지만 스키마 미강제 — exit 0(검증됨)과 구별
}

# 벤더별 명령 배열 조립
m=(); [ -n "$model" ] && m=(--model "$model")
case "$agent" in
  claude)
    e=(); [ -n "$effort" ] && e=(--effort "$effort")
    if [ "$mode" = write ]; then perm=(--dangerously-skip-permissions)
    else perm=(--allowedTools=Read,Grep,Glob --disallowedTools=Bash,Edit,Write,NotebookEdit); fi
    cmd=("$agent_bin" -p "${perm[@]}" ${m[@]+"${m[@]}"} ${e[@]+"${e[@]}"}) ;;
  codex)
    # write는 전용 bypass 플래그 — danger-full-access는 샌드박스만 풀고 승인 정책을 남긴다
    if [ "$mode" = write ]; then sb=(--dangerously-bypass-approvals-and-sandbox)
    else sb=(-c sandbox_mode=read-only); fi
    e=(); [ -n "$effort" ] && e=(-c "model_reasoning_effort=$effort")
    sc=(); [ -n "$schema" ] && sc=(--output-schema "$schema")
    cmd=("$agent_bin" exec "${sb[@]}" ${m[@]+"${m[@]}"} ${e[@]+"${e[@]}"} ${sc[@]+"${sc[@]}"}) ;;
  agy)
    e=(); [ -n "$effort" ] && e=(--effort "$effort")
    # 실행 모드와 권한 자동승인은 별개 축 — write는 둘 다 명시해야 저장된 agentMode(plan일 수 있음)에 좌우되지 않음
    # 미실측 보류(2026-08-12, quota 리셋 후 확인): print 모드에서 --mode가 무시된다는 리뷰 보고 있음 — 선언적 의도로 유지
    if [ "$mode" = write ]; then md=(--mode accept-edits --dangerously-skip-permissions)
    else md=(--mode plan); fi
    # --json-schema는 --output-format json 의존(리뷰 보고, 미실측 선반영 — 동일 시점 확인 대상)
    sc=(); [ -n "$schema" ] && sc=(--output-format json --json-schema "$schema")
    cmd=("$agent_bin" -p "${md[@]}" ${m[@]+"${m[@]}"} ${e[@]+"${e[@]}"} ${sc[@]+"${sc[@]}"}) ;;
esac

# 실행 경로: capture 필요 = codex 정규화(비-raw) 또는 claude schema 사후검증
need_capture=0
{ [ "$agent" = codex ] && [ "$raw" -eq 0 ]; } && need_capture=1
[ -n "$schema" ] && [ "$agent" = claude ] && need_capture=1
# codex·agy + schema: 네이티브 강제라 사후검증 불필요(codex는 정규화만 위 조건에 포함, agy는 exec 통과)

# 프롬프트는 stdin(herestring)으로 전달 — argv 크기 한계(E2BIG) 회피, 플래그 격리는 stdin이라 자동
if [ "$need_capture" -eq 0 ]; then
  exec "${cmd[@]}" <<<"$prompt"
fi

out=$(mktemp) || { echo "mktemp failed for output capture" >&2; exit 2; }  # 환경 오류(계약상 2); trap·cleanup은 설치됨
rc=0
degraded=0  # validate_json 강등(스키마 미강제)만 표시 — 벤더의 우연한 exit 3과 구별
if [ "$agent" = codex ]; then
  # 정규화: 최종 메시지만 -o로 받고 세션로그는 stderr로
  "${cmd[@]}" --output-last-message "$out" <<<"$prompt" >&2 &
  wait "$!" || rc=$?
else
  # claude schema: clean stdout 캡처 후 검증 (벤더 성공 시에만 — 실패 rc 보존). agy는 네이티브라 이 분기에 오지 않음
  "${cmd[@]}" <<<"$prompt" >"$out" &
  wait "$!" || rc=$?
  if [ "$rc" -eq 0 ] && [ -n "$schema" ]; then
    if validate_json "$out"; then vrc=0; else vrc=$?; fi  # if 형태 = set -e 안전
    [ "$vrc" -eq 0 ] || rc=$vrc
    [ "$vrc" -eq 3 ] && degraded=1
  fi
fi

# 벤더 성공(rc=0)인데 출력이 비거나 공백뿐이면 stdout 계약("사용 가능한 최종 결과만") 위반 — 사용불가(1)로 승격.
# grep rc 1(no match)=blank, 그 외 비0(EIO 등)=환경 오류(2) — 오진 방지 위해 구분.
if [ "$rc" -eq 0 ]; then
  grc=0; grep -q '[^[:space:]]' "$out" || grc=$?
  if [ "$grc" -eq 1 ]; then
    echo "error: vendor succeeded but produced empty/blank output (unusable)" >&2; rc=1
  elif [ "$grc" -ne 0 ]; then
    echo "error: blank-check failed reading vendor output (grep rc=$grc)" >&2; rc=2
  fi
fi

# 출력 채널: 성공(0)·강등(degraded 플래그)은 usable → stdout, 실패는 오염방지 위해 stderr.
# rc==3을 직접 보지 않음 — 벤더가 우연히 exit 3이면 강등 아닌 실패이므로 stderr로 가야 함.
# emit: cat 실패 중 141(SIGPIPE=하류 조기종료, 양성)만 무시하고 실제 전달실패(디스크풀 등)는 rc로 전파.
#   조용한 성공-데이터손실 방지. rc가 이미 0/강등일 때만 덮어씀(벤더 실패 rc 보존).
emit() {  # $1=대상 fd(1|2)
  local crc=0
  # 백그라운드+wait — 안 읽는 하류로 cat이 write 블록돼도 시그널(TERM)이 인터럽트 가능(전경이면 bash가 보류).
  cat "$out" >&"$1" &
  if wait "$!"; then crc=0; else crc=$?; fi
  # 141(SIGPIPE)=양성 무시. 그 외 실전달실패는 결과가 deliverable(성공 0 또는 강등)이었을 때만 rc로 승격
  # (벤더 자체 실패 rc는 더 정보량 많으므로 보존). return 0 = emit이 set -e를 트립하지 않음.
  if [ "$crc" -ne 0 ] && [ "$crc" -ne 141 ]; then
    { [ "$rc" -eq 0 ] || [ "$degraded" -eq 1 ]; } && rc=$crc
  fi
  return 0
}
if [ "$rc" -eq 0 ] || [ "$degraded" -eq 1 ]; then
  emit 1
else
  emit 2
fi
exit "$rc"
