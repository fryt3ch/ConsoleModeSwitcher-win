param(
    [string]$ConsoleMode = "TV",
    [string]$DesktopMode = "Desktop",
    [string]$ProfilesDir = "$env:APPDATA\MonitorSwitcher\Profiles",
    [string]$Tool = ".\MonitorProfileSwitcher\MonitorSwitcher.exe",
    [string]$ControllerName = "Xbox 360 Controller for Windows",
    [int]$GracePeriodSeconds = 300,
    [int]$WinHoldSeconds = 2,
    [switch]$AutoSwitch,
    [switch]$TVControl,
    [string]$HAServer  = "http://homeassistant.local:8123",
    [string]$HAToken,
    [string]$TVEntity  = "media_player.tv",
    [string]$TVSource,
    [string]$TVHdmiUri,
    [int]$TVStartupSeconds = 5,
    [switch]$TVAutoOff,
    [switch]$TVAutoHome,
    [string]$TVRemoteEntity = "remote.tv"
)

$consoleModeConfig = Join-Path $ProfilesDir "$ConsoleMode.xml"
$desktopModeConfig = Join-Path $ProfilesDir "$DesktopMode.xml"

if (-not [System.IO.Path]::IsPathRooted($Tool)) {
    $Tool = Join-Path $PSScriptRoot $Tool
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class NativeMethods {
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);
}

[StructLayout(LayoutKind.Sequential)]
public struct XINPUT_GAMEPAD {
    public ushort wButtons;
    public byte bLeftTrigger;
    public byte bRightTrigger;
    public short sThumbLX;
    public short sThumbLY;
    public short sThumbRX;
    public short sThumbRY;
}

[StructLayout(LayoutKind.Sequential)]
public struct XINPUT_STATE {
    public uint dwPacketNumber;
    public XINPUT_GAMEPAD Gamepad;
}

public class XInput {
    private delegate uint GetStateDelegate(uint dwUserIndex, ref XINPUT_STATE pState);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LoadLibrary(string lpFileName);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GetProcAddress(IntPtr hModule, string lpProcName);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GetProcAddress(IntPtr hModule, IntPtr lpProcName);

    private static GetStateDelegate _getStateFn = null;
    private static bool _resolved = false;

    private static void Resolve() {
        if (_resolved) return;
        _resolved = true;

        string[] dlls = { "xinput1_4.dll", "xinput1_3.dll", "xinput9_1_0.dll" };

        for (int i = 0; i < dlls.Length; i++) {
            IntPtr hModule = LoadLibrary(dlls[i]);
            if (hModule == IntPtr.Zero) continue;

            IntPtr fn100 = GetProcAddress(hModule, (IntPtr)100);
            if (fn100 != IntPtr.Zero) {
                _getStateFn = (GetStateDelegate)Marshal.GetDelegateForFunctionPointer(
                    fn100, typeof(GetStateDelegate));
                return;
            }

            IntPtr fn = GetProcAddress(hModule, "XInputGetState");
            if (fn != IntPtr.Zero) {
                _getStateFn = (GetStateDelegate)Marshal.GetDelegateForFunctionPointer(
                    fn, typeof(GetStateDelegate));
                return;
            }
        }
    }

    public static uint GetState(uint dwUserIndex, ref XINPUT_STATE pState) {
        if (!_resolved) Resolve();
        if (_getStateFn != null) return _getStateFn(dwUserIndex, ref pState);
        return 0x8007007E;
    }
}
'@ -ErrorAction SilentlyContinue

function Test-ControllerConnected {
    $devices = Get-PnpDevice | Where-Object { $_.FriendlyName -eq $controllerName -and $_.Status -eq "OK" }
    return [bool]$devices
}

function Test-SteamBigPicture {
    $steam = Get-Process -Name "steamwebhelper" -ErrorAction SilentlyContinue
    if ($steam -and $steam.MainWindowTitle -match "Big Picture") { return $true }
    return $false
}

function Test-GuideButtonPressed {
    for ($i = 0; $i -lt 4; $i++) {
        $state = New-Object XINPUT_STATE
        if ([XInput]::GetState($i, [ref]$state) -eq 0) {
            if (($state.Gamepad.wButtons -band 0x0400) -ne 0) {
                return $true
            }
        }
    }
    return $false
}

function Test-WinHeld {
    $keyState = [NativeMethods]::GetAsyncKeyState(0x5B)
    return ($keyState -band 0x8000) -ne 0
}

