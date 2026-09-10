[CmdletBinding()]
param(
    [Parameter()]
    [string]$LinuxUsername,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [string]$OutputPath,

    # Test hook: skips only the Windows WSL availability/status preflight.
    [Parameter()]
    [switch]$SkipWslPreflight,

    # Test hook: simulates registered distributions without invoking wsl.exe.
    [Parameter(DontShow = $true)]
    [string[]]$TestRegisteredDistributions
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$distributionName = 'Ubuntu-24.04'
$templatePath = Join-Path $PSScriptRoot 'cloud-init/Ubuntu-24.04.user-data.template'
$bootstrapPath = Join-Path $PSScriptRoot 'scripts/bootstrap.sh'
$validatePath = Join-Path $PSScriptRoot 'scripts/validate.sh'
$tokenPattern = '__[A-Z0-9_]+__'
$useTestRegisteredDistributions = $PSBoundParameters.ContainsKey('TestRegisteredDistributions')

function Fail([string]$Message) {
    throw $Message
}

function Get-RequiredFile([string]$Path, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Fail "Required $Description was not found: $Path"
    }
    return (Get-Item -LiteralPath $Path)
}

function Get-LinuxScriptBytes([string]$Path) {
    $scriptText = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($Path))
    $linuxText = $scriptText -replace "`r`n?", "`n"
    Write-Output -NoEnumerate ([System.Text.UTF8Encoding]::new($false).GetBytes($linuxText))
}

function Get-LinuxScriptBase64([string]$Path) {
    return [Convert]::ToBase64String((Get-LinuxScriptBytes $Path))
}

function Assert-LinuxUsername([string]$Username) {
    if ([string]::IsNullOrWhiteSpace($Username)) {
        Fail 'A Linux username is required.'
    }
    if ($Username.Length -gt 32 -or $Username -cnotmatch '^[a-z_][a-z0-9_-]*$') {
        Fail 'Linux username must be 1-32 characters: lowercase letter or underscore first, then lowercase letters, digits, underscores, or hyphens.'
    }
    if ($Username -in @('root', 'daemon', 'bin', 'sys', 'sync', 'games', 'man', 'lp', 'mail', 'news', 'uucp', 'proxy', 'www-data', 'backup', 'list', 'irc', 'nobody', 'systemd-network', 'systemd-resolve', 'systemd-timesync')) {
        Fail "Linux username '$Username' is reserved."
    }
}

function Get-RegisteredDistributions {
    if ($useTestRegisteredDistributions) {
        return @($TestRegisteredDistributions)
    }
    $wsl = @(Get-Command -Name 'wsl.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($wsl.Count -eq 0) {
        Fail 'wsl.exe was not found. IT Ops must prepare WSL before running this script.'
    }
    try {
        $names = & $wsl[0].Source --list --quiet 2>&1
        if ($LASTEXITCODE -ne 0) {
            Fail "wsl.exe --list --quiet failed with exit code $LASTEXITCODE. Confirm that IT Ops WSL preparation is complete."
        }
        return @($names | ForEach-Object { "$($_)".Trim() } | Where-Object { $_ })
    }
    catch {
        Fail "Unable to query WSL distributions: $($_.Exception.Message)"
    }
}

Get-RequiredFile $templatePath 'cloud-init template' | Out-Null
Get-RequiredFile $bootstrapPath 'bootstrap script' | Out-Null
Get-RequiredFile $validatePath 'validation script' | Out-Null

if ([string]::IsNullOrWhiteSpace($LinuxUsername)) {
    $LinuxUsername = Read-Host 'Linux username'
}
Assert-LinuxUsername $LinuxUsername

if (-not $SkipWslPreflight) {
    $registered = Get-RegisteredDistributions
    if ($registered -contains $distributionName) {
        Fail "$distributionName is already registered. Cloud-init user-data is consumed only on first launch; do not render a replacement configuration for this instance."
    }
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        Fail 'USERPROFILE is unavailable; specify -OutputPath explicitly.'
    }
    $OutputPath = Join-Path $env:USERPROFILE ".cloud-init/$distributionName.user-data"
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

if ((Test-Path -LiteralPath $OutputPath -PathType Leaf) -and -not $Force) {
    Fail "Refusing to overwrite existing cloud-init user-data: $OutputPath. Use -Force only after confirming the distribution has not been installed."
}
if ((Test-Path -LiteralPath $OutputPath -PathType Leaf) -and $Force) {
    Write-Warning "Replacing existing cloud-init user-data: $OutputPath"
}

$template = [System.IO.File]::ReadAllText($templatePath, [System.Text.UTF8Encoding]::new($false))
$rendered = $template.Replace('__LINUX_USERNAME__', $LinuxUsername).Replace('__BOOTSTRAP_B64__', (Get-LinuxScriptBase64 $bootstrapPath)).Replace('__VALIDATE_B64__', (Get-LinuxScriptBase64 $validatePath))

if ($rendered -match $tokenPattern) {
    Fail 'Rendering failed: unresolved template token remains in generated user-data.'
}
if (-not $rendered.StartsWith('#cloud-config' + [Environment]::NewLine) -and -not $rendered.StartsWith("#cloud-config`n")) {
    Fail 'Rendering failed: generated user-data does not begin with #cloud-config.'
}

foreach ($payload in @(
    @{ Name = 'bootstrap'; Path = $bootstrapPath },
    @{ Name = 'validate'; Path = $validatePath }
)) {
    $escapedPath = [regex]::Escape("/usr/local/lib/wsl-development-environment/$($payload.Name).sh")
    $match = [regex]::Match($rendered, ('path: ' + $escapedPath + '[\s\S]*?content: ([A-Za-z0-9+/=]+)'))
    if (-not $match.Success) {
        Fail "Rendering failed: $($payload.Name) payload is missing."
    }
    try {
        $decoded = [Convert]::FromBase64String($match.Groups[1].Value)
    }
    catch {
        Fail "Rendering failed: $($payload.Name) payload is not valid base64. $($_.Exception.Message)"
    }
    if (-not [System.Linq.Enumerable]::SequenceEqual([byte[]]$decoded, (Get-LinuxScriptBytes $payload.Path))) {
        Fail "Rendering failed: $($payload.Name) payload does not round-trip."
    }
}

$outputDirectory = Split-Path -Parent $OutputPath
[System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
[System.IO.File]::WriteAllText($OutputPath, $rendered, [System.Text.UTF8Encoding]::new($false))

Write-Host "Rendered cloud-init user-data: $OutputPath"
Write-Host "Linux username: $LinuxUsername"
Write-Host 'Next step (run explicitly from PowerShell):'
Write-Host "  wsl --install $distributionName"
