# pipecheck 6-target cross-compile; PowerShell twin of build.sh for Windows without bash. Output: dist/ (tracked in git - commit after refresh).
# ASCII only: Windows PowerShell 5.1 reads BOM-less files as ANSI.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
foreach ($t in 'darwin-arm64', 'darwin-amd64', 'linux-amd64', 'linux-arm64', 'windows-amd64', 'windows-arm64') {
  $goos, $goarch = $t -split '-'
  $ext = if ($goos -eq 'windows') { '.exe' } else { '' }
  $env:CGO_ENABLED = '0'; $env:GOOS = $goos; $env:GOARCH = $goarch
  go build -trimpath '-ldflags=-s -w' -o "dist/pipecheck-$t$ext" ./cmd/pipecheck
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  "built dist/pipecheck-$t$ext"
}
Remove-Item Env:GOOS, Env:GOARCH, Env:CGO_ENABLED
go test ./... > $null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
'TESTS OK'
Get-ChildItem dist | ForEach-Object { "$($_.Name) $($_.Length)" }
