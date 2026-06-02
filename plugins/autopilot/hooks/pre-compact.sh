#!/bin/sh
# PreCompact hook: 자동 컴팩션 직전, 대화형 세션의 작업 상태를 7필드 구조화
# 핸드오프 문서로 디스크에 떠 둔다. 다음 세션 시작 시 session-restore.sh 가 복원한다.
#
# 절대 차단하지 않는다: 어떤 실패·타임아웃에도 exit 0 으로 통과(graceful passthrough).
# loop 헤드리스 작업 공간(`.loop/`)에서는 적용하지 않는다.
#
# stdin(JSON): {session_id, transcript_path, cwd, hook_event_name, trigger, ...}

ROOT="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}"
# CLAUDE_PLUGIN_ROOT 는 플러그인 루트(…/autopilot)를 가리킨다. common 은 hooks/ 아래.
if [ -f "$ROOT/handoff-common.sh" ]; then
  . "$ROOT/handoff-common.sh"
elif [ -f "$ROOT/hooks/handoff-common.sh" ]; then
  . "$ROOT/hooks/handoff-common.sh"
else
  exit 0   # 헬퍼 부재 — 조용히 통과(세션을 막지 않는다).
fi

# stdin 전체를 읽는다(없어도 통과).
INPUT=$(cat 2>/dev/null || true)

TRANSCRIPT=$(printf '%s' "$INPUT" | handoff_json_field transcript_path)
CWD=$(printf '%s' "$INPUT" | handoff_json_field cwd)
SESSION=$(printf '%s' "$INPUT" | handoff_json_field session_id)
TRIGGER=$(printf '%s' "$INPUT" | handoff_json_field trigger)

PROJ=$(handoff_project_dir "$CWD")

# AC4: loop 헤드리스 작업 공간이면 핸드오프를 적용하지 않는다.
if handoff_is_loop_workspace "$PROJ"; then
  exit 0
fi

# 상태 디렉토리(+ 자가-무시 .gitignore) 준비. 실패해도 통과.
handoff_ensure_state_dir "$PROJ" || { handoff_log "$PROJ" "상태 디렉토리 생성 실패"; exit 0; }

OUT=$(handoff_file "$PROJ")
TMP="$OUT.tmp.$$"

emit_field_header() { printf '\n## %s\n' "$1" >> "$TMP"; }

