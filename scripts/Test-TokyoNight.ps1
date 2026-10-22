[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [switch]$RepositoryOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}
$failures = [Collections.Generic.List[string]]::new()
$passes = [Collections.Generic.List[string]]::new()

function Add-Check {
    param([bool]$Condition, [string]$Success, [string]$Failure)
    if ($Condition) {
        $script:passes.Add($Success)
    }
    else {
        $script:failures.Add($Failure)
    }
}

$requiredFiles = @(
    'install.cmd',
    'install.ps1',
    'Komorebi\komorebi.json',
    'Komorebi\whkdrc',
    'YASB (Win taskbar replace)\config.yaml',
    'YASB (Win taskbar replace)\styles.css',
    'Nilesoft-Shell\theme.nss',
    'Windhawk\Taskbar.json',
    'Windhawk\Startmenu.json',
    'Windhawk\NotificationCenter.json',
    'Windhawk\ShellFlyoutPositions.json',
    'scripts\Apply-WindhawkTheme.ps1',
    'scripts\komorebi-workspace.ps1',
    'scripts\Restore-TokyoNight.ps1'
)

foreach ($relativePath in $requiredFiles) {
    $fullPath = Join-Path $RepositoryRoot $relativePath
    Add-Check (Test-Path -LiteralPath $fullPath) "Found $relativePath" "Missing $relativePath"
}

foreach ($jsonFile in Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'Windhawk') -Filter '*.json') {
    try {
        Get-Content -Raw -LiteralPath $jsonFile.FullName | ConvertFrom-Json | Out-Null
        $passes.Add("Valid JSON: $($jsonFile.Name)")
    }
    catch {
        $failures.Add("Invalid JSON: $($jsonFile.Name): $($_.Exception.Message)")
    }
}

$powershellFiles = @(
    (Join-Path $RepositoryRoot 'install.ps1'),
    (Join-Path $RepositoryRoot 'scripts\Apply-WindhawkTheme.ps1'),
    (Join-Path $RepositoryRoot 'scripts\komorebi-workspace.ps1'),
    (Join-Path $RepositoryRoot 'scripts\Restore-TokyoNight.ps1'),
    $PSCommandPath
)
foreach ($file in $powershellFiles) {
    $tokens = $null
    $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$parseErrors) | Out-Null
    Add-Check ($parseErrors.Count -eq 0) "Valid PowerShell: $(Split-Path -Leaf $file)" "PowerShell parse errors in $file`: $($parseErrors -join '; ')"
}

$yasbTemplate = Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'YASB (Win taskbar replace)\config.yaml')
Add-Check ($yasbTemplate.Contains('__USERPROFILE__')) 'YASB user-profile token found' 'YASB config does not contain __USERPROFILE__ token'
Add-Check ($yasbTemplate.Contains('__WALLPAPER_DIR__')) 'YASB wallpaper token found' 'YASB config does not contain __WALLPAPER_DIR__ token'
Add-Check (-not ($yasbTemplate -match 'C:\\Users\\(MrDLi|elrond|AI2C)')) 'No hard-coded username in preferred YASB config' 'Hard-coded username remains in preferred YASB config'

$whkd = Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'Komorebi\whkdrc')
Add-Check ($whkd -match 'win \+ shift \+ p\s*:\s*start ms-screenclip:') 'Screenshot hotkey is present' 'Screenshot hotkey is missing'
Add-Check ($whkd -match 'win \+ 1\s*:.*komorebi-workspace\.ps1.*-Number 1.*-Mode focus') 'Global workspace hotkeys are present' 'Global workspace hotkeys are missing'

$workspaceScript = Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'scripts\komorebi-workspace.ps1')
Add-Check ($workspaceScript -match 'SetCursorPos') 'Workspace jumps move the pointer explicitly' 'Workspace jumps do not move the pointer explicitly'

