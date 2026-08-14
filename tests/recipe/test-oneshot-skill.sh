#!/usr/bin/env bash
# recipe oneshot 스킬의 런타임 계약 검증
#
# 이 스킬은 다른 스킬과 달리 실행되는 스크립트다 — 문서 문구뿐 아니라 동작
# 불변식을 못박는다. 계약이 주석에만 있으면 구조를 바꿀 때마다 같은 결함이
# 다른 자리에서 재발하기 때문이다.
#
# 에이전트는 가짜 CLI로 대역한다 — 실제 모델을 호출하지 않아 빠르고 결정적이다.
# 가짜는 받은 argv와 stdin을 그대로 기록한다. 이 래퍼의 존재 이유가 벤더별 호출
# 관례 흡수인데, 가짜가 argv를 무시하면 그 관례를 검사하는 곳이 어디에도 없다.

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_DIR="$REPO_ROOT/plugins/recipe/skills/oneshot"
SCRIPT="$SKILL_DIR/references/oneshot.sh"
SKILL_MD="$SKILL_DIR/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

# set -e 없는 스위트라 실패 대입이 조용히 지나간다 — WORK가 비면 BIN="/bin"이 되어
# 시스템 디렉터리에 가짜를 쓰려 들므로 여기서만은 명시 가드.
WORK="$(mktemp -d)" || fail "mktemp -d 실패"
[[ -n "$WORK" && -d "$WORK" ]] || fail "mktemp -d 산출물 이상: '$WORK'"
command -v jq >/dev/null 2>&1 || fail "테스트 전제 위반: jq 필요"
trap 'rm -rf "$WORK"' EXIT
# BIN 생성 실패를 승격 — 실패하면 PATH가 /usr/bin:/bin으로 폴백해 **실물** claude/codex/agy가
# 호출되고, write 셀의 권한 해제 플래그까지 실물에 전달된다.
BIN="$WORK/bin"; mkdir -p "$BIN" || fail "가짜 CLI 디렉터리 생성 실패: $BIN"
[[ -d "$BIN" && -w "$BIN" ]] || fail "가짜 CLI 디렉터리 사용 불가: $BIN"
# 벤더 CLI는 PATH 선두의 $BIN 가짜가 가린다 — 시스템 실물 존재 여부는 일반 케이스에
# 영향 없음. 실물이 /usr/bin·/bin에 있으면 "부재 재현" 케이스(TEST 19)만 개별 skip.
ln -sf "$(command -v jq)" "$BIN/jq" || fail "가짜 bin에 jq 링크 실패"
[[ -x "$BIN/jq" ]] || fail "가짜 bin의 jq 실행 불가"
SANDBOX_PATH="$BIN:/usr/bin:/bin"

# 가짜 벤더 CLI — argv를 한 줄에 하나씩, stdin을 바이트 그대로 기록한 뒤
# FAKE_BEHAVIOR에 따라 응답한다. codex 정규화 경로(--output-last-message)를
# 실물처럼 존중한다: 최종 메시지는 지정 파일로, 세션 로그는 stdout으로.
make_fake() {   # $1=이름
  cat > "$BIN/$1" <<EOF
#!/usr/bin/env bash
name=\$(basename "\$0")
echo . >> "$WORK/calls.\$name"   # 호출 횟수 — "정확히 1회 실행" 계약용(기록 파일은 덮어써도 이건 누적)
printf '%s\n' "\$@" > "$WORK/argv.\$name"
# 서브커맨드 문법 대역 — 실물 codex는 첫 인자가 exec가 아니면 거부한다. 가짜가 무엇이든 받으면
# "exec 서브커맨드로 호출" 계약이 argv 문자열 비교로만 남고 실제 수용성은 무검증이 된다.
if [[ "\$name" == codex && "\${1-}" != exec ]]; then
  echo "error: unrecognized subcommand '\${1-}'" >&2; exit 2
fi
env > "$WORK/env.\$name"        # env 오염 검사용 — unset -v prompt/sch(E2BIG 방어) 핀
cat > "$WORK/stdin.\$name"
out_file="" schema_file="" prev=""
for a in "\$@"; do
  [[ "\$prev" == --output-last-message ]] && out_file="\$a"
  [[ "\$prev" == --output-schema || "\$prev" == --json-schema ]] && schema_file="\$a"
  prev="\$a"
done
# 네이티브 스키마 강제 대역 — 실물은 스키마 위반 출력을 거부한다. 가짜가 무조건 성공하면
# "네이티브라 사후검증 불필요"라는 래퍼 계약이 어떤 테스트로도 확인되지 않는다.
enforce() {   # \$1=출력 후보. 스키마 자체가 불량이면 rc 2, 출력이 스키마 위반이면 rc 1 — 실물과 동일
  [[ -n "\$schema_file" ]] || return 0
  [[ -f "\$schema_file" ]] || { echo "schema file unreadable: \$schema_file" >&2; exit 2; }
  # 실물 벤더는 jq에 의존하지 않는다 — 대역이 PATH의 jq를 쓰면 "codex·agy는 jq 면제" 케이스가
  # (정의상 jq 없는 PATH로 도는) NOJQ 환경에서 거짓 실패한다. 굽어둔 절대경로로 호출해 강제는 유지.
  local JQ="$(command -v jq)"
  [[ -x "\$JQ" ]] || return 0
  "\$JQ" -e . "\$schema_file" >/dev/null 2>&1 || { echo "invalid schema file: not valid JSON" >&2; exit 2; }
  local k t
  for k in \$("\$JQ" -r '(.required // [])[]' "\$schema_file"); do
    "\$JQ" -e --arg k "\$k" 'has(\$k)' >/dev/null 2>&1 <<<"\$1" \
      || { echo "structured output violates schema: missing \$k" >&2; exit 1; }
  done
  # 타입 검사는 required가 아니라 **출력에 존재하는 모든 선언 속성**에 건다 — optional 속성의
  # 타입 위반도 strict 모드가 거부하므로, required만 보면 그 위반이 대역을 통과한다.
  for k in \$("\$JQ" -r '(.properties // {} | keys)[]' "\$schema_file"); do
    "\$JQ" -e --arg k "\$k" 'has(\$k)' >/dev/null 2>&1 <<<"\$1" || continue
    t=\$("\$JQ" -r --arg k "\$k" '.properties[\$k].type // empty' "\$schema_file")
    [[ -z "\$t" ]] || "\$JQ" -e --arg k "\$k" --arg t "\$t" '(.[\$k]|type) == \$t' >/dev/null 2>&1 <<<"\$1" \
      || { echo "structured output violates schema: \$k type != \$t" >&2; exit 1; }
  done
  # additionalProperties:false — 스키마에 선언되지 않은 키는 실물 strict 모드가 거부
  if [[ "\$("\$JQ" -r '.additionalProperties' "\$schema_file")" == false ]]; then
    "\$JQ" -e --slurpfile s "\$schema_file" \
      'keys - (\$s[0].properties // {} | keys) | length == 0' >/dev/null 2>&1 <<<"\$1" \
      || { echo "structured output violates schema: additionalProperties" >&2; exit 1; }
  fi
}
# 실물 codex는 -o 지정 시에도 최종 메시지를 stdout(세션 스트림)에 함께 출력 — 가짜도 동일해야
# "세션로그 stderr 회수" 어서션이 실물 조건에서 검증됨 (가짜가 실물보다 깨끗하면 오탐 통과)
emit() { if [[ -n "\$out_file" ]]; then printf '%s' "\$1" > "\$out_file"; printf '%s\n' "\$1"; echo SESSION_LOG; else printf '%s' "\$1"; fi; }
case "\${FAKE_BEHAVIOR:-echo}" in
  # echo는 emit을 안 쓴다 — \$( ) 명령 치환이 후행 개행을 지워 바이트 판정을 오염시킨다
  echo)     if [[ -n "\$out_file" ]]; then cat "$WORK/stdin.\$name" > "\$out_file"; cat "$WORK/stdin.\$name"; echo SESSION_LOG
            else cat "$WORK/stdin.\$name"; fi ;;
  json)     enforce '{"ok":true}'; emit '{"ok":true}' ;;
  badschema) enforce '{"nope":1}'; emit '{"nope":1}' ;;   # 스키마 위반(키 누락) — 네이티브 벤더는 거부
  badtype)   enforce '{"ok":"wrong"}'; emit '{"ok":"wrong"}' ;;   # required 속성 타입 위반
  badopt)    enforce '{"ok":true,"note":9}'; emit '{"ok":true,"note":9}' ;;   # optional 속성 타입 위반
  badextra)  enforce '{"ok":true,"extra":1}'; emit '{"ok":true,"extra":1}' ;;   # 미선언 키 — additionalProperties:false 위반
  notjson)  emit 'plain text' ;;
  multidoc) emit '{"a":1} {"b":2}' ;;
  blank)    emit '   ' ;;
  fail)     printf 'boom-out'; printf 'boom-err' >&2; exit 42 ;;
  fail3)    printf 'oops'; exit 3 ;;   # 벤더의 "우연한" exit 3 — 강등과 구별돼야 함
  block)    echo \$\$ > "$WORK/pid.\$name"; sleep 15 ;;   # 시그널 계약용 — pid 기록 후 블록
  big)      emit "\$(head -c 1500000 /dev/zero | tr '\\0' 'y')" ;;   # 파이프 버퍼 초과 — SIGPIPE 면제 핀용
