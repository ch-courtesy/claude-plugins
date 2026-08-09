#!/usr/bin/env bash
# recipe oneshot 스킬의 런타임 계약 검증
#
# 이 스킬은 다른 스킬과 달리 실행되는 스크립트다 — 문서 문구뿐 아니라 동작
# 불변식을 못박는다. 계약이 주석에만 있으면 구조를 바꿀 때마다(파일↔변수↔파이프)
# 같은 결함이 다른 자리에서 재발하기 때문이다.
#
# 에이전트는 가짜 CLI 로 대역한다 — 실제 모델을 호출하지 않아 빠르고 결정적이다.

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_DIR="$REPO_ROOT/plugins/recipe/skills/oneshot"
SCRIPT="$SKILL_DIR/references/oneshot.sh"
SKILL_MD="$SKILL_DIR/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN"
# 벤더 CLI 는 이 BIN 안의 가짜만 보이게 한다 — 시스템에 실제 설치된 것(homebrew·
# ~/.local)이 잡히면 "CLI 부재" 경로를 재현할 수 없다. 표준 유틸리티는 필요하므로
# /usr/bin·/bin 만 덧붙인다(거기에는 claude·codex·agy 가 없음을 전제).
for d in /usr/bin /bin; do
  for v in claude codex agy; do
    [[ -e "$d/$v" ]] && fail "테스트 전제 위반: $d/$v 가 존재해 가짜 CLI 로 대체할 수 없음"
  done
done
ln -sf "$(command -v jq)" "$BIN/jq"
SANDBOX_PATH="$BIN:/usr/bin:/bin"

# 가짜 벤더 CLI — 프롬프트를 어디로 받았는지, 얼마나 받았는지 보고한다.
# 분기는 실물 계약(agy=argv, 나머지=stdin)과 1:1 로 자기 이름을 본다. 프롬프트 모양
# (`--` 로 시작하는지)으로 분기하면 옵션형 프롬프트에서 실물과 다르게 동작해 가짜로
# 통과시킨다 — 실제로 그래서 agy 의 옵션 오인식을 이 테스트가 못 잡았다.
make_fake() {   # $1=이름  $2=동작(echo|size|big|fail)
  cat > "$BIN/$1" <<EOF
#!/usr/bin/env bash
mode=$2
# 받은 argv 를 그대로 남긴다. 이 래퍼의 존재 이유가 벤더별 호출 관례 흡수인데,
# 가짜가 argv 를 무시하면 그 관례를 검사하는 곳이 어디에도 없다 — 플래그가 빠지거나
# 오타여도 스위트가 초록이다.
printf '%s\n' "\$@" > "$WORK/argv.\$(basename "\$0")"
if [[ "\$(basename "\$0")" == agy ]]; then
  prompt=""
  while (( \$# )); do [[ "\$1" == "--print" ]] && { prompt="\${2:-}"; break; }; shift; done
else
  prompt="\$(cat)"
fi
case "\$mode" in
  echo)  printf '%s' "\$prompt" ;;
  size)  printf 'BYTES=%s' "\${#prompt}" ;;
  big)   head -c 1500000 /dev/zero | tr '\\0' 'y' ;;
  fail)  printf 'boom' >&2; exit 42 ;;
esac
EOF
  chmod +x "$BIN/$1"
}

# 바이트 무결성 전용 가짜 — 받은 stdin 을 변형 없이 16진수로 보고한다.
# 셸 변수를 거치면 후행 개행·NUL 이 사라지므로 od 로 원본을 되돌려 판정한다.
make_hexdump() {   # $1=이름
  cat > "$BIN/$1" <<'EOF'
#!/usr/bin/env bash
od -An -tx1 -v | tr -d ' \n'
EOF
  chmod +x "$BIN/$1"
}

# 케이스마다 시간 상한을 건다. 상한이 없으면 멈추는 회귀(writer 없는 FIFO 를 지침
# 파일로 여는 등)가 "실패" 가 아니라 "무한 대기" 로 나타나 판정 자체가 일어나지 않는다.
# macOS 에 timeout(1) 이 없어 직접 센다 — 폴링이라 정상 케이스마다 최대 POLL 만큼
# 늦어지지만(23케이스 × 0.1초 ≈ 3초), 백그라운드 킬러에 의존하지 않아 상한을 거는
# 코드가 상한 없는 것에 기대지 않는다.
RUN_TIMEOUT=20
POLL=0.1

# 산출물 경로. stdout·stderr 를 **파일로** 남긴다 — 변수로 받으면 명령 치환이 후행
# 개행을 전부 잘라, 개행·바이트에 관한 단언이 구조적으로 항상 참이 된다(피검체에서
# 고친 바로 그 결함이 하네스에 남아 있었다). 바이트를 보는 단언은 $RUN_OUT 을 본다.
RUN_OUT=""; RUN_ERR=""

