[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [switch]$UninstallPackages
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$stateRoot = Join-Path $env:LOCALAPPDATA 'Win11TokyoNight'
$manifestPath = Join-Path $stateRoot 'latest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "No restore manifest was found at $manifestPath."
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json

$komorebic = Get-Command komorebic.exe -ErrorAction SilentlyContinue
if ($komorebic -and $PSCmdlet.ShouldProcess('Komorebi and whkd', 'Stop')) {
    & $komorebic.Source stop --whkd 2>$null
}

$yasbc = Get-Command yasbc.exe -ErrorAction SilentlyContinue
if ($yasbc -and $PSCmdlet.ShouldProcess('YASB', 'Stop and disable autostart')) {
    & $yasbc.Source stop 2>$null
    & $yasbc.Source disable-autostart
}

foreach ($entry in $manifest.Entries) {
    $target = [string]$entry.Path
    $backup = [string]$entry.BackupPath
    if ($entry.Existed) {
        if (-not (Test-Path -LiteralPath $backup)) {
            Write-Warning "Backup missing; leaving current target untouched: $target"
            continue
        }
        if ($PSCmdlet.ShouldProcess($target, "Restore from $backup")) {
            if (Test-Path -LiteralPath $target) {
                Remove-Item -LiteralPath $target -Recurse -Force
            }
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Copy-Item -LiteralPath $backup -Destination $target -Recurse -Force
        }
    }
    elseif ((Test-Path -LiteralPath $target) -and $PSCmdlet.ShouldProcess($target, 'Remove file created by Tokyo Night installer')) {
        Remove-Item -LiteralPath $target -Recurse -Force
    }
}

if ($manifest.PSObject.Properties.Name -contains 'ThemeSettings') {
    $themeKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $theme = $manifest.ThemeSettings
    foreach ($name in @('AppsUseLightTheme', 'SystemUsesLightTheme')) {
        $existsProperty = 'Has' + $name
        if ($theme.$existsProperty) {
            if ($PSCmdlet.ShouldProcess("$themeKey\$name", 'Restore previous value')) {
                New-ItemProperty -Path $themeKey -Name $name -PropertyType DWord -Value ([int]$theme.$name) -Force | Out-Null
            }
        }
        elseif ($PSCmdlet.ShouldProcess("$themeKey\$name", 'Remove value created by Tokyo Night installer')) {
            Remove-ItemProperty -Path $themeKey -Name $name -ErrorAction SilentlyContinue
        }
    }
}

if ($manifest.PSObject.Properties.Name -contains 'DesktopWallpaper' -and $manifest.DesktopWallpaper) {
    $wallpaper = [string]$manifest.DesktopWallpaper
    if ((Test-Path -LiteralPath $wallpaper) -and $PSCmdlet.ShouldProcess($wallpaper, 'Restore desktop wallpaper')) {
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class TokyoNightRestoreWallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool SystemParametersInfo(int action, int parameter, string path, int flags);
}
'@
        [TokyoNightRestoreWallpaper]::SystemParametersInfo(20, 0, $wallpaper, 3) | Out-Null
    }
}

if ($UninstallPackages) {
    foreach ($id in @('LGUG2Z.komorebi', 'LGUG2Z.whkd', 'AmN.yasb', 'karlstav.cava', 'Flow-Launcher.Flow-Launcher', 'Nilesoft.Shell', 'RamenSoftware.Windhawk')) {
        if ($PSCmdlet.ShouldProcess($id, 'Uninstall WinGet package')) {
            & winget uninstall --id $id --exact --silent --accept-source-agreements
        }
    }
}

Write-Host 'Tokyo Night files and settings were restored from the latest backup.' -ForegroundColor Green
