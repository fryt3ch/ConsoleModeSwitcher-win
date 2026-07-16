param(
    [string]$ConsoleMode = "TV",
    [string]$DesktopMode = "Desktop",
    [string]$ProfilesDir = "$env:APPDATA\MonitorSwitcher\Profiles",
    [string]$Tool = ".\MonitorProfileSwitcher\MonitorSwitcher.exe",
    [string]$ControllerName = "Xbox 360 Controller for Windows",
    [int]$GracePeriodSeconds = 300,
    [int]$WinHoldSeconds = 2
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
'@

function Test-ControllerConnected {
    $devices = Get-PnpDevice | Where-Object { $_.FriendlyName -eq $controllerName -and $_.Status -eq "OK" }
    return [bool]$devices
}

function Test-SteamBigPicture {
    $steam = Get-Process -Name "steamwebhelper" -ErrorAction SilentlyContinue
    if ($steam -and $steam.MainWindowTitle -match "Big Picture") { return $true }
    return $false
}

function Test-WinHeld {
    $keyState = [NativeMethods]::GetAsyncKeyState(0x5B)
    return ($keyState -band 0x8000) -ne 0
}

function Set-ConsoleMode {
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

    Write-Host "  [*]" -ForegroundColor Cyan -NoNewline
    Write-Host " Loading profile: " -ForegroundColor White -NoNewline
    Write-Host "Desktop" -ForegroundColor Blue
    & $tool -load:$desktopModeConfig
    Start-Sleep -Milliseconds 2000

    Write-Host "  [+] " -ForegroundColor Blue -NoNewline
    Write-Host "Desktop Mode enabled" -ForegroundColor Blue
}

# ──────────────────────────────────────────────
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
Write-Host ""

# ─── State ────────────────────────────────────
$lastMode            = $false
$disconnectStartTime = $null
$winHoldStartTime    = $null
$winLastShown        = -1
    $manualOverride      = $false
    $overrideDirection   = $null    # "desktop" or "console"

if (Test-ControllerConnected) {
    $lastMode = $true
    Set-ConsoleMode
}
else {
    Set-DesktopMode
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
    }
    else {
        if ($controllerConnected) {
            if ($null -ne $disconnectStartTime) {
                $wasGone = [math]::Round(((Get-Date) - $disconnectStartTime).TotalSeconds, 0)
                Write-Host "  [+]" -ForegroundColor Green -NoNewline
                Write-Host " Controller reconnected after " -ForegroundColor White -NoNewline
                Write-Host "${wasGone}s" -ForegroundColor Green -NoNewline
                Write-Host " — staying in Console Mode" -ForegroundColor White
                $disconnectStartTime = $null
            }
            if (-not $lastMode) {
                Set-ConsoleMode
                $lastMode = $true
            }
        }
        else {
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
                        $lastMode      = $false
                        $disconnectStartTime = $null
                    }
                }
            }
        }
    }

    Start-Sleep -Milliseconds 500
}