esac
EOF
  chmod +x "$BIN/$1" || fail "가짜 CLI 실행권한 설정 실패: $1"
  [[ -s "$BIN/$1" && -x "$BIN/$1" ]] || fail "가짜 CLI 생성 실패: $1 (실물 벤더 실행 위험)"
}
for v in claude codex agy; do make_fake "$v"; done
# PATH 해소가 가짜를 가리키는지 최종 확인 — 하나라도 실물이면 write 셀이 실물 권한 해제로 돈다
for v in claude codex agy; do
  [[ "$(PATH="$SANDBOX_PATH" command -v "$v")" == "$BIN/$v" ]] \
    || fail "PATH 해소가 가짜를 가리키지 않음: $v → $(PATH="$SANDBOX_PATH" command -v "$v")"
done

# 래퍼 실행 하네스. stdout/stderr를 파일로 남긴다 — 변수로 받으면 명령 치환이
# 후행 개행을 지워 바이트 판정이 불가능하다. stdin은 기본 /dev/null(--stdin
# 케이스만 호출측이 파이프로 공급).
RC=0
run() {   # $@=래퍼 인자. BEHAVIOR 전역으로 가짜 동작 선택.
  # bash는 *함수* 앞 변수 대입을 호출 후에도 유지한다(posix 모드 아님) — `BEHAVIOR=x run …`의
  # 값이 다음 무접두 run까지 새어 의도와 다른 가짜 동작으로 조용히 돌게 되므로 매 호출 후 해제.
  rm -f "$WORK"/argv.* "$WORK"/stdin.* "$WORK"/calls.* "$WORK/out" "$WORK/err"
  PATH="$SANDBOX_PATH" FAKE_BEHAVIOR="${BEHAVIOR:-echo}" \
    bash "$SCRIPT" "$@" >"$WORK/out" 2>"$WORK/err" </dev/null
  RC=$?
  unset BEHAVIOR
}

argv_has()  { grep -Fxq -- "$2" "$WORK/argv.$1" || fail "argv.$1 에 '$2' 없음: $(tr '\n' ' ' < "$WORK/argv.$1")"; }
argv_not()  { grep -Fxq -- "$2" "$WORK/argv.$1" 2>/dev/null && fail "argv.$1 에 '$2' 가 있으면 안 됨"; return 0; }
# 짝(인접) 검사 — 존재만 보면 `--model high --effort m1`처럼 짝이 바뀌거나 `-c` 가
# 탈락해 값이 positional로 새는 회귀(실물 codex는 설정 아닌 프롬프트로 해석)를 놓친다.
argv_pair() {   # $1=벤더 $2=플래그 $3=바로 다음 인자
  awk -v f="$2" -v v="$3" 'p{if($0==v)found=1;p=0} $0==f{p=1} END{exit found?0:1}' "$WORK/argv.$1" \
    || fail "argv.$1 에 인접 짝 '$2 $3' 없음: $(tr '\n' ' ' < "$WORK/argv.$1")"
}
out_is()    { printf '%s' "$1" | cmp -s - "$WORK/out" || fail "stdout 불일치 (기대 $(printf '%s' "$1" | od -c | head -2 | tr '\n' ' ') / 실제 $(od -c < "$WORK/out" | head -2 | tr '\n' ' '))"; }
err_has()   { grep -q "$1" "$WORK/err" || fail "stderr 에 '$1' 없음: $(head -3 "$WORK/err")"; }
stdin_is()  { printf '%s' "$2" | cmp -s - "$WORK/stdin.$1" || fail "stdin.$1 바이트 불일치: $(od -c < "$WORK/stdin.$1" | head -2 | tr '\n' ' ')"; }
rc_is()     { [[ "$RC" -eq "$1" ]] || fail "rc 기대 $1, 실제 $RC ($(head -3 "$WORK/err" 2>/dev/null))"; }
no_vendor() { ls "$WORK"/argv.* 2>/dev/null && fail "벤더가 호출되면 안 되는 경로에서 호출됨"; return 0; }
calls_is()  { local n; n=$(wc -l < "$WORK/calls.$1" 2>/dev/null) || n=0; [[ "$((n))" -eq "$2" ]] || fail "벤더 $1 호출 횟수 기대 $2, 실제 $((n))"; }
# 정확한 인자 개수 핀 — 잉여 positional(실물 codex는 PROMPT로 해석)이 조용히 붙는 회귀 차단
argv_len()  { local n; n=$(wc -l < "$WORK/argv.$1"); [[ "$((n))" -eq "$2" ]] || fail "argv.$1 인자 개수 기대 $2, 실제 $((n)): $(tr '\n' ' ' < "$WORK/argv.$1")"; }

# 실물 codex Structured Outputs strict 제약 충족 fixture — required·additionalProperties 없으면 실물은 거부
VALID_SCHEMA="$WORK/schema.json"
# optional 속성(note)을 포함 — required만 있는 fixture로는 optional 타입 위반 경로가 검증되지 않는다
printf '{"type":"object","properties":{"ok":{"type":"boolean"},"note":{"type":"string"}},"required":["ok"],"additionalProperties":false}' > "$VALID_SCHEMA"

echo "=== TEST 1: claude read 기본 argv + 프롬프트 stdin 전달 ==="
BEHAVIOR=echo run claude "hi"
rc_is 0
argv_has claude "-p"
argv_has claude "--allowedTools=Read,Grep,Glob"
argv_has claude "--disallowedTools=Bash,Edit,Write,NotebookEdit"
argv_not claude "--dangerously-skip-permissions"   # read에 해제 플래그 병기 회귀 차단
argv_not claude "--model"
# 명시적 --mode read — 기본값 경로와 별개 분기 입력. 파서가 명시 read를 write로 오해하는 회귀 차단
BEHAVIOR=echo run --mode read claude "hi"
rc_is 0
argv_has claude "--allowedTools=Read,Grep,Glob"
argv_not claude "--dangerously-skip-permissions"
argv_not claude "hi"        # 프롬프트는 stdin 전용 — argv 병기 회귀(E2BIG·codex 이중 주입) 차단
stdin_is claude $'hi\n'     # herestring이 개행 1개 추가
out_is $'hi\n'              # exec 경로: 벤더 stdout 그대로
calls_is claude 1           # 정확히 1회 실행
argv_len claude 3           # -p --allowedTools --disallowedTools — 그 외 아무것도 없음
# 호출자 export 상속 차단(unset -v prompt sch) — 대형 프롬프트가 벤더 env에 실리면 execve E2BIG
export prompt=ENV_CANARY sch=ENV_CANARY2
BEHAVIOR=echo run claude "hi"
rc_is 0
grep -q '^prompt=' "$WORK/env.claude" && fail "prompt가 벤더 env에 노출(unset -v 회귀)"
grep -q '^sch=' "$WORK/env.claude" && fail "sch가 벤더 env에 노출(unset -v 회귀)"
unset prompt sch
ok "claude read 기본 + env 오염 차단"

echo "=== TEST 2: claude write + model + effort ==="
BEHAVIOR=echo run --mode write --model m1 --effort high claude "x"
rc_is 0
argv_has claude "--dangerously-skip-permissions"
argv_pair claude --model m1
argv_pair claude --effort high
argv_not claude "--allowedTools=Read,Grep,Glob"
argv_not claude "--disallowedTools=Bash,Edit,Write,NotebookEdit"   # write에 제한 병기 회귀 차단
argv_len claude 6   # -p bypass --model m1 --effort high — 실물이 거부할 잉여 플래그 금지
ok "claude write 플래그 매핑"

