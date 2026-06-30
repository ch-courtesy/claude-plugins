---
label: 버전 관리 (versioning)
description: 버전 규약·단일 출처·워치 디렉토리를 한 문서로 정의하고, 기본 브랜치 머지에 버전업을 강제합니다.
recommended: true
inputs:
  - name: scheme
    header: "버전 규약"
    question: "이 프로젝트가 따를 버전 규약은? (자유 입력은 'Other'로 직접 입력하세요)"
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
dynamic_inputs:
  - name: watch_directories
    header: "워치 디렉토리"
    question: "변경이 발생하면 반드시 버전이 올라가야 하는 디렉토리는? (다중 선택 가능, 'Other'로 자유 입력 가능)"
    multi_select: true
    candidate_source: depth1_dirs_filtered
    free_input: true
    render: bullet_list
---

# 버전 관리 지침

릴리스 버전 번호, 단일 출처, 버전업 강제 대상을 정하는 규칙입니다. 같은 산출물에 두 버전이 노출되지 않게 합니다.

## 버전 규약

이 프로젝트는 **{{scheme}}** 를 따릅니다.

프로젝트 사정에 맞지 않으면 이 값을 직접 수정해 고유 정책을 정의하세요.

- 새 버전의 자리 올림은 위 규약을 따릅니다. 자체 변형은 명시적으로 기록합니다.
- 호환성 깨짐은 규약상 큰 자리(예: SemVer MAJOR)를 올리는 릴리스에만 묶습니다.

## 버전의 단일 출처 (Source of Truth, SoT)

이 프로젝트의 버전 SoT는 **{{source_of_truth}}** 입니다.

- 코드·문서·CI·배포 산출물의 버전 값은 모두 SoT에서 파생합니다.
- 버전 증가는 SoT 갱신 commit으로 시작합니다. 파생 위치는 파이프라인 또는 명시적 동기화 스크립트로 갱신합니다.

## 워치 디렉토리 (watch directories)

이 프로젝트에서 **변경이 발생하면 반드시 버전이 올라가야 하는 디렉토리**는 다음과 같습니다:

{{watch_directories}}

- 위 목록에 변경이 머지되면 같은 머지 안에서 SoT를 갱신합니다.
- 빌드 산출물(`dist/`·`build/`·`target/`), 종속성 캐시(`node_modules/`), 숨김 디렉토리(`.*`)는 워치 대상이 아닙니다.
- 자동 후보가 틀리면 목록을 직접 수정합니다.

## 머지 강제 (필수 규칙)

**기본 브랜치 머지에서 워치 디렉토리가 바뀌면 같은 머지 안에서 버전이 올라가야 한다.**

- "다음 릴리스에 묶기"·"hotfix 예외"는 위반입니다. 예외가 필요하면 먼저 이 룰을 갱신합니다.
- PR 머지 차단, hotfix, 경고 등 대응 정책과 자동 감지(CI·hook·PR check)는 별도로 정합니다.
- 워치 디렉토리 변경 여부는 머지 대상 diff의 파일 경로로 판정합니다. 공백·줄바꿈도 변경으로 셉니다.

## 릴리스 절차 (요지)

1. **버전 자리 결정** — 머지된 변경을 규약에 따라 분류하고 다음 버전을 정합니다.
2. **SoT 갱신** — 단일 출처를 새 버전으로 갱신합니다.
3. **tag·릴리스** — 새 버전 tag·release를 만듭니다. SoT가 tag이면 이 단계가 SoT 갱신입니다.
4. **배포 산출물 게시** — 빌드·배포가 SoT를 읽어 같은 버전으로 게시합니다.

## 위반 발견 시

두 버전 노출, 워치 디렉토리 변경의 버전업 누락을 발견하면 즉시 멈추고 SoT를 정상화합니다. 다음 릴리스로 미루지 않습니다.
