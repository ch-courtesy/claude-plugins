#!/usr/bin/env bash
# per-spec directory layout — 마이그레이션 로직 검증 (AC7).
#
# SPEC: spec/loop/dispatch per-spec directory layout 전환.
#   AC7 — 기존 docs/specs/ 단일 파일 SPEC 을 이전하면 각 SPEC 은 <date>-<slug>/SPEC.md 로
#         옮겨지고, 이전 후 같은 slug 의 구 단일 파일 경로는 남지 않아야 한다.
#   제약 — 마이그레이션은 docs/specs/ 최상위 실행 중 흔적(락·워크트리 메타)을 인지하고
#          활성 loop 실행 상태를 깨지 않도록 처리한다(= *.md 본문만 옮기고 락·메타는 보존).
#          신 형식 디렉토리(<slug>/SPEC.md)를 본문으로 오인해 재중첩하지 않는다.

set -uo pipefail

fail=0
chk()      { if [[ "$2" == "$3" ]]; then echo "PASS  $1"; else echo "FAIL  $1  got='$2' exp='$3'"; fail=1; fi; }
chk_file() { if [[ -f "$2" ]]; then echo "PASS  $1"; else echo "FAIL  $1  파일 없음: $2"; fail=1; fi; }
chk_nofile(){ if [[ ! -e "$2" ]]; then echo "PASS  $1"; else echo "FAIL  $1  잔존: $2"; fail=1; fi; }

# 마이그레이션 로직 — docs/specs/ 최상위 단일 파일 *.md 만 <base>/SPEC.md 로 이전.
#   - 락·워크트리 메타(.loop-lock/.loop-wt) 와 이미 디렉토리인 신 형식은 *.md 글롭에
#     매치되지 않으므로 자연히 보존/스킵된다(활성 run 무손상, 재중첩 없음).
migrate_specs() {
  local specs_dir="$1"
  local f base target
  shopt -s nullglob
  for f in "$specs_dir"/*.md; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f" .md)"
    target="$specs_dir/$base"
    mkdir -p "$target"
    mv "$f" "$target/SPEC.md"
  done
  shopt -u nullglob
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SPECS="$WORK/docs/specs"
mkdir -p "$SPECS"

# 구 형식 단일 파일 2개
printf -- '---\n---\n# alpha spec\nALPHA-BODY\n' > "$SPECS/2026-05-29-alpha.md"
printf -- '---\ndepends_on: ["alpha"]\n---\n# beta spec\nBETA-BODY\n' > "$SPECS/2026-05-29-beta.md"
# 활성 run 흔적 (최상위 락·메타) — 보존되어야 함
printf '12345\n' > "$SPECS/.loop-lock"
printf '/some/wt\n' > "$SPECS/.loop-wt"
# 이미 신 형식인 스펙 — 재중첩되지 않아야 함
mkdir -p "$SPECS/2026-05-28-already"
printf -- '---\n---\n# already\nALREADY-BODY\n' > "$SPECS/2026-05-28-already/SPEC.md"

migrate_specs "$SPECS"

echo "=== AC7: 구 단일 파일 → <slug>/SPEC.md 이전 ==="
chk_file   "alpha SPEC.md 생성"          "$SPECS/2026-05-29-alpha/SPEC.md"
chk_file   "beta SPEC.md 생성"           "$SPECS/2026-05-29-beta/SPEC.md"
chk_nofile "alpha 구 단일 파일 제거"      "$SPECS/2026-05-29-alpha.md"
chk_nofile "beta 구 단일 파일 제거"       "$SPECS/2026-05-29-beta.md"
chk "alpha 본문 보존" "$(grep -c ALPHA-BODY "$SPECS/2026-05-29-alpha/SPEC.md")" "1"
chk "beta depends_on 보존" "$(grep -c 'depends_on' "$SPECS/2026-05-29-beta/SPEC.md")" "1"

echo ""
echo "=== 제약: 최상위 단일 .md 잔존 0 ==="
remaining=$(shopt -s nullglob; set -- "$SPECS"/*.md; echo $#)
chk "최상위 *.md 잔존 수" "$remaining" "0"

echo ""
echo "=== 제약: 활성 run 흔적(락·메타) 보존 ==="
chk_file   ".loop-lock 보존" "$SPECS/.loop-lock"
chk_file   ".loop-wt 보존"   "$SPECS/.loop-wt"

echo ""
echo "=== 제약: 신 형식 디렉토리 재중첩 없음 ==="
chk_file   "already SPEC.md 그대로"        "$SPECS/2026-05-28-already/SPEC.md"
chk_nofile "already 재중첩 안 됨"           "$SPECS/2026-05-28-already/SPEC/SPEC.md"
chk "already 본문 보존" "$(grep -c ALREADY-BODY "$SPECS/2026-05-28-already/SPEC.md")" "1"

if [[ $fail -ne 0 ]]; then echo "FAIL: 마이그레이션 로직 결함"; exit 1; fi
echo ""
echo "PASS: per-spec 마이그레이션 (AC7 + 제약)"
