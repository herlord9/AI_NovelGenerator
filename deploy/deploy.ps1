# Full deploy: backend then frontend (flask/blog style)
$ErrorActionPreference = "Stop"
& "$PSScriptRoot\deploy-backend.ps1"
& "$PSScriptRoot\deploy-frontend.ps1"