echo "=== TEST 3: agy read=plan / write=skip-permissions ==="
BEHAVIOR=echo run agy "x"
rc_is 0; argv_has agy "-p"; argv_pair agy --mode plan
argv_not agy "--dangerously-skip-permissions"
argv_not agy "x"   # 프롬프트 argv 누출 차단
argv_len agy 3     # -p --mode plan
BEHAVIOR=echo run --mode write --model m2 --effort low agy "x"
rc_is 0; argv_has agy "--dangerously-skip-permissions"; argv_not agy "plan"
argv_pair agy --mode accept-edits   # 실행 모드 명시 — 저장된 agentMode(plan) 의존 차단
argv_pair agy --model m2
argv_pair agy --effort low
argv_not agy "x"
argv_len agy 8   # -p --mode accept-edits --dangerously-skip-permissions --model m2 --effort low
ok "agy 모드·model·effort 매핑"

echo "=== TEST 4: codex read 정규화 — 최종 메시지 stdout, 세션 로그 stderr ==="
BEHAVIOR=json run codex "x"
rc_is 0
argv_has codex "exec"
[[ "$(head -1 "$WORK/argv.codex")" == exec ]] || fail "codex 첫 인자가 exec 아님 — 서브커맨드 전용 옵션은 exec 뒤에 와야 실물이 수용"
argv_pair codex -c sandbox_mode=read-only
argv_not codex "sandbox_mode=danger-full-access"
argv_not codex "--dangerously-bypass-approvals-and-sandbox"   # read에 bypass 혼입 = read 계약 전면 무력화
argv_has codex "--output-last-message"
argv_not codex "x"   # 프롬프트 argv 누출 차단 — 실물 codex는 positional을 프롬프트로 해석
out_is '{"ok":true}'
err_has SESSION_LOG
stdin_is codex $'x\n'
calls_is codex 1
argv_len codex 5   # exec -c sandbox_mode=read-only --output-last-message <파일> — 잉여 positional 금지
# read + model/effort — 옵션 배열이 모드 플래그를 잠식하는 회귀 차단.
# codex는 이 조합에서만 -c가 2개가 되므로 write 셀들로는 대체 불가.
BEHAVIOR=json run --effort low --model m9 codex "x"
rc_is 0
argv_pair codex -c sandbox_mode=read-only
argv_pair codex -c model_reasoning_effort=low
argv_pair codex --model m9
argv_not codex "--dangerously-bypass-approvals-and-sandbox"
argv_len codex 9   # exec -c smro --model m9 -c mre=low -o <f>
BEHAVIOR=echo run --effort high --model m9 claude "hi"
rc_is 0
argv_has claude "--allowedTools=Read,Grep,Glob"
argv_not claude "--dangerously-skip-permissions"
argv_len claude 7   # -p --allowedTools --disallowedTools --model m9 --effort high
BEHAVIOR=echo run --effort high --model m9 agy "hi"
rc_is 0
argv_pair agy --mode plan
argv_not agy "--dangerously-skip-permissions"
argv_len agy 7     # -p --mode plan --model m9 --effort high
ok "codex 정규화 채널 분리 + read×model·effort 직교"

echo "=== TEST 5: codex write + effort ==="
BEHAVIOR=json run --mode write --effort low --model m3 codex "x"
rc_is 0
argv_has codex "--dangerously-bypass-approvals-and-sandbox"   # 승인 정책까지 해제하는 전용 플래그
argv_not codex "sandbox_mode=read-only"       # 이중 -c 재정의 회귀 차단(실물 codex는 나중 값 승리)
argv_not codex "sandbox_mode=danger-full-access"   # 승인 정책 남기는 반쪽 해제로의 회귀 차단
argv_pair codex -c model_reasoning_effort=low
argv_pair codex --model m3
# write도 캡처(정규화) 경로 — exec 경로로 새면 세션로그가 stdout 오염 (헤더 계약은 모드 무관)
argv_has codex "--output-last-message"
err_has SESSION_LOG
out_is '{"ok":true}'
argv_len codex 8   # exec bypass --model m3 -c mre=low -o <파일> — 잉여 인자 금지
ok "codex write·effort·model 매핑·정규화 유지"

echo "=== TEST 6: codex --raw = exec 통과, 정규화 없음 ==="
BEHAVIOR=echo run --raw codex "x"
rc_is 0
argv_not codex "--output-last-message"
argv_pair codex -c sandbox_mode=read-only   # --raw는 출력 정규화만 끔 — 샌드박스 유지
argv_not codex "--dangerously-bypass-approvals-and-sandbox"
argv_len codex 3   # exec -c sandbox_mode=read-only
out_is $'x\n'
# claude/agy의 --raw는 no-op 계약 — 기본 exec 경로와 동일하게 성공·통과해야 함
BEHAVIOR=echo run --raw claude "hi"
rc_is 0; out_is $'hi\n'; argv_has claude "--allowedTools=Read,Grep,Glob"
argv_not claude "--raw"; argv_len claude 3   # no-op = 기본 경로와 동일 argv(실물엔 --raw 없음)
BEHAVIOR=echo run --raw agy "hi"
rc_is 0; out_is $'hi\n'; argv_pair agy --mode plan
argv_not agy "--raw"; argv_len agy 3
# raw×write — raw가 모드를 read로 강등하면 안 됨(raw는 출력 정규화만 담당)
BEHAVIOR=echo run --raw --mode write codex "x"
rc_is 0
argv_has codex "--dangerously-bypass-approvals-and-sandbox"
argv_not codex "sandbox_mode=read-only"
argv_len codex 2   # exec bypass
ok "raw: codex 정규화 해제, claude·agy no-op, 모드 보존"

echo "=== TEST 7: codex --schema 네이티브 전달(강등 없음) ==="
BEHAVIOR=json run --schema "$VALID_SCHEMA" codex "x"
rc_is 0
argv_pair codex --output-schema "$VALID_SCHEMA"
argv_has codex "--output-last-message"   # schema 경로도 캡처(정규화) 유지 — exec 경로로 새면 세션로그가 stdout 오염
err_has SESSION_LOG
stdin_is codex $'x\n'    # 네이티브 경로에 프롬프트 주입이 새는 회귀 차단
out_is '{"ok":true}'
grep -q DEGRADED "$WORK/err" && fail "codex 네이티브 경로에 강등이 있으면 안 됨"
# 스키마 요청 ≠ 모드 변경 — read 플래그 유지·bypass 부재
argv_pair codex -c sandbox_mode=read-only
argv_not codex "--dangerously-bypass-approvals-and-sandbox"
argv_len codex 7   # exec -c smro --output-schema <f> -o <f>
# write×schema — bypass와 --output-schema 동시 유지(어느 쪽도 탈락 금지)
BEHAVIOR=json run --mode write --schema "$VALID_SCHEMA" codex "x"
rc_is 0
argv_has codex "--dangerously-bypass-approvals-and-sandbox"
argv_pair codex --output-schema "$VALID_SCHEMA"
argv_len codex 6   # exec bypass --output-schema <f> -o <f>
out_is '{"ok":true}'   # write+schema에서도 최종 결과가 stdout에 실려야 함
err_has SESSION_LOG
# agy 네이티브(--json-schema) — 주입·강등 없음, exec 경로 그대로
BEHAVIOR=json run --schema "$VALID_SCHEMA" agy "x"
rc_is 0
argv_pair agy --json-schema "$VALID_SCHEMA"
argv_pair agy --output-format json   # --json-schema의 플래그 의존성(output-format json 필수)
stdin_is agy $'x\n'   # 프롬프트에 스키마 주입 금지(네이티브)
out_is '{"ok":true}'
grep -q DEGRADED "$WORK/err" && fail "agy 네이티브 경로에 강등이 있으면 안 됨"
argv_pair agy --mode plan
argv_not agy "--dangerously-skip-permissions"
argv_len agy 7   # -p --mode plan --output-format json --json-schema <f>
# agy write×schema — accept-edits·skip-permissions·--json-schema 동시 유지
BEHAVIOR=json run --mode write --schema "$VALID_SCHEMA" agy "x"
rc_is 0
argv_pair agy --mode accept-edits
argv_has agy "--dangerously-skip-permissions"
argv_pair agy --json-schema "$VALID_SCHEMA"
argv_len agy 8   # -p --mode accept-edits --dangerously-skip-permissions --output-format json --json-schema <f>
out_is '{"ok":true}'   # exec 통과 채널로 결과가 stdout에 그대로
stdin_is agy $'x\n'    # 네이티브라 write 분기에서도 주입 금지
# 네이티브 강제 실작동 — 스키마 위반 출력이면 벤더가 거부하고 래퍼는 그 rc를 전달, stdout 오염 없음.
# 플래그를 전달만 하고 벤더가 무시하는(=강제 안 되는) 상태와 구별하는 유일한 핀.
BEHAVIOR=badschema run --schema "$VALID_SCHEMA" codex "x"
rc_is 1
out_is ''
err_has "violates schema"
BEHAVIOR=badschema run --schema "$VALID_SCHEMA" agy "x"
rc_is 1
err_has "violates schema"
BEHAVIOR=badtype run --schema "$VALID_SCHEMA" codex "x"   # required 속성 타입 위반
rc_is 1
out_is ''
err_has "type !="
BEHAVIOR=badtype run --schema "$VALID_SCHEMA" agy "x"     # agy도 동일 강제
rc_is 1
err_has "type !="
BEHAVIOR=badopt run --schema "$VALID_SCHEMA" codex "x"    # optional 속성 타입 위반
rc_is 1
out_is ''
err_has "note type !="
BEHAVIOR=badopt run --schema "$VALID_SCHEMA" agy "x"
rc_is 1
err_has "note type !="
BEHAVIOR=badextra run --schema "$VALID_SCHEMA" codex "x"   # 미선언 키 — additionalProperties 분기(전엔 데드코드)
rc_is 1
out_is ''
err_has additionalProperties
BEHAVIOR=badextra run --schema "$VALID_SCHEMA" agy "x"
rc_is 1
err_has additionalProperties
# 깨진 스키마 — codex·agy는 콘텐츠 사전검증 면제(네이티브)라 벤더가 거부하고 래퍼는 그 rc를 전달.
# 래퍼가 조용히 성공시키거나 스키마를 무시하는 회귀 차단.
printf 'not json' > "$WORK/bad-native.json"
BEHAVIOR=json run --schema "$WORK/bad-native.json" codex "x"
rc_is 2
out_is ''
err_has "invalid schema file"
BEHAVIOR=json run --schema "$WORK/bad-native.json" agy "x"
rc_is 2
err_has "invalid schema file"
ok "codex·agy 스키마 네이티브·모드 직교·강제 실작동"