$komorebiConfig = Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'Komorebi\komorebi.json')
Add-Check ($komorebiConfig -match '"top"\s*:\s*36') 'Komorebi top offset is 36' 'Komorebi top offset is not 36'
Add-Check ($komorebiConfig -match '"bottom"\s*:\s*42') 'Komorebi bottom offset is 42' 'Komorebi bottom offset is not 42'
Add-Check ($komorebiConfig -match 'CabinetWClass') 'File Explorer manage rule is present' 'File Explorer manage rule is missing'
Add-Check ($komorebiConfig -match 'SnippingTool\.exe' -and $komorebiConfig -match 'ScreenClippingHost\.exe') 'Snipping exclusions are present' 'Snipping exclusions are incomplete'
Add-Check ($komorebiConfig -match '"mouse_follows_focus"\s*:\s*true') 'Mouse follows workspace focus' 'Mouse-following is disabled'
Add-Check ($komorebiConfig -match '"display_index_preferences"\s*:') 'Stable display-index preferences are present' 'Display-index preferences are missing'
Add-Check (([regex]::Matches($komorebiConfig, '"work_area_offset"\s*:')).Count -eq 3) 'All three monitors have work-area offsets' 'Expected exactly three configured monitors'

$installer = Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'install.ps1')
$restoreScript = Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'scripts\Restore-TokyoNight.ps1')
Add-Check ($installer -match 'enable-autostart\s+--task') 'Installer enables YASB scheduled-task autostart' 'Installer does not enable YASB scheduled-task autostart'
Add-Check ($restoreScript -match 'disable-autostart\s+--task') 'Restore script disables YASB scheduled-task autostart' 'Restore script does not disable YASB scheduled-task autostart'
Add-Check ($installer -match "DisabledHotkeys.*Reserve Win\+0-9" -or $installer -match "Reserve Win\+0-9.*DisabledHotkeys") 'Installer reserves Win+0-9 for whkd' 'Installer does not reserve Win+0-9 for whkd'
Add-Check ($restoreScript -match 'HotkeySettings' -and $restoreScript -match 'DisabledHotkeys') 'Restore script restores Windows hotkeys' 'Restore script does not restore Windows hotkeys'

if (-not $RepositoryOnly) {
    foreach ($command in @('komorebic.exe', 'whkd.exe', 'yasbc.exe', 'cava.exe')) {
        Add-Check ([bool](Get-Command $command -ErrorAction SilentlyContinue)) "Command available: $command" "Command unavailable: $command"
    }

    $activeYasb = Join-Path $env:USERPROFILE '.config\yasb\config.yaml'
    if (Test-Path -LiteralPath $activeYasb) {
        $activeYasbText = Get-Content -Raw -LiteralPath $activeYasb
        Add-Check (-not ($activeYasbText -match '__[A-Z_]+__')) 'Active YASB tokens were resolved' 'Active YASB config still contains installer tokens'
    }
    else {
        $failures.Add("Active YASB config missing: $activeYasb")
    }

    $activeKomorebi = Join-Path $env:USERPROFILE 'komorebi.json'
    $komorebic = Get-Command komorebic.exe -ErrorAction SilentlyContinue
    if ($komorebic -and (Test-Path -LiteralPath $activeKomorebi)) {
        & $komorebic.Source check -k $activeKomorebi
        Add-Check ($LASTEXITCODE -eq 0) 'Active Komorebi config passed komorebic check' 'Active Komorebi config failed komorebic check'
    }

    $shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'komorebi.lnk'
    if (Test-Path -LiteralPath $shortcutPath) {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        Add-Check ($shortcut.Arguments -eq 'start --whkd --clean-state') 'Komorebi autostart uses clean state' "Unexpected Komorebi autostart arguments: $($shortcut.Arguments)"
    }
    else {
        $failures.Add('Komorebi startup shortcut is missing')
    }

    try {
        $yasbTask = Get-ScheduledTask -TaskName 'YASB Reborn' -ErrorAction Stop
        $yasbAction = @($yasbTask.Actions)[0]
        Add-Check ($yasbTask.State -in @('Ready', 'Running')) 'YASB scheduled task is enabled' 'YASB scheduled task is disabled'
        Add-Check ($yasbAction.Execute -like '*\YASB\yasb.exe') 'YASB scheduled task launches yasb.exe' "Unexpected YASB scheduled task action: $($yasbAction.Execute)"
    }
    catch {
        $failures.Add('YASB scheduled task is missing or inaccessible')
    }
}

foreach ($message in $passes) {
    Write-Host "[pass] $message" -ForegroundColor Green
}
foreach ($message in $failures) {
    Write-Host "[fail] $message" -ForegroundColor Red
}

if ($failures.Count -gt 0) {
    throw "$($failures.Count) validation check(s) failed."
}

Write-Host "All $($passes.Count) validation checks passed." -ForegroundColor Green