run() {  # run [-d <cwd>] <입력 JSON>. stdout 은 OUT(편의용 문자열)·$RUN_OUT(원본 파일).
  local dir="" tmp="" input pid ticks=0
  while :; do
    case "${1:-}" in
      -d) dir="$2"; shift 2 ;;
      -t) tmp="$2"; shift 2 ;;   # TMPDIR 주입 — 준비 단계 실패를 재현한다
      *)  break ;;
    esac
  done
  input="$1"
  local max=$(( RUN_TIMEOUT * 10 ))
  RUN_OUT="$WORK/run.out"; RUN_ERR="$WORK/run.err"
  # 입력·출력을 파이프가 아니라 파일로 둔다 — 파이프라인이면 $! 가 끝 요소만 가리켜
  # 앞쪽 프로세스가 남고, 죽일 때 상속된 파이프를 붙잡아 다음 케이스를 막는다.
  printf '%s' "$input" > "$WORK/run.in"
  ( [[ -z "$dir" ]] || cd "$dir"
    [[ -z "$tmp" ]] || export TMPDIR="$tmp"
    PATH="$SANDBOX_PATH" exec bash "$SCRIPT" ) < "$WORK/run.in" > "$RUN_OUT" 2>"$RUN_ERR" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && (( ticks < max )); do
    sleep "$POLL"; ticks=$(( ticks + 1 ))
  done
  if kill -0 "$pid" 2>/dev/null; then
    pkill -P "$pid" 2>/dev/null; kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    fail "케이스가 ${RUN_TIMEOUT}초 안에 끝나지 않음 (입력: ${input:0:40})"
  fi
  wait "$pid"; RUN_CODE=$?
  OUT="$(cat "$RUN_OUT")"
}

echo "=== TEST 1: 스킬 패키지 ==="
[[ -f "$SCRIPT" ]] || fail "스크립트 없음: $SCRIPT"
bash -n "$SCRIPT" || fail "스크립트 문법 오류"
grep -qE '^name: oneshot' "$SKILL_MD" || fail "SKILL.md name 누락"
# 계약 본문은 스크립트 헤더 한 곳에만 둔다 — SKILL.md 는 그리로 보내기만 한다.
# 주석 줄에 앵커한다. 앵커가 없으면 코드의 exit_code 를 맞혀 헤더를 통째로 지워도 통과한다.
grep -q '단일 출처' "$SKILL_MD" || fail "SKILL.md 에 계약 단일 출처 지시 없음"
grep -q '^#.*exit_code' "$SCRIPT" || fail "스크립트 헤더가 exit_code 계약을 설명하지 않음"
ok "패키지 구조와 문법"

echo ""
echo "=== TEST 2: stdout 은 언제나 JSON 객체 하나 ==="
# 성공·도구 오류·에이전트 실패 어느 경우든 호출자의 파서가 깨지지 않아야 한다.
make_fake claude echo
for input in \
  '{"prompt":"hello"}' \
  'not json' \
  '{"prompt":"x","vendor":"nope"}' \
  '{"prompt":"x","cwd":"/no/such/dir"}' \
  '{"prompt":"x","system_prompt_file":"/no/such/file"}' \
  '{"a":1}{"a":2}'
do
  run "$input"
  # -s 로 문서 수까지 본다 — 문서별 검사는 이어붙은 객체 두 개도 통과시킨다.
  jq -es 'length == 1 and (.[0] | type == "object")' >/dev/null 2>&1 <<< "$OUT" \
    || fail "stdout 이 JSON 객체 하나가 아님 (입력: ${input:0:30})"
  jq -e 'has("exit_code") and has("output")' >/dev/null <<< "$OUT" \
    || fail "필수 필드 누락 (입력: ${input:0:30})"
  # 줄 단위로 읽는 호출자를 위해 형태도 한 줄로 고정한다(성공·오류 경로 동일).
  # 변수가 아니라 파일을 센다 — 변수는 후행 개행이 이미 잘려 항상 1 이 나온다.
  [[ "$(wc -l < "$RUN_OUT")" -eq 1 ]] \
    || fail "출력이 한 줄이 아님 (입력: ${input:0:30})"
  # 도구 층 메시지가 stderr 로 새면 호출자가 "에이전트가 말한 것" 으로 적재한다.
  [[ ! -s "$RUN_ERR" ]] \
    || fail "도구 오류 경로에서 stderr 오염 (입력: ${input:0:30}): $(head -c 80 "$RUN_ERR")"