echo "=== TEST 8: claude --schema = 프롬프트 주입 + 강등(3) ==="
BEHAVIOR=json run --schema "$VALID_SCHEMA" claude "x"
rc_is 3
out_is '{"ok":true}'
err_has DEGRADED
# 주입 계약 실검증 — 벤더 stdin에 원 프롬프트가 먼저, 스키마 본문·출력 지시가 뒤에.
# 이 어서션이 없으면 주입 블록을 통째로 지워도 스위트가 초록이다(라운드 1 실측).
head -1 "$WORK/stdin.claude" | grep -qx 'x' || fail "주입 후에도 원 프롬프트가 첫 줄이어야 함"
grep -Fq '"additionalProperties":false' "$WORK/stdin.claude" || fail "스키마 본문이 벤더 stdin에 주입되지 않음"
grep -Fq '[출력 요구]' "$WORK/stdin.claude" || fail "출력 지시문이 벤더 stdin에 주입되지 않음"
# 캡처 분기 재구조화로 read 제약 플래그를 잃는 회귀 차단 — 스키마 요청이 권한 해제가 되면 안 됨
argv_has claude "--allowedTools=Read,Grep,Glob"
argv_has claude "--disallowedTools=Bash,Edit,Write,NotebookEdit"
argv_not claude "--dangerously-skip-permissions"
argv_len claude 3   # 캡처 분기도 잉여 플래그 금지
calls_is claude 1   # 캡처 경로도 정확히 1회 실행
# "스키마 미강제라 항상 강등" 계약 — 충족 출력만으론 미강제가 증명되지 않는다.
# 스키마 위반 출력도 well-formed면 강등(3)으로 통과해야 한다(래퍼가 강제를 도입하면 rc 1로 갈라짐).
BEHAVIOR=badschema run --schema "$VALID_SCHEMA" claude "x"
rc_is 3
out_is '{"nope":1}'
err_has DEGRADED
# jq 하이재킹 — exported 셸 함수가 검증 결과를 위조하면 비JSON도 rc 3으로 stdout에 방출된다.
# 벤더 CLI와 동일하게 type -P(실행파일)만 인정해야 한다.
rm -f "$WORK"/argv.* "$WORK"/calls.* "$WORK/out" "$WORK/err"
jq() { printf 1; }; export -f jq
BEHAVIOR=notjson run --schema "$VALID_SCHEMA" claude "x"
unset -f jq
rc_is 1
out_is ''
err_has "not valid JSON"
# 역방향 핀 — 캡처 분기가 mode를 무시하고 write를 read로 강등하는 회귀 차단
BEHAVIOR=json run --mode write --schema "$VALID_SCHEMA" claude "x"
rc_is 3
argv_has claude "--dangerously-skip-permissions"
argv_not claude "--allowedTools=Read,Grep,Glob"
argv_len claude 2   # -p --dangerously-skip-permissions
out_is '{"ok":true}'
head -1 "$WORK/stdin.claude" | grep -qx 'x' || fail "write 분기에서도 원 프롬프트가 첫 줄이어야 함"
grep -Fq '"additionalProperties":false' "$WORK/stdin.claude" || fail "write 분기 스키마 주입 누락"
# 캡처 경로의 셸 함수 하이재킹 — exec와 달리 `"${cmd[@]}" &`는 함수를 우선 실행한다.
# cmd가 $agent_bin(절대경로) 대신 $agent(이름)를 쓰는 회귀면 여기서 함수가 대신 돈다.
claude() { echo hijacked; }; export -f claude
BEHAVIOR=json run --schema "$VALID_SCHEMA" claude "x"
unset -f claude
rc_is 3
out_is '{"ok":true}'
calls_is claude 1
grep -q hijacked "$WORK/out" && fail "캡처 경로에서 exported 셸 함수가 실행됨"
ok "claude 스키마 주입·강등·모드 보존"

echo "=== TEST 9: claude --schema 비JSON = 1, stdout 오염 없음 ==="
BEHAVIOR=notjson run --schema "$VALID_SCHEMA" claude "x"
rc_is 1
out_is ''
err_has "not valid JSON"
err_has "plain text"    # 벤더 출력은 stderr로 회수
ok "비JSON 실패 격리"

echo "=== TEST 10: claude --schema 다중 문서 = 1 ==="
BEHAVIOR=multidoc run --schema "$VALID_SCHEMA" claude "x"
rc_is 1
out_is ''
err_has "expected single JSON document"
ok "다중 문서 거부"

echo "=== TEST 11: 캡처 경로 벤더 실패 = rc 보존 + stdout 청결 (claude·codex 양 분기) ==="
BEHAVIOR=fail run --schema "$VALID_SCHEMA" claude "x"
rc_is 42
out_is ''
err_has boom-err
err_has boom-out
BEHAVIOR=fail run codex "x"    # codex 정규화 분기의 실패 계약도 동일해야 함
rc_is 42
out_is ''
err_has boom-err
err_has boom-out
# 벤더가 우연히 exit 3 — degraded 플래그 없인 강등 아님: stdout 오염 금지, rc 그대로
BEHAVIOR=fail3 run --schema "$VALID_SCHEMA" claude "x"
rc_is 3
out_is ''
err_has oops
ok "벤더 rc 보존·출력 stderr 회수 (양 분기 + 우연한 exit 3)"

