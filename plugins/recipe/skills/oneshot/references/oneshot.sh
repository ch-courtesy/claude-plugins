#!/usr/bin/env bash
# oneshot.sh — 외부 에이전트 CLI 를 1회 실행하는 raw 래퍼 (claude -p 수준).
#
# 계약: stdin 으로 입력 JSON, stdout 으로 출력 JSON. 에이전트의 stderr 는 그대로
# 통과시킨다(호출자가 본다). 이 도구는 판단하지 않는다 — 격리(작업 공간 준비),
# 커밋 여부, 종료 표지 규약, 반복은 전부 호출자의 몫이다. 다만 "지시한 대로
# 실행했다"는 전제(입력 해석·벤더 지원·작업 디렉토리 이동·지침 파일 읽기)가 깨지면
# 조용히 진행하지 않고 도구 오류로 중단한다 — 격리를 믿는 호출자가 속지 않게.
#
# 필요 도구: jq(1.5+, --argjson), 선택한 벤더 CLI.
#
# 입력 (JSON 객체, 필드는 전부 문자열):
#   prompt              에이전트에 줄 지시 (비어 있어도 막지 않는다)
#   cwd                 실행 디렉토리 (기본: 현재 디렉토리, 제어문자 불가)
#   system_prompt_file  시스템 지침 파일 — 정규 파일만, 호출 시점 디렉토리 기준으로 해석
#                       (내용이 비어 있으면 지침 없이 실행)
#   vendor              claude(기본) | codex | agy (별칭: antigravity)
#   model               벤더의 모델 이름 (생략하면 벤더 기본값 — 플래그를 넣지 않는다).
#                       쿼터 소진 시 다른 모델로 넘기는 것은 판단이므로 호출자가 정한다.
#
# 출력 (JSON 객체): {exit_code, output}
#   output     에이전트 stdout. 손실은 정확히 셋이다 — (1) 후행 공백·개행(CR 포함)을
#              제거해 마지막 줄이 실제 마지막 내용이 되게 한다, (2) NUL 바이트는
#              보존하지 않는다, (3) 유효하지 않은 UTF-8 바이트는 U+FFFD 로 치환된다.
#              바이트 단위 비교가 필요하면 이 필드를 쓰면 안 된다.
#   exit_code  에이전트 종료 코드. 도구 자체 오류면 {exit_code: 1, output: "", error: "..."}
#              이고 프로세스도 1 이다 — 에이전트가 몇으로 죽든 프로세스는 0 이므로
#              에이전트 성패는 반드시 exit_code 필드로 본다. 단 126·127 은 "실행하지
#              못했다"는 신호라 에이전트 실패가 아니라 도구 오류로 올린다.
#
# 실행 환경: 호출자가 준 값은 데이터로만 흐른다. 래퍼 자신의 cwd·PATH·TMPDIR 은 호출
# 시점 그대로 유지되고, `cwd` 로는 벤더 프로세스만 서브셸에서 이동한다 — 래퍼가 이동하면
# 이후 모든 이름 해석이 호출자가 통제하는 디렉토리 기준으로 재해석된다.
#
# 바이트 무결성: prompt 와 지침 파일 내용은 변형 없이 벤더에 도달한다. 그래서 둘 다
# 셸 변수를 거치지 않고 임시 파일로만 흐른다 — 명령 치환 `$(...)` 은 후행 개행을 전부
# 자르고 셸 변수는 NUL 을 담지 못하므로, 변수를 경유하는 순간 계약이 깨진다.
# 예외는 agy 뿐이다(아래).
#
# 준비를 끝낸 뒤에 벤더를 띄운다. 프롬프트를 스트림으로 흘리면 EOF 가 "끝" 과 "생산자
# 사망" 을 구분하지 못해 잘린 프롬프트로 에이전트가 돌고 exit_code:0 이 나온다 —
# 파일이면 각 단계의 종료 상태를 보고 크기를 확정한 뒤 실행한다.
#
# 벤더 관례 차이는 이 층이 흡수한다: 지침은 프롬프트 선두에 병합하고, 프롬프트는
# claude·codex 에 stdin 으로 준다. agy 만 stdin 을 받지 않아 argv 로 넘기므로 그
# 경로에서만 (a) 바이트 무결성이 없고 (b) 크기 한계가 있고 (c) 내용이 ps 에 노출되며
# (d) 프롬프트가 `-` 로 시작하면 거부한다 — agy 는 --version·--help 를 위치와 무관하게
# 선스캔해 그 문자열이 프롬프트 자리에 있어도 플래그로 가로챈다(실측). `--` 를 붙이거나
# 순서를 바꿔도 막히지 않아, 에이전트가 뜬 적 없이 성공으로 보고되는 것을 도구가 먼저
# 막는다. 큰 프롬프트·바이트 보존이 필요하면 claude·codex 를 쓴다.
#
# 이 파일의 계약은 tests/recipe/test-oneshot-skill.sh 가 검증한다 — 자동 실행 경로는
# 없으니 구조를 바꾸면 직접 돌려라. 크기 경계·오류 분류·stdout 순수성·바이트 무결성은
# 주석으로만 두면 리팩터마다 다른 자리에서 조용히 깨진다.
#
# 시그널(SIGTERM 등)로 중단되면 stdout 이 비고 종료 코드도 규약 밖이다 — 위 계약은
# 정상 종료 경로에만 적용된다. 회차 타임아웃을 거는 호출자는 빈 stdout 을 대비한다.