done
ok "모든 경로에서 한 줄짜리 JSON 객체 하나 · stderr 순수"

echo ""
echo "=== TEST 3: 오류 채널 분리 ==="
# 도구 오류 = 프로세스 1 + error 필드. 에이전트 실패 = 프로세스 0 + exit_code 필드.
run '{"prompt":"x","vendor":"nope"}'
[[ $RUN_CODE -eq 1 ]] || fail "도구 오류인데 프로세스 코드가 $RUN_CODE"
jq -e 'has("error")' >/dev/null <<< "$OUT" || fail "도구 오류에 error 필드 없음"

make_fake claude fail
run '{"prompt":"x"}'
[[ $RUN_CODE -eq 0 ]] || fail "에이전트 실패인데 프로세스 코드가 $RUN_CODE (0 이어야 호출자가 파싱한다)"
# 에이전트 stderr 는 가로채지 않고 통과시킨다는 계약 — 단언이 없으면 벤더 호출에
# 2>/dev/null 을 붙이는 리팩터로 계약이 깨져도 전 그룹이 초록이다.
grep -q boom "$RUN_ERR" || fail "에이전트 stderr 가 통과되지 않음"
grep -q "$SCRIPT" "$RUN_ERR" && fail "에이전트 stderr 에 도구 층 문구가 섞임: $(head -c 80 "$RUN_ERR")"
[[ "$(jq -r .exit_code <<< "$OUT")" == "42" ]] || fail "에이전트 종료 코드가 exit_code 로 전달되지 않음"
jq -e 'has("error") | not' >/dev/null <<< "$OUT" || fail "에이전트 실패에 error 필드가 붙음 (도구 오류와 혼동)"
ok "도구 오류와 에이전트 실패가 구분됨"

echo ""
echo "=== TEST 4: 오류 원인별 메시지 ==="
declare -a CASES=(
  'not json|JSON'
  '{"prompt":"x","vendor":"nope"}|vendor'
  '{"prompt":"x","cwd":"/no/such/dir"}|cwd'
  '{"prompt":"x","system_prompt_file":"/no/such/file"}|system_prompt_file'
)
for c in "${CASES[@]}"; do
  run "${c%%|*}"
  jq -r .error <<< "$OUT" | grep -qF "${c##*|}" \
    || fail "원인이 메시지에 안 드러남: ${c%%|*} → $(jq -r .error <<< "$OUT")"
done
# 지원하는 벤더인데 CLI 가 없는 경우만 설치 문제로 보고해야 한다 — 양방향으로 본다.
# 있을 때도 부재로 보고하면 벤더 검사 순서가 뒤집힌 것이다.
make_fake codex echo
run '{"prompt":"CODEXOK","vendor":"codex"}'
jq -e 'has("error") | not' >/dev/null <<< "$OUT" || fail "설치된 codex 가 오류로 보고됨: $(jq -r .error <<< "$OUT")"
rm -f "$BIN/codex"
run '{"prompt":"x","vendor":"codex"}'
jq -r .error <<< "$OUT" | grep -q '찾을 수 없음' || fail "CLI 부재가 설치 문제로 보고되지 않음"
ok "원인별 고유 메시지"

echo ""
echo "=== TEST 5: 임의 크기 데이터가 경계를 통과한다 ==="
# 재발이 가장 잦았던 클래스 — 프롬프트·지침·출력 어느 쪽도 argv 한계에 걸리면 안 된다.
BIG="$WORK/big.txt"; head -c 1500000 /dev/zero | tr '\0' 'x' > "$BIG"

make_fake claude size
run "$(jq -nc --rawfile p "$BIG" '{prompt:$p}')"
[[ "$(jq -r .output <<< "$OUT")" == "BYTES=1500000" ]] \
  || fail "큰 프롬프트가 전달되지 않음: $(jq -r .output <<< "$OUT" | head -c 60)"

run "$(jq -nc --rawfile p "$BIG" --arg f "$BIG" '{prompt:"tail", system_prompt_file:$f}')"
[[ "$(jq -r .output <<< "$OUT")" == "BYTES=1500006" ]] \
  || fail "큰 지침이 병합되지 않음: $(jq -r .output <<< "$OUT" | head -c 60)"

# agy 는 stdin 을 받지 않아 프롬프트가 구조적으로 argv 다 — 실행 자체가 불가능한
# 크기면 도구 오류로 보고해야 한다. 126/127 을 그대로 내보내면 호출자가 "에이전트
# 실패"로 읽고 성공 가능성 없는 재시도를 돈다.
make_fake agy echo
run "$(jq -nc --rawfile p "$BIG" '{prompt:$p, vendor:"agy"}')"
jq -e 'has("error")' >/dev/null <<< "$OUT" \
  || fail "agy 크기 초과가 도구 오류로 보고되지 않음 (exit_code=$(jq -r .exit_code <<< "$OUT"))"