echo "=== TEST 12: 캡처 경로 공백 출력 = 1 승격 ==="
BEHAVIOR=blank run codex "x"
rc_is 1
out_is ''
err_has "empty/blank output"
# agy --schema는 exec 경로 — 승격 없음이 현행 계약(헤더: 승격은 캡처 한정). 스코프 회귀 감지용 핀
BEHAVIOR=blank run --schema "$VALID_SCHEMA" agy "x"
rc_is 0
calls_is agy 1
out_is '   '   # exec 경로 = 벤더 stdout 네이티브 통과(공백도 그대로)
# emit SIGPIPE(141) 면제 — 조기 닫힘 하류에서도 캡처 성공 rc 유지(파이프 조합성). 1.5MB로 버퍼 초과 강제
rm -f "$WORK"/argv.* "$WORK"/calls.* "$WORK/err"
PATH="$SANDBOX_PATH" FAKE_BEHAVIOR=big bash "$SCRIPT" codex "x" </dev/null > >(head -c 1 >/dev/null) 2>"$WORK/err"
RC=$?
rc_is 0
# non-SIGPIPE 전달실패 승격 — 성공 결과가 하류에 못 실리면(rc≠141) 성공으로 위장하면 안 됨.
# /dev/full은 Linux 전용 — macOS는 SKIP
if [ -w /dev/full ] 2>/dev/null && [ -c /dev/full ]; then
  rm -f "$WORK"/argv.* "$WORK"/calls.* "$WORK/err"
  PATH="$SANDBOX_PATH" FAKE_BEHAVIOR=json bash "$SCRIPT" codex "x" </dev/null >/dev/full 2>"$WORK/err"
  RC=$?
  [[ "$RC" -ne 0 && "$RC" -ne 141 ]] || fail "전달실패(ENOSPC)인데 rc=$RC — 조용한 성공-데이터손실"
else
  echo "SKIP(부분): /dev/full 부재(macOS) — non-SIGPIPE 전달실패 승격 검증 생략"
fi
ok "공백 출력 승격 (캡처 한정 스코프) + emit 전달 계약"

echo "=== TEST 13: exec 경로 벤더 실패 = rc·stdout 네이티브 통과 ==="
BEHAVIOR=fail run claude "x"
rc_is 42
out_is 'boom-out'
err_has boom-err
# agy는 --schema여도 exec 경로 — 실패 격리 없음이 현행 계약(SKILL.md 주의와 일치)
BEHAVIOR=fail run --schema "$VALID_SCHEMA" agy "x"
rc_is 42
out_is 'boom-out'
err_has boom-err
# codex --raw도 exec 경로 — 실패 시 정규화·stderr 회수 없이 원형 통과가 계약
BEHAVIOR=fail run --raw codex "x"
rc_is 42
out_is 'boom-out'
err_has boom-err
ok "exec 경로 네이티브 통과 (agy --schema·codex --raw 포함)"

echo "=== TEST 14: 후행 개행 정규화 — 소스 무관 동일 바이트 ==="
printf 'abc\n\n\n' > "$WORK/p.txt"
BEHAVIOR=echo run --prompt-file "$WORK/p.txt" claude
rc_is 0
stdin_is claude $'abc\n'
BEHAVIOR=echo run claude $'abc\n\n\n'   # positional 소스도 동일 정규화
rc_is 0
stdin_is claude $'abc\n'
ok "prompt-file·positional 개행 정규화"

echo "=== TEST 15: --stdin 경로 ==="
rm -f "$WORK"/argv.* "$WORK"/stdin.* "$WORK/out" "$WORK/err"
printf 'from-stdin' | PATH="$SANDBOX_PATH" FAKE_BEHAVIOR=echo \
  bash "$SCRIPT" --stdin claude >"$WORK/out" 2>"$WORK/err"
RC=$?
rc_is 0
stdin_is claude $'from-stdin\n'
# 후행 개행 정규화가 --stdin 분기에도 적용되는지 — 개행 3개 → 1개
rm -f "$WORK"/argv.* "$WORK"/stdin.* "$WORK"/calls.* "$WORK/out" "$WORK/err"
printf 'abc\n\n\n' | PATH="$SANDBOX_PATH" FAKE_BEHAVIOR=echo \
  bash "$SCRIPT" --stdin claude >"$WORK/out" 2>"$WORK/err"
RC=$?
rc_is 0
stdin_is claude $'abc\n'
# 소스 분기 × 캡처 경로 직교성 — stdin 버퍼링(cat &; wait) 뒤에 벤더 백그라운드 실행(& wait)이
# 이어지는 경로. exec 경로 셀만으론 이 연쇄가 한 번도 실행되지 않는다.
rm -f "$WORK"/argv.* "$WORK"/stdin.* "$WORK"/calls.* "$WORK/out" "$WORK/err"
printf 'abc\n\n\n' | PATH="$SANDBOX_PATH" FAKE_BEHAVIOR=json \
  bash "$SCRIPT" --stdin codex >"$WORK/out" 2>"$WORK/err"
RC=$?
rc_is 0
stdin_is codex $'abc\n'
out_is '{"ok":true}'
err_has SESSION_LOG
calls_is codex 1
rm -f "$WORK"/argv.* "$WORK"/stdin.* "$WORK"/calls.* "$WORK/out" "$WORK/err"
printf 'abc\n\n\n' | PATH="$SANDBOX_PATH" FAKE_BEHAVIOR=json \
  bash "$SCRIPT" --stdin --schema "$VALID_SCHEMA" claude >"$WORK/out" 2>"$WORK/err"
RC=$?
rc_is 3
head -1 "$WORK/stdin.claude" | grep -qx 'abc' || fail "stdin 소스 + 주입 경로에서 원 프롬프트가 첫 줄이어야 함"
out_is '{"ok":true}'
ok "stdin 버퍼링·개행 정규화 + 캡처 경로 직교"

echo "=== TEST 16: NUL 프롬프트 거부 — 벤더 미호출 ==="
printf 'a\0b' > "$WORK/nul.txt"
BEHAVIOR=echo run --prompt-file "$WORK/nul.txt" claude
rc_is 2; no_vendor; err_has NUL
# --stdin 분기의 NUL 검사는 별도 호출(require_no_nul "$stin") — 독립 핀 필요
rm -f "$WORK"/argv.* "$WORK"/stdin.* "$WORK"/calls.* "$WORK/out" "$WORK/err"
printf 'a\0b' | PATH="$SANDBOX_PATH" FAKE_BEHAVIOR=echo \
  bash "$SCRIPT" --stdin claude >"$WORK/out" 2>"$WORK/err"
RC=$?
rc_is 2; no_vendor; err_has NUL
ok "NUL 거부 fail-fast (prompt-file·stdin 양 분기)"

echo "=== TEST 17: 깨진/빈 스키마 사전검증 — 벤더 미호출 ==="
printf 'not json' > "$WORK/bad.json"
BEHAVIOR=echo run --schema "$WORK/bad.json" claude "x"
rc_is 2; no_vendor; err_has "not a single well-formed JSON"
: > "$WORK/empty.json"
BEHAVIOR=echo run --schema "$WORK/empty.json" claude "x"
rc_is 2; no_vendor
err_has "schema file is empty"   # 빈-파일 전용 가드([-s])가 잡았는지 핀 — jq 검사가 대신 잡으면 항상-참
printf 'a\0b' > "$WORK/nul-schema.json"   # NUL 스키마 — $(cat) 무경고 제거로 인한 변조 주입 차단 핀
BEHAVIOR=echo run --schema "$WORK/nul-schema.json" claude "x"
rc_is 2; no_vendor; err_has NUL
printf '{"a":1} {"b":2}' > "$WORK/multi-schema.json"   # 복수 문서 스키마 — 단일 문서 조건 완화 회귀 차단
BEHAVIOR=echo run --schema "$WORK/multi-schema.json" claude "x"
rc_is 2; no_vendor; err_has "not a single well-formed"
# 경로 자체 유효성 — codex는 콘텐츠 사전검증 면제라 이 가드가 유일. 삭제 시 부재 경로가 벤더 argv에 실림
BEHAVIOR=json run --schema "$WORK/no-such.json" codex "x"
rc_is 2; no_vendor; err_has "readable regular file"
BEHAVIOR=json run --schema "$WORK" codex "x"
rc_is 2; no_vendor; err_has "readable regular file"
# agy도 동일 — 콘텐츠 사전검증이 claude 전용이 된 뒤로 이 경로 가드가 agy의 유일한 방어선이다
BEHAVIOR=json run --schema "$WORK/no-such.json" agy "x"
rc_is 2; no_vendor; err_has "readable regular file"
BEHAVIOR=json run --schema "$WORK" agy "x"
rc_is 2; no_vendor; err_has "readable regular file"
# 순서 핀 — 사전검증이 프롬프트 소비(--stdin 버퍼링)보다 앞: 불량 스키마 + 비종료 stdin = 즉시 종료
printf 'not json' > "$WORK/bad-order.json"
rm -f "$WORK"/argv.* "$WORK"/calls.* "$WORK/out" "$WORK/err"
PATH="$SANDBOX_PATH" FAKE_BEHAVIOR=echo \
  bash "$SCRIPT" --schema "$WORK/bad-order.json" --stdin claude < <(sleep 15) >"$WORK/out" 2>"$WORK/err" &
