#!/usr/bin/env bash
# usage: oneshot.sh [--mode read|write] [--schema <f>] [--model <m>] [--effort low|medium|high]
#                   [--prompt-file <f> | --stdin] [--raw] <agent> ["<prompt>"]
#
# 벤더 중립 facade: 모든 파라미터를 벤더 플래그로 매핑. passthrough 없음.
#
# 프롬프트 소스: positional "<prompt>" | --prompt-file <f> | --stdin 중 "정확히 하나"(0개·2개는 오류).
#   래퍼가 소스를 읽어 전체를 벤더 stdin으로 전달(스트리밍 아님, EOF까지 버퍼링). 후행 개행은 정규화됨.
# --mode: read(기본)=읽기전용 안전. write=권한·샌드박스 "완전해제"(claude/agy는 --dangerously-skip-permissions,
#   codex는 danger-full-access) — "호출자가 이미 격리했다"는 선언. 단순 쓰기추가 아님.
# --schema <f>: 구조화 출력. codex는 네이티브(--output-schema), claude/agy는 프롬프트 주입+사후검증.
#   jsonschema 미설치 시 well-formed만 검증(강등, exit 3). --raw와 상호배타.
# --raw: 출력 정규화 끄기 — 사실상 codex 전용(claude/agy는 기본 출력이 이미 최종만이라 no-op).
#
# 출력 채널(캡처 경로 = --schema 또는 codex 정규화): 성공/강등 결과 → stdout, 실패 시 벤더 출력·진단·codex 세션로그 → stderr.
#   (stdout은 "사용 가능한 최종 결과"만 담는 깨끗한 채널 — 파이프 조합용.)
#   예외: exec 경로(--raw, 또는 스키마 없는 순수 read)는 벤더 stdout/stderr를 네이티브 그대로 통과 —
#   실패해도 벤더 stdout이 stdout에 남음(성능·스트리밍 위해 캡처 안 함). 실패 격리 필요 시 --schema로 캡처 경로 사용.
# exit code: 0=성공(스키마 지정 시 검증 통과) | 1=스키마 검증 실패(위반·비JSON) | 2=usage/인자 오류
#   | 3=강등(well-formed지만 스키마 미강제, 출력은 usable) | 그 외=벤더 CLI의 rc 그대로 전달.
#   (주의: 벤더가 우연히 1/2/3을 쓰면 겹칠 수 있음.)
set -euo pipefail