[[ $RUN_CODE -eq 1 ]] || fail "agy 크기 초과인데 프로세스 코드가 $RUN_CODE"

make_fake claude big
run '{"prompt":"x"}'
[[ "$(jq -r '.output | length' <<< "$OUT")" == "1500000" ]] \
  || fail "큰 출력이 손실됨: 길이 $(jq -r '.output | length' <<< "$OUT")"
[[ $RUN_CODE -eq 0 ]] || fail "큰 출력에서 프로세스 코드가 $RUN_CODE"
ok "1.5MB 프롬프트·지침·출력 무손실"

echo ""
echo "=== TEST 6: output 은 마지막 줄 판정이 성립한다 ==="
cat > "$BIN/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf '결과\n<<DONE>>  \r\n\r\n'
EOF
chmod +x "$BIN/claude"
run '{"prompt":"x"}'
LAST="$(jq -r '.output | split("\n") | last' <<< "$OUT")"
[[ "$LAST" == "<<DONE>>" ]] || fail "후행 공백·CR·개행이 남아 마지막 줄이 '$LAST'"
ok "후행 공백·CR·개행 제거"

echo ""
echo "=== TEST 7: 지시한 대로 실행한다 ==="
# cwd 로 실제 이동했는지 — 격리를 믿는 호출자의 최소 전제.
SUB="$WORK/sub"; mkdir -p "$SUB"
cat > "$BIN/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
pwd -P
EOF
chmod +x "$BIN/claude"
run "$(jq -nc --arg c "$SUB" '{prompt:"x", cwd:$c}')"
[[ "$(jq -r .output <<< "$OUT")" == "$(cd "$SUB" && pwd -P)" ]] \
  || fail "cwd 로 이동하지 않음: $(jq -r .output <<< "$OUT")"

# 벤더 규약 — claude·codex 는 stdin, agy 는 --print 인자로 받는다.
make_fake agy echo
run '{"prompt":"AGYPROMPT","vendor":"agy"}'
[[ "$(jq -r .output <<< "$OUT")" == "AGYPROMPT" ]] || fail "agy 프롬프트 전달 실패"
run '{"prompt":"ALIAS","vendor":"antigravity"}'
[[ "$(jq -r .output <<< "$OUT")" == "ALIAS" ]] || fail "antigravity 별칭 미지원"

# 벤더별 argv 를 등식으로 고정한다. 이 플래그들은 실행 반경을 정의하는 값이라
# "있다/없다" 가 아니라 "정확히 이것" 이어야 한다 — `--dangerously-skip-permissions`
# 가 빠지면 에이전트가 권한 프롬프트에서 영원히 멈추고, `--sandbox` 오타면 codex 의
# 쓰기 반경이 바뀐다. agy 는 `--print` 다음 인자가 프롬프트라 순서까지 의미가 있다.
argv_is() {  # $1=벤더  나머지=기대 argv
  local v="$1"; shift
  diff <(printf '%s\n' "$@") "$WORK/argv.$v" >/dev/null \
    || fail "$v 호출 규약이 바뀜: $(tr '\n' ' ' < "$WORK/argv.$v")"
}
make_fake claude echo; make_fake codex echo; make_fake agy echo
run '{"prompt":"x"}'
argv_is claude --print --no-session-persistence --dangerously-skip-permissions --add-dir .
run '{"prompt":"x","vendor":"codex"}'
argv_is codex exec --ephemeral --sandbox workspace-write -
run '{"prompt":"x","vendor":"agy"}'
argv_is agy --dangerously-skip-permissions --add-dir . --print x

# 지침 파일은 cwd 이동 **전** 기준으로 해석한다 — 순서가 뒤집히면 같은 상대 경로가
# 작업 디렉토리 안의 동명 파일을 가리켜 엉뚱한 지침으로 조용히 바뀐다.
make_fake claude echo
printf 'ROOTGUIDE' > "$WORK/guide.txt"
printf 'WRONGGUIDE' > "$SUB/guide.txt"
run -d "$WORK" '{"prompt":"tail","cwd":"sub","system_prompt_file":"guide.txt"}'
[[ "$(jq -r .output <<< "$OUT")" == ROOTGUIDE* ]] \
  || fail "지침이 cwd 이동 후 기준으로 해석됨: $(jq -r .output <<< "$OUT" | head -c 40)"