opid=$!
i=0
while kill -0 "$opid" 2>/dev/null; do
  sleep 0.1; i=$((i+1))
  [[ $i -lt 50 ]] || { kill -KILL "$opid" 2>/dev/null; fail "불량 스키마인데 stdin 소비 대기 — 사전검증 순서 회귀"; }
done
wait "$opid" 2>/dev/null; RC=$?
rc_is 2; no_vendor
# agent 검증·벤더 해소도 프롬프트 소비보다 앞 — 오타 + 비종료 --stdin이 무한 대기하면 안 된다
for bad_case in "foo" "claude"; do
  rm -f "$WORK"/argv.* "$WORK"/calls.* "$WORK/out" "$WORK/err"
  if [[ "$bad_case" == foo ]]; then srch="$SANDBOX_PATH"; else srch="$WORK/emptybin2:/usr/bin:/bin"; mkdir -p "$WORK/emptybin2"; fi
  # 두 번째 케이스는 PATH에 claude가 없어야 의미 있음 — 시스템 실물이 있으면 건너뛴다
  if [[ "$bad_case" == claude && ( -e /usr/bin/claude || -e /bin/claude ) ]]; then continue; fi
  PATH="$srch" FAKE_BEHAVIOR=echo \
    bash "$SCRIPT" --stdin "$bad_case" < <(sleep 15) >"$WORK/out" 2>"$WORK/err" &
  apid=$!
  i=0
  while kill -0 "$apid" 2>/dev/null; do
    sleep 0.1; i=$((i+1))
    [[ $i -lt 50 ]] || { kill -KILL "$apid" 2>/dev/null; fail "$bad_case: stdin 소비 대기 — agent 검증 순서 회귀"; }
  done
  wait "$apid" 2>/dev/null; RC=$?
  rc_is 2; no_vendor
done
ok "스키마·agent 사전검증 fail-fast (+순서)"

echo "=== TEST 18: usage 오류 계열 = 2, 전부 벤더 미호출 ==="
# no_vendor 병기 — 검증이 벤더 실행 뒤로 밀리는 회귀(write면 부작용 후 rc 2)를 차단
run foo "x";                            rc_is 2; no_vendor; err_has "unknown agent"
run jq "x";                             rc_is 2; no_vendor; err_has "unknown agent"   # PATH에 존재하는 비벤더 — 열거 삭제 시 unbound cmd(rc≠2)로 구별됨
run --raw --schema "$VALID_SCHEMA" claude "x"; rc_is 2; no_vendor
run claude;                             rc_is 2; no_vendor   # 소스 0개
run --stdin claude "x";                 rc_is 2; no_vendor; err_has "exactly one prompt source"   # 소스 2개 — 사유 핀(완화 시 extra-args가 대신 잡는 위장 차단)
printf 'p' > "$WORK/src2.txt"
run --prompt-file "$WORK/src2.txt" claude "x";      rc_is 2; no_vendor; err_has "exactly one prompt source"   # file+positional
rm -f "$WORK"/argv.* "$WORK"/calls.*
printf 'q' | PATH="$SANDBOX_PATH" FAKE_BEHAVIOR=echo \
  bash "$SCRIPT" --prompt-file "$WORK/src2.txt" --stdin claude >"$WORK/out" 2>"$WORK/err"; RC=$?
rc_is 2; no_vendor; err_has "exactly one prompt source"   # file+stdin
run claude "x" y;                       rc_is 2; no_vendor   # 잉여 인자
run claude "-p";                        rc_is 2; no_vendor   # dash 프롬프트(오배치 플래그 의심)
run --mode chaos claude "x";            rc_is 2; no_vendor
run --effort turbo claude "x";          rc_is 2; no_vendor
run --model --raw claude "x";           rc_is 2; no_vendor   # 플래그 흡수 방지
run --bogus claude "x";                 rc_is 2; no_vendor   # unknown option — passthrough 없음 계약
run --prompt-file "$WORK/no-such-file" claude; rc_is 2; no_vendor; err_has "readable regular file"   # 부재 파일 — 사유 핀(NUL 검사 실패 위장 차단)
run --prompt-file "$WORK" claude;       rc_is 2; no_vendor; err_has "readable regular file"   # 디렉터리 — 정규파일 제약([-f]) 핀
run claude "   ";                       rc_is 2; no_vendor   # 공백 프롬프트
ok "usage 오류 계약 + fail-fast"

echo "=== TEST 19: 벤더 CLI 부재 = 2 (127 아님) ==="
# 부재 재현은 PATH에서 가짜를 빼고 표준 유틸(/usr/bin:/bin)은 남겨야 하므로,
# 그 경로에 실물 claude가 있으면 이 케이스만 재현 불가 — skip (다른 케이스는 $BIN이 가림).
if [[ -e /usr/bin/claude || -e /bin/claude ]]; then
  echo "SKIP: /usr/bin|/bin 에 실물 claude 존재 — 부재 재현 불가"
else
  EMPTY="$WORK/emptybin"; mkdir -p "$EMPTY"; ln -sf "$(command -v jq)" "$EMPTY/jq"
  rm -f "$WORK"/argv.* "$WORK"/calls.* "$WORK/out" "$WORK/err"
  PATH="$EMPTY:/usr/bin:/bin" bash "$SCRIPT" claude "x" >"$WORK/out" 2>"$WORK/err" </dev/null
  RC=$?
  rc_is 2; err_has "vendor CLI not found"
  # type -P 계약 — exported 셸 함수는 벤더로 인정하지 않는다(command -v로 되돌리면 함수가 실행됨)
  rm -f "$WORK"/argv.* "$WORK"/calls.* "$WORK/out" "$WORK/err"
  claude() { echo hijacked; }; export -f claude
  PATH="$EMPTY:/usr/bin:/bin" bash "$SCRIPT" claude "x" >"$WORK/out" 2>"$WORK/err" </dev/null
  RC=$?
  unset -f claude
  rc_is 2; err_has "vendor CLI not found"
  grep -q hijacked "$WORK/out" && fail "exported 셸 함수가 벤더로 실행됨(type -P 계약 위반)"
  ok "CLI 부재 fail-fast + 셸 함수 배제"
fi

echo "=== TEST 19b: jq 부재 + --schema(주입 경로) = 2, 벤더 미호출 ==="
# 사전검사(스크립트의 jq 가드)가 사라지면 벤더 완주(write면 부작용까지) 후에야 실패하는 회귀 차단.
if [[ -e /usr/bin/jq || -e /bin/jq ]]; then
  echo "SKIP: /usr/bin|/bin 에 시스템 jq 존재 — 부재 재현 불가"
else
  NOJQ="$WORK/nojqbin"; mkdir -p "$NOJQ"
  for v in claude codex agy; do ln -sf "$BIN/$v" "$NOJQ/$v"; done
  rm -f "$WORK"/argv.* "$WORK"/calls.* "$WORK/out" "$WORK/err"
  PATH="$NOJQ:/usr/bin:/bin" FAKE_BEHAVIOR=json bash "$SCRIPT" --schema "$VALID_SCHEMA" claude "x" \
    >"$WORK/out" 2>"$WORK/err" </dev/null
  RC=$?
  rc_is 2; no_vendor; err_has "jq required"
  # codex·agy는 jq 면제(네이티브 스키마) — jq 부재 환경에서도 성공해야 함(면제 조건 무조건화 회귀 차단)
  for v in codex agy; do
    rm -f "$WORK"/argv.* "$WORK"/calls.* "$WORK/out" "$WORK/err"
    PATH="$NOJQ:/usr/bin:/bin" FAKE_BEHAVIOR=json bash "$SCRIPT" --schema "$VALID_SCHEMA" "$v" "x" \
      >"$WORK/out" 2>"$WORK/err" </dev/null
    RC=$?
    rc_is 0
    calls_is "$v" 1        # 벤더 미호출 후 rc 0만 내는 위장 차단
    out_is '{"ok":true}'   # 결과가 실제로 stdout에 실렸는지
  done
  ok "jq 부재 fail-fast (claude) + 면제 (codex·agy)"
