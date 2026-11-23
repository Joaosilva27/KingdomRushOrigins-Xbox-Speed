[CmdletBinding()]
param(
    [string]$DataDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ModuleName = 'kro_speed'
$script:LegacyModules = @('kro_xbox_speed')
$script:Utf8 = New-Object System.Text.UTF8Encoding($false, $true)

function Get-KroSaveDir {
    param([string]$Override)

    if ($Override) {
        $path = [IO.Path]::GetFullPath($Override)
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            throw "Save directory not found: $path"
        }
        return $path
    }

    $package = Get-AppxPackage -Name 'IronhideS.A.KingdomRushOrigins' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($package) {
        $candidate = Join-Path $env:LOCALAPPDATA "Packages\$($package.PackageFamilyName)\LocalCache\Local\LOVE\kingdom_rush_origins"
        if (Test-Path -LiteralPath $candidate -PathType Container) { return $candidate }
    }

    $packages = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $packages) {
        $dir = Get-ChildItem -LiteralPath $packages -Directory -Filter 'IronhideS.A.KingdomRushOrigins_*' |
            Select-Object -First 1
        if ($dir) {
            $candidate = Join-Path $dir.FullName 'LocalCache\Local\LOVE\kingdom_rush_origins'
            if (Test-Path -LiteralPath $candidate -PathType Container) { return $candidate }
        }
    }

    throw @'
Could not find the Xbox / Microsoft Store save folder for Kingdom Rush Origins.
Launch the game once, then run the installer again.
If your copy lives somewhere else, pass -DataDir "C:\path\to\kingdom_rush_origins".
'@
}

function Assert-GameClosed {
    if (Get-Process -Name 'kr3-gdk' -ErrorAction SilentlyContinue) {
        throw "Close Kingdom Rush Origins before installing or uninstalling the mod."
    }
}

function Read-Utf8([string]$Path) {
    $text = [IO.File]::ReadAllText($Path, $script:Utf8)
    return $text.TrimStart([char]0xFEFF)
}

function Write-Utf8Atomic([string]$Path, [string]$Text) {
    $temporary = $Path + '.kro-tmp-' + [Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($temporary, $Text, $script:Utf8)
        if ([IO.File]::Exists($Path)) {
            [IO.File]::Replace($temporary, $Path, [NullString]::Value)
        } else {
            [IO.File]::Move($temporary, $Path)
        }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Backup-File([string]$Path, [string]$StateDir, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $backupDir = Join-Path $StateDir 'backups'
    [IO.Directory]::CreateDirectory($backupDir) | Out-Null
    $name = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + $Label
    $target = Join-Path $backupDir $name
    [IO.File]::Copy($Path, $target, $false)
    return $target
}

function Set-Loader([string]$Text) {
    $pattern = '(?m)^(?<indent>[ \t]*)\[\s*["'']custom_script["'']\s*\]\s*=\s*(?:"[^"\r\n]*"|''[^''\r\n]*''|nil)\s*;?[ \t]*$'
    $line = '["custom_script"] = "' + $script:ModuleName + '";'

    if ([regex]::IsMatch($Text, $pattern)) {
        return [regex]::Replace($Text, $pattern, '${indent}' + $line)
    }

    $return = [regex]::Match($Text, '(?m)^(?<indent>[ \t]*)return[ \t]+(?<name>[A-Za-z_]\w*)[ \t]*;?[ \t]*$')
    if (-not $return.Success) {
        throw 'settings.lua does not end with a simple "return <table>" line. Nothing was changed.'
    }
    if ($Text.Substring($return.Index + $return.Length).Trim().Length -ne 0) {
        throw 'Unexpected content after the final settings return. Nothing was changed.'
    }

    $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $block = $return.Groups['indent'].Value + $line + $newline
    return $Text.Insert($return.Index, $block)
}

$saveDir = Get-KroSaveDir $DataDir
$settingsPath = Join-Path $saveDir 'settings.lua'
$modulePath = Join-Path $saveDir "$($script:ModuleName).lua"
$stateDir = Join-Path $saveDir ".$($script:ModuleName)"
$sourceModule = Join-Path $PSScriptRoot "$($script:ModuleName).lua"

Assert-GameClosed

if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
    throw "settings.lua was not found in: $saveDir`nLaunch the game once, then run the installer again."
}
if (-not (Test-Path -LiteralPath $sourceModule -PathType Leaf)) {
    throw "The mod file is missing from this package: $sourceModule"
}

[IO.Directory]::CreateDirectory($stateDir) | Out-Null
$oldSettings = [IO.File]::ReadAllBytes($settingsPath)
$oldModule = $null
if (Test-Path -LiteralPath $modulePath -PathType Leaf) {
    $oldModule = [IO.File]::ReadAllBytes($modulePath)
}

$newSettings = Set-Loader (Read-Utf8 $settingsPath)
$settingsBackup = Backup-File $settingsPath $stateDir 'settings.lua'
if ($null -ne $oldModule) {
    Backup-File $modulePath $stateDir "$($script:ModuleName).lua" | Out-Null
}

try {
    [IO.File]::WriteAllBytes($modulePath, [IO.File]::ReadAllBytes($sourceModule))
    # Commit the loader last so it never points at a missing module.
    Write-Utf8Atomic $settingsPath $newSettings
} catch {
    [IO.File]::WriteAllBytes($settingsPath, $oldSettings)
    if ($null -ne $oldModule) { [IO.File]::WriteAllBytes($modulePath, $oldModule) }
    elseif (Test-Path -LiteralPath $modulePath) { [IO.File]::Delete($modulePath) }
    throw
}

# Retire the module from the earlier 1.x attempt, if present.
foreach ($legacy in $script:LegacyModules) {
    $legacyPath = Join-Path $saveDir "$legacy.lua"
    if (Test-Path -LiteralPath $legacyPath -PathType Leaf) {
        Backup-File $legacyPath $stateDir "$legacy.lua" | Out-Null
        Remove-Item -LiteralPath $legacyPath -Force
    }
}

Write-Host ''
Write-Host 'Installed the Kingdom Rush Origins Xbox speed mod.' -ForegroundColor Green
Write-Host "  Save folder : $saveDir"
Write-Host "  Module      : $modulePath"
Write-Host "  Backup      : $settingsBackup"
Write-Host ''
Write-Host 'Launch the game, play a level and press R: 1x -> 2x -> 3x -> 5x -> 1x.'
Write-Host "Log file     : $saveDir\kro_speed.log"
