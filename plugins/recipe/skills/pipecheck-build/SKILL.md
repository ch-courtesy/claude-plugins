---
name: pipecheck-build
description: recipe 플러그인의 pipecheck Go 바이너리를 6타깃(darwin·linux·windows × amd64·arm64)으로 다시 빌드하고 테스트·dist 변경을 보고한다. Go가 없으면 OS별 설치까지 안내·실행한다. pipecheck 소스(tools/pipecheck의 cmd·internal·go.mod)를 고친 뒤 커밋 전에 dist를 갱신할 때, dist에 현재 플랫폼 바이너리가 없거나 깨졌을 때, "pipecheck 빌드", "pipecheck 다시 빌드", "dist 갱신", "build.sh 돌려 줘", "pipecheck 바이너리 못 찾음", "pipecheck 빌드 환경 구성" 같은 요청에서 사용한다. macOS·Linux·Windows(PowerShell·Git Bash)에서 동작한다.
allowed-tools:
  - AskUserQuestion
  - Read
  - Bash(bash:*)
  - Bash(go:*)
  - Bash(git:*)
  - Bash(uname:*)
  - Bash(brew:*)
  - Bash(winget:*)
  - Bash(curl:*)
  - Bash(tar:*)
  - Bash(powershell:*)
  - Bash(pwsh:*)
---

# pipecheck-build

`<이 SKILL.md가 있는 디렉터리>/../../tools/pipecheck`(이하 `PC`)의 빌드 스크립트로 `dist/`의 6타깃 바이너리를 다시 만들고, 테스트 결과와 dist 변경을 보고한다. 커밋하지 않는다.

## 절차

### 1. 실행 경로 결정

명령을 셸에 맞게 고르기 위해 실행 환경을 다음 둘 중 하나로 정한다.

- **bash 경로**: macOS·Linux, 또는 Windows의 Git Bash(MINGW·MSYS·Cygwin). 빌드 스크립트는 `PC/build.sh`.
- **PowerShell 경로**: bash가 없는 Windows. 빌드 스크립트는 `PC/build.ps1`.

bash 경로의 Windows에서는 bash가 CRLF 줄 끝을 `$'\r': command not found`로 실패시키기 때문에 `build.sh`에 CR이 섞였는지(`grep -c $'\r' build.sh`) 확인하고, 있으면 PowerShell 경로로 바꾼다.

### 2. Go 환경 구성

`PC`에서 `go version`을 실행한다. 성공하면 3단계로 간다. Go 1.21 이상은 `go.mod`의 `go` 지시어 버전 툴체인을 스스로 내려받기 때문에 설치 버전이 낮아도 이 명령이 성공하면 그대로 쓴다.

`go`가 없거나, 툴체인 다운로드 실패가 아닌 이유로 `go version`이 실패하면 설치한다. 시스템을 바꾸는 작업이므로 아래 표에서 OS에 맞는 설치 명령을 그대로 보여 주고 구조화된 사용자 질문 기능으로 승인을 받은 뒤에만 실행한다. 거절되면 필요한 버전(`PC/go.mod`의 `go` 지시어)과 설치 명령을 보고하고 끝낸다.

| OS | 설치 명령 | 현재 세션 PATH 반영 |
|---|---|---|
| macOS | `brew install go` | 불필요 |
| Windows | `winget install --id GoLang.Go -e --accept-source-agreements --accept-package-agreements` | bash: `export PATH="/c/Program Files/Go/bin:$PATH"` · PowerShell: `$env:Path = "C:\Program Files\Go\bin;$env:Path"` |
| Linux | `curl -fsSL https://go.dev/dl/go<버전>.linux-<arch>.tar.gz \| tar -C "$HOME/.local" -xz` | `export PATH="$HOME/.local/go/bin:$PATH"` |

- macOS에서 `brew`가 없으면 Homebrew 설치는 범위 밖이므로 https://go.dev/dl 의 `.pkg` 설치를 안내하고 끝낸다.
- Windows에서 `winget`이 없으면 https://go.dev/dl 의 `.msi` 설치를 안내하고 끝낸다.
- Linux는 배포판 패키지가 `go.mod` 요구 버전보다 낮은 경우가 많고 sudo가 필요하기 때문에 공식 tarball을 사용자 홈에 푼다. `<버전>`은 `PC/go.mod`의 `go` 지시어 값, `<arch>`는 `uname -m`의 `x86_64`→`amd64`, `aarch64`→`arm64`로 쓴다. 이전 버전 위에 풀면 파일이 섞이기 때문에 `$HOME/.local/go`가 이미 있으면 그 삭제(`rm -rf "$HOME/.local/go"`)를 같은 승인 화면에 포함한다.

설치 뒤 표의 PATH 반영을 이 세션의 이후 명령마다 앞에 붙이고 `go version`으로 다시 확인한다. 셸 시작 파일(`~/.zshrc`·`~/.bashrc`·Windows 사용자 PATH)은 사용자 파일이므로 고치지 않고, 영구 반영에 필요한 줄만 보고에 적는다.

### 3. 빌드

- bash 경로: `bash "<PC>/build.sh"`
- PowerShell 경로: `powershell -NoProfile -ExecutionPolicy Bypass -File "<PC>\build.ps1"` (`pwsh`가 있으면 `pwsh`로 같은 인자)

`built dist/pipecheck-<타깃>` 6줄과 `TESTS OK`가 나오면 성공이다.

실패하면 출력에서 실패 타깃과 오류 줄을 보고한다. 6줄이 다 나오고 `TESTS OK`가 없으면 빌드 스크립트가 테스트 출력을 버리기 때문에 `PC`에서 `go test ./...`를 다시 실행해 실패 테스트 이름과 메시지를 보고한다.

### 4. 현재 플랫폼 바이너리 확인

빌드 산출물이 실제로 실행되는지 보기 위해 현재 플랫폼 바이너리를 인자 없이 실행한다. 사용법 한 줄(`usage: pipecheck <check-expr|...>`)과 exit 2가 정상이다.

bash 경로:

```bash
OS=$(uname -s | tr A-Z a-z); EXT=""
case "$OS" in mingw*|msys*|cygwin*) OS=windows; EXT=".exe" ;; esac
BIN="<PC>/dist/pipecheck-$OS-$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')$EXT"
"$BIN"; echo "exit=$?"
```

PowerShell 경로:

```powershell
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
& "<PC>\dist\pipecheck-windows-$arch.exe"; "exit=$LASTEXITCODE"
```

### 5. 보고

커밋 판단을 사용자에게 넘기기 위해 다음을 보고한다.

- 2단계 `go version` 출력, 설치했다면 실행한 설치 명령과 영구 PATH 반영에 필요한 줄
- 6타깃 빌드·테스트 결과
- `git status --short -- <PC>/dist` 결과 — 바뀐 바이너리 목록. 빌드 환경이 달라도 소스 변경 없이 바이트가 바뀌므로, 소스 변경 없이 dist만 바뀌었으면 그 사실을 함께 적는다
- 4단계 실행 결과