ok "cwd 이동·벤더별 프롬프트 전달·지침 경로 해석 순서"

echo ""
echo "=== TEST 8: 적대적 모양의 입력값 ==="
# 입력은 호출자가 만든 임의 문자열이다 — 셸 구문의 암묵 의미(옵션 해석, 문자 vs
# 바이트)에 그대로 넘기면 계약이 가정한 것과 다른 일이 조용히 일어난다.
make_fake claude echo

# 옵션처럼 생긴 cwd 는 cd 의 옵션으로 먹혀 $HOME 으로 이동한다 — 격리 붕괴가
# 성공으로 보고된다.
run '{"prompt":"x","cwd":"-P"}'
jq -e 'has("error")' >/dev/null <<< "$OUT" \
  || fail "옵션형 cwd 가 오류로 보고되지 않음 (output=$(jq -r .output <<< "$OUT" | head -c 40))"

# 옵션처럼 생긴 지침 경로도 마찬가지 — cat - 은 EOF 인 stdin 을 읽어 "빈 지침"으로
# 성공해 지침 없는 실행과 구분되지 않는다.
run '{"prompt":"x","system_prompt_file":"-"}'
jq -e 'has("error")' >/dev/null <<< "$OUT" \
  || fail "옵션형 system_prompt_file 이 오류로 보고되지 않음"

# agy 크기 가드는 바이트로 재야 한다. 한글은 문자 하나가 3바이트라 문자 수로 재면
# 실제 argv 한계를 세 배 넘겨도 가드를 통과하고, exec 실패(126)가 에이전트 실패로
# 위장된다. (Linux 는 한계가 더 낮아 문자 수로도 걸리므로 이 케이스의 회귀 탐지력은
# macOS 기준이다.)
make_fake agy echo
KBIG="$WORK/kbig.txt"; : > "$KBIG"
for _ in $(seq 400); do printf '가나다라마바사아자차카타파하%.0s' $(seq 71) >> "$KBIG"; done
# 약 39.8만 자 = 119만 바이트. 문자 수로 재면 한계 아래라 통과하지만 바이트로는 초과다
# — 이 간극이 정확히 회귀 탐지 지점이다.
run "$(jq -nc --rawfile p "$KBIG" '{prompt:$p, vendor:"agy"}')"
jq -e 'has("error")' >/dev/null <<< "$OUT" \
  || fail "멀티바이트 프롬프트가 agy 크기 가드를 통과함 (exit_code=$(jq -r .exit_code <<< "$OUT"))"

# 실물 agy 는 전역 플래그(--version·--help)를 위치와 무관하게 선스캔한다 — `--` 를
# 붙이거나 순서를 바꿔도 프롬프트 자리의 그 문자열이 플래그로 가로챈다(실측). 그러면
# 에이전트가 뜬 적 없는데 {"exit_code":0} 성공으로 보고된다. argv 로는 못 막으므로
# 도구가 먼저 거부한다.
run '{"prompt":"--version","vendor":"agy"}'
jq -e 'has("error")' >/dev/null <<< "$OUT" \
  || fail "agy 옵션형 프롬프트가 거부되지 않음 (output=$(jq -r .output <<< "$OUT" | head -c 40))"

# 제어문자가 든 경로는 명령 치환이 후행 개행을 잘라 다른 경로로 정규화한다 —
# 요청과 다른 디렉토리에서 무인 에이전트가 뜨고 성공으로 보고된다.
run "$(jq -nc '{prompt:"x", cwd:"/tmp/\n"}')"
jq -e 'has("error")' >/dev/null <<< "$OUT" \
  || fail "제어문자가 든 cwd 가 거부되지 않음"

# 문서화된 타입을 강제하지 않으면 {"prompt":7} 이 "7" 로, {"vendor":false} 가 기본
# 벤더로 조용히 흘러 "전제가 깨지면 중단한다" 는 계약이 거짓이 된다.
for bad in '{"prompt":7}' '{"vendor":false,"prompt":"x"}' '{"prompt":"x","cwd":3}'; do
  run "$bad"
  jq -e 'has("error")' >/dev/null <<< "$OUT" \
    || fail "타입 위반이 통과함: $bad"
done

# FIFO·장치 파일은 -r 과 ! -d 를 통과한 뒤 cat 이 끝나지 않아 프로세스가 영원히 멈춘다.
FIFO="$WORK/fifo"; mkfifo "$FIFO"
run "$(jq -nc --arg f "$FIFO" '{prompt:"x", system_prompt_file:$f}')"
jq -e 'has("error")' >/dev/null <<< "$OUT" \
  || fail "FIFO 가 지침 파일로 통과함 (정규 파일 검사 부재)"