usage() {
  echo "usage: oneshot.sh [--mode read|write] [--schema <f>] [--model <m>] [--effort low|medium|high] [--prompt-file <f>|--stdin] [--raw] <agent> \"<prompt>\"" >&2
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

# 프롬프트 소스 정확히 하나: positional | --prompt-file | --stdin
src=0
[ -n "$prompt_file" ] && src=$((src+1))
[ "$use_stdin" -eq 1 ] && src=$((src+1))
[ $# -ge 1 ] && src=$((src+1))
[ "$src" -eq 1 ] || { echo "exactly one prompt source required (positional | --prompt-file | --stdin), got $src" >&2; exit 2; }

# --- 리소스/시그널 생명주기 (프롬프트 읽기 전에 설치 — --stdin 버퍼링 중 시그널도 커버) ---
stin=""; out=""; child=""
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
on_signal() {  # $1=시그널명. 실행 중인 자식 트리 kill → temp 정리 → 시그널 재전파.
  # child는 [백그라운드 spawn, wait 복귀 직후 클리어] 구간에만 설정됨(그 밖엔 ""). $! 폴백 안 씀 —
  # reap된 stale PID(재사용 시 무관 프로세스)를 kill하는 위험 회피. child 항상 초기화됨(set -u 안전).
  [ -n "$child" ] && kill_tree "$child"
  cleanup
  trap - INT TERM EXIT
  kill -"$1" "$$"
}
trap cleanup EXIT
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM

if [ -n "$prompt_file" ]; then
  # 정규파일만 — /dev/zero 등 특수·무한 장치로 인한 무한 읽기(hang) 차단.
  # 파이프·process-substitution(<(...))은 정규파일 아님 → --stdin으로 넣을 것.
  [ -f "$prompt_file" ] && [ -r "$prompt_file" ] || { echo "prompt file must be a readable regular file: $prompt_file (for pipes/<(...) use --stdin)" >&2; exit 2; }
  # NUL 바이트 = 바이너리 파일 오지정. $(cat)이 NUL을 조용히 제거해 프롬프트가 절단되므로 거부.
  [ "$(LC_ALL=C tr -dc '\000' < "$prompt_file" | wc -c)" -eq 0 ] || { echo "prompt file contains NUL bytes (binary?): $prompt_file" >&2; exit 2; }
  prompt=$(cat -- "$prompt_file")
elif [ "$use_stdin" -eq 1 ]; then
  # stdin은 스트림이라 한 번만 읽힘 → temp로 버퍼 후 NUL 검사(--prompt-file과 동일 계약).
  # stin 정리는 통합 cleanup(EXIT/시그널)이 담당.
  # cat을 백그라운드+wait로 — 전경 외부명령 중엔 bash가 trap을 보류해 비종료 stdin+단일 PID TERM 시 hang.
  # wait(빌트인)은 인터럽트 가능 → on_signal이 cat 자식 kill·정리·재전파.
  # <&0: 비대화형 bash는 'cmd &' stdin을 /dev/null로 돌리므로 스크립트 stdin(fd0)을 명시 연결.
  # 시그널은 on_signal이 재전파(스크립트 종료)하므로 여기 도달하는 실패는 순수 cat 실패 → fail-loud.
  stin=$(mktemp); cat <&0 > "$stin" & child=$!
  if wait "$child"; then scrc=0; else scrc=$?; fi
  child=""
  [ "$scrc" -eq 0 ] || { echo "stdin read failed (rc=$scrc)" >&2; exit 2; }  # 입력오류 계열(계약상 2)
  [ "$(LC_ALL=C tr -dc '\000' < "$stin" | wc -c)" -eq 0 ] || { echo "stdin contains NUL bytes (binary?)" >&2; exit 2; }
  prompt=$(cat -- "$stin"); rm -f -- "$stin"; stin=""
else
  # positional 프롬프트가 -로 시작 = 오배치된 래퍼 플래그일 가능성. dash 프롬프트는 --prompt-file/--stdin으로.
  case "$1" in -*) echo "prompt starts with '-' (put wrapper flags before <agent>, or use --prompt-file/--stdin)" >&2; exit 2 ;; esac
  prompt="$1"; shift
fi
[ $# -eq 0 ] || { echo "unexpected extra args: $*" >&2; exit 2; }
[ -n "$prompt" ] || { echo "empty prompt (source produced no content)" >&2; exit 2; }

# schema 주입(codex 외): 네이티브 미지원 벤더는 프롬프트에 스키마 주입 + 사후검증
if [ -n "$schema" ] && [ "$agent" != codex ]; then
  prompt="$prompt

[출력 요구] 아래 JSON 스키마를 정확히 따르는 단일 JSON 문서만 출력하라. 산문·코드펜스 없이 JSON만.
스키마:
$(cat -- "$schema")"
fi

# JSON 사후검증: jsonschema 있으면 스키마 검증, 없으면 well-formed만(폴백)
validate_json() {  # $1=data_file $2=schema_file
  python3 - "$1" "$2" <<'PY'
import json, sys
def _reject(c): raise ValueError(f"non-RFC JSON constant: {c}")
try:
    obj = json.loads(open(sys.argv[1]).read(), parse_constant=_reject)  # NaN/Infinity 등 비-RFC 거부
except Exception as e:
    print(f"schema validation: output is not valid JSON: {e}", file=sys.stderr); sys.exit(1)
try:
    import jsonschema
    jsonschema.validate(obj, json.load(open(sys.argv[2])))
except ImportError:
    print("schema validation DEGRADED: jsonschema not installed, checked well-formed JSON only (schema NOT enforced)", file=sys.stderr)
    sys.exit(3)  # 강등: well-formed지만 스키마 미강제 — exit 0(검증됨)과 구별
except Exception as e:
    print(f"schema validation failed: {e}", file=sys.stderr); sys.exit(1)
sys.exit(0)
PY
}

# 벤더별 명령 배열 조립
m=(); [ -n "$model" ] && m=(--model "$model")
case "$agent" in
  claude)
    e=(); [ -n "$effort" ] && e=(--effort "$effort")
    if [ "$mode" = write ]; then perm=(--dangerously-skip-permissions)
    else perm=(--allowedTools=Read,Grep,Glob --disallowedTools=Bash,Edit,Write,NotebookEdit); fi
    cmd=(claude -p "${perm[@]}" ${m[@]+"${m[@]}"} ${e[@]+"${e[@]}"}) ;;
  codex)
    sb=read-only; [ "$mode" = write ] && sb=danger-full-access
    e=(); [ -n "$effort" ] && e=(-c "model_reasoning_effort=$effort")
    sc=(); [ -n "$schema" ] && sc=(--output-schema "$schema")
    cmd=(codex exec -c "sandbox_mode=$sb" ${m[@]+"${m[@]}"} ${e[@]+"${e[@]}"} ${sc[@]+"${sc[@]}"}) ;;
  agy)
    e=(); [ -n "$effort" ] && e=(--effort "$effort")
    if [ "$mode" = write ]; then md=(--dangerously-skip-permissions)
    else md=(--mode plan); fi
    cmd=(agy -p "${md[@]}" ${m[@]+"${m[@]}"} ${e[@]+"${e[@]}"}) ;;
  *)
    echo "unknown agent: $agent (claude|codex|agy)" >&2; exit 2 ;;
