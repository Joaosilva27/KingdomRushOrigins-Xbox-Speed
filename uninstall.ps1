[CmdletBinding()]
param(
    [string]$DataDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ModuleName = 'kro_speed'
$script:Utf8 = New-Object System.Text.UTF8Encoding($false, $true)

function Get-KroSaveDir {
    param([string]$Override)

    if ($Override) {
        $path = [IO.Path]::GetFullPath($Override)
        if (Test-Path -LiteralPath $path -PathType Container) { return $path }
        throw "Save directory not found: $path"
    }

    $package = Get-AppxPackage -Name 'IronhideS.A.KingdomRushOrigins' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($package) {
        $candidate = Join-Path $env:LOCALAPPDATA "Packages\$($package.PackageFamilyName)\LocalCache\Local\LOVE\kingdom_rush_origins"
        if (Test-Path -LiteralPath $candidate -PathType Container) { return $candidate }
    }

    throw 'Could not find the Kingdom Rush Origins save folder. Pass -DataDir "C:\path\to\kingdom_rush_origins".'
}

function Write-Utf8Atomic([string]$Path, [string]$Text) {
    $temporary = $Path + '.kro-tmp-' + [Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($temporary, $Text, $script:Utf8)
        [IO.File]::Replace($temporary, $Path, [NullString]::Value)
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

if (Get-Process -Name 'kr3-gdk' -ErrorAction SilentlyContinue) {
    throw 'Close Kingdom Rush Origins before removing the mod.'
}

$saveDir = Get-KroSaveDir $DataDir
$settingsPath = Join-Path $saveDir 'settings.lua'
$modulePath = Join-Path $saveDir "$($script:ModuleName).lua"

if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
    $text = [IO.File]::ReadAllText($settingsPath, $script:Utf8).TrimStart([char]0xFEFF)
    $pattern = '(?m)^[ \t]*\[\s*["'']custom_script["'']\s*\]\s*=\s*["'']' + [regex]::Escape($script:ModuleName) + '["'']\s*;?[ \t]*\r?\n?'
    $updated = [regex]::Replace($text, $pattern, '')
    if ($updated -ne $text) {
        $backupDir = Join-Path $saveDir ".$($script:ModuleName)\backups"
        [IO.Directory]::CreateDirectory($backupDir) | Out-Null
        [IO.File]::Copy($settingsPath, (Join-Path $backupDir ((Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-settings-before-uninstall.lua')), $false)
        Write-Utf8Atomic $settingsPath $updated
        Write-Host 'Removed the custom_script loader entry.'
    }
}

if (Test-Path -LiteralPath $modulePath -PathType Leaf) {
    Remove-Item -LiteralPath $modulePath -Force
    Write-Host "Removed $modulePath"
}

Write-Host 'Uninstalled. Save slots were not touched.' -ForegroundColor Green