ok "옵션형 경로·멀티바이트 크기 가드·타입·비정규 파일"

echo ""
echo "=== TEST 9: 프롬프트 바이트열이 변형 없이 벤더에 도달한다 ==="
# 셸 변수를 거치면 명령 치환이 후행 개행을 전부 자른다(POSIX 규정). 계약은 프롬프트·
# 지침의 바이트열을 보존한다고 선언하므로, 도착 바이트를 16진수로 되돌려 판정한다.
make_hexdump claude
run "$(jq -nc '{prompt:"a\n\n\n"}')"
[[ "$(jq -r .output <<< "$OUT")" == "610a0a0a" ]] \
  || fail "프롬프트 후행 개행이 소실됨: $(jq -r .output <<< "$OUT")"

# 지침 병합도 같은 경로다 — 지침 + 빈 줄 + 프롬프트가 바이트 그대로여야 한다.
printf 'S\n' > "$WORK/sys.txt"
run "$(jq -nc --arg f "$WORK/sys.txt" '{prompt:"P\n", system_prompt_file:$f}')"
[[ "$(jq -r .output <<< "$OUT")" == "530a0a0a500a" ]] \
  || fail "지침 병합에서 바이트가 변형됨: $(jq -r .output <<< "$OUT")"

# NUL 보존 — 프레이밍 구조의 명시적 존재 이유다(셸 변수는 NUL 을 담지 못한다).
# 이걸 고정하지 않으면 구조가 변수 경유로 회귀해도 나머지 테스트가 전부 통과한다.
run "$(jq -nc '{prompt: ([97,0,98]|implode)}')"
[[ "$(jq -r .output <<< "$OUT")" == "610062" ]] \
  || fail "프롬프트의 NUL 이 보존되지 않음: $(jq -r .output <<< "$OUT")"
ok "프롬프트·지침 바이트 무결성 (후행 개행·NUL)"

echo ""
echo "=== TEST 10: 계약이 열거한 손실이 실제 손실과 일치한다 ==="
# 헤더는 output 의 손실을 후행 공백·NUL·비 UTF-8 치환 셋으로 열거한다. 열거가 코드보다
# 좁으면 호출자가 감지 수단 없이 변조된 값을 성공 신호와 함께 받는다.
cat > "$BIN/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf 'ok\xffbin'
EOF
chmod +x "$BIN/claude"
run '{"prompt":"x"}'
[[ "$(jq -r .output <<< "$OUT")" == $'ok�bin' ]] \
  || fail "비 UTF-8 처리가 계약과 다름: $(jq -r .output <<< "$OUT" | od -An -tx1 | tr -d ' \n')"
grep -q 'U+FFFD' "$SCRIPT" || fail "헤더의 손실 목록에 UTF-8 치환이 없음"

# 에이전트 출력은 신뢰 불가 데이터다 — 여기에 가하는 연산이 초선형이면 에이전트가
# 호출자를 멈춰 세울 수 있다. 공백 30만 개는 2차 백트래킹에서 5분 가까이 걸렸다.
cat > "$BIN/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
head -c 300000 /dev/zero | tr '\\0' ' '; printf x
EOF
chmod +x "$BIN/claude"
T0=$(date +%s)
run '{"prompt":"x"}'
(( $(date +%s) - T0 < 10 )) \
  || fail "공백 30만 개 출력 처리가 10초를 넘음 — 후행 공백 제거가 선형이 아니다"
ok "손실 목록 일치 · 출력 처리 선형"

echo ""
echo "=== TEST 11: 검사한 대상과 실행한 대상이 같다 ==="
# 벤더 CLI 를 cd 전에 검사하고 cd 후에 이름으로 다시 찾으면, PATH 에 '.' 이나 빈
# 컴포넌트가 있을 때 호출자가 준 cwd 안의 파일이 이긴다 — 검사 통과라는 착시 속에
# 무인 권한으로 임의 바이너리가 뜬다.
# 클래스 검증: 호출자가 준 값은 데이터로만 흘러야 하고, 래퍼의 실행 환경(cwd·PATH·
# TMPDIR)은 호출 시점 그대로여야 한다. 지점을 하나씩 막는 방식은 네 라운드 동안
# 여섯 번 뚫렸다 — cd 후 이름이 재해석되는 자리를 전부 한 케이스로 본다.
SHADOW="$WORK/shadow"; mkdir -p "$SHADOW"
# 정당한 가짜를 **래퍼의 cwd** 에 둔다. PATH 선두가 `.` 이므로 command -v 가 절대
# 경로가 아니라 `./claude` 를 돌려주는 조건이 만들어진다 — 그걸 그대로 믿고 벤더를
# $CWD 에서 실행하면 그림자가 이긴다. 절대 경로가 아닌 $BIN 에 두면 이 조건이 안 생겨
# 방어가 검사되지 않는다(뮤테이션으로 확인함).
# 절대 경로 유틸리티만 쓴다 — 벤더는 $CWD 에서 도는 게 정상이라, 상대 해석으로
# 그림자를 집으면 래퍼 결함과 구분되지 않는다.
printf '#!/usr/bin/env bash\nprintf "%%s" "$(/bin/cat)"\n' > "$WORK/claude"
chmod +x "$WORK/claude"
# 그림자는 외부 명령을 부르지 않는다 — `cat` 그림자가 `cat` 을 부르면 자기 자신으로
# 해석돼 무한 재귀한다(하네스가 멈추지 제품 결함이 아니다).
for name in claude cat jq mktemp stat wc head; do
  printf '#!/usr/bin/env bash\nprintf CWD-SHADOW\n' > "$SHADOW/$name"
  chmod +x "$SHADOW/$name"
