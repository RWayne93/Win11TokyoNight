[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepositoryRoot,
    [switch]$RestartExplorer
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator) -and -not $WhatIfPreference) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -RepositoryRoot `"$RepositoryRoot`""
    if ($RestartExplorer) {
        $arguments += ' -RestartExplorer'
    }
    $process = Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    exit $process.ExitCode
}

$windhawkRegistry = 'HKLM:\Software\Windhawk\Engine\Mods'
$windhawkExe = Join-Path $env:ProgramFiles 'Windhawk\windhawk.exe'
$backupDirectory = Join-Path $env:LOCALAPPDATA ("Win11TokyoNight\windhawk-backups\{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

$mods = @(
    @{ Id = 'windows-11-taskbar-styler'; File = 'Taskbar.json'; Display = 'Windows 11 Taskbar Styler' },
    @{ Id = 'windows-11-start-menu-styler'; File = 'Startmenu.json'; Display = 'Windows 11 Start Menu Styler' },
    @{ Id = 'windows-11-notification-center-styler'; File = 'NotificationCenter.json'; Display = 'Windows 11 Notification Center Styler' },
    @{ Id = 'shell-flyout-positions'; File = 'ShellFlyoutPositions.json'; Display = 'Shell Flyout Positions' }
)

$missing = @()
foreach ($mod in $mods) {
    if (-not (Test-Path -LiteralPath (Join-Path $windhawkRegistry $mod.Id))) {
        $missing += $mod.Display
    }
}

if ($missing.Count -gt 0) {
    Write-Warning 'Windhawk is installed, but these required mods are missing:'
    foreach ($name in $missing) {
        Write-Host "  - $name"
    }
    Write-Host 'Install them from Windhawk, then run this script again as Administrator.'
    return
}

if ($PSCmdlet.ShouldProcess($backupDirectory, 'Back up current Windhawk mod settings')) {
    New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
}

foreach ($mod in $mods) {
    $modKey = Join-Path $windhawkRegistry $mod.Id
    $settingsKey = Join-Path $modKey 'Settings'
    $jsonPath = Join-Path (Join-Path $RepositoryRoot 'Windhawk') $mod.File
    if (-not (Test-Path -LiteralPath $jsonPath)) {
        throw "Missing Windhawk settings file: $jsonPath"
    }

    $backupFile = Join-Path $backupDirectory ($mod.Id + '.reg')
    if ($PSCmdlet.ShouldProcess($mod.Display, "Back up registry settings to $backupFile")) {
        & reg.exe export ("HKLM\Software\Windhawk\Engine\Mods\{0}" -f $mod.Id) $backupFile /y | Out-Null
    }

    $settings = Get-Content -Raw -LiteralPath $jsonPath | ConvertFrom-Json
    if ($PSCmdlet.ShouldProcess($mod.Display, 'Apply Tokyo Night settings')) {
        if (Test-Path -LiteralPath $settingsKey) {
            Remove-Item -LiteralPath $settingsKey -Recurse -Force
        }
        New-Item -Path $settingsKey -Force | Out-Null
        foreach ($property in $settings.PSObject.Properties) {
            $value = $property.Value
            if ($value -is [bool]) {
                New-ItemProperty -Path $settingsKey -Name $property.Name -PropertyType DWord -Value ([int]$value) -Force | Out-Null
            }
            elseif ($value -is [byte] -or $value -is [int16] -or $value -is [int32] -or $value -is [long]) {
                New-ItemProperty -Path $settingsKey -Name $property.Name -PropertyType DWord -Value ([int]$value) -Force | Out-Null
            }
            else {
                New-ItemProperty -Path $settingsKey -Name $property.Name -PropertyType String -Value ([string]$value) -Force | Out-Null
            }
        }

        $changeTime = [uint32]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -band 0xffffffff)
        New-ItemProperty -Path $modKey -Name SettingsChangeTime -PropertyType DWord -Value $changeTime -Force | Out-Null
    }
}

if ((Test-Path -LiteralPath $windhawkExe) -and $PSCmdlet.ShouldProcess('Windhawk', 'Restart with updated settings')) {
    & $windhawkExe -restart -tray-only
}

if ($RestartExplorer -and $PSCmdlet.ShouldProcess('Windows Explorer', 'Restart to apply shell styles')) {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
}

Write-Host 'Windhawk Tokyo Night settings applied.' -ForegroundColor Green
Write-Host "Registry backups: $backupDirectory"
