
<h1 align="center">
  Console Mode Switcher
</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Windows-✓-0078D6?style=flat-square&logo=windows" alt="Windows" />
  <img src="https://img.shields.io/badge/PowerShell-✓-5391FE?style=flat-square&logo=powershell" alt="PowerShell" />
  <img src="https://img.shields.io/badge/License-MIT-yellow?style=flat-square" alt="License: MIT" />
</p>

<p align="center">
  <b>Switch to console mode by pressing the Xbox Guide button.</b><br/>
  Detects gamepad via PnP, waits for Guide button press, then loads the matching
  <code>MonitorSwitcher</code> profile and launches Steam Big Picture.<br/>
  Optionally controls your TV (power on/off, HDMI switch, home screen) via
  <b>Home Assistant</b>.
</p>

<p align="center">
  <b>Windows only.</b>
</p>

---

## How It Works

The script polls controller presence every 500ms. By default it waits for the **Xbox Guide button** press — it does **not** switch automatically on connect.

| Event | Action |
|-------|--------|
| **Controller connected** | Prints detection message, waits for Guide button |
| **Guide button pressed** | Turns on TV (if `-TVControl`), switches HDMI, loads console profile, launches Steam BPM |
| **Controller disconnected + grace period expires** | Switches TV to home screen (if `-TVAutoHome`), turns off TV (if `-TVAutoOff`), loads desktop profile |
| **`-AutoSwitch` flag** | Switches to console mode immediately when the controller connects (old behavior) |
| **Win key held for 2s** | Manual override — force-switch to the opposite mode |

