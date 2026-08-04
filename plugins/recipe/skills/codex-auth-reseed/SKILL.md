---
name: codex-auth-reseed
description: Codex PR 리뷰 CI(codex-review.yml)가 인증 문제로 깨질 때 CODEX_AUTH_JSON 시크릿을 격리 재시드한다. 다음 신호에서 사용 — 워크플로 로그에 refresh_token_reused / token_expired / 401 Unauthorized / "Your refresh token has already been used" / codex_login::auth 오류; review 잡이 인증으로 실패·skip; Codex 리뷰가 계속 UNSTABLE·실패; "Codex 리뷰 토큰 만료", "CODEX_AUTH_JSON 재시드", "codex 인증 시크릿 갱신", "Codex 리뷰가 401로 실패" 같은 요청. 대화형 브라우저 device-auth 로그인이 필요하므로 완전 무인 실행에는 쓰지 않는다.
allowed-tools:
  - AskUserQuestion
  - Read
  - Bash(bash:*)
  - Bash(gh:*)
---

# codex-auth-reseed

임시 격리 `CODEX_HOME` 디렉터리에서 새 Codex 인증 토큰을 발급받아 GitHub Actions 시크릿을 갱신한다. host `~/.codex` 시드는 건드리지 않는다.

## 배경 (왜 재시드가 필요한가)

Codex(ChatGPT) 인증은 **1회용 회전 리프레시 토큰**이다 — 리프레시할 때마다 새 토큰이 발급되고 직전 것은 즉시 무효화된다. CI의 `auth-refresh` 잡, 매트릭스 `review` 잡, 그리고 같은 계정을 쓰는 다른 소비자(예: 로컬 머신)가 단일 토큰을 두고 경쟁하면 시크릿의 토큰이 **소진·desync**되어 `refresh_token_reused`·`token_expired`로 리뷰가 실패한다. 재실행으로는 안 풀리고 **새 로그인으로 재시드**해야 한다.

격리가 필요한 이유: 그냥 `codex login`을 돌리면 host의 `~/.codex/auth.json`(다른 소비자가 쓰는 시드)을 덮어써 그 토큰까지 회전시킨다. codex는 인증 상태를 `$CODEX_HOME` 아래에만 쓰므로, 임시 디렉터리를 `CODEX_HOME`으로 지정하면 host 시드를 무접촉으로 둔 채 CI용 토큰만 새로 만든다.

## 절차

### 1. 전제 확인

`codex`(없으면 `npx`로 일회 실행)·`gh`(secrets 쓰기 권한으로 인증됨)·`jq`가 필요하다. 대상 repo와 시크릿 이름을 정한다(기본: 현재 gh repo, `CODEX_AUTH_JSON`). 다르면 `RESEED_REPO=owner/name`·`RESEED_SECRET=<이름>`으로 지정한다.

**대상 repo 검증 필수**: 기본값(현재 repo)을 쓰기 전에 그 repo에 `codex-review.yml`이 실제로 있는지 확인한다(`gh api repos/<owner>/<repo>/actions/workflows --jq '.workflows[].path' | grep -i codex`). 없으면 워크플로가 있는 repo를 찾아 `RESEED_REPO`로 지정한다 — 현재 repo에 시크릿을 넣어봤자 아무도 안 쓰고, 발급된 토큰은 시크릿에서 되읽을 수 없어 인증을 처음부터 다시 해야 한다.

### 2. 격리 CODEX_HOME 생성 + device-auth 시작

`references/reseed.sh setup`을 실행한다. 이 스크립트가 결정적으로 수행한다 — 소유자 전용(umask 077) 임시 디렉터리를 격리 `CODEX_HOME`으로 생성하고(host `~/.codex` 무접촉), 그 안에서 `codex login --device-auth`를 백그라운드로 시작한다(codex 미설치면 `npx -y @openai/codex`로 일회 실행). 출력된 **인증 URL과 일회용 코드**를 사용자에게 그대로 전달한다.

### 3. 사용자 인증 (대화형 게이트)

사용자에게 안내한다 — 브라우저에서 URL을 열고, 코드를 입력하고, **CI Codex 리뷰에 쓸 그 ChatGPT 계정**(기존 시크릿을 시드했던 것과 동일)으로 로그인. 코드는 약 15분 후 만료된다. 어느 계정을 쓸지 모호하면 구조화된 사용자 질문 기능으로 확인한다.

### 4. 완료 — 시크릿 갱신 + 정리

`references/reseed.sh complete`를 실행한다(인증 완료까지 폴링하므로 백그라운드 실행 권장). setup 에 `RESEED_REPO`를 줬다면 complete 에도 동일하게 준다. 스크립트가 auth.json을 검증(토큰 값 미출력)하고 `gh secret set`으로 시크릿을 갱신한 뒤 격리 디렉터리를 파기한다. `SECRET_UPDATED_OK`가 성공 신호다. complete는 성공·실패 모두 EXIT 트랩으로 토큰 파일을 shred하고 격리 디렉터리를 파기하므로, 실패·만료 시 별도 정리 없이 2단계부터 재시도한다(`abort`는 complete 진입 전 중도 취소용).

### 5. 검증

Codex 리뷰 워크플로를 재실행해(`gh run rerun <run-id>` 또는 새 커밋/재리뷰 트리거) `auth-refresh`·`review`·`merge` 잡이 모두 통과하는지 확인한다. 토큰 소진이 반복되면 근본은 CI 설계(1회용 토큰 레이스·되쓰기 실패 연쇄)이므로 워크플로 수정을 검토한다.

## 규칙

- 사용자에게 선택·승인·해명을 요청할 때는 현재 런타임의 구조화된 사용자 질문 기능을 우선 사용한다. 사용할 수 없으면 동일 선택지를 간결한 직접 질문으로 제시한다.
- 토큰 값(auth.json 내용·access/refresh token)을 stdout·로그·PR에 출력하지 않는다. 스크립트는 umask 077 격리 디렉터리 안에서만 다루고 완료 후 shred한다.
- host `~/.codex/auth.json`을 읽거나 수정하지 않는다(다른 소비자 시드 보호) — 격리 `CODEX_HOME` 밖의 codex 상태를 건드리지 않는다.
- 무인 실행에는 쓰지 않는다 — 3단계 device-auth는 사람 인증이 필수다.

## references

| 파일 | 용도 | 읽는 시점 |
|------|------|-----------|
| `references/reseed.sh` | 격리 재시드 결정적 실행(setup/complete/status/abort) | 2·4단계 실행 시 |
