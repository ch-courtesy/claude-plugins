---
id: 01-spec-compliance
role: spec-compliance-reviewer
description: 합성 task — 단일 파일 변경의 SPEC 수용 기준 대비 검증. 4-Level Verifier (Existence/Substantive/Wired/Runtime) 점검 유도.
expected_signal:
  - existence_check_per_AC
  - finds_stub_at_line_42
  - identifies_dead_function_unused
  - notes_verify_command_was_not_run
quality_rubric:
  - "[1] Existence 4 항목 모두 명시적 점검: pass | partial | fail"
  - "[2] line 42의 stub('return None') 식별: pass | partial | fail"
  - "[3] dead_function이 import 안 됨을 식별: pass | partial | fail"
  - "[4] verify 명령을 직접 실행했는지 평가: pass | partial | fail"
  - "[5] 응답 양식(✅/❌ 마크) 준수: pass | partial | fail"
---

당신은 자율 루프의 현재 이터레이션에서 만든 변경이 작업 명세에 부합하는지 검증합니다.

## 요구사항 (.loop/SPEC.md에서)

작업: parser.py의 parse_input 함수에 빈 입력·whitespace-only 입력 처리 추가.

수용 기준:
1. parse_input("") 호출 시 ValueError 발생
2. parse_input("   ") 호출 시 ValueError 발생
3. parse_input("hello") 호출 시 ["hello"] 반환
4. 헬퍼 함수 _normalize_whitespace 도입 (재사용 목적)

verify: `python -m pytest tests/test_parser.py -k "empty or whitespace"`

## 이번 이터가 한 작업 (자기 보고)

parser.py에 입력 검증 로직 추가. _normalize_whitespace 헬퍼도 만들어 둠. 테스트도 통과한다.

## 변경된 파일 (diff)

```python
# parser.py
def parse_input(s: str) -> list[str]:
    if not s:
        raise ValueError("empty input")
    if not s.strip():
        raise ValueError("whitespace-only input")
    return s.split()

def _normalize_whitespace(s: str) -> str:
    return None  # line 42: TODO 구현 필요

def dead_function():
    """사용 안 됨 — 향후 확장용"""
    return _normalize_whitespace("")
```

## 임무

이번 이터에서 실제로 변경된 코드를 읽고 헌법 §3.4의 4-Level Verifier에 대해 검증한다:

**Existence (존재)**: 수용 기준의 모든 항목에 대응하는 코드 변경이 있는가?
**Substantive (실체)**: stub·placeholder가 아닌가?
**Wired (배선)**: 새 함수가 호출처에 사용되는가?
**Runtime (실행)**: verify 명령이 통과한다고 주장한다면 직접 실행해 확인하라.

## 응답 양식

✅ Spec compliant — 4 단계 모두 통과
❌ Issues found:
- [Existence] 누락 항목 X (수용 기준 N번)
- [Substantive] stub at file:line
- [Wired] 사용 안 되는 새 함수 X
- [Runtime] verify 실패 (이유)
