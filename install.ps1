[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$SkipPackages,
    [switch]$SkipWindhawk,
    [switch]$NoStart,
    [switch]$IncludeExtras
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSCommandPath
$stateRoot = Join-Path $env:LOCALAPPDATA 'Win11TokyoNight'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $stateRoot "backups\$timestamp"
$manifestEntries = @()

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-Elevated {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($SkipPackages) { $arguments += ' -SkipPackages' }
    if ($SkipWindhawk) { $arguments += ' -SkipWindhawk' }
    if ($NoStart) { $arguments += ' -NoStart' }
    if ($IncludeExtras) { $arguments += ' -IncludeExtras' }

    Write-Host 'Administrator access is required to install packages and configure Nilesoft Shell.' -ForegroundColor Yellow
    $process = Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    exit $process.ExitCode
}

function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath"
}

function Invoke-WingetInstall {
    param(
        [Parameter(Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [string]$Name
    )

    $installed = (& winget list --id $Id --exact --accept-source-agreements 2>$null | Out-String)
    if ($installed -match [regex]::Escape($Id)) {
        Write-Host "[installed] $Name"
        return
    }

    if ($PSCmdlet.ShouldProcess($Name, "Install package $Id")) {
        Write-Host "[installing] $Name" -ForegroundColor Cyan
        & winget install --id $Id --exact --silent --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "WinGet failed to install $Name ($Id), exit code $LASTEXITCODE."
        }
    }
}

function Backup-Target {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name
    )

    $exists = Test-Path -LiteralPath $Path
    $backupPath = Join-Path $backupRoot $Name
    if ($exists -and $PSCmdlet.ShouldProcess($Path, "Back up to $backupPath")) {
        $parent = Split-Path -Parent $backupPath
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        Copy-Item -LiteralPath $Path -Destination $backupPath -Recurse -Force
    }

    $script:manifestEntries += [pscustomobject]@{
        Path = $Path
        BackupPath = $backupPath
        Existed = $exists
    }
}

function Copy-ConfigFile {
    param(
        [Parameter(Mandatory)] [string]$Source,
        [Parameter(Mandatory)] [string]$Destination
    )

    if ($PSCmdlet.ShouldProcess($Destination, "Copy configuration from $Source")) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
}

function Resolve-Executable {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [string[]]$Fallbacks = @()
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    foreach ($fallback in $Fallbacks) {
        if (Test-Path -LiteralPath $fallback) {
            return $fallback
        }
    }

    return $null
}

if (-not (Test-Administrator) -and -not $WhatIfPreference) {
    Restart-Elevated
}

$windowsVersion = [Environment]::OSVersion.Version
if ($windowsVersion.Major -lt 10) {
    throw 'Windows 10 or Windows 11 is required.'
}

if (-not $SkipPackages) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'WinGet is required. Install Microsoft App Installer, then run this script again.'
    }

    $packages = @(
        @{ Id = 'LGUG2Z.komorebi'; Name = 'Komorebi' },
        @{ Id = 'LGUG2Z.whkd'; Name = 'whkd' },
        @{ Id = 'AmN.yasb'; Name = 'YASB' },
        @{ Id = 'karlstav.cava'; Name = 'Cava audio visualizer' },
        @{ Id = 'Microsoft.VCRedist.2015+.x64'; Name = 'Visual C++ runtime' },
        @{ Id = 'DEVCOM.JetBrainsMonoNerdFont'; Name = 'JetBrainsMono Nerd Font' },
        @{ Id = 'Flow-Launcher.Flow-Launcher'; Name = 'Flow Launcher' },
        @{ Id = 'Nilesoft.Shell'; Name = 'Nilesoft Shell' }
    )

    if (-not $SkipWindhawk) {
        $packages += @{ Id = 'RamenSoftware.Windhawk'; Name = 'Windhawk' }
    }

    if ($IncludeExtras) {
        $packages += @(
            @{ Id = 'Microsoft.PowerShell'; Name = 'PowerShell 7' },
            @{ Id = 'Microsoft.WindowsTerminal'; Name = 'Windows Terminal' },
            @{ Id = 'Git.Git'; Name = 'Git' }
        )
    }

    foreach ($package in $packages) {
        Invoke-WingetInstall -Id $package.Id -Name $package.Name
    }

    Refresh-Path
}