fi

echo "=== TEST 20: 스킬 패키지 정합 ==="
[[ -f "$SKILL_MD" ]] || fail "SKILL.md 부재"
# frontmatter 구조 검증 — 필드 문자열이 본문에 남아 있어도 구분자 없으면 런타임 등록 불가
[[ "$(head -1 "$SKILL_MD")" == "---" ]] || fail "frontmatter 시작 구분자(1행 ---) 부재"
awk 'NR>1 && /^---$/{f=1; exit} END{exit f?0:1}' "$SKILL_MD" || fail "frontmatter 종료 구분자 부재"
fm() { awk '/^---$/{c++; next} c==1' "$SKILL_MD"; }   # frontmatter 블록만 추출
fm | grep -q '^name: oneshot$' || fail "frontmatter 내 name 불일치"
fm | grep -q '^description: ' || fail "frontmatter 내 description 부재"
# 파서 없이 잡는 보조 핀 — description 값이 YAML flow 컬렉션 시작 문자로 시작하면 파손 가능성
fm | grep -qE '^description: [^\[{]' || fail "frontmatter description 값 형태 이상([/{ 시작)"
fm | grep -qE '^description: .{20,}' || fail "frontmatter description이 실문장 길이 미달(비문자열 값 의심)"
# allowed-tools는 정확 블록 비교 — 항목 소실([]화)·YAML 파손을 grep 존재 검사로는 못 잡음
[[ "$(fm | sed -n '/^allowed-tools:/,$p')" == $'allowed-tools:\n  - Read\n  - Bash(bash:*)' ]] \
  || fail "allowed-tools 블록 불일치(정확 비교): $(fm | sed -n '/^allowed-tools:/,$p' | tr '\n' ' ')"
# YAML 실파싱 — grep으로 못 잡는 파손(description: [broken 등). PyYAML 부재 환경은 SKIP
if python3 -c 'import yaml' 2>/dev/null; then
  fm | python3 -c '
import sys, yaml
d = yaml.safe_load(sys.stdin.read())
assert isinstance(d, dict) and d.get("name") == "oneshot", "frontmatter 구조 이상"
assert isinstance(d.get("description"), str) and len(d["description"]) >= 20, "description 비문자열/미달"
' || fail "frontmatter YAML 파싱 실패"
else
  echo "SKIP(부분): PyYAML 부재 — frontmatter YAML 실파싱 생략"
fi
grep -Fq 'references/oneshot.sh' "$SKILL_MD" || fail "실행 스크립트 경로 참조 부재"
# CWD 비의존 양성 핀 — 부분 문자열 존재만 보면 `bash references/oneshot.sh`(CWD 의존)로 되돌려도 통과한다.
# 금지 대상은 "bash 바로 뒤에 상대 경로가 오는 실행 형태"뿐(산문 속 경로 언급은 허용).
grep -qE 'bash +references/oneshot\.sh' "$SKILL_MD" \
  && fail "SKILL.md에 CWD 의존 호출 예시 존재(디렉터리 플레이스홀더 접두 필요)"
grep -Fq '<이 SKILL.md가 있는 디렉터리>/references/oneshot.sh' "$SKILL_MD" \
  || fail "호출 예시에 스킬 디렉터리 플레이스홀더 접두 부재"
grep -Fq 'tests/recipe/test-oneshot-skill.sh' "$SKILL_MD" || fail "테스트 포인터 부재"
# usage 문법이 3곳(런타임 usage 함수·헤더 주석·SKILL.md)에 손복사돼 있다 — 각각을 따로 뽑아 대조한다.
# 파일 전체 grep이면 헤더가 usage 함수의 표류를 가린다(실측으로 확인된 마스킹).
usage_fn="$(sed -n '/^usage()/,/^}/p' "$SCRIPT" | tr -d '\\')"
header_cm="$(sed -n '1,40p' "$SCRIPT" | grep '^#' | tr -d '\\')"
for pair in "런타임 usage 함수|$usage_fn" "헤더 주석|$header_cm" "SKILL.md|$(cat "$SKILL_MD")"; do
  label="${pair%%|*}"; body="${pair#*|}"
  grep -q '\["<prompt>"\]' <<<"$body" || fail "$label: positional 프롬프트 선택 표기 부재"
  grep -qE '(<agent>|agy>) +"<prompt>"' <<<"$body" && fail "$label: positional 프롬프트를 필수로 표기"
done
# 벤더 중립 규범(plugins/recipe/README.md) — Claude 전용 경로 변수 금지 (codex 런타임에도 배포됨)
grep -Fq 'CLAUDE_PLUGIN_ROOT' "$SKILL_MD" && fail "벤더 전용 경로 변수(CLAUDE_PLUGIN_ROOT) 잔존"
ok "패키지 정합"

echo "=== TEST 21: TERM 시그널 — 자식 종료·임시파일 정리 ==="
# pgrep 기능 프로브 — 존재해도 프로세스 열거가 막힌 환경(샌드박스 macOS)이면 래퍼는 degrade가
# 계약이므로 어서션도 SKIP해야 함. 존재 검사만으로는 이 환경에서 거짓 실패.
# 메인 셸에서 프로브 — bash 3.2(macOS 기본)엔 BASHPID가 없어 서브셸+set -u 조합이 즉사한다(실측).
# 프로브는 재시도한다 — 단발 호출은 자식이 아직 프로세스 테이블에 안 잡힌 순간 false negative를
# 내고, 그 경우 고장 난 트랩도 자식 검증을 SKIP해 통과한다(검증 우회).
pgrep_ok=0
if command -v pgrep >/dev/null 2>&1; then
  sleep 3 & _probe=$!
  for _i in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -P $$ >/dev/null 2>&1 && { pgrep_ok=1; break; }
    sleep 0.1
  done
  kill "$_probe" 2>/dev/null; wait "$_probe" 2>/dev/null || :
