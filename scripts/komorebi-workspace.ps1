[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][int]$Number,
    [Parameter(Mandatory = $false)][ValidateSet('focus', 'move', 'send')][string]$Mode = 'focus'
)

# Gives komorebi a single global workspace numbering scheme across monitors.
#
# Workspaces are named with their global number ("1", "2", "3", ...), so they
# can be addressed from any monitor with focus-named-workspace. A number that
# does not exist yet is created on the monitor the user is working on:
#
#   1. the monitor holding the focused window, if there is one;
#   2. otherwise the monitor the last workspace jump landed on;
#   3. otherwise komorebi's own focused monitor.
#
# Step 2 matters because focusing an empty workspace on another monitor does
# not move real OS focus, so komorebi's focused monitor snaps back to the
# window that still has focus.

$ErrorActionPreference = 'Stop'
$name = [string]$Number

# Komorebi can focus a named workspace on another monitor without moving the
# physical pointer, especially when Windows keeps foreground focus on the old
# monitor. Move it explicitly after focus/move operations so Win+number behaves
# like a Hyprland workspace jump.
if (-not ('Win11TokyoNight.Cursor' -as [type])) {
    Add-Type -Namespace Win11TokyoNight -Name Cursor -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetCursorPos(int X, int Y);
'@
}

$stateRoot = Join-Path $env:LOCALAPPDATA 'Win11TokyoNight'
$lastMonitorFile = Join-Path $stateRoot 'last-workspace-monitor.txt'

$state = & komorebic state | ConvertFrom-Json
$monitors = @($state.monitors.elements)

$targetMonitor = -1
for ($m = 0; $m -lt $monitors.Count; $m++) {
    foreach ($workspace in @($monitors[$m].workspaces.elements)) {
        if ($workspace.name -eq $name) { $targetMonitor = $m; break }
    }
    if ($targetMonitor -ge 0) { break }
}

$focusedMonitor = [int]$state.monitors.focused
if ($focusedMonitor -lt 0 -or $focusedMonitor -ge $monitors.Count) { $focusedMonitor = 0 }
$focusedWorkspace = [int]$monitors[$focusedMonitor].workspaces.focused
$focusedContainerCount = @($monitors[$focusedMonitor].workspaces.elements[$focusedWorkspace].containers.elements).Count

if ($targetMonitor -lt 0) {
    if ($focusedContainerCount -gt 0) {
        $createMonitor = $focusedMonitor
    }
    elseif (Test-Path -LiteralPath $lastMonitorFile) {
        $createMonitor = [int](Get-Content -LiteralPath $lastMonitorFile -TotalCount 1)
        if ($createMonitor -lt 0 -or $createMonitor -ge $monitors.Count) { $createMonitor = $focusedMonitor }
    }
    else {
        $createMonitor = $focusedMonitor
    }

    $workspaceCount = @($monitors[$createMonitor].workspaces.elements).Count
    & komorebic ensure-workspaces $createMonitor ($workspaceCount + 1) | Out-Null
    & komorebic workspace-name $createMonitor $workspaceCount $name | Out-Null
    $targetMonitor = $createMonitor
}

switch ($Mode) {
    'focus' { & komorebic focus-named-workspace $name | Out-Null }
    'move' { & komorebic move-to-named-workspace $name | Out-Null }
    'send' { & komorebic send-to-named-workspace $name | Out-Null }
}

if ($Mode -ne 'send') {
    $bounds = $monitors[$targetMonitor].size
    $cursorX = [int]($bounds.left + ($bounds.right / 2))
    $cursorY = [int]($bounds.top + ($bounds.bottom / 2))
    [void][Win11TokyoNight.Cursor]::SetCursorPos($cursorX, $cursorY)
}

# Remember where the user is working so the next new workspace lands there.
# Sending a window away does not move the user, so keep the previous value.
if ($Mode -ne 'send' -or $focusedContainerCount -eq 0) {
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    Set-Content -LiteralPath $lastMonitorFile -Value $targetMonitor -Encoding ASCII
}
