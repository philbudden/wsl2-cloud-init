$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$setup = Join-Path $repoRoot 'setup.ps1'
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wsl-cloud-init-tests-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Get-LinuxScriptBytes([string]$Path) {
    $scriptText = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($Path))
    Write-Output -NoEnumerate ([System.Text.UTF8Encoding]::new($false).GetBytes(($scriptText -replace "`r`n?", "`n")))
}

function Invoke-Setup([string]$Username, [string]$Path, [switch]$Force, [string[]]$Registered) {
    & $setup -LinuxUsername $Username -OutputPath $Path -SkipWslPreflight -TestRegisteredDistributions $Registered -Force:$Force
}

try {
    $output = Join-Path $temporaryRoot 'Ubuntu-24.04.user-data'
    Invoke-Setup -Username 'engineer_1' -Path $output
    Assert-True (Test-Path -LiteralPath $output -PathType Leaf) 'Renderer did not create output.'
    $bytes = [System.IO.File]::ReadAllBytes($output)
    Assert-True (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) 'Output has a UTF-8 BOM.'
    $content = [System.IO.File]::ReadAllText($output)
    Assert-True $content.StartsWith('#cloud-config') 'Output is not cloud-config.'
    Assert-True ($content -notmatch '__[A-Z0-9_]+__') 'Output has unresolved template tokens.'
    Assert-True ($content -match 'name: engineer_1') 'Username was not rendered.'
    Assert-True ($content -match 'default=engineer_1') 'WSL default user was not rendered.'
    Assert-True ($content -match 'lock_passwd: true') 'Locked password missing.'
    Assert-True ($content -match 'NOPASSWD:ALL') 'Passwordless sudo missing.'
    Assert-True ($content -match '/usr/local/lib/wsl-development-environment/bootstrap.sh') 'Bootstrap path missing.'
    Assert-True ($content -match 'systemd=true') 'Explicit systemd setting missing.'

    foreach ($scriptName in @('bootstrap', 'validate')) {
        $source = Get-LinuxScriptBytes (Join-Path $repoRoot "scripts/$scriptName.sh")
        $encoded = [regex]::Match($content, "path: /usr/local/lib/wsl-development-environment/$scriptName\.sh[\s\S]*?content: ([A-Za-z0-9+/=]+)").Groups[1].Value
        Assert-True (-not [string]::IsNullOrEmpty($encoded)) "$scriptName payload is missing."
        Assert-True ([System.Linq.Enumerable]::SequenceEqual($source, [Convert]::FromBase64String($encoded))) "$scriptName payload changed during rendering."
    }

    $failed = $false
    try { Invoke-Setup -Username 'BadName' -Path (Join-Path $temporaryRoot 'invalid.yml') } catch { $failed = $true }
    Assert-True $failed 'Invalid username was accepted.'
    $failed = $false
    try { Invoke-Setup -Username 'root' -Path (Join-Path $temporaryRoot 'root.yml') } catch { $failed = $true }
    Assert-True $failed 'Reserved username was accepted.'
    $failed = $false
    try { Invoke-Setup -Username 'engineer_1' -Path $output } catch { $failed = $true }
    Assert-True $failed 'Existing output was overwritten without -Force.'
    Invoke-Setup -Username 'engineer_1' -Path $output -Force

    $failed = $false
    try { & $setup -LinuxUsername engineer_1 -OutputPath (Join-Path $temporaryRoot 'existing-distro.yml') -TestRegisteredDistributions 'Ubuntu-24.04' } catch { $failed = $true }
    Assert-True $failed 'Existing distribution safeguard did not fail.'

    $cloudInit = Get-Command cloud-init -ErrorAction SilentlyContinue
    if ($null -ne $cloudInit) {
        & $cloudInit.Source schema --config-file $output
        Assert-True ($LASTEXITCODE -eq 0) 'cloud-init schema validation failed.'
    }
    else {
        Write-Warning 'cloud-init is unavailable; schema validation was skipped. Install cloud-init to run the complete Phase 1 test.'
    }
    Write-Host 'setup.Tests.ps1: PASS'
}
finally {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}
