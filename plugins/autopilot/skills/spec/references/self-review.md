# SPEC 자체 검토 체크리스트

스킬은 SPEC.md 작성 직후 (단계 7 이후, 사용자 검토 단계 전) 다음 5항목을 자체 점검합니다. 발견 시 인라인 수정 또는 `[NEEDS CLARIFICATION: <질문>]` 마커만 — 재루프 없음, 사용자 Q&A 없음. 마커는 단계 9 사용자 최종 검토에서 일괄 해결.

## 1. Placeholder 스캔

다음 패턴이 SPEC.md에 남아 있으면 안 됨:
- `{{...}}` 미치환 placeholder
- `TBD`, `TODO`, `FIXME`, `XXX`
- 빈 섹션 (헤더만 있고 본문 없음 — Constraints·Risks 제외)

발견 시: 인라인으로 채울 수 있으면 채우고, 모호하면 `[NEEDS CLARIFICATION: <구체 질문>]` 마커.

## 2. 내부 모순 검사

다음 모순 패턴 자동 검사:
- "무엇을 만들 것인가"가 X를 명시했는데 "수용 기준"에 X 관련 기준 없음
- "범위.포함"과 "범위.비-목표"가 같은 경로 패턴을 모두 포함
- "검증" 명령이 "범위.포함"에 없는 디렉터리를 빌드·테스트
- frontmatter `scope.include`와 본문 "범위.포함"이 불일치

발견 시: `[NEEDS CLARIFICATION: 모순 — A: <한쪽 표현> / B: <다른쪽 표현>, 어느 쪽이 정답?]` 마커.

## 3. 범위 검사

다음 신호가 있으면 범위 분해 필요:
- 수용 기준이 2개 이상의 *독립적* 기능 영역을 포함 (예: "로그인" + "결제")
- "무엇을 만들 것인가"에 "그리고", "또한", "추가로" 같은 접속사가 다중 등장
- `scope.include`가 5개 이상의 서로 다른 최상위 디렉터리를 포함

발견 시: 단계 3에서 사용자가 이미 "단일 강행"을 확인하여 SPEC "위험" 섹션에 기록되어 있으면 통과. 새로 발견된 신호면 `[NEEDS CLARIFICATION: 다중 영역 가능성 — 영역 A: <...>, 영역 B: <...>, 분해 vs 단일 강행?]` 마커.

추가 항목 — **test 코드 변경 sweep 화이트리스트 검사**:
- task scope가 test 코드 변경 (rename·cleanup·삭제·내용 수정 등)을 포함하면 SPEC frontmatter `test_sweep_paths` 필드가 비어 있지 않거나, §5.1 절차를 거쳐 no-sweep으로 결정됐다는 명시 흔적이 frontmatter에 남아 있어야 한다.
- 신호 (하나라도 해당): `scope.include` 또는 본문 "범위.포함" 항목 중 어느 하나가 `tests/**`·`test/**`·`__tests__/**`·`spec/**`·`*_test.*`·`*.test.*`·`*_spec.*` 같은 test 경로 패턴 매칭, "무엇을 만들 것인가"·"위험"·"제약" 본문에 "테스트 rename"·"tests 정리"·"test cleanup"·"스펙 삭제" 같은 어구 등장.
- 위 신호가 있고 다음 두 흔적이 **모두** 부재하면 — step 5.1 자동 판단·yes/no 단발 확인 절차가 누락됐다는 신호로 판정한다:
  - frontmatter `test_sweep_paths` 키 (비어 있지 않은 list)
  - frontmatter YAML 주석 `# test_sweep_paths: reviewed-no-sweep` (§5.1 변경 없음/no 응답 흔적)
- 발견 시 (둘 다 부재): `[NEEDS CLARIFICATION: test 코드 변경 sweep 화이트리스트 누락 — step 5.1 절차에서 test_sweep_paths를 추출·확정했나? 비워 두면 loop 단계의 weakening 게이트가 합법적 sweep을 "테스트 약화"로 오인할 수 있음.]` 마커.
- 둘 중 하나라도 존재하면 통과 — `reviewed-no-sweep` 주석은 "사용자가 no 응답·모델이 변경 없음 판단"을 self-review와 구분하기 위한 명시 표식이므로, 부재만으로 절차 누락을 단정하면 거짓 양성(no 응답을 반복 마커로 오인)이 발생한다.

## 4. 모호성 검사

다음 어휘는 모호 신호:
- "적절한", "충분한", "합리적인", "필요한 만큼" — *얼마나*가 안 정해짐
- "유저 친화적", "직관적", "심플하게" — 측정 불가
- "또는 비슷한", "등등", "기타" — 열거 미완

발견 시: 구체화 (수치·기준·예시) 또는 `[NEEDS CLARIFICATION: <구체 질문>]`.

## 5. EARS fail-가능성 검사

각 수용 기준에 대해:
- EARS 5패턴 중 하나에 맞는가? 안 맞으면 변환 시도 (`references/ears-patterns.md` 변환 가이드).
- verify 명령 안에서 *원리적으로* fail 가능한가? (실제 테스트 작성은 loop의 일이지만, 검증 가능성은 spec 단계에서 확인.)

불가능하면 `[NEEDS CLARIFICATION: 검증 가능한 형태로 재작성 — 어떤 fail 시나리오?]`.

### 자유 텍스트 → EARS 변환 가이드 (작성 언어별)

자체 검토 단계에서 자유 텍스트가 발견되면 `references/ears-patterns.md` 변환 가이드를
적용한다. 작성 언어는 SPEC frontmatter `ears_language`를 따른다(미명시 시 `ko`).

ko EARS 패턴 예시 (Event-driven):
- 자유 텍스트: "사용자가 빈 비밀번호를 제출하면 400으로 거부함"
- ko 변환: 사용자가 빈 비밀번호를 제출할 때, 시스템은 400으로 요청을 거부한다.

다른 모드(en·hybrid)와 5패턴 전체 예시는 `references/ears-patterns.md`의
"EARS 작성 언어"·"5개 패턴" 절을 단일 출처로 참조한다.

## 검토 출력 형식

자체 검토 후 사용자에게:
- 0개 발견: "자체 검토 통과. 사용자 최종 검토로 진행합니다."
- 1개 이상: "자체 검토에서 N개 항목 인라인 수정·N개 마커 박음. 변경된 SPEC.md를 사용자 최종 검토하세요."
