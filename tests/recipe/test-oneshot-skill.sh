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
# claude·codex 는 stdin, agy 는 --print 인자가 규약이다.
make_fake() {   # $1=이름  $2=동작(echo|size|big|fail)
  cat > "$BIN/$1" <<EOF
#!/usr/bin/env bash
mode=$2
prompt=""
if [[ "\$1" == "--print" && -n "\${2:-}" && "\${2:0:2}" != "--" ]]; then prompt="\$2"; else prompt="\$(cat)"; fi
case "\$mode" in
  echo) printf '%s' "\$prompt" ;;
  size) printf 'BYTES=%s' "\${#prompt}" ;;
  big)  head -c 1500000 /dev/zero | tr '\\0' 'y' ;;
  fail) printf 'boom' >&2; exit 42 ;;
esac
EOF
  chmod +x "$BIN/$1"
}

run() {  # stdin JSON 을 주고 stdout 을 돌려준다. 종료 코드는 RUN_CODE 로.
  local input="$1"
  OUT="$(printf '%s' "$input" | PATH="$SANDBOX_PATH" bash "$SCRIPT" 2>/dev/null)"
  RUN_CODE=$?
}

echo "=== TEST 1: 스킬 패키지 ==="
[[ -f "$SCRIPT" ]] || fail "스크립트 없음: $SCRIPT"
bash -n "$SCRIPT" || fail "스크립트 문법 오류"
grep -qE '^name: oneshot' "$SKILL_MD" || fail "SKILL.md name 누락"
# 계약 본문은 스크립트 헤더 한 곳에만 둔다 — SKILL.md 는 그리로 보내기만 한다.
grep -q '단일 출처' "$SKILL_MD" || fail "SKILL.md 에 계약 단일 출처 지시 없음"
grep -q 'exit_code' "$SCRIPT" || fail "스크립트 헤더가 exit_code 계약을 설명하지 않음"
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
  [[ "$(wc -l <<< "$OUT")" -eq 1 ]] \
    || fail "출력이 한 줄이 아님 (입력: ${input:0:30})"
done
ok "모든 경로에서 한 줄짜리 JSON 객체 하나"

echo ""
echo "=== TEST 3: 오류 채널 분리 ==="
# 도구 오류 = 프로세스 1 + error 필드. 에이전트 실패 = 프로세스 0 + exit_code 필드.
run '{"prompt":"x","vendor":"nope"}'
[[ $RUN_CODE -eq 1 ]] || fail "도구 오류인데 프로세스 코드가 $RUN_CODE"
jq -e 'has("error")' >/dev/null <<< "$OUT" || fail "도구 오류에 error 필드 없음"

make_fake claude fail
run '{"prompt":"x"}'
[[ $RUN_CODE -eq 0 ]] || fail "에이전트 실패인데 프로세스 코드가 $RUN_CODE (0 이어야 호출자가 파싱한다)"
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

# 지침 파일은 cwd 이동 **전** 기준으로 해석한다 — 순서가 뒤집히면 같은 상대 경로가
# 작업 디렉토리 안의 동명 파일을 가리켜 엉뚱한 지침으로 조용히 바뀐다.
make_fake claude echo
printf 'ROOTGUIDE' > "$WORK/guide.txt"
printf 'WRONGGUIDE' > "$SUB/guide.txt"
OUT="$(printf '%s' '{"prompt":"tail","cwd":"sub","system_prompt_file":"guide.txt"}' \
  | (cd "$WORK" && PATH="$SANDBOX_PATH" bash "$SCRIPT") 2>/dev/null)"
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
for _ in $(seq 200); do printf '가나다라마바사아자차카타파하%.0s' $(seq 71) >> "$KBIG"; done
run "$(jq -nc --rawfile p "$KBIG" '{prompt:$p, vendor:"agy"}')"
jq -e 'has("error")' >/dev/null <<< "$OUT" \
  || fail "멀티바이트 프롬프트가 agy 크기 가드를 통과함 (exit_code=$(jq -r .exit_code <<< "$OUT"))"
ok "옵션형 경로·멀티바이트 크기 가드"

echo ""
echo "모든 oneshot 스킬 테스트 통과"