esac

# 실행 경로: capture 필요 = codex 정규화(비-raw) 또는 schema 사후검증
need_capture=0
{ [ "$agent" = codex ] && [ "$raw" -eq 0 ]; } && need_capture=1
[ -n "$schema" ] && [ "$agent" != codex ] && need_capture=1
# codex + schema: 네이티브 --output-schema라 검증 불필요, 정규화만(위 조건에 포함)

# 프롬프트는 stdin(herestring)으로 전달 — argv 크기 한계(E2BIG) 회피, 플래그 격리는 stdin이라 자동
if [ "$need_capture" -eq 0 ]; then
  exec "${cmd[@]}" <<<"$prompt"
fi

out=$(mktemp)   # 시그널/EXIT trap·cleanup은 앞에서 이미 설치됨
rc=0
degraded=0  # validate_json 강등(스키마 미강제)만 표시 — 벤더의 우연한 exit 3과 구별
if [ "$agent" = codex ]; then
  # 정규화: 최종 메시지만 -o로 받고 세션로그는 stderr로
  "${cmd[@]}" --output-last-message "$out" <<<"$prompt" >&2 & child=$!
  wait "$child" || rc=$?; child=""   # 즉시 클리어 — 이후 foreground 구간서 stale PID kill 방지
else
  # claude/agy schema: clean stdout 캡처 후 검증 (벤더 성공 시에만 — 실패 rc 보존)
  "${cmd[@]}" <<<"$prompt" >"$out" & child=$!
  wait "$child" || rc=$?; child=""   # 즉시 클리어 — validate_json(foreground) 구간 stale PID kill 방지
  if [ "$rc" -eq 0 ] && [ -n "$schema" ]; then
    if validate_json "$out" "$schema"; then vrc=0; else vrc=$?; fi  # if 형태 = set -e 안전
    [ "$vrc" -eq 0 ] || rc=$vrc
    [ "$vrc" -eq 3 ] && degraded=1
  fi
fi
child=

# 벤더 성공(rc=0)인데 출력이 비면 파이프 하류(|jq)가 조용히 빈입력 소비 — stderr로 fail-loud 진단.
[ "$rc" -eq 0 ] && [ ! -s "$out" ] && echo "warning: vendor succeeded but produced empty output" >&2

# 출력 채널: 성공(0)·강등(degraded 플래그)은 usable → stdout, 실패는 오염방지 위해 stderr.
# rc==3을 직접 보지 않음 — 벤더가 우연히 exit 3이면 강등 아닌 실패이므로 stderr로 가야 함.
# emit: cat 실패 중 141(SIGPIPE=하류 조기종료, 양성)만 무시하고 실제 전달실패(디스크풀 등)는 rc로 전파.
#   조용한 성공-데이터손실 방지. rc가 이미 0/강등일 때만 덮어씀(벤더 실패 rc 보존).
emit() {  # $1=대상 fd(1|2)
  local crc=0
  # 백그라운드+wait — 안 읽는 하류로 cat이 write 블록돼도 시그널(TERM)이 인터럽트 가능(전경이면 bash가 보류).
  cat "$out" >&"$1" & child=$!
  if wait "$child"; then crc=0; else crc=$?; fi
  child=""
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
