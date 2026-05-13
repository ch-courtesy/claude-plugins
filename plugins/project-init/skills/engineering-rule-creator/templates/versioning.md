---
label: 버전 관리 (versioning)
description: 릴리스 버전 규약과 변경 기록 위치 — 사용자 입력으로 핵심 항목을 채웁니다.
recommended: true
inputs:
  - name: scheme
    header: "버전 규약"
    question: "이 프로젝트가 따를 버전 규약은?"
    options:
      - label: "SemVer (MAJOR.MINOR.PATCH)"
        description: "공개 API를 가진 라이브러리·SDK·플러그인의 표준"
      - label: "CalVer (YYYY.MM.PATCH)"
        description: "릴리스 주기가 시간 기반인 애플리케이션·서비스"
      - label: "ZeroVer (0.x.y)"
        description: "공개 API가 아직 안정되지 않은 초기 단계"
  - name: source_of_truth
    header: "버전 SoT"
    question: "버전 값의 단일 출처(Source of Truth)는 어디인가?"
    options:
      - label: "매니페스트 파일"
        description: "package.json·pyproject.toml·plugin.json 등 패키지 매니페스트"
        value: "패키지 매니페스트 (예: package.json·pyproject.toml·plugin.json)"
      - label: "git tag"
        description: "tag가 SoT, 매니페스트는 빌드 시 주입"
        value: "git tag (매니페스트는 빌드 시 주입)"
      - label: "전용 파일"
        description: "VERSION·__version__.py·version.txt 등 단일 텍스트 파일"
        value: "전용 버전 파일 (예: VERSION·__version__.py·version.txt)"
  - name: changelog_location
    header: "변경 기록"
    question: "변경 기록(changelog)은 어디에 누적하는가?"
    options:
      - label: "CHANGELOG.md"
        description: "리포 루트의 단일 마크다운. Keep a Changelog 양식 권장"
        value: "리포 루트의 `CHANGELOG.md`"
      - label: "GitHub Releases"
        description: "release note 본문. 자동 생성 또는 수동 작성"
        value: "GitHub Releases note"
      - label: "분할 fragment"
        description: "릴리스 시 합쳐지는 fragment 파일(towncrier·changesets 등)"
        value: "릴리스 시 합쳐지는 fragment (예: towncrier·changesets)"
---

# 버전 관리 지침

릴리스 버전을 어떻게 번호 매기고, 어디에서 단일 출처로 관리하고, 변경 기록을 어떻게 누적하는지에 대한 규칙입니다. 동일한 산출물에 두 가지 다른 버전이 붙는 일을 막고, 사용자·다른 에이전트가 "지금이 어떤 버전인지"를 항상 한 곳에서 알 수 있게 합니다.

## 버전 규약

이 프로젝트는 **{{scheme}}** 를 따릅니다.

- 새 버전을 끊을 때마다 어떤 자리(자릿수)가 올라가는지는 위 규약의 정의를 그대로 따릅니다. 자체 변형(예: "MINOR를 두 자리로 끊는다")은 도입하지 않습니다.
- 호환성 깨짐을 동반하는 변경은 규약상 큰 자리(예: SemVer의 MAJOR)를 올리는 시점에만 묶습니다 — 작은 자리 릴리스에 호환성 깨짐을 끼워 넣지 않습니다.

## 버전의 단일 출처 (Source of Truth)

이 프로젝트의 버전 SoT는 **{{source_of_truth}}** 입니다.

- 코드·문서·CI·배포 산출물에 나타나는 버전 값은 모두 이 SoT에서 파생됩니다. 같은 산출물에 두 곳에서 손으로 적은 버전이 동시에 존재하지 않게 합니다.
- 버전 증가는 SoT를 먼저 갱신하는 commit으로 시작합니다. 파생 위치는 빌드·릴리스 파이프라인이 SoT를 읽어 갱신하거나, 명시적 동기화 스크립트를 commit에 포함합니다.

## 변경 기록 (Changelog)

이 프로젝트의 변경 기록은 **{{changelog_location}}** 에 누적합니다.

- 사용자 가시(behavior-changing) 변경은 릴리스 직전이 아니라 **변경이 머지될 때마다** 기록합니다. 릴리스 시점에 사후 정리하지 않습니다.
- 항목 분류는 최소한 다음을 구분합니다: 새 기능, 변경(호환), 변경(깨짐), 버그 수정, 보안. 분류 라벨은 위 변경 기록 위치의 관례를 따릅니다.
- 내부 리팩토링·빌드 설정처럼 사용자 가시 영향이 없는 변경은 변경 기록에 넣지 않습니다 — commit 히스토리로 충분합니다.

## 릴리스 절차 (요지)

1. **버전 자리 결정** — 머지된 변경을 위 규약에 따라 큰/작은/패치 자리로 분류하고 다음 버전 번호를 정합니다.
2. **SoT 갱신** — 위의 단일 출처를 새 버전 값으로 갱신하는 commit을 만듭니다.
3. **변경 기록 마무리** — 다음 버전 헤더 아래로 누적된 항목을 모읍니다 (또는 fragment를 합칩니다).
4. **tag·릴리스** — 새 버전에 해당하는 tag·release를 만듭니다. SoT가 tag인 경우 이 단계가 SoT 갱신 자체가 됩니다.
5. **배포 산출물 게시** — 빌드·배포가 SoT를 읽어 동일 버전으로 산출물을 게시합니다. 손으로 다른 버전 문자열을 끼워 넣지 않습니다.

## 위반 발견 시

같은 산출물에 두 다른 버전이 동시에 노출되거나, 변경 기록 없이 사용자 가시 변경이 머지된 사실을 인지·지적당하면, 즉시 작업을 멈추고 SoT·변경 기록을 정상화한 뒤 다음 단계로 넘어갑니다. "다음 릴리스에 묶어서 정리"하지 않습니다 — 다음 릴리스를 만드는 사람이 같은 잡음에 빠집니다.
