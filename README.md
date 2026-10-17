# Windows 11 Tokyo Night

A reproducible Windows 11 desktop setup built around Komorebi, whkd, YASB, Cava, Flow Launcher, Nilesoft Shell, and Windhawk.

![Tokyo Night desktop](https://github.com/user-attachments/assets/cd3df315-ecce-447d-af31-084550eedcb3)

## Fresh installation

Open PowerShell in the cloned repository and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1
```

You can also double-click `install.cmd`. The installer asks for administrator access, installs the required packages with WinGet, backs up existing configuration, deploys the rice, sets the wallpaper and dark mode, and configures Komorebi and YASB to start when you sign in.

Sign out once after installation. This allows Explorer, Windhawk, Nilesoft Shell, and the startup entries to load cleanly.

Useful installer options:

```powershell
.\install.ps1 -WhatIf                         # preview changes
.\install.ps1 -SkipPackages                   # only deploy configuration
.\install.ps1 -SkipWindhawk                   # skip the Windhawk import step
.\install.ps1 -IncludeExtras                  # also install Git, PowerShell, and Terminal
.\install.ps1 -NoStart                        # configure without launching the bars
```

## What is configured

- Komorebi and whkd with ten workspaces and the included hotkeys.
- Correct 36 px top and 42 px bottom work-area offsets for this YASB layout.
- File Explorer as a managed tiled window.
- Snipping Tool and Screen Clipping Host as floating/ignored windows.
- Reliable YASB scheduled-task autostart at sign-in, with paths expanded for the current Windows user.
- Cava so the audio visualizer widget works.
- Flow Launcher's Tokyo Night theme.
- Nilesoft Shell's Tokyo Night context menu theme.
- A Tokyo Night wallpaper and Windows dark mode.
- Backups and a restore manifest under `%LOCALAPPDATA%\Win11TokyoNight`.

The supplied Komorebi configuration is a one-monitor baseline. Add monitor entries to `Komorebi\komorebi.json` before installing if the machine has a different monitor layout.

## Windhawk finishing step

Windhawk does not provide a supported command-line mod installer, so install these four mods in the Windhawk app:

1. Windows 11 Taskbar Styler
2. Windows 11 Start Menu Styler
3. Windows 11 Notification Center Styler
4. Shell Flyout Positions

Then import the included settings:

```powershell
.\scripts\Apply-WindhawkTheme.ps1 -RestartExplorer
```

The importer validates that all four mods are installed and backs up their current registry settings before changing them.

## Main hotkeys

| Hotkey | Action |
| --- | --- |
| `Alt + Space` | Open Flow Launcher (default Flow hotkey) |
| `Win + T` | Open Windows Terminal |
| `Win + E` | Open File Explorer |
| `Win + Shift + P` | Open Windows screen snipping |
| `Win + 1` through `Win + 0` | Focus workspace |
| `Win + Shift + 1` through `Win + Shift + 0` | Move the focused window to a workspace |
| `Win + Arrow` | Focus in a direction |
| `Win + Ctrl + Shift + Arrow` | Move a window in the layout |
| `Win + Shift + Arrow` | Resize the focused window |
| `Win + Q` | Close focused window |
| `Win + Shift + R` | Retile the current workspace |
| `Win + Alt + R` | Reload Komorebi configuration |

See `Komorebi\whkdrc` for the full list.

## Validate the setup

Validate the repository before installing:

```powershell
.\scripts\Test-TokyoNight.ps1 -RepositoryOnly
```

Validate the installed desktop afterward:

```powershell
.\scripts\Test-TokyoNight.ps1
komorebic check -k "$env:USERPROFILE\komorebi.json"
```

## Restore the previous setup

Each installation creates a timestamped backup. To restore the most recent pre-install state:

```powershell
& "$env:LOCALAPPDATA\Win11TokyoNight\Restore-TokyoNight.ps1"
```

Add `-UninstallPackages` if you also want to remove packages installed by the setup script.

## Optional application themes

The repository also contains Firefox, Discord/Vencord, Spotify/Spicetify, Windows Terminal, and Winfetch assets. They are intentionally not applied by the base installer because those applications may not exist on a fresh machine and can require account-specific setup.

## Gallery

![Tokyo Night desktop](https://github.com/user-attachments/assets/7327aaed-3a87-4323-a61c-5484a27ae41d)
![Tokyo Night desktop](https://github.com/user-attachments/assets/a1a34dda-7d3b-46d8-bdaa-f67c36cf47a1)
![Tokyo Night desktop](https://github.com/user-attachments/assets/5c99dfde-6c5d-4490-ba36-d44f8b50bd19)
