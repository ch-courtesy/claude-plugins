#!/usr/bin/env bash
# pipecheck 6타깃 크로스컴파일. 산출물: dist/ (git 추적 — 갱신 후 커밋).
set -euo pipefail
cd "$(dirname "$0")"
for t in darwin-arm64 darwin-amd64 linux-amd64 linux-arm64 windows-amd64 windows-arm64; do
  goos=${t%-*} goarch=${t#*-} ext=""
  [ "$goos" = windows ] && ext=".exe"
  CGO_ENABLED=0 GOOS=$goos GOARCH=$goarch \
    go build -trimpath -ldflags="-s -w" -o "dist/pipecheck-$t$ext" ./cmd/pipecheck
  echo "built dist/pipecheck-$t$ext"
done
go test ./... > /dev/null && echo "TESTS OK"
ls -la dist/ | awk 'NR>1 {print $NF, $5}'