done
OLD_SANDBOX="$SANDBOX_PATH"
# PATH 선두의 `.` 과 상대 TMPDIR — 둘 다 cd 이후 의미가 바뀌는 자리다.
SANDBOX_PATH=".:$BIN:/usr/bin:/bin"
printf 'REALGUIDE' > "$WORK/cls-guide.txt"
run -d "$WORK" "$(jq -nc --arg c "$SHADOW" --arg g "$WORK/cls-guide.txt" \
  '{prompt:"x", cwd:$c, system_prompt_file:$g}')"
SANDBOX_PATH="$OLD_SANDBOX"
# 양성 단언: 정당한 가짜(echo)가 실제로 실행돼 지침+프롬프트를 받았어야 한다.
# 음성 단언만 두면 스크립트가 아무 이유로든 일찍 죽어도 통과한다.
[[ "$(jq -r .output <<< "$OUT")" == "REALGUIDE"*"x" ]] \
  || fail "cwd 가 이름 해석을 오염시켰다 (output=$(jq -r '.output // .error' <<< "$OUT" | head -c 60))"
jq -e 'has("error") | not' >/dev/null <<< "$OUT" \
  || fail "클래스 케이스가 도구 오류로 떨어짐: $(jq -r .error <<< "$OUT")"

# 지침 파일도 같다: 경로로 -f·-s 를 보고 fd 로 읽으면 두 객체가 다를 수 있다.
# /dev/fd/N 을 EOF 오프셋으로 넘기면 크기 검사는 통과하고 내용은 0바이트다.
make_hexdump claude
printf 'GUIDE' > "$WORK/g.txt"
cat > "$WORK/fdprobe.sh" <<'SH'
#!/usr/bin/env bash
exec 3< "$1"
cat <&3 > /dev/null
printf '%s' '{"prompt":"P","system_prompt_file":"/dev/fd/3"}' | bash "$2"
SH
FDOUT="$(PATH="$SANDBOX_PATH" bash "$WORK/fdprobe.sh" "$WORK/g.txt" "$SCRIPT" 2>/dev/null)"
if jq -e 'has("error")' >/dev/null 2>&1 <<< "$FDOUT"; then :
elif [[ "$(jq -r .output <<< "$FDOUT")" == 475549444520* ]]; then :
else
  fail "지침이 소실됐는데 성공 보고: $(jq -r .output <<< "$FDOUT")"
fi

# 부분 소실도 같은 계열이다 — 전량 소실보다 발견이 어렵다(그럴듯한 지침이 도착한다).
# 크기 가드가 "둘 다 0 아님" 이 아니라 등식이어야 잡힌다.
printf 'AAAAABBBBBCCCCC' > "$WORK/g15.txt"
cat > "$WORK/fdpart.sh" <<'SH'
#!/usr/bin/env bash
exec 3< "$1"
head -c 10 <&3 >/dev/null
printf '%s' '{"prompt":"P","system_prompt_file":"/dev/fd/3"}' | bash "$2"
SH
PARTOUT="$(PATH="$SANDBOX_PATH" bash "$WORK/fdpart.sh" "$WORK/g15.txt" "$SCRIPT" 2>/dev/null)"
jq -e 'has("error")' >/dev/null 2>&1 <<< "$PARTOUT" \
  || fail "지침 부분 소실이 성공으로 보고됨: $(jq -r .output <<< "$PARTOUT")"