> Guide button detection requires [DirectX End-User Runtime](#guide-button-support) (`xinput1_3.dll`).
> If not installed, use `-AutoSwitch` instead.

## Dependencies

- [**MonitorSwitcher**](https://github.com/cooolinho/monitor-profile-switcher) (`MonitorSwitcher.exe`) — loads and saves monitor configurations. Download from [SourceForge](https://sourceforge.net/projects/monitorswitcher/).
- Monitor profiles (`.xml`) saved via MonitorSwitcherGUI — one for console mode, one for desktop.
- **Home Assistant** (optional) — if you want TV power/HDMI/home-screen control. Requires a [long-lived access token](https://www.home-assistant.io/docs/authentication/#your-account-profile).

## Parameters

### Core

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ConsoleMode` | `string` | `TV` | Profile name for console mode (without `.xml`) |
| `DesktopMode` | `string` | `Desktop` | Profile name for desktop mode (without `.xml`) |
| `ProfilesDir` | `string` | `$env:APPDATA\MonitorSwitcher\Profiles` | Folder containing `.xml` profiles |
| `Tool` | `string` | `.\MonitorProfileSwitcher\MonitorSwitcher.exe` | Path to `MonitorSwitcher.exe` |
| `ControllerName` | `string` | `Xbox 360 Controller for Windows` | PnP friendly name to detect |
| `GracePeriodSeconds` | `int` | `300` | Seconds to wait before switching to desktop after disconnect |
| `WinHoldSeconds` | `int` | `2` | Seconds to hold Win key for manual override |

### Guide Button

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `AutoSwitch` | `switch` | `✗` | Switch to console mode immediately on controller connect (disables guide button wait) |

### TV Control (Home Assistant)

All require `-TVControl` to be set.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `TVControl` | `switch` | `✗` | Enable TV control via Home Assistant |
| `HAServer` | `string` | `http://homeassistant.local:8123` | Home Assistant server URL |
| `HAToken` | `string` | *required* | HA long-lived access token |
| `TVEntity` | `string` | `media_player.tv` | HA entity ID of your TV |
| `TVSource` | `string` | — | HDMI input name for `select_source` (e.g. `"HDMI 1"`) |
| `TVHdmiUri` | `string` | — | Deep-link URI for `play_media` HDMI switch (Android TV fallback) |
| `TVStartupSeconds` | `int` | `5` | Delay after TV power-on before proceeding |
| `TVAutoHome` | `switch` | `✗` | Switch TV to home screen via `remote.send_command HOME` on exit |
| `TVAutoOff` | `switch` | `✗` | Turn off TV on exit |

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
# Default: wait for Guide button, no TV control
.\ConsoleModeSwitcher.ps1

# Old behavior: auto-switch on controller connect
.\ConsoleModeSwitcher.ps1 -AutoSwitch

# Full setup: Guide button + TV on/off + home screen on exit
.\ConsoleModeSwitcher.ps1 `
    -TVControl -HAToken "eyJhbGci..." `
    -TVEntity "media_player.googletv4948" `
    -TVHdmiUri "content://android.media.tv/passthrough/com.tcl.tvinput%2F...HW1413744128" `
    -TVAutoHome -TVAutoOff

# With explicit HDMI source (select_source in HA)
.\ConsoleModeSwitcher.ps1 `
    -TVControl -HAToken "eyJhbGci..." `
    -TVEntity "media_player.living_room_tv" `
    -TVSource "HDMI 1" -TVAutoHome -TVAutoOff
```

## TV Control Setup

### 1. Get a Home Assistant token

1. Open your **HA profile** (icon in bottom-left corner)
2. Scroll to **Long-Lived Access Tokens** → **Create Token**
3. Give it a name (e.g. `"Console Mode Switcher"`) → **OK**
4. Copy the token — it is shown **only once**

### 2. Find your TV entity

1. In HA: **Developer Tools** → **States**
2. Filter by `media_player.` — find your TV's entity ID
3. Example: `media_player.googletv4948`, `media_player.living_room_tv`

### 3. HDMI switching (Android / Google TV)

Most Android TV integrations in HA do **not** support `select_source`. Use `-TVHdmiUri`
with a deep-link URI to switch HDMI inputs.

#### Known HDMI URIs

Use these with `-TVHdmiUri`. If your TV model isn't listed, find the URI by running
`adb shell dumpsys tv input` on your Android TV device.

**TCL Google TV**

| Input | URI |
|-------|-----|
| HDMI 1 | `content://android.media.tv/passthrough/com.tcl.tvinput%2F.passthroughinput.TvPassThroughService%2FHW1413744128` |
| HDMI 2 | `content://android.media.tv/passthrough/com.tcl.tvinput%2F.passthroughinput.TvPassThroughService%2FHW1413744129` |
| HDMI 3 | `content://android.media.tv/passthrough/com.tcl.tvinput%2F.passthroughinput.TvPassThroughService%2FHW1413744130` |

### 4. Home screen on exit (`-TVAutoHome`)

Uses `remote.send_command` with `HOME` command. The remote entity is derived automatically from `-TVEntity` by replacing `media_player.` with `remote.` (e.g. `media_player.googletv4948` → `remote.googletv4948`).

## Guide Button Support

The guide button (central Xbox button) is detected via the **undocumented** `XInputGetState` at ordinal #100 in `xinput1_3.dll`.

This DLL is part of the [DirectX End-User Runtime (June 2010)](https://www.microsoft.com/en-us/download/details.aspx?id=8109).

**If the guide button doesn't work:**
- Install the DirectX Runtime from the link above
- Or use `-AutoSwitch` to revert to auto-switch-on-connect behavior

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

## Extra

### Disabling Steam Big Picture intro video

1. Execute commands:

```powershell
$steamPath = "C:\Program Files (x86)\Steam"
$blankIntroUrl = "https://github.com/fryt3ch/ConsoleModeSwitcher-win/releases/download/Extra/bigpicture_startup_blank.webm"

$moviesPath = "$steamPath\config\uioverrides\movies"

New-Item -ItemType Directory -Path $moviesPath -Force -ErrorAction SilentlyContinue

Invoke-WebRequest -Uri $blankIntroUrl -OutFile "$moviesPath\bigpicture_startup.webm"
```

2. Restart Steam.

## License

MIT