function Invoke-HAService($domain, $service, $entity, $extraData) {
    $body = @{ entity_id = $entity }
    if ($extraData) { $body += $extraData }
    $uri = "$HAServer/api/services/$domain/$service"
    $json = $body | ConvertTo-Json -Compress -Depth 3

    try {
        $null = Invoke-RestMethod -Uri $uri -Method Post `
            -Headers @{ Authorization = "Bearer $HAToken" } `
            -Body $json `
            -ContentType "application/json"
        return $true
    }
    catch {
        if ($_.ErrorDetails.Message) {
            Write-Host "    [!] " -ForegroundColor Red -NoNewline
            Write-Host "$($_.ErrorDetails.Message)" -ForegroundColor Red
        }
        return $false
    }
}

function Set-ConsoleMode {
    if ($TVControl) {
        Write-Host "  [*]" -ForegroundColor Cyan -NoNewline
        Write-Host " Turning on TV..." -ForegroundColor White
        Invoke-HAService "media_player" "turn_on" $TVEntity

        Start-Sleep -Seconds $TVStartupSeconds

        Write-Host "  [*]" -ForegroundColor Cyan -NoNewline
        Write-Host " TV ready" -ForegroundColor Green

        if ($TVSource) {
            Write-Host "  [*]" -ForegroundColor Cyan -NoNewline
            Write-Host " Switching TV input to $TVSource..." -ForegroundColor White
            $ok = Invoke-HAService "media_player" "select_source" $TVEntity @{ source = $TVSource }
            if (-not $ok -and $TVHdmiUri) {
                Write-Host "  [*]" -ForegroundColor Cyan -NoNewline
                Write-Host " select_source failed, trying play_media..." -ForegroundColor White
                $ok = Invoke-HAService "media_player" "play_media" $TVEntity @{
                    media_content_type = "app"
                    media_content_id   = $TVHdmiUri
                }
            }
            if (-not $ok) {
                Write-Host "  [!] " -ForegroundColor Yellow -NoNewline
                Write-Host "HDMI switch failed — switch manually" -ForegroundColor Yellow
            }
        }
        elseif ($TVHdmiUri) {
            Write-Host "  [*]" -ForegroundColor Cyan -NoNewline
            Write-Host " Switching TV input via play_media..." -ForegroundColor White
            $ok = Invoke-HAService "media_player" "play_media" $TVEntity @{
                media_content_type = "app"
                media_content_id   = $TVHdmiUri
            }
            if (-not $ok) {
                Write-Host "  [!] " -ForegroundColor Yellow -NoNewline
                Write-Host "HDMI switch failed — switch manually" -ForegroundColor Yellow
            }
        }
    }

    Write-Host "  [*]" -ForegroundColor Cyan -NoNewline
    Write-Host " Loading profile: " -ForegroundColor White -NoNewline
    Write-Host $ConsoleMode -ForegroundColor Green
    & $tool -load:$consoleModeConfig
    Start-Sleep -Milliseconds 2000

    Write-Host "  [*]" -ForegroundColor Cyan -NoNewline
    Write-Host " Launching Steam Big Picture..." -ForegroundColor White
    Start-Process "steam://open/bigpicture"
    Write-Host "  [+] " -ForegroundColor Green -NoNewline
    Write-Host "Console Mode enabled" -ForegroundColor Green
}

function Set-DesktopMode {
    if (Test-SteamBigPicture) {
        Write-Host "  [*]" -ForegroundColor Cyan -NoNewline
        Write-Host " Closing Steam Big Picture..." -ForegroundColor White
        Start-Process "steam://close/bigpicture"
    }

    if ($TVControl) {
        if ($TVAutoHome) {
            Write-Host "  [*]" -ForegroundColor Cyan -NoNewline
            Write-Host " Switching TV to home screen..." -ForegroundColor White
            $ok = Invoke-HAService "remote" "send_command" $TVRemoteEntity @{ command = "HOME" }
            if (-not $ok) {
                Write-Host "  [!] " -ForegroundColor Yellow -NoNewline
                Write-Host "send_command failed — skipping home screen" -ForegroundColor Yellow
            }
        }

        if ($TVAutoOff) {
            Write-Host "  [*]" -ForegroundColor Cyan -NoNewline
            Write-Host " Turning off TV..." -ForegroundColor White
            Invoke-HAService "media_player" "turn_off" $TVEntity
        }
    }

    Write-Host "  [*]" -ForegroundColor Cyan -NoNewline
    Write-Host " Loading profile: " -ForegroundColor White -NoNewline
    Write-Host "Desktop" -ForegroundColor Blue
    & $tool -load:$desktopModeConfig
    Start-Sleep -Milliseconds 2000

    Write-Host "  [+] " -ForegroundColor Blue -NoNewline
    Write-Host "Desktop Mode enabled" -ForegroundColor Blue
}

# ──────────────────────────────────────────────
if ($TVControl -and -not $HAToken) {
    Write-Host "  [!]" -ForegroundColor Red -NoNewline
    Write-Host " -TVControl requires -HAToken" -ForegroundColor Red
    exit 1
}
Write-Host ""
Write-Host "  ───  " -ForegroundColor DarkCyan -NoNewline
Write-Host "Console Mode Switcher" -ForegroundColor Cyan -NoNewline
Write-Host "  ───" -ForegroundColor DarkCyan
Write-Host ""

Write-Host "    Console Mode Profile:      " -ForegroundColor DarkGray -NoNewline
Write-Host $ConsoleMode -ForegroundColor White
Write-Host "    Grace period: " -ForegroundColor DarkGray -NoNewline
Write-Host "${GracePeriodSeconds}s" -ForegroundColor White
Write-Host "    Win override: " -ForegroundColor DarkGray -NoNewline
Write-Host "hold ${WinHoldSeconds}s" -ForegroundColor White

$triggerMode = if ($AutoSwitch) { "Auto (on connect)" } else { "Guide button" }
Write-Host "    Trigger: " -ForegroundColor DarkGray -NoNewline
Write-Host $triggerMode -ForegroundColor White

if ($TVControl) {
    $tvInfo = "$TVEntity  |  Startup: ${TVStartupSeconds}s"
    if ($TVSource) { $tvInfo += "  |  $TVSource" }
    elseif ($TVHdmiUri) { $tvInfo += "  |  play_media" }
    if ($TVAutoHome) { $tvInfo += "  |  home on exit ($TVRemoteEntity)" }
    if ($TVAutoOff) { $tvInfo += "  |  off on exit" }
    Write-Host "    TV Control: " -ForegroundColor DarkGray -NoNewline
    Write-Host $tvInfo -ForegroundColor White
}
Write-Host ""

# ─── State ────────────────────────────────────
$lastMode            = $false
$disconnectStartTime = $null
$winHoldStartTime    = $null
$winLastShown        = -1
    $manualOverride      = $false
    $overrideDirection   = $null    # "desktop" or "console"
    $announcedController = $false

if (Test-ControllerConnected) {
    if ($AutoSwitch) {
        Set-ConsoleMode
        $lastMode = $true
    }
    else {
        Write-Host "  [+] " -ForegroundColor Green -NoNewline
        Write-Host "Controller detected — press Guide button to enter Console Mode" -ForegroundColor Green
        $announcedController = $true
    }
}

# ─── Main Loop ────────────────────────────────
while ($true) {

    $winHeld = Test-WinHeld

    # ── Win hold tracking ──
    if ($winHeld) {
        if ($null -eq $winHoldStartTime) {
            $winHoldStartTime = Get-Date
            $targetMode = if ($lastMode) { "Desktop" } else { "Console" }
            Write-Host "  [WIN]" -ForegroundColor Yellow -NoNewline
            Write-Host " Hold for " -ForegroundColor DarkYellow -NoNewline
            Write-Host "${WinHoldSeconds}s" -ForegroundColor Yellow -NoNewline
            Write-Host " to force $targetMode Mode" -ForegroundColor DarkYellow
        }
        else {
            $winElapsed    = ((Get-Date) - $winHoldStartTime).TotalSeconds
            $winRemaining  = [math]::Max(0, $WinHoldSeconds - [math]::Floor($winElapsed))
            if ($winRemaining -ne $winLastShown) {
                if ($winRemaining -gt 0) {
                    Write-Host "  [WIN]" -ForegroundColor Yellow -NoNewline
                    Write-Host "  " -NoNewline
                    Write-Host "$winRemaining..." -ForegroundColor DarkYellow
                }
                $winLastShown = $winRemaining
            }
        }
    }
    else {
        if ($null -ne $winHoldStartTime) {
            $heldFor = [math]::Round(((Get-Date) - $winHoldStartTime).TotalSeconds, 1)
            if ($heldFor -lt $WinHoldSeconds) {
                Write-Host "  [WIN]" -ForegroundColor DarkGray -NoNewline
                Write-Host " Released after ${heldFor}s — cancelled" -ForegroundColor DarkGray
            }
            $winHoldStartTime = $null
            $winLastShown     = -1
        }
    }

    # ── Win override trigger ──
    if ($null -ne $winHoldStartTime -and ((Get-Date) - $winHoldStartTime).TotalSeconds -ge $WinHoldSeconds) {
        if ($lastMode) {
            Write-Host "  [WIN]" -ForegroundColor Red -NoNewline
            Write-Host " Override triggered — forcing Desktop Mode" -ForegroundColor Red
            Set-DesktopMode
            $lastMode            = $false
            $disconnectStartTime = $null
            $manualOverride      = $true
            $overrideDirection   = "desktop"
        }
        else {
            Write-Host "  [WIN]" -ForegroundColor Green -NoNewline
            Write-Host " Override triggered — forcing Console Mode" -ForegroundColor Green
            Set-ConsoleMode
            $lastMode            = $true
            $disconnectStartTime = $null
            $manualOverride      = $true
            $overrideDirection   = "console"
        }
        $winHoldStartTime = $null
        $winLastShown     = -1
    }

    # ── Controller check ──
    $controllerConnected = Test-ControllerConnected

    if ($manualOverride) {
        if ($overrideDirection -eq "desktop" -and -not $controllerConnected) {
            Write-Host "  [o]" -ForegroundColor DarkGray -NoNewline
            Write-Host " Manual override cleared — ready for next connect" -ForegroundColor DarkGray
            $manualOverride    = $false
            $overrideDirection = $null
        }
        elseif ($overrideDirection -eq "console" -and $controllerConnected) {
            Write-Host "  [o]" -ForegroundColor DarkGray -NoNewline
            Write-Host " Manual override cleared — controller present, resuming normal operation" -ForegroundColor DarkGray
            $manualOverride    = $false
            $overrideDirection = $null
        }

        if ($overrideDirection -eq "desktop" -and $controllerConnected) {
            for ($tick = 0; $tick -lt 10; $tick++) {
                if (Test-GuideButtonPressed) {
                    Write-Host "  [G]" -ForegroundColor Green -NoNewline
                    Write-Host " Guide button detected — entering Console Mode" -ForegroundColor Green
                    Set-ConsoleMode
                    $lastMode            = $true
                    $disconnectStartTime = $null
                    $manualOverride      = $false
                    $overrideDirection   = $null
                    break
                }
                Start-Sleep -Milliseconds 50
            }
        }
        else {
            Start-Sleep -Milliseconds 500
        }
    }
    else {
        if ($controllerConnected) {
            if ($null -ne $disconnectStartTime) {
                $wasGone = [math]::Round(((Get-Date) - $disconnectStartTime).TotalSeconds, 0)
                Write-Host "  [+]" -ForegroundColor Green -NoNewline
                Write-Host " Controller reconnected after " -ForegroundColor White -NoNewline
                Write-Host "${wasGone}s" -ForegroundColor Green
                $disconnectStartTime = $null
                $announcedController = $false
            }

            if (-not $announcedController) {
                if ($AutoSwitch) {
                    Write-Host "  [+] " -ForegroundColor Green -NoNewline
                    Write-Host "Controller detected — entering Console Mode" -ForegroundColor Green
                }
                else {
                    Write-Host "  [+] " -ForegroundColor Green -NoNewline
                    Write-Host "Controller detected — press Guide button to enter Console Mode" -ForegroundColor Green
                }
                $announcedController = $true
            }

            if (-not $lastMode) {
                if ($AutoSwitch) {
                    Set-ConsoleMode
                    $lastMode = $true
                }
                else {
                    for ($tick = 0; $tick -lt 10; $tick++) {
                        if (Test-GuideButtonPressed) {
                            Write-Host "  [G]" -ForegroundColor Green -NoNewline
                            Write-Host " Guide button detected — entering Console Mode" -ForegroundColor Green
                            Set-ConsoleMode
                            $lastMode = $true
                            break
                        }
                        Start-Sleep -Milliseconds 50
                    }
                }
            }
            else {
                Start-Sleep -Milliseconds 500
            }
        }
        else {
            if ($announcedController) {
                $announcedController = $false
            }

            if ($lastMode) {
                if ($null -eq $disconnectStartTime) {
                    $disconnectStartTime = Get-Date
                    Write-Host "  [-]" -ForegroundColor Yellow -NoNewline
                    Write-Host " Controller disconnected — " -ForegroundColor White -NoNewline
                    Write-Host "waiting ${GracePeriodSeconds}s" -ForegroundColor Yellow -NoNewline
                    Write-Host " before switching..." -ForegroundColor White
                }
                else {
                    $elapsed = ((Get-Date) - $disconnectStartTime).TotalSeconds
                    if ($elapsed -ge $GracePeriodSeconds) {
                        Write-Host "  [!]" -ForegroundColor Red -NoNewline
                        Write-Host " Grace period expired — switching to Desktop Mode" -ForegroundColor Red
                        Set-DesktopMode
                        $lastMode            = $false
                        $disconnectStartTime = $null
                        $announcedController = $false
                    }
                }
            }

            Start-Sleep -Milliseconds 500
        }
    }
}
