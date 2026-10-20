$ErrorActionPreference = "Stop"
$bash = $null
$candidates = @(
    "C:\Program Files\Git\bin\bash.exe",
    "C:\Program Files (x86)\Git\bin\bash.exe"
)
foreach ($c in $candidates) {
    if (Test-Path $c) { $bash = $c; break }
}
if (-not $bash) {
    $cmd = Get-Command bash -ErrorAction SilentlyContinue
    if ($cmd) { $bash = $cmd.Source }
}
if (-not $bash) {
    throw "Need Git Bash. Or run: bash deploy/deploy_frontend.sh"
}
& $bash "$PSScriptRoot/deploy_frontend.sh" @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
