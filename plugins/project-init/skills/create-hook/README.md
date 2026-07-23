# create-hook

소비 프로젝트에 Claude Code 훅(이벤트 핸들러 + `lib/<command>/` 기능 스크립트 +
settings 등록)을 인터뷰 기반으로 설계·작성하는 스킬. 표준·검사기의 단일 출처는
`../../shared/hook-standard/`이며, 작성 후 검사기로 BLOCKER·MAJOR 0 을 확인한다.

## 호출 예시

- "PreToolUse 훅 만들어줘 — 위험 명령을 막고 싶어"
- "세션 시작할 때 컨텍스트 주입하는 훅 추가해줘"
- "settings.json에 훅 등록해줘"

기존 훅의 수리·점검은 repair-hook 몫이다.
