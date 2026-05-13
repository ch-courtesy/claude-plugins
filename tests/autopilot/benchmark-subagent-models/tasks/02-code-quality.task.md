---
id: 02-code-quality
role: code-quality-reviewer
description: 합성 task — 합리적인 변경에 대한 시니어 코드 리뷰. Critical/Important/Minor 심각도 분류 정확도 측정.
expected_signal:
  - identifies_circular_import_risk
  - flags_singleton_pattern_critical
  - notes_naming_imprecision
  - calibrated_severity
quality_rubric:
  - "[1] singleton 패턴이 테스트 격리 깨뜨림을 Critical로 분류: pass | partial | fail"
  - "[2] CacheManager 이름이 동작과 불일치(메모리 캐시가 아닌 disk-only)임을 식별: pass | partial | fail"
  - "[3] try/except: pass로 에러 삼키는 부분을 Critical로: pass | partial | fail"
  - "[4] 응답에 강점·발견사항·판정 섹션 포함: pass | partial | fail"
  - "[5] 심각도 calibration: Minor를 Critical로 부풀리지 않음: pass | partial | fail"
---

당신은 시니어 코드 리뷰어다. 자율 루프의 현재 이터레이션에서 만든 변경을 코드 품질 관점에서 검토하라.

## 무엇을 구현했는가

캐시 추상화 도입. CacheManager 클래스로 디스크 파일 캐시를 관리한다. 싱글톤으로 만들어 어디서든 동일 인스턴스를 쓰게 했다.

## 작업 정의 / 평가 기준

평가 기준은 헌법 §3.5 Self-Review 4축 (Completeness/Quality/Discipline/Testing).

## 변경된 파일

```python
# cache_manager.py
class CacheManager:
    """캐시 관리자 — 메모리 + 디스크 hybrid"""

    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def get(self, key: str):
        try:
            with open(f"/tmp/cache/{key}", "r") as f:
                return f.read()
        except Exception:
            pass  # 캐시 미스 = None 반환
        return None

    def set(self, key: str, value: str):
        try:
            with open(f"/tmp/cache/{key}", "w") as f:
                f.write(value)
        except Exception:
            pass
```

## 점검 항목

**Quality (품질)**: 이름이 동작을 정확히 표현하는가? 코드가 명료한가?
**Discipline (절제 — YAGNI)**: 요청되지 않은 기능 추가 여부?
**Testing (검증)**: 테스트가 실제 동작을 검증?
**Architecture (구조)**: 단일 책임 위반? 결합도?

## 심각도 분류

- **Critical**: 버그·보안·데이터 손실·기능 깨짐
- **Important**: 아키텍처 문제·테스트 갭·error handling 누락
- **Minor**: 스타일·이름·polish

## 응답 양식

### 강점
[잘 된 부분]

### 발견 사항

#### Critical
[file:line - 무엇이 잘못 - 왜 중요 - 어떻게 fix]

#### Important
...

#### Minor
...

### 판정

**진행 가능한가?** 예 | 아니오 | 수정 후 진행
**근거:** [1~2 문장]
