---
name: security-rule-creator
description: 현재 프로젝트에 맞는 보안 지침을 `rules/security.md`로 생성하거나 갱신할 때 활성화됩니다. project-init 초기화 흐름 중 호출되거나, 사용자가 보안 지침을 새로 만들고 싶어 할 때.
---

# security-rule-creator

현재 프로젝트에 맞는 보안 지침 문서를 `rules/security.md`에 생성·갱신합니다.

## 생성 절차

1. **프로젝트 스캔** — 보안 맥락을 파악합니다.
   - 인증·세션 관련 코드 존재 여부.
   - `.env*`, 시크릿 매니저 사용(`sops`, Vault, AWS Secrets Manager 힌트).
   - 외부 API 호출 패턴, 데이터베이스 접근 계층.
   - 로깅 구성과 PII 취급 여부.
2. **내용 구성**
   - 같은 디렉토리의 `security.md` 전체를 기본 내용으로 사용합니다.
   - 프로젝트 고유의 비밀 저장소, 인증 방식, 로깅 마스킹 규칙, 컴플라이언스 요구사항을 "## 이 프로젝트의 세부 지침"에 추가합니다.
3. **파일 기록**
   - 대상: `rules/security.md`
   - 상위 디렉토리 부재 시 함께 생성.
   - 이미 존재하면 덮어쓰지 않고 diff 후 사용자에게 확인.