set -u

command -v jq >/dev/null \
  || { printf '{"exit_code":1,"output":"","error":"jq 가 필요합니다."}\n'; exit 1; }

fail() { jq -nc --arg e "$1" '{exit_code: 1, output: "", error: $e}'; exit 1; }

# 스키마 위반은 jq 안에서 판정해 {error} 로 싣는다 — 셸이 필드를 하나씩 꺼내 검사하면
# 그때마다 명령 치환을 타야 하고 거기서 값이 변형된다. 입력이 JSON 이 아니면 jq 가
# 실패해 출력이 비고, 그걸 빈 결과로 감지한다.
VALIDATE='
  def ctl: explode | any(. < 32);
  def bad($o):
    if   ($o|has("prompt"))             and ($o.prompt|type)             != "string" then "prompt 는 문자열이어야 합니다"
    elif ($o|has("cwd"))                and ($o.cwd|type)                != "string" then "cwd 는 문자열이어야 합니다"
    elif ($o|has("system_prompt_file")) and ($o.system_prompt_file|type) != "string" then "system_prompt_file 은 문자열이어야 합니다"
    elif ($o|has("vendor"))             and ($o.vendor|type)             != "string" then "vendor 는 문자열이어야 합니다"
    elif ($o|has("model"))              and ($o.model|type)              != "string" then "model 은 문자열이어야 합니다"
    elif (($o.cwd // "") | ctl)                then "cwd 에 제어문자가 들어 있습니다"
    elif (($o.system_prompt_file // "") | ctl) then "system_prompt_file 에 제어문자가 들어 있습니다"
    elif (($o.vendor // "") | ctl)             then "vendor 에 제어문자가 들어 있습니다"
    elif (($o.model // "") | ctl)              then "model 에 제어문자가 들어 있습니다"
    elif (($o | keys) - ["prompt","cwd","system_prompt_file","vendor","model"] | length > 0)
      then "알 수 없는 필드: " + (($o | keys) - ["prompt","cwd","system_prompt_file","vendor","model"] | join(", "))
    else "" end;
  if length != 1 or (.[0]|type) != "object" then
    {error: "입력이 JSON 객체 하나가 아닙니다 (stdin 으로 {prompt: ...} 전달)"}
  else
    .[0] as $o | (bad($o)) as $e |
    if $e != "" then {error: $e}
    else {cwd: ($o.cwd // ""), spf: ($o.system_prompt_file // ""),
          vendor: ($o.vendor // "claude"), model: ($o.model // "")}
    end
  end'

# 프롬프트를 실체화한 뒤 벤더를 띄운다. 스트림으로 흘리면 EOF 가 "프롬프트 끝" 과
# "생산자 사망" 을 구분하지 못해(실측) 잘린 프롬프트로 에이전트가 돌고 exit_code:0 이
# 나온다 — "전제가 깨지면 에이전트를 띄우지 않는다" 는 계약이 거기서 깨진다. 파일로
# 두면 각 단계의 종료 상태를 볼 수 있고 실행 전에 크기가 확정된다. 셸 변수를 안 거치는
# 것은 그대로다(파일도 바이트를 보존한다).
# 템플릿을 명시한다 — macOS mktemp 는 템플릿 없이는 TMPDIR 을 무시한다.
TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/oneshot.XXXXXX" 2>/dev/null)" \
  || fail "임시 디렉토리를 만들 수 없음"
trap 'rm -rf "$TMPROOT"' EXIT
IN="$TMPROOT/in"; PROMPT="$TMPROOT/prompt"; SYS_SNAP="$TMPROOT/sys"

{
  cat > "$IN" || fail "입력을 읽을 수 없음"
  META="$(jq -sc "$VALIDATE" "$IN" 2>/dev/null)" \
    || fail "입력이 JSON 객체 하나가 아닙니다 (stdin 으로 {prompt: ...} 전달)"
  ERR="$(jq -r '.error // empty' <<< "$META")"
  [[ -z "$ERR" ]] || fail "$ERR"
  jq -sj '.[0].prompt // ""' "$IN" > "$PROMPT" 2>/dev/null \
    || fail "프롬프트를 준비하지 못했습니다"

  CWD="$(jq -r '.cwd' <<< "$META")"
  SYSTEM_FILE="$(jq -r '.spf' <<< "$META")"
  VENDOR="$(jq -r '.vendor' <<< "$META")"
  MODEL="$(jq -r '.model' <<< "$META")"
  # 빈 값이면 플래그 자체를 넣지 않는다 — `--model ""` 은 벤더가 "빈 모델 이름" 으로
  # 읽거나 다음 인자를 값으로 삼는다. 배열로 두면 set -u 에서도 안전하게 펼쳐진다.
  MODEL_ARG=(); [[ -z "$MODEL" ]] || MODEL_ARG=(--model "$MODEL")

  # 지원 여부를 CLI 존재 검사보다 먼저 본다 — 순서가 반대면 오타·미지원 벤더가
  # "설치하라"로 오보고된다.
  case "$VENDOR" in
    claude|codex) ;;
    agy|antigravity) VENDOR=agy ;;
    *) fail "지원하지 않는 vendor: $VENDOR (claude, codex, agy)" ;;
  esac
  # 여기서 한 번만 해석하고 절대 경로로 고정한다. `command -v` 는 PATH 에 `.` 이나
  # 빈 컴포넌트가 있으면 상대 경로(`./claude`)를 돌려주므로 결과를 그냥 믿으면 안 된다.
  # 아직 이동하지 않았으니 $PWD 가 호출 시점 디렉토리다.
  VENDOR_BIN="$(command -v "$VENDOR")" \
    || fail "벤더 CLI 를 찾을 수 없음: $VENDOR"
  case "$VENDOR_BIN" in /*) ;; *) VENDOR_BIN="$PWD/$VENDOR_BIN" ;; esac

  # 정규 파일만 받는다. `-r && ! -d` 는 FIFO·/dev/zero 를 통과시켜 cat 이 끝나지 않고
  # 프로세스가 영원히 멈춘다. `-` 도 `--` 를 붙이면 파일로 해석되지만 실재하지 않아
  # 여기서 걸린다. 읽기는 cwd 이동 전에 — 이동 후엔 상대 경로가 다른 파일을 가리킨다.
  # 그리고 검사와 사용을 같은 바이트에 묶는다. 경로로 -s 를 보고 fd 로 읽으면 두 객체가
  # 다를 수 있다 — `/dev/fd/N` 을 EOF 오프셋으로 넘기면 크기 검사는 통과하고 실제
  # 도착 내용은 0바이트라, 지침이 통째로 사라진 채 성공으로 보고된다(재현함).
  # 그래서 스냅샷을 뜨고 그 스냅샷만 검사·사용한다.
  HAVE_SYS=0
  if [[ -n "$SYSTEM_FILE" ]]; then
    [[ -f "$SYSTEM_FILE" && -r "$SYSTEM_FILE" ]] \
      || fail "system_prompt_file 을 읽을 수 없음: $SYSTEM_FILE"
    cat -- "$SYSTEM_FILE" > "$SYS_SNAP" 2>/dev/null \
      || fail "system_prompt_file 을 읽을 수 없음: $SYSTEM_FILE"
    # 경로가 말하는 크기와 실제로 읽은 바이트 수가 같아야 한다. "둘 다 0 아님" 만
    # 보면 부분 소실이 통과한다 — `/dev/fd/N` 을 중간 오프셋으로 넘기면 그럴듯한
    # 지침 일부가 도착하고, 전량 소실보다 발견이 어렵다.
    DECL="$(stat -f%z "$SYSTEM_FILE" 2>/dev/null || stat -c%s "$SYSTEM_FILE" 2>/dev/null || echo -1)"
    SNAP="$(wc -c < "$SYS_SNAP")"
    (( DECL == SNAP )) \
      || fail "system_prompt_file 의 크기(${DECL})와 실제 읽은 바이트(${SNAP})가 다름: $SYSTEM_FILE"
    [[ ! -s "$SYS_SNAP" ]] || HAVE_SYS=1
  fi

  # 래퍼 자신은 이동하지 않는다. cwd 는 호출자가 준 신뢰 불가 입력이고, 그걸 래퍼의
  # 실행 환경으로 삼는 순간 이후 모든 이름 해석(PATH·상대 경로·TMPDIR)이 그 디렉토리
  # 기준으로 재해석된다 — 네 라운드에 걸쳐 여섯 번 그 자리에서 뚫렸다. 벤더 프로세스만
  # 서브셸에서 이동시킨다. 여기서는 갈 수 있는지만 확인한다(CDPATH 는 cd 가 stdout 에
  # 경로를 찍어 출력 JSON 을 오염시키므로 끄고, `--` 가 없으면 `-P` 같은 경로가 cd
  # 옵션으로 먹혀 $HOME 으로 이동한 뒤 성공으로 보고된다).
  # 확인과 실제 이동 사이에 창이 있지만, 그 창을 쓰려면 공격자가 이미 그 디렉토리에
  # 쓸 수 있어야 하고 그 경우 무인 권한 에이전트가 거기서 뜨는 더 쉬운 길이 열려 있다.
  if [[ -n "$CWD" ]]; then
    ( CDPATH= cd -- "$CWD" ) 2>/dev/null || fail "cwd 로 이동할 수 없음: $CWD"
  fi

  # 지침 스냅샷 + 빈 줄 + 남은 fd(프롬프트). 전부 스트림 연결이라 변수 경유가 없다.
  # 지침이 비어 있으면 선두 빈 줄을 만들지 않는다. 이 함수는 이동하지 않은 래퍼에서
  # 돌기 때문에 `cat` 도 호출 시점 PATH 로 해석된다.
  # stderr 를 닫는 이유: printf 는 빌트인이라 EPIPE 에서 시그널사하지 않고 bash 가
  # "write error: Broken pipe" 를 찍는다 — 벤더가 stdin 을 다 읽지 않고 끝나면 그 도구
  # 층 문구가 "에이전트 stderr" 채널로 샌다.
  feed() {
    {
      (( HAVE_SYS == 0 )) || { cat -- "$SYS_SNAP"; printf '\n\n'; }
      cat -- "$PROMPT"
    } 2>/dev/null
  }

  # 벤더만 대상 디렉토리에서 실행한다. `exec` 를 쓰지 않는 이유: bash 3.2 는 exec
  # 실패를 126 이 아니라 1 로 보고해(실측) 아래 126·127 분류가 무력화된다. 프로세스
  # 하나를 더 쓰는 대신 셸의 표준 코드를 그대로 받는다.
  vendor_run() { ( [[ -z "$CWD" ]] || { CDPATH= cd -- "$CWD" || exit 127; }; "$@" ); }

  CODE=0
  case "$VENDOR" in
    claude)
      OUTPUT="$(feed | vendor_run "$VENDOR_BIN" --print --no-session-persistence \
        --dangerously-skip-permissions --add-dir . ${MODEL_ARG[@]+"${MODEL_ARG[@]}"})" || CODE=$?
      ;;
    codex)
      OUTPUT="$(feed | vendor_run "$VENDOR_BIN" exec --ephemeral --sandbox workspace-write \
        ${MODEL_ARG[@]+"${MODEL_ARG[@]}"} -)" || CODE=$?
      ;;
    agy)
      # 여기서만 변수를 경유한다 — argv 가 구조적 요구라 피할 수 없다.
      FULL="$(feed)"
      [[ "${FULL:0:1}" != "-" ]] \
        || fail "agy 는 '-' 로 시작하는 프롬프트를 플래그로 가로챈다 — claude·codex 를 쓰거나 선두에 공백을 넣는다"
      # 커널이 세는 단위는 바이트다. macOS 는 인자 총합(ARG_MAX), Linux 는 인자 하나당
      # 128KiB(MAX_ARG_STRLEN, 끝 NUL 포함). 환경 블록이 같은 예산을 먹으므로 실측치를
      # 빼고 여유를 둔다 — 정확할 수는 없고, 통과시켜 exec 실패(126)를 에이전트 실패로
      # 위장하기보다 일찍 거부하는 쪽으로 틀린다.
      if [[ "$(uname)" == Linux ]]; then
        limit=131071
      else
        limit=$(( $(getconf ARG_MAX) - $(env | LC_ALL=C wc -c) - 4096 ))
      fi
      (( $(printf '%s' "$FULL" | LC_ALL=C wc -c) < limit )) \
        || fail "프롬프트가 agy 인자 한계(${limit} 바이트)를 넘음 — stdin 을 받는 claude·codex 를 쓰거나 프롬프트를 줄인다"
      OUTPUT="$(vendor_run "$VENDOR_BIN" --dangerously-skip-permissions --add-dir . \
        ${MODEL_ARG[@]+"${MODEL_ARG[@]}"} --print "$FULL")" || CODE=$?
      ;;
  esac

  # 126·127 은 셸이 "실행하지 못했다"고 알리는 코드다. 그대로 내보내면 에이전트가
  # 시작조차 안 했는데 호출자가 에이전트 실패로 읽고 성공 가능성 0인 재시도를 돈다.
  # 에이전트가 진짜 그 코드로 죽는 경우를 오분류하는 대가를 치르되, 그쪽이 드물고
  # 반대 방향 오분류보다 손해가 작다.
  if (( CODE == 126 || CODE == 127 )); then
    fail "벤더 CLI 를 실행할 수 없음(코드 $CODE): $VENDOR_BIN — 설치·실행 권한·인터프리터 확인"
  fi

  # 출력은 파이프로 넘긴다 — argv(--arg)로 주면 큰 출력에서 jq 가 exec 되지 못해
  # stdout 이 통째로 비고(계약 위반) 프로세스 코드도 규약 밖 값이 된다. printf 는
  # 빌트인이라 크기 제한이 없다. -Rs 로 전체를 문자열 하나로 읽는다. 여기서 OUTPUT 이
  # 변수를 거치며 잃는 것은 헤더가 열거한 셋뿐이다.
  # 후행 공백 제거는 시작 위치를 고정한 형태로 쓴다. `sub("[[:space:]]+$";"")` 는 매
  # 시작 위치에서 공백 런을 끝까지 먹고 `$` 실패 후 되돌려 런 길이당 O(L²) 다 — 그리고
  # 이 입력은 에이전트가 통제한다. 공백 30만 개에서 292초 vs 0.045초로 실측됐다.
  printf '%s' "$OUTPUT" | jq -Rsc --argjson c "$CODE" \
    '{exit_code: $c, output: (capture("(?s)^(?<h>.*[^[:space:]])[[:space:]]*$").h // "")}'

}

