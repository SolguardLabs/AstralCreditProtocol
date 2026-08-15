$ErrorActionPreference = "Stop"
Set-Location (Resolve-Path "$PSScriptRoot\..")

$forge = Get-Command forge -ErrorAction SilentlyContinue
if (-not $forge) { $forge = Get-Command forge.exe -ErrorAction SilentlyContinue }
if (-not $forge) { throw "forge executable not found" }

if (-not (Test-Path "lib\forge-std")) {
    & $forge.Source install foundry-rs/forge-std@v1.16.2 --no-git --shallow
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

& $forge.Source fmt --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $forge.Source build
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$env:FOUNDRY_PROFILE = "ci"
& $forge.Source test
$forgeExit = $LASTEXITCODE
Remove-Item Env:FOUNDRY_PROFILE
if ($forgeExit -ne 0) { exit $forgeExit }

npm ci --ignore-scripts
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
npm test
exit $LASTEXITCODE