$komorebiConfig = Join-Path $env:USERPROFILE 'komorebi.json'
$whkdConfig = Join-Path $env:USERPROFILE '.config\whkdrc'
$yasbDirectory = Join-Path $env:USERPROFILE '.config\yasb'
$flowTheme = Join-Path $env:APPDATA 'FlowLauncher\Themes\Tokyo Night Dark.xaml'
$wallpaperDirectory = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'Win11TokyoNight'
$nilesoftTheme = Join-Path $env:ProgramFiles 'Nilesoft Shell\imports\theme.nss'
$komorebiShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'komorebi.lnk'

$personalizationKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$personalization = Get-ItemProperty -LiteralPath $personalizationKey -ErrorAction SilentlyContinue
$themeSettings = [pscustomobject]@{
    HasAppsUseLightTheme = [bool]($personalization -and $personalization.PSObject.Properties.Name -contains 'AppsUseLightTheme')
    AppsUseLightTheme = if ($personalization -and $personalization.PSObject.Properties.Name -contains 'AppsUseLightTheme') { [int]$personalization.AppsUseLightTheme } else { 1 }
    HasSystemUsesLightTheme = [bool]($personalization -and $personalization.PSObject.Properties.Name -contains 'SystemUsesLightTheme')
    SystemUsesLightTheme = if ($personalization -and $personalization.PSObject.Properties.Name -contains 'SystemUsesLightTheme') { [int]$personalization.SystemUsesLightTheme } else { 1 }
}
$desktopWallpaper = (Get-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop' -Name WallPaper -ErrorAction SilentlyContinue).WallPaper

foreach ($target in @(
    @{ Path = $komorebiConfig; Name = 'komorebi.json' },
    @{ Path = $whkdConfig; Name = '.config\whkdrc' },
    @{ Path = $yasbDirectory; Name = '.config\yasb' },
    @{ Path = $flowTheme; Name = 'FlowLauncher\Tokyo Night Dark.xaml' },
    @{ Path = $wallpaperDirectory; Name = 'Wallpapers' },
    @{ Path = $nilesoftTheme; Name = 'Nilesoft-Shell\theme.nss' },
    @{ Path = $komorebiShortcut; Name = 'Startup\komorebi.lnk' }
)) {
    Backup-Target -Path $target.Path -Name $target.Name
}

Copy-ConfigFile -Source (Join-Path $repoRoot 'Komorebi\komorebi.json') -Destination $komorebiConfig
Copy-ConfigFile -Source (Join-Path $repoRoot 'Komorebi\whkdrc') -Destination $whkdConfig

if ($PSCmdlet.ShouldProcess($yasbDirectory, 'Install YASB Tokyo Night configuration')) {
    New-Item -ItemType Directory -Path $yasbDirectory -Force | Out-Null
    $yasbTemplate = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'YASB (Win taskbar replace)\config.yaml')
    $escapedProfile = $env:USERPROFILE.Replace('\', '\\')
    $escapedWallpapers = $wallpaperDirectory.Replace('\', '\\')
    $yasbConfig = $yasbTemplate.Replace('__USERPROFILE__', $escapedProfile).Replace('__WALLPAPER_DIR__', $escapedWallpapers)
    [IO.File]::WriteAllText((Join-Path $yasbDirectory 'config.yaml'), $yasbConfig, [Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath (Join-Path $repoRoot 'YASB (Win taskbar replace)\styles.css') -Destination (Join-Path $yasbDirectory 'styles.css') -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'YASB (Win taskbar replace)\theme.json') -Destination (Join-Path $yasbDirectory 'theme.json') -Force
}

if ($PSCmdlet.ShouldProcess($wallpaperDirectory, 'Install Tokyo Night wallpapers')) {
    New-Item -ItemType Directory -Path $wallpaperDirectory -Force | Out-Null
    Copy-Item -Path (Join-Path $repoRoot 'Wallpapers\*') -Destination $wallpaperDirectory -Force
}

Copy-ConfigFile -Source (Join-Path $repoRoot 'Flow Launcher\Tokyo Night Dark.xaml') -Destination $flowTheme

if ((Test-Path -LiteralPath (Split-Path -Parent $nilesoftTheme)) -and
    $PSCmdlet.ShouldProcess($nilesoftTheme, 'Install Nilesoft Tokyo Night context-menu theme')) {
    Copy-Item -LiteralPath (Join-Path $repoRoot 'Nilesoft-Shell\theme.nss') -Destination $nilesoftTheme -Force
}

if ($PSCmdlet.ShouldProcess('HKCU Windows theme settings', 'Enable dark app and system modes')) {
    $themeKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    New-Item -Path $themeKey -Force | Out-Null
    New-ItemProperty -Path $themeKey -Name AppsUseLightTheme -PropertyType DWord -Value 0 -Force | Out-Null
    New-ItemProperty -Path $themeKey -Name SystemUsesLightTheme -PropertyType DWord -Value 0 -Force | Out-Null
}

$firstWallpaper = Join-Path $wallpaperDirectory 'TN1.png'
if ((Test-Path -LiteralPath $firstWallpaper) -and $PSCmdlet.ShouldProcess($firstWallpaper, 'Set desktop wallpaper')) {
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class TokyoNightWallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool SystemParametersInfo(int action, int parameter, string path, int flags);
}
'@
    [TokyoNightWallpaper]::SystemParametersInfo(20, 0, $firstWallpaper, 3) | Out-Null
}

Refresh-Path
$komorebic = Resolve-Executable -Name 'komorebic.exe' -Fallbacks @(
    (Join-Path $env:ProgramFiles 'komorebi\bin\komorebic.exe')
)
$komorebicNoConsole = Resolve-Executable -Name 'komorebic-no-console.exe' -Fallbacks @(
    (Join-Path $env:ProgramFiles 'komorebi\bin\komorebic-no-console.exe')
)
$yasbc = Resolve-Executable -Name 'yasbc.exe' -Fallbacks @(
    (Join-Path $env:ProgramFiles 'YASB\yasbc.exe')
)

if ($komorebic) {
    if ($PSCmdlet.ShouldProcess('applications.json', 'Fetch Komorebi application-specific rules')) {
        & $komorebic fetch-asc
    }

    if ($komorebicNoConsole -and $PSCmdlet.ShouldProcess('Startup\komorebi.lnk', 'Enable clean-state Komorebi and whkd autostart')) {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($komorebiShortcut)
        $shortcut.TargetPath = $komorebicNoConsole
        $shortcut.Arguments = 'start --whkd --clean-state'
        $shortcut.WorkingDirectory = Split-Path -Parent $komorebicNoConsole
        $shortcut.Save()
    }
}
else {
    Write-Warning 'komorebic.exe was not found. Komorebi configuration was copied, but autostart was not created.'
}

if ($yasbc) {
    if ($PSCmdlet.ShouldProcess('YASB', 'Enable reliable scheduled-task autostart')) {
        # Remove the shortcut-based mode first so YASB cannot start twice.
        & $yasbc disable-autostart 2>$null
        & $yasbc enable-autostart --task
        if ($LASTEXITCODE -ne 0) {
            throw "YASB scheduled-task autostart could not be enabled (exit code $LASTEXITCODE)."
        }
    }
}
else {
    Write-Warning 'yasbc.exe was not found. YASB configuration was copied, but autostart was not enabled.'
}

if ($PSCmdlet.ShouldProcess($stateRoot, 'Save restore manifest')) {
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    $manifest = [pscustomobject]@{
        InstalledAt = (Get-Date).ToString('o')
        Repository = $repoRoot
        BackupRoot = $backupRoot
        Entries = $manifestEntries
        ThemeSettings = $themeSettings
        DesktopWallpaper = $desktopWallpaper
    }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $stateRoot 'latest.json') -Encoding UTF8
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\Restore-TokyoNight.ps1') -Destination (Join-Path $stateRoot 'Restore-TokyoNight.ps1') -Force
}

if (-not $SkipWindhawk) {
    $windhawkScript = Join-Path $repoRoot 'scripts\Apply-WindhawkTheme.ps1'
    if (Test-Path -LiteralPath $windhawkScript) {
        & $windhawkScript -RepositoryRoot $repoRoot
    }
}

if (-not $NoStart) {
    if ($komorebic -and $PSCmdlet.ShouldProcess('Komorebi', 'Start window manager and whkd')) {
        & $komorebic stop --whkd 2>$null
        & $komorebic start --whkd --clean-state
    }
    if ($yasbc -and $PSCmdlet.ShouldProcess('YASB', 'Start status bar')) {
        & $yasbc stop 2>$null
        & $yasbc start
    }
}

Write-Host ''
Write-Host 'Tokyo Night core installation is complete.' -ForegroundColor Green
Write-Host "Backups: $backupRoot"
Write-Host 'If Windhawk listed missing mods, install those four mods and rerun scripts\Apply-WindhawkTheme.ps1 as Administrator.'
Write-Host 'YASB is registered as a scheduled task and will start automatically at sign-in.'
Write-Host 'Sign out once after the first installation so all Explorer, font, PATH, and shell changes load cleanly.'