# ---- raw 구조 덤프(기본 경로, 비용 0, 결정론적) -----------------------------
build_raw() {
  : > "$TMP" || return 1
  {
    printf '# autopilot 대화형 세션 핸드오프 (handoff)\n'
    printf '<!-- generator=raw session=%s trigger=%s -->\n' "${SESSION:-unknown}" "${TRIGGER:-unknown}"
    printf '이 문서는 자동 컴팩션 직전 캡처된 작업 상태다. 다음 세션 컨텍스트로 복원된다.\n'
  } >> "$TMP"

  task=""; files=""; recent=""; last_assistant=""
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && command -v jq >/dev/null 2>&1; then
    task=$(jq -rs '
      [ .[] | select(.type=="user") | (.message.content // empty)
        | if type=="string" then . else (.[]? | select(.type=="text")? | .text) end
      ] | map(select(. != null and . != "")) | .[0] // empty' "$TRANSCRIPT" 2>/dev/null || true)
    files=$(jq -rs '
      [ .[] | select(.type=="assistant") | (.message.content // empty) | .[]?
        | select(.type=="tool_use")
        | select(.name|test("Edit|Write|NotebookEdit"))
        | .input.file_path ] | map(select(. != null)) | unique | .[]' "$TRANSCRIPT" 2>/dev/null || true)
    recent=$(jq -rs '
      [ .[] | (.message.content // empty)
        | if type=="string" then . else (.[]? | select(.type=="text")? | .text) end
      ] | map(select(. != null and . != "")) | .[-8:] | .[]' "$TRANSCRIPT" 2>/dev/null || true)
    last_assistant=$(jq -rs '
      [ .[] | select(.type=="assistant") | (.message.content // empty) | .[]?
        | select(.type=="text")? | .text ] | map(select(. != null and . != "")) | .[-1] // empty' "$TRANSCRIPT" 2>/dev/null || true)
  elif [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    # jq 부재: 원시 tail 폴백.
    recent=$(tail -c 4000 "$TRANSCRIPT" 2>/dev/null || true)
  fi

  emit_field_header task
  if [ -n "$task" ]; then printf '%s\n' "$task" >> "$TMP"
  else printf '(이 세션 transcript 에서 명시적 task 문구를 추출하지 못함)\n' >> "$TMP"; fi

  emit_field_header completed
  if [ -n "$files" ]; then
    printf '편집·생성된 파일:\n' >> "$TMP"
    printf '%s\n' "$files" | while IFS= read -r f; do [ -n "$f" ] && printf -- '- %s\n' "$f" >> "$TMP"; done
  else
    printf '(완료 항목을 transcript 에서 구조적으로 추출하지 못함 — current_state 참조)\n' >> "$TMP"
  fi

  emit_field_header current_state
  if [ -n "$recent" ]; then printf '최근 대화 발췌:\n%s\n' "$recent" >> "$TMP"
  else printf '(최근 상태를 추출하지 못함)\n' >> "$TMP"; fi

  emit_field_header constraints
  cons=$(printf '%s\n' "$recent" | grep -iE '제약|constraint|반드시|금지|must|should not|scope' | head -8 || true)
  if [ -n "$cons" ]; then printf '%s\n' "$cons" >> "$TMP"
  else printf '(이 세션에서 명시적으로 캡처된 제약 없음 — 프로젝트 CLAUDE.md·SPEC 우선)\n' >> "$TMP"; fi

  emit_field_header files_touched
  if [ -n "$files" ]; then
    printf '%s\n' "$files" | while IFS= read -r f; do [ -n "$f" ] && printf -- '- %s\n' "$f" >> "$TMP"; done
  else
    printf '(이 세션에서 감지된 파일 편집 없음)\n' >> "$TMP"
  fi

  emit_field_header open_questions
  oq=$(printf '%s\n' "$recent" | grep -E '\?|미해결|open question|TODO|확인 필요' | head -8 || true)
  if [ -n "$oq" ]; then printf '%s\n' "$oq" >> "$TMP"
  else printf '(미해결 질문이 명시적으로 캡처되지 않음)\n' >> "$TMP"; fi

  emit_field_header next_steps
  if [ -n "$last_assistant" ]; then printf '직전 작업 맥락(다음 단계 추정):\n%s\n' "$last_assistant" >> "$TMP"
  else printf '(다음 단계가 명시되지 않음 — current_state 에서 이어가기)\n' >> "$TMP"; fi

  return 0
}

# ---- 선택적 모델 요약(opt-in) ----------------------------------------------
# AUTOPILOT_HANDOFF_SUMMARIZER 가 설정되면 transcript 를 stdin 으로 그 명령에 넘겨
# 구조화 문서를 받는다. timeout 가드 + 실패 시 raw 폴백.
build_via_summarizer() {
  [ -n "${AUTOPILOT_HANDOFF_SUMMARIZER:-}" ] || return 1
  [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || return 1
  to=${AUTOPILOT_HANDOFF_TIMEOUT:-60}
  if command -v timeout >/dev/null 2>&1; then
    out=$(timeout "$to" sh -c "$AUTOPILOT_HANDOFF_SUMMARIZER" < "$TRANSCRIPT" 2>/dev/null) || return 1
  else
    out=$(sh -c "$AUTOPILOT_HANDOFF_SUMMARIZER" < "$TRANSCRIPT" 2>/dev/null) || return 1
  fi
  [ -n "$out" ] || return 1
  printf '%s\n' "$out" > "$TMP" || return 1
  return 0
}

if build_via_summarizer; then
  :
elif build_raw; then
  :
else
  handoff_log "$PROJ" "핸드오프 본문 생성 실패 — 통과"
  rm -f "$TMP" 2>/dev/null || true
  exit 0
fi

# 원자적 교체. 실패해도 통과.
if mv "$TMP" "$OUT" 2>/dev/null; then
  :
else
  handoff_log "$PROJ" "핸드오프 파일 쓰기 실패: $OUT"
  rm -f "$TMP" 2>/dev/null || true
fi

exit 0
