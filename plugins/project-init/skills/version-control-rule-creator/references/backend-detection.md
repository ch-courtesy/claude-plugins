# 백엔드 판별 절차 (단일 출처)

SKILL.md 생성 절차의 "백엔드 판별" 스텝이 가리키는 상세 규칙. 후보 확정 전 **1회** 판별하고, git 계열 동반 산출 판정과 백엔드 변형 본문 선택에서 **재사용**하며 재판별하지 않는다.

## 입력 읽기

- origin URL은 `git remote get-url origin`(또는 `git config --get remote.origin.url`)으로 읽는다.
- https 양식(`https://host/owner/repo.git`)과 ssh 양식(`git@host:owner/repo.git`·`ssh://git@host/owner/repo.git`) **모두**에서 호스트를 추출한다.
- **origin이 설정되어 있지 않으면**: 어떤 룰 파일도 생성하지 않고, origin remote를 먼저 설정하라고 안내한 뒤 종료한다.
- 후보 중 어떤 sub-룰도 백엔드 정보를 필요로 하지 않으면 이 절차를 건너뛴다.

## (a) 공식 도메인 정밀 매칭 — 네트워크 호출 없음

추출한 호스트가 아래 공식 도메인 집합에 **정밀히 일치**하면 호스트명만으로 백엔드를 판별하고 probe를 생략한다.

- GitHub: `github.com`, 그리고 `*.github.com`·`*.ghe.com`·`*.githubenterprise.com`에 대한 서브도메인.
- GitLab: `gitlab.com`, 그리고 `*.gitlab.com`에 대한 서브도메인.

정밀 매칭은 **라벨 경계**로 판단한다 — 호스트가 그 도메인과 같거나 그 도메인을 온전한 접미사 라벨로 끝낼 때만 일치다(`host == d` 또는 `host`가 `.d`로 끝남). `github.com.evil.test`·`mygithub.com`처럼 문자열만 포함하는 경우는 일치가 아니다. **호스트명 substring 매칭은 쓰지 않는다**(`github-mirror.*`·`mygithub.com` 류 오판별 방지).

## (b) self-hosted read-only API probe — 공식 도메인이 아닐 때만

호스트가 (a)에 해당하지 않으면, 그 호스트에 대해 **부작용 없는 read-only(GET류) API probe**로 백엔드를 식별한다. 상태를 바꾸는 요청은 보내지 않는다.

- 잘 알려진 백엔드 식별 엔드포인트의 **상태코드·응답 헤더·본문 마커** 조합으로 github/gitlab을 판별한다(예: GitLab은 `/api/v4/` 계열 응답·헤더, GitHub Enterprise는 `/api/v3` 계열 응답·헤더).
- probe는 best-effort다. **timeout·도달 불가·인증요구(401/403)·식별 마커 부재는 모두 inconclusive**로 처리한다.

## 판별 실패 시 중단 — 추측 금지

(a) 정밀 매칭에도 해당하지 않고 (b) probe로도 백엔드를 확정하지 못하면(inconclusive 포함), 감지된 호스트와 지원 백엔드 목록(github·gitlab)을 안내하고 어떤 룰 파일도 생성하지 않고 종료한다. 추측해서 생성하지 않는다.

## git 계열 분류

판별된 백엔드를 git 계열로 분류하는 **정적 매핑**만 둔다: `github`·`gitlab`은 git 계열이다. 이 정적 매핑이 git 계열 분류의 단일 출처이며, 매핑에 없는 백엔드의 기본값은 **"git 계열 아님"**이다. 향후 비-git 백엔드는 이 매핑에 넣지 않는 것만으로 동반 산출에서 자연히 빠진다. 분류 판정은 `references/template_tools.py git-family <backend>`로 고정한다.
