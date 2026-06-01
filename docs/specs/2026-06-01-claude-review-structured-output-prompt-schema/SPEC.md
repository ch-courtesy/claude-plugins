---
scope:
  include:
    - .github/workflows/claude-review.yml
    - tests/claude/test-claude-review-workflow.sh
    - .github/prompts/claude-pr-review.ko.md
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
ears_language: ko
---

# claude-review structured output을 prompt schema + 결과 텍스트 파싱으로 안정화

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
Claude PR 리뷰 워크플로가 모든 PR에서 구조화 결과를 신뢰성 있게 얻도록 결과 획득 방식을 바꾼다. 현재는 모델 호출 액션의 강제 구조화 출력 채널(`--json-schema` → `structured_output`)에 의존하는데, 공유 리뷰 스키마가 복잡해 모델이 구조화 출력 도구를 호출하지 않고 텍스트로 한 번에 응답을 끝내는 경우가 잦고, 그러면 액션이 "구조화 출력이 없다"며 스텝을 오류 종료시켜 이후 게시 단계가 전부 막힌다. 대신 공유 스키마를 프롬프트 본문으로 모델에 전달해 스키마에 맞는 JSON만 출력하도록 지시하고, 워크플로가 모델의 결과 텍스트에서 JSON을 추출해 결과 파일로 저장한 뒤 유효성과 핵심 필드 존재를 확인하는 방식으로 전환한다. 1차 리뷰와 추가 컨텍스트 2차 리뷰 모두 동일 방식을 쓴다. 결과 파일을 소비하는 후속 게시 단계(정식 리뷰 verdict 제출·관리형 PR 코멘트)와 그 동작, 그리고 Codex 리뷰 워크플로·공유 자산은 그대로 둔다.

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면)과 언어 규칙은 references/ears-patterns.md. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->
- PR 리뷰가 트리거되어 Claude 리뷰가 실행될 때, 모델은 공유 리뷰 스키마를 프롬프트로 전달받아 그 스키마에 맞는 JSON 객체를 산출하며, 워크플로는 모델 호출 액션의 강제 구조화 출력 채널(`--json-schema`/`structured_output`)에 의존하지 않는다.
- Claude 리뷰가 실행되어 모델이 응답을 반환하면, 워크플로는 모델의 결과 텍스트에서 JSON을 추출하고(코드펜스 등 비-JSON 래핑 제거) 결과 파일로 저장한다.
- 결과 파일을 저장한 뒤, 워크플로는 그 파일이 유효한 JSON이고 후속 게시 단계가 사용하는 핵심 필드(verdict·eligibility·findings 및 automation_safety·reviewed_context)를 포함함을 확인한다.
- 모델 응답에서 유효한 JSON을 추출하지 못하거나 핵심 필드가 없으면, 워크플로는 그 사실을 알리는 명확한 오류로 실패한다.
- 모델이 구조화 출력 도구를 호출하지 않고 텍스트로만 응답하더라도, 워크플로는 더 이상 "구조화 출력이 반환되지 않았다"는 사유로 모델 호출 스텝을 오류 종료시키지 않고 결과를 정상 처리한다.
- 모델이 추가 컨텍스트(needs_context)를 요청하는 2차 리뷰 흐름에서도, 스키마를 프롬프트로 전달하고 결과 텍스트에서 JSON을 추출하는 동일 방식이 적용된다.
- 항상, 결과 파일을 소비하는 후속 게시 단계(정식 리뷰 verdict 제출, 관리형 PR 코멘트 생성·갱신)의 동작은 변경되지 않는다.
- 항상, Codex 리뷰 워크플로(`.github/workflows/codex-review.yml`)와 공유 리뷰 컨텍스트 수집 스크립트, 공유 리뷰 스키마는 변경되지 않는다.
- 워크플로 contract 테스트가 새 방식을 검증하도록 갱신된다 — 스키마를 프롬프트로 전달함·결과 텍스트에서 JSON 추출·핵심 필드 확인의 존재를 단언하고, `--json-schema`/`structured_output` 의존의 부재를 단언하며, 전체 테스트가 통과한다.

## 범위
포함:
- `.github/workflows/claude-review.yml` 수정 — 모델 호출에서 강제 구조화 출력 채널 의존을 제거하고, 프롬프트에 공유 스키마를 실어 JSON-only 출력을 지시하며, 결과 텍스트에서 JSON을 추출·저장·검증(유효성 + 핵심 필드)하도록 1차/2차 리뷰 단계를 전환.
- `tests/claude/test-claude-review-workflow.sh` 갱신 — 새 방식 단언으로 전환(프롬프트 스키마 전달·텍스트 JSON 추출·핵심 필드 확인 존재; `--json-schema`/`structured_output` 의존 부재).
- `.github/prompts/claude-pr-review.ko.md` — 필요한 경우 JSON-only 출력 지시·스키마 준수 문구 보강(Claude 전용 프롬프트).

비-목표 / 제외:
- 후속 게시 단계(verdict 제출·관리형 코멘트)의 게이팅·문구·동작 변경.
- `.github/workflows/codex-review.yml` 변경.
- `.github/scripts/pr-review-context.sh`·`.github/prompts/codex-pr-review.schema.json`(공유 스키마)·`.github/prompts/codex-pr-review.ko.md` 변경.
- 공유 스키마 자체의 단순화(공유 자산이므로 손대지 않는다).

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- 모델 결과 텍스트는 모델 호출 액션이 남기는 실행 로그(execution_file)의 최종 결과 메시지에서 얻는다 — 강제 구조화 출력(`structured_output`) 채널에 의존하지 않는다.
- 프롬프트에는 공유 스키마(`.github/prompts/codex-pr-review.schema.json`) 내용을 실어 전달하고, "스키마에 맞는 JSON 객체만 출력하고 코드펜스·산문을 붙이지 말 것"을 명시한다. JSON 추출 시 혹시 모를 코드펜스/선행·후행 산문을 제거한다.
- 핵심 필드 확인은 jq 유효성 + 후속 게시 스텝이 실제로 읽는 필드(verdict·eligibility·findings·automation_safety·reviewed_context)의 존재 확인 수준으로 한다(전체 JSON Schema 강제 검증은 하지 않는다 — 미세한 스키마 어긋남으로 매번 실패하는 위험 회피).
- 기존 보안 불변식(체크아웃 자격증명 제거, PR 본문 미주입, untrusted 컨텍스트 표시, 액션 SHA 고정)은 유지한다.

## 위험 (있을 때만)
- 강제 구조화 출력을 떼면 모델이 드물게 비-JSON 산문이나 코드펜스로 감싼 출력을 낼 수 있다. — 코드펜스 제거 + jq 유효성/핵심 필드 확인으로 방어하고, 실패 시 명확한 오류로 떨어뜨린다.
- 전체 스키마 강제 검증을 하지 않으므로 스키마의 비핵심 필드 누락은 통과할 수 있다. — 후속 게시 스텝이 읽는 핵심 필드만 보장하면 게시 동작은 깨지지 않으므로 수용한다(사용자 선택: jq 유효성 + 핵심 필드 확인).
- 결과 텍스트 추출이 액션의 실행 로그(execution_file) 형식에 의존한다. — 고정한 액션 SHA 기준으로 형식을 확인하고, 액션 버전 갱신 시 재검증한다.
