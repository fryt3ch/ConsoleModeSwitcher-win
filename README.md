
<h1 align="center">
  Console Mode Switcher
</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Windows-✓-0078D6?style=flat-square&logo=windows" alt="Windows" />
  <img src="https://img.shields.io/badge/PowerShell-✓-5391FE?style=flat-square&logo=powershell" alt="PowerShell" />
  <img src="https://img.shields.io/badge/License-MIT-yellow?style=flat-square" alt="License: MIT" />
</p>

<p align="center">
  <b>Auto-switch monitor profiles when you connect/disconnect a gamepad.</b><br/>
  Detects Xbox 360 / Xbox One / Xbox Series controllers via PnP, loads the matching
  <code>MonitorSwitcher</code> profile, and launches/closes Steam Big Picture.<br/>
  Includes a grace period and a Win-key override for manual control.
</p>

<p align="center">
  <b>Windows only.</b>
</p>

---

## How It Works

The script polls controller presence via `Get-PnpDevice` and switches modes automatically.

| Event | Action |
|-------|--------|
| **Controller connected** | Load console profile, launch Steam Big Picture |
| **Controller disconnected + grace period expires** | Load desktop profile, close Steam Big Picture |
| **Win key held for 2s** | Manual override — force-switch to the opposite mode |

A grace period (default 300s) prevents accidental switching when the controller briefly disconnects.

## Dependencies

- [**MonitorSwitcher**](https://github.com/cooolinho/monitor-profile-switcher) (`MonitorSwitcher.exe`) — loads and saves monitor configurations. Download from [SourceForge](https://sourceforge.net/projects/monitorswitcher/).
- Monitor profiles (`.xml`) saved via MonitorSwitcherGUI — one for console mode, one for desktop.

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ConsoleMode` | `string` | `TV_2K_60` | Profile name for console mode (without `.xml`) |
| `DesktopMode` | `string` | `Desktop` | Profile name for desktop mode (without `.xml`) |
| `ProfilesDir` | `string` | `$env:APPDATA\MonitorSwitcher\Profiles` | Folder containing `.xml` profiles |
| `Tool` | `string` | `.\MonitorProfileSwitcher\MonitorSwitcher.exe` | Path to `MonitorSwitcher.exe` |
| `ControllerName` | `string` | `Xbox 360 Controller for Windows` | PnP friendly name to detect |
| `GracePeriodSeconds` | `int` | `300` | Time (s) to wait before switching to desktop after disconnect |
| `WinHoldSeconds` | `int` | `2` | Time (s) to hold Win key for manual override |

## Creating Profiles

### Prerequisite
Launch **MonitorSwitcherGUI.exe** — it runs in the system tray. All profiles are saved via its tray menu.

### Desktop Profile
1. Open **Windows display settings** (`Win + P` → *Extend* or *Duplicate* as desired)
2. Disable the TV display (select it → *Disconnect this display*)
3. Arrange your working monitors, set resolution, refresh rate, orientation
4. Right-click **MonitorSwitcherGUI** in the tray → *Save current configuration*
5. Name it `Desktop` (or match your `-DesktopMode` parameter)
6. Click *Save*

### Console Profile
1. Open **Windows display settings** again
2. Enable the TV, set its resolution and refresh rate (e.g. 3840×2160 @ 60 Hz)
3. **Make the TV the primary display** (select it → check *Make this my main display*)
4. Disable your working monitors
5. Right-click **MonitorSwitcherGUI** → *Save current configuration*
6. Name it `TV_2K_60` (or match your `-ConsoleMode` parameter)
7. Click *Save*

### Verify
Right-click **MonitorSwitcherGUI** → *Load configuration* — both profiles should appear in the list. Select each to verify the switch works.

> Profiles are saved as `.xml` files in `%APPDATA%\MonitorSwitcher\Profiles\` by default.

## Usage

```powershell
.\ConsoleModeSwitcher.ps1
.\ConsoleModeSwitcher.ps1 -ConsoleMode "TV_4K_60" -DesktopMode "Work" -GracePeriodSeconds 600
```

## Auto-start via Task Scheduler

### PowerShell (one-liner)

```powershell
$exePath = "C:\Path\To\powershell.exe"
$args = "-WindowStyle Hidden -File `"C:\Path\To\ConsoleModeSwitcher.ps1`""

$action = New-ScheduledTaskAction -Execute $exePath -Argument $args
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType InteractiveToken -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]0)

Register-ScheduledTask -TaskName ConsoleModeSwitcher -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
```

Replace paths with the actual absolute paths to your script and PowerShell.

## License

MIT