# 벤더가 stdin 을 다 읽지 않고 끝나면 feed 의 printf 가 EPIPE 를 만난다. printf 는
# 빌트인이라 SIGPIPE 로 조용히 죽지 않고 bash 가 "write error: Broken pipe" 를 찍는다
# — 그 도구 층 문구가 "에이전트 stderr" 채널로 샌다. 지침이 파이프 버퍼보다 커야
# 재현되므로 200KB 로 만든다.
printf '#!/usr/bin/env bash\nprintf EARLY >&2\nexit 3\n' > "$BIN/claude"
chmod +x "$BIN/claude"
BIGSYS="$WORK/bigsys.txt"; head -c 200000 /dev/zero | tr '\0' 'S' > "$BIGSYS"
run "$(jq -nc --rawfile p "$BIG" --arg f "$BIGSYS" '{prompt:$p, system_prompt_file:$f}')"
grep -q 'Broken pipe\|write error' "$RUN_ERR" \
  && fail "도구 층 파이프 오류가 에이전트 stderr 로 샘: $(head -c 80 "$RUN_ERR")"
grep -q EARLY "$RUN_ERR" || fail "에이전트 stderr 가 통과되지 않음(조기 종료 경로)"

# 프롬프트 준비가 실패하면 에이전트를 띄우면 안 된다. 스트림 구조에서는 EOF 가 "끝" 과
# "생산자 사망" 을 구분하지 못해 잘린 프롬프트로 에이전트가 돌고 exit_code:0 이 나왔다
# (실측). 쓰기 불가한 TMPDIR 로 준비 단계를 실패시키고, argv 기록이 없는지로 벤더
# 미실행을 확인한다.
make_fake claude echo
rm -f "$WORK/argv.claude"
RO="$WORK/ro"; mkdir -p "$RO"; chmod 500 "$RO"
run -t "$RO" '{"prompt":"x"}'
chmod 700 "$RO"
jq -e 'has("error")' >/dev/null <<< "$OUT" \
  || fail "임시 디렉토리 생성 실패가 도구 오류로 보고되지 않음: $OUT"
[[ ! -e "$WORK/argv.claude" ]] \
  || fail "임시 디렉토리 생성이 실패했는데 에이전트가 실행됨"

# 프롬프트 추출 단계만 실패시킨다 — 검증은 통과하고 그 다음에 깨지는 경로다.
# 여기가 정확히 스트림 구조에서 감지 불가였던 자리다.
REALJQ="$(command -v jq)"
rm -f "$BIN/jq"    # 심링크를 통해 쓰면 실제 jq 를 덮어쓰려 한다
cat > "$BIN/jq" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do [[ "\$a" == *'.[0].prompt'* ]] && exit 9; done
exec "$REALJQ" "\$@"
EOF
chmod +x "$BIN/jq"
rm -f "$WORK/argv.claude"
run '{"prompt":"x"}'
ln -sf "$REALJQ" "$BIN/jq"
jq -e 'has("error")' >/dev/null <<< "$OUT" \
  || fail "프롬프트 준비 실패가 도구 오류로 보고되지 않음: $OUT"
[[ ! -e "$WORK/argv.claude" ]] \
  || fail "프롬프트 준비가 실패했는데 에이전트가 실행됨 — 잘린 프롬프트로 돌 수 있다"

# 알 수 없는 키는 조용히 무시하면 안 된다. system_prompt_file 오타 하나면 지침 없이
# 실행되고, vendor 오타면 실행 반경 자체가 바뀌는데 둘 다 성공으로 보고된다.
for typo in '{"prompt":"P","system_prompt_fil":"/tmp"}' '{"prompt":"P","vendorr":"codex"}'; do
  run "$typo"
  jq -e 'has("error")' >/dev/null <<< "$OUT" \
    || fail "알 수 없는 키가 통과함: $typo"
done

# exec 실패(126/127)는 에이전트 실패가 아니라 도구 오류다 — 그대로 내보내면
# 호출자가 성공 가능성 0인 재시도를 돈다.
printf '#!/nonexistent/interp\n' > "$BIN/claude"; chmod +x "$BIN/claude"
run '{"prompt":"x"}'
jq -e 'has("error")' >/dev/null <<< "$OUT" \
  || fail "벤더 실행 실패(126)가 에이전트 실패로 보고됨: $OUT"

# vendor 만 제어문자 검사에서 빠지면 "agy\n" 이 문서화된 세 값이 아닌데도 통과한다.
make_fake agy echo
run "$(jq -nc '{prompt:"P", vendor:"agy\n"}')"
jq -e 'has("error")' >/dev/null <<< "$OUT" \
  || fail "제어문자가 든 vendor 가 통과함: $OUT"
ok "벤더 바이너리·지침 fd·실행 실패·vendor 정규화"

echo ""
echo "모든 oneshot 스킬 테스트 통과"