fi
# blocking 가짜(pid 기록 후 sleep 15) + TMPDIR 격리로 래퍼 mktemp 산출물 관찰.
# 캡처 경로(--schema)라 래퍼가 out 임시파일을 만들고 벤더를 백그라운드로 띄운 상태에서 TERM.
SIGTMP="$WORK/sigtmp"; mkdir -p "$SIGTMP"
# 정상 종료 경로의 EXIT 트랩 정리 — 시그널 케이스는 on_signal이 cleanup을 직접 부르므로
# `trap cleanup EXIT`를 지워도 잡히지 않는다. 캡처 경로가 만드는 out 임시파일이 대상.
# macOS mktemp는 TMPDIR을 무시하므로 PATH 선두에 mktemp 스텁을 세워 산출 위치를 강제한다.
LEAKDIR="$WORK/leak"; mkdir -p "$LEAKDIR"
cat > "$BIN/mktemp" <<EOF
#!/usr/bin/env bash
# 관측 가능한 위치에만 만든다 — -d 도 지원(래퍼는 현재 무인자만 쓰지만 계약 변화에 대비)
if [[ "\${1-}" == -d ]]; then d="$LEAKDIR/d.\$\$.\$RANDOM"; mkdir -p "\$d"; echo "\$d"
else f="$LEAKDIR/f.\$\$.\$RANDOM"; : > "\$f"; echo "\$f"; fi
EOF
chmod +x "$BIN/mktemp" || fail "mktemp 스텁 생성 실패"
rm -f "$LEAKDIR"/*
rm -f "$WORK"/argv.* "$WORK"/calls.* "$WORK/out" "$WORK/err"
PATH="$SANDBOX_PATH" FAKE_BEHAVIOR=json \
  bash "$SCRIPT" --schema "$VALID_SCHEMA" codex "x" >"$WORK/out" 2>"$WORK/err"
RC=$?
rc_is 0
n_left=$(find "$LEAKDIR" -mindepth 1 | wc -l)
[[ "$((n_left))" -eq 0 ]] || fail "정상 종료 후 임시파일 잔존(EXIT 트랩 회귀): $(find "$LEAKDIR" -mindepth 1 | tr '\n' ' ')"
# --stdin × exec 경로 — exec은 셸을 교체해 EXIT 트랩이 실행되지 않으므로 stin 정리는
# 명시 rm에만 의존한다. 캡처 경로 케이스로는 이 누수가 잡히지 않는다.
rm -f "$LEAKDIR"/* "$WORK"/argv.* "$WORK"/calls.* "$WORK/out" "$WORK/err"
printf 'abc' | PATH="$SANDBOX_PATH" FAKE_BEHAVIOR=echo \
  bash "$SCRIPT" --stdin claude >"$WORK/out" 2>"$WORK/err"
RC=$?
rm -f "$BIN/mktemp"   # 스텁은 이 케이스들 전용 — 이후 케이스는 실물 mktemp를 쓴다
rc_is 0
n_left=$(find "$LEAKDIR" -mindepth 1 | wc -l)
[[ "$((n_left))" -eq 0 ]] || fail "--stdin exec 경로 임시파일 잔존(stin 정리 회귀): $(find "$LEAKDIR" -mindepth 1 | tr '\n' ' ')"
rm -f "$WORK"/argv.* "$WORK"/stdin.* "$WORK"/calls.* "$WORK/pid.claude" "$WORK/out" "$WORK/err"
TMPDIR="$SIGTMP" PATH="$SANDBOX_PATH" FAKE_BEHAVIOR=block \
  bash "$SCRIPT" --schema "$VALID_SCHEMA" claude "x" >"$WORK/out" 2>"$WORK/err" </dev/null &
wpid=$!
i=0
until [[ -s "$WORK/pid.claude" ]]; do   # 벤더 기동 대기(최대 10초)
  sleep 0.1; i=$((i+1))
  [[ $i -lt 100 ]] || { kill -KILL "$wpid" 2>/dev/null; fail "blocking 가짜 기동 실패"; }
done
vpid="$(cat "$WORK/pid.claude")"
kill -TERM "$wpid"
wait "$wpid" 2>/dev/null; wrc=$?
[[ "$wrc" -eq 143 ]] || fail "TERM 재전파 identity 위반 — 기대 143(SIGTERM), 실제 $wrc"
if [[ "$pgrep_ok" -eq 1 ]]; then   # 래퍼의 자식 kill은 pgrep 기반 — 부재/불능 시 degrade가 계약이라 어서션도 조건부
  i=0
  while kill -0 "$vpid" 2>/dev/null; do   # kill_tree 전파로 벤더 자식 소멸(최대 5초)
    sleep 0.1; i=$((i+1))
    [[ $i -lt 50 ]] || { kill -KILL "$vpid" 2>/dev/null; fail "TERM 후 벤더 자식 생존(kill_tree 미전파)"; }
  done
else
  kill -KILL "$vpid" 2>/dev/null; echo "SKIP(부분): pgrep 부재/불능 — 자식 소멸 검증 생략(래퍼 degrade 계약)"
fi
# --stdin 버퍼링 단계 TERM — 벤더 기동 전. 전경 cat 회귀(bash가 전경 외부명령 중 trap 보류 → EOF까지 hang) 차단
rm -f "$WORK"/argv.* "$WORK"/calls.*
TMPDIR="$SIGTMP" PATH="$SANDBOX_PATH" FAKE_BEHAVIOR=echo \
  bash "$SCRIPT" --stdin claude < <(sleep 15) >"$WORK/out2" 2>"$WORK/err2" &
bpid=$!
# 고정 sleep 대신 버퍼링 단계 진입을 관찰 — 래퍼가 stdin cat 자식을 띄울 때까지 폴링(전경/백그라운드 무관 자식 존재).
# pgrep 부재/불능(procps 없는 최소 Linux, 열거 제한 샌드박스)이면 고정 대기로 폴백 — 래퍼도 동일 degrade 허용
if [[ "$pgrep_ok" -eq 1 ]]; then
  i=0
  until pgrep -P "$bpid" >/dev/null 2>&1; do
    sleep 0.1; i=$((i+1))
    [[ $i -lt 50 ]] || { kill -KILL "$bpid" 2>/dev/null; fail "버퍼링 단계 진입 관찰 실패"; }
  done
  sleep 0.1   # cat 기동 여유
else
  sleep 0.5
fi
kill -TERM "$bpid"
i=0
while kill -0 "$bpid" 2>/dev/null; do
  sleep 0.1; i=$((i+1))
  [[ $i -lt 50 ]] || { kill -KILL "$bpid" 2>/dev/null; fail "버퍼링 중 TERM에 미종료(전경 cat 회귀)"; }
done
wait "$bpid" 2>/dev/null; brc=$?
[[ "$brc" -eq 143 ]] || fail "버퍼링 TERM 재전파 identity 위반 — 기대 143, 실제 $brc"
no_vendor

# INT·HUP 트랩 배선 — 세 시그널이 각자 재전파되는지. 배선이 뒤바뀌면(예: INT 트랩이 TERM 재전파)
# 호출자 셸이 Ctrl-C에 SIGTERM을 받는다. 종료 status로 identity를 못박는다(130=INT, 129=HUP).
# 비대화형 셸의 백그라운드 job은 SIGINT를 무시 처분으로 상속하므로(실사용 전경 Ctrl-C엔 없는 조건),
# perl로 처분을 DEFAULT로 되돌린 뒤 exec — 이걸 안 하면 래퍼의 `trap - INT; kill -INT $$`가 무시된다.
sigrunner=(perl -e '$SIG{INT}="DEFAULT"; $SIG{HUP}="DEFAULT"; exec @ARGV')
command -v perl >/dev/null 2>&1 || sigrunner=()
for sig_pair in "INT 130" "HUP 129"; do
  set -- $sig_pair
  signame="$1"; expect="$2"
  if [[ ${#sigrunner[@]} -eq 0 ]]; then
    echo "SKIP(부분): perl 부재 — $signame 처분 복원 불가"; continue
  fi
  rm -f "$WORK"/argv.* "$WORK"/calls.* "$WORK/pid.claude"
  TMPDIR="$SIGTMP" PATH="$SANDBOX_PATH" FAKE_BEHAVIOR=block \
    "${sigrunner[@]}" bash "$SCRIPT" --schema "$VALID_SCHEMA" claude "x" >"$WORK/out3" 2>"$WORK/err3" &
  spid=$!
  i=0
  until [[ -s "$WORK/pid.claude" ]]; do
    sleep 0.1; i=$((i+1))
    [[ $i -lt 100 ]] || { kill -KILL "$spid" 2>/dev/null; fail "$signame 케이스: 벤더 기동 실패"; }
  done
  svpid="$(cat "$WORK/pid.claude")"
  kill -"$signame" "$spid"
  wait "$spid" 2>/dev/null; src2=$?
  [[ "$src2" -eq "$expect" ]] || fail "$signame 재전파 identity 위반 — 기대 $expect, 실제 $src2"
  # identity만으론 트랩 유무를 구별 못한다 — 기본 동작도 같은 status를 낸다(HUP=129).
  # 트랩이 실제로 걸렸는지는 자식 정리로만 확인된다(트랩 없으면 벤더 자식이 고아로 생존).
  if [[ "$pgrep_ok" -eq 1 ]]; then
    i=0
    while kill -0 "$svpid" 2>/dev/null; do
      sleep 0.1; i=$((i+1))
      [[ $i -lt 30 ]] || { kill -KILL "$svpid" 2>/dev/null; fail "$signame 후 벤더 자식 생존 — 트랩 미배선"; }
    done
  fi
  kill -KILL "$svpid" 2>/dev/null || :
done

# 임시파일 정리 검증은 mktemp가 TMPDIR을 존중하는 플랫폼에서만 가능 — macOS mktemp(무인자)는
# TMPDIR을 무시하고 /var/folders 에 생성하므로 SIGTMP 검사가 항상-참이 된다(실측). 프로브로 구분.
probe="$(TMPDIR="$SIGTMP" mktemp)"
case "$probe" in
  "$SIGTMP"/*)
    rm -f "$probe"
    leftover=$(find "$SIGTMP" -type f | wc -l)
    [[ "$((leftover))" -eq 0 ]] || fail "TERM 후 임시파일 잔존: $(find "$SIGTMP" -type f | tr '\n' ' ')"
    ok "TERM 전파·자식 종료·임시파일 정리" ;;
  *)
    rm -f "$probe"
    echo "SKIP(부분): mktemp가 TMPDIR 미존중(macOS) — 시그널 시 임시파일 정리는 이 플랫폼에서 검증 불가"
    ok "TERM 전파·자식 종료 (정리 검증은 TMPDIR 존중 플랫폼 전용)" ;;
esac

echo ""
echo "=== 모든 oneshot 스킬 테스트 통과 ==="
