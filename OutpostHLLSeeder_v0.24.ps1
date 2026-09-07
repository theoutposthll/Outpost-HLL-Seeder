<#
===============================================================================
THE OUTPOST HLL AUTO-SEEDER
Transparent PowerShell Edition - Version 0.24
===============================================================================
Uses UTC for scheduling so every machine triggers at the same real-world moment.
Configuration is stored in readable config.txt.
No administrator rights are requested.
===============================================================================
#>

param(
    [switch]$Setup,
    [switch]$Scheduler,
    [switch]$RunNow,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

$SeederVersion = "0.24"

$ServerName = "The Outpost HLL"
$ServerAddress = "67.217.48.14:8772"
$CrconPublicInfoUrl = "https://op2.hlladmin.com/api/get_public_info"
$SeedStartTimeUrl = "https://the-outpost.ngrok.app/api/get_seed_start_time"
$SteamPath = "C:\Program Files (x86)\Steam\steam.exe"
$HllAppId = "686810"

# Exact known Hell Let Loose game process names.
$HllProcessNames = @(
    "HLL-Win64-Shipping",
    "HLL",
    "HellLetLoose"
)

$AppDirectory = Join-Path $env:LOCALAPPDATA "OutpostHLLSeeder"
$InstalledPs1 = Join-Path $AppDirectory "OutpostHLLSeeder.ps1"
$InstalledBat = Join-Path $AppDirectory "OutpostHLLSeeder.bat"
$ConfigFile = Join-Path $AppDirectory "config.txt"
$LogFile = Join-Path $AppDirectory "seeder.log"
$ErrorLogFile = Join-Path $AppDirectory "errors.txt"
$StatusFile = Join-Path $AppDirectory "scheduler_status.txt"
$UpdateNoticeFile = Join-Path $AppDirectory "update_notice.txt"

$StartupDirectory = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
$StartupFile = Join-Path $StartupDirectory "Outpost HLL Auto-Seeder.cmd"
$SchedulerPollSeconds = 15

function Write-Log {
    param([string]$Message = "")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = if ($Message) { "[$timestamp] $Message" } else { "" }
    Write-Host $line
    try {
        New-Item -ItemType Directory -Force -Path $AppDirectory | Out-Null
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    } catch {}
}

function Write-ErrorLog {
    param(
        [string]$Context,
        $ErrorRecord
    )

    # Dedicated plain-text error log. This is separate from the normal activity
    # log so a user can send errors.txt when asking for help.
    try {
        New-Item -ItemType Directory -Force -Path $AppDirectory | Out-Null

        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $message = if ($ErrorRecord) { $ErrorRecord.Exception.Message } else { "Unknown error" }
        $position = if ($ErrorRecord -and $ErrorRecord.InvocationInfo) {
            $ErrorRecord.InvocationInfo.PositionMessage
        } else {
            ""
        }

        $entry = @"
===============================================================================
TIME:    $timestamp
CONTEXT: $Context
ERROR:   $message
$position
===============================================================================

"@

        Add-Content -Path $ErrorLogFile -Value $entry -Encoding UTF8
    }
    catch {
        # Error logging itself must never crash the seeder.
    }
}


# UPDATE INVARIANT:
# AUTO_UPDATE_SEED_TIME is a persistent user preference. Future install/repair/
# update code must preserve an existing installed value and only add the default
# when the key does not yet exist.
function Read-Config {
    if (-not (Test-Path $ConfigFile)) { throw "Configuration file not found: $ConfigFile" }

    $values = @{}
    foreach ($rawLine in Get-Content $ConfigFile) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith("#")) { continue }

        $parts = $line.Split("=", 2)
        if ($parts.Count -ne 2) { continue }

        $values[$parts[0].Trim()] = $parts[1].Trim()
    }

    $required = @(
        "START_TIME_UTC",
        "AUTO_UPDATE_SEED_TIME",
        "START_BELOW_PLAYERS",
        "STOP_ABOVE_PLAYERS",
        "SHUTDOWN_CHANCE_ONE_IN",
        "CHECK_INTERVAL_SECONDS",
        "SPLASH_WAIT_SECONDS",
        "WAKE_BEFORE_MINUTES",
        "RETURN_TO_SLEEP_AFTER_SEEDING",
        "RETURN_TO_SLEEP_DELAY_SECONDS"
    )

    foreach ($name in $required) {
        if (-not $values.ContainsKey($name)) { throw "Missing configuration value: $name" }
    }

    if ($values["START_TIME_UTC"] -notmatch '^([01]\d|2[0-3]):[0-5]\d$') {
        throw "START_TIME_UTC must be HH:MM in 24-hour UTC format."
    }

    if ($values["AUTO_UPDATE_SEED_TIME"] -notmatch '^(?i:true|false)$') {
        throw "AUTO_UPDATE_SEED_TIME must be true or false."
    }

    if ([int]$values["SHUTDOWN_CHANCE_ONE_IN"] -lt 1) {
        throw "SHUTDOWN_CHANCE_ONE_IN must be 1 or greater."
    }

    if ($values["RETURN_TO_SLEEP_AFTER_SEEDING"] -notmatch '^(?i:true|false)$') {
        throw "RETURN_TO_SLEEP_AFTER_SEEDING must be true or false."
    }

    if ([int]$values["RETURN_TO_SLEEP_DELAY_SECONDS"] -lt 0) {
        throw "RETURN_TO_SLEEP_DELAY_SECONDS must be 0 or greater."
    }

    return @{
        StartTimeUtc = $values["START_TIME_UTC"]
        AutoUpdateSeedTime = [System.Convert]::ToBoolean($values["AUTO_UPDATE_SEED_TIME"])
        StartBelowPlayers = [int]$values["START_BELOW_PLAYERS"]
        StopAbovePlayers = [int]$values["STOP_ABOVE_PLAYERS"]
        ShutdownChanceOneIn = [int]$values["SHUTDOWN_CHANCE_ONE_IN"]
        CheckIntervalSeconds = [int]$values["CHECK_INTERVAL_SECONDS"]
        SplashWaitSeconds = [int]$values["SPLASH_WAIT_SECONDS"]
        WakeBeforeMinutes = [int]$values["WAKE_BEFORE_MINUTES"]
        ReturnToSleepAfterSeeding = [System.Convert]::ToBoolean($values["RETURN_TO_SLEEP_AFTER_SEEDING"])
        ReturnToSleepDelaySeconds = [int]$values["RETURN_TO_SLEEP_DELAY_SECONDS"]
    }
}

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class OutpostWin32
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    // Wakeable timer APIs. SetWaitableTimer with fResume=true asks Windows to
    // wake the machine when the timer expires.
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr CreateWaitableTimer(
        IntPtr lpTimerAttributes,
        bool bManualReset,
        string lpTimerName
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetWaitableTimer(
        IntPtr hTimer,
        ref long pDueTime,
        int lPeriod,
        IntPtr pfnCompletionRoutine,
        IntPtr lpArgToCompletionRoutine,
        bool fResume
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CancelWaitableTimer(IntPtr hTimer);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("powrprof.dll", SetLastError = true)]
    public static extern bool SetSuspendState(
        bool hibernate,
        bool forceCritical,
        bool disableWakeEvent
    );
}
"@

$WM_KEYDOWN = 0x0100
$WM_KEYUP = 0x0101
$VK_SPACE = 0x20


function Get-NextWakeUtc {
    param(
        [string]$StartTimeUtc,
        [int]$WakeBeforeMinutes
    )

    $parts = $StartTimeUtc.Split(":")
    $hour = [int]$parts[0]
    $minute = [int]$parts[1]

    $nowUtc = [DateTime]::UtcNow

    $seedUtc = New-Object DateTime(
        $nowUtc.Year,
        $nowUtc.Month,
        $nowUtc.Day,
        $hour,
        $minute,
        0,
        [DateTimeKind]::Utc
    )

    $wakeUtc = $seedUtc.AddMinutes(-$WakeBeforeMinutes)

    # If today's wake time has already passed, arm tomorrow's timer.
    if ($wakeUtc -le $nowUtc) {
        $wakeUtc = $wakeUtc.AddDays(1)
    }

    return $wakeUtc
}


function Set-WakeTimer {
    param(
        [string]$StartTimeUtc,
        [int]$WakeBeforeMinutes,
        [IntPtr]$ExistingTimer = [IntPtr]::Zero
    )

    if ($ExistingTimer -eq [IntPtr]::Zero) {
        $timer = [OutpostWin32]::CreateWaitableTimer(
            [IntPtr]::Zero,
            $true,
            "OutpostHLLSeederWakeTimer"
        )

        if ($timer -eq [IntPtr]::Zero) {
            $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "CreateWaitableTimer failed. Windows error code: $code"
        }
    }
    else {
        $timer = $ExistingTimer
    }

    $wakeUtc = Get-NextWakeUtc `
        -StartTimeUtc $StartTimeUtc `
        -WakeBeforeMinutes $WakeBeforeMinutes

    # SetWaitableTimer accepts an absolute UTC FILETIME when the value is
    # positive. DateTime.ToFileTimeUtc() gives exactly that representation.
    [long]$dueTime = $wakeUtc.ToFileTimeUtc()

    $ok = [OutpostWin32]::SetWaitableTimer(
        $timer,
        [ref]$dueTime,
        0,
        [IntPtr]::Zero,
        [IntPtr]::Zero,
        $true
    )

    if (-not $ok) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "SetWaitableTimer failed. Windows error code: $code"
    }

    $lastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()

    Write-Log (
        "Wake timer armed for " +
        $wakeUtc.ToString("yyyy-MM-dd HH:mm:ss") +
        " UTC (" +
        $WakeBeforeMinutes +
        " minute(s) before seeding time)."
    )

    if ($lastError -eq 50) {
        Write-Log (
            "WARNING: Windows reported ERROR_NOT_SUPPORTED for wake resume. " +
            "This PC/firmware may not support waking from this sleep state."
        )
    }

    return $timer
}



function Write-SchedulerStatus {
    param(
        [string]$State,
        [Nullable[DateTime]]$ArmedWakeUtc = $null
    )

    try {
        $wakeText = ""
        if ($null -ne $ArmedWakeUtc) {
            $wakeText = ([DateTime]$ArmedWakeUtc).ToString("yyyy-MM-dd HH:mm:ss")
        }

        $lines = @(
            "Version=$SeederVersion",
            "PID=$PID",
            "State=$State",
            "LastHeartbeatUtc=$([DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss'))",
            "ArmedWakeUtc=$wakeText"
        )

        Set-Content -Path $StatusFile -Value $lines -Encoding ASCII
    }
    catch {
        Write-ErrorLog -Context "Writing scheduler status" -ErrorRecord $_
    }
}


function Read-SchedulerStatus {
    if (-not (Test-Path $StatusFile)) {
        return $null
    }

    try {
        $status = @{}

        foreach ($line in Get-Content $StatusFile) {
            if ($line -match '^\s*([^=]+)=(.*)$') {
                $status[$matches[1].Trim()] = $matches[2].Trim()
            }
        }

        return $status
    }
    catch {
        return $null
    }
}


function Test-SchedulerStatusFresh {
    param(
        [hashtable]$Status
    )

    if ($null -eq $Status -or -not $Status.ContainsKey("LastHeartbeatUtc")) {
        return $false
    }

    try {
        $heartbeat = [DateTime]::SpecifyKind(
            [DateTime]::ParseExact(
                $Status["LastHeartbeatUtc"],
                "yyyy-MM-dd HH:mm:ss",
                [Globalization.CultureInfo]::InvariantCulture
            ),
            [DateTimeKind]::Utc
        )

        return (([DateTime]::UtcNow - $heartbeat).TotalMinutes -lt 3)
    }
    catch {
        return $false
    }
}


function Show-WakeTimerStatus {
    $config = Read-Config

    $nextWake = Get-NextWakeUtc `
        -StartTimeUtc $config.StartTimeUtc `
        -WakeBeforeMinutes $config.WakeBeforeMinutes

    $status = Read-SchedulerStatus
    $fresh = Test-SchedulerStatusFresh -Status $status

    Write-Host ""
    Write-Host "Configured seeding time (UTC): $($config.StartTimeUtc)"
    Write-Host "Wake-before period:             $($config.WakeBeforeMinutes) minute(s)"
    Write-Host "Next requested wake (UTC):      $($nextWake.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Host ""

    if ($fresh) {
        Write-Host "Background scheduler:           RUNNING"
        Write-Host "Seeder wake timer:              $($status["State"])"

        if ($status.ContainsKey("ArmedWakeUtc") -and $status["ArmedWakeUtc"]) {
            Write-Host "Timer armed for (UTC):          $($status["ArmedWakeUtc"])"
        }

        Write-Host "Scheduler PID:                  $($status["PID"])"
        Write-Host "Last heartbeat (UTC):           $($status["LastHeartbeatUtc"])"
    }
    elseif ($null -ne $status) {
        Write-Host "Background scheduler:           NOT CONFIRMED"
        Write-Host "Seeder wake timer:              NOT CONFIRMED"
        Write-Host ""
        Write-Host "A scheduler status file exists, but its heartbeat is stale."
        Write-Host "Use option 6 (Reinstall / repair setup) if this persists."
    }
    else {
        Write-Host "Background scheduler:           NOT DETECTED"
        Write-Host "Seeder wake timer:              NOT CONFIRMED"
        Write-Host ""
        Write-Host "No scheduler status file has been written yet."
        Write-Host "Use option 6 (Reinstall / repair setup) if this persists."
    }

    Write-Host ""
    Write-Host "Windows' full wake-timer list requires administrator privileges"
    Write-Host "and is not needed for normal operation."
}

function Convert-ToSeederVersion {
    param([string]$Value)
    try {
        $clean = ([string]$Value).Trim()
        if ($clean.StartsWith("v", [System.StringComparison]::OrdinalIgnoreCase)) {
            $clean = $clean.Substring(1)
        }
        return [Version]$clean
    }
    catch { return $null }
}

function Check-SeederVersionFromWeb {
    # Read-only informational check. This never downloads, installs or executes code.
    try {
        $remote = Invoke-RestMethod `
            -Uri $SeedStartTimeUrl `
            -Method Get `
            -TimeoutSec 10 `
            -ErrorAction Stop

        $latestText = [string]$remote.latest_seeder_version
        if ([string]::IsNullOrWhiteSpace($latestText)) { return }

        $currentVersion = Convert-ToSeederVersion -Value $SeederVersion
        $latestVersion = Convert-ToSeederVersion -Value $latestText
        if ($null -eq $currentVersion -or $null -eq $latestVersion) { return }
        if ($latestVersion -le $currentVersion) { return }

        $latest = $latestVersion.ToString()

        try {
            if (Test-Path -LiteralPath $UpdateNoticeFile) {
                $seen = (Get-Content -LiteralPath $UpdateNoticeFile -Raw -ErrorAction Stop).Trim()
                if ($seen -eq $latest) { return }
            }
        }
        catch {}

        Write-Log "UPDATE AVAILABLE: Seeder v$latest is available. Current version is v$SeederVersion."

        try {
            $shell = New-Object -ComObject WScript.Shell
            [void]$shell.Popup(
                "A new version of The Outpost HLL Auto-Seeder is available.`r`n`r`n" +
                "Installed: v$SeederVersion`r`n" +
                "Available: v$latest`r`n`r`n" +
                "Please download the latest version from the link in The Outpost Discord.",
                0,
                "Outpost HLL Auto-Seeder - Update Available",
                64
            )
        }
        catch {}

        try { Set-Content -LiteralPath $UpdateNoticeFile -Value $latest -Encoding UTF8 } catch {}
    }
    catch {
        Write-Log "Seeder version check unavailable. Continuing normally."
    }
}


function Update-SeedStartTimeFromWeb {
    param(
        [hashtable]$Config,
        [string]$TargetConfigPath = $ConfigFile
    )

    # User-controlled opt-out. When false, START_TIME_UTC is entirely local and
    # no request is made to the Outpost seed-time endpoint.
    if (-not $Config.AutoUpdateSeedTime) {
        Write-Log "Automatic seed-time updates are disabled. Using configured START_TIME_UTC=$($Config.StartTimeUtc)."
        return $false
    }

    try {
        $remote = Invoke-RestMethod `
            -Uri $SeedStartTimeUrl `
            -Method Get `
            -TimeoutSec 10 `
            -ErrorAction Stop

        $newTime = [string]$remote.start_time_utc

        if ($newTime -notmatch '^(?:[01]\d|2[0-3]):[0-5]\d$') {
            Write-Log "Remote seed time was invalid. Keeping current START_TIME_UTC=$($Config.StartTimeUtc)."
            return $false
        }

        if ($newTime -eq [string]$Config.StartTimeUtc) {
            Write-Log "Remote seed time confirmed unchanged at $newTime UTC."
            return $false
        }

        $oldTime = [string]$Config.StartTimeUtc

        $lines = @(Get-Content -LiteralPath $TargetConfigPath -ErrorAction Stop)
        $found = $false

        $lines = @($lines | ForEach-Object {
            if ($_ -match '^\s*START_TIME_UTC\s*=') {
                $found = $true
                "START_TIME_UTC=$newTime"
            }
            else {
                $_
            }
        })

        if (-not $found) {
            $lines += "START_TIME_UTC=$newTime"
        }

        Set-Content -LiteralPath $TargetConfigPath -Value $lines -Encoding UTF8

        # Keep the in-memory config in sync with what was persisted.
        $Config.StartTimeUtc = $newTime

        Write-Log "Remote schedule updated: $oldTime UTC -> $newTime UTC. Saved as last-known-good time."
        return $true
    }
    catch {
        Write-Log "Remote seed time unavailable. Keeping current START_TIME_UTC=$($Config.StartTimeUtc)."
        return $false
    }
}


function Get-PublicServerInfo {
    # Public CRCON endpoint; no credentials are used or required.
    # Keeping this in its own function means all population reads use the same
    # timeout/error behavior and makes the external call easy to audit.
    return Invoke-RestMethod `
        -Uri $CrconPublicInfoUrl `
        -Method Get `
        -TimeoutSec 15 `
        -ErrorAction Stop
}


function Get-PlayerCount {
    $data = Get-PublicServerInfo
    [int]$data.result.player_count
}

function Get-HllProcesses {
    try {
        $processes = @()

        foreach ($name in $HllProcessNames) {
            $matches = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
            if ($matches.Count -gt 0) {
                $processes += $matches
            }
        }

        return @($processes | Sort-Object Id -Unique)
    }
    catch {
        return @()
    }
}


function Find-HllWindow {
    # Only accept windows owned by exact known HLL processes.
    $hllProcesses = @(Get-HllProcesses)
    if ($hllProcesses.Count -eq 0) {
        return [IntPtr]::Zero
    }

    $hllPids = @{}
    foreach ($process in $hllProcesses) {
        $hllPids[[uint32]$process.Id] = $true
    }

    $script:FoundHllWindow = [IntPtr]::Zero

    $callback = [OutpostWin32+EnumWindowsProc] {
        param([IntPtr]$hWnd, [IntPtr]$lParam)

        if (-not [OutpostWin32]::IsWindowVisible($hWnd)) {
            return $true
        }

        [uint32]$windowProcessId = 0
        [void][OutpostWin32]::GetWindowThreadProcessId($hWnd, [ref]$windowProcessId)

        if ($hllPids.ContainsKey($windowProcessId)) {
            $script:FoundHllWindow = $hWnd
            return $false
        }

        return $true
    }

    [void][OutpostWin32]::EnumWindows($callback, [IntPtr]::Zero)
    return $script:FoundHllWindow
}


function Wait-ForHllWindow {
    param([int]$TimeoutSeconds = 30)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        $window = Find-HllWindow
        if ($window -ne [IntPtr]::Zero) {
            return $window
        }

        Start-Sleep -Seconds 1
    }

    return [IntPtr]::Zero
}


function Test-HllRunning {
    return (@(Get-HllProcesses).Count -gt 0)
}


function Get-OtherSteamGameProcess {
    # Steam itself is allowed. We only block an active game executable living
    # under a Steam library's steamapps\common folder and owning a visible
    # main window. HLL is excluded because it is handled separately above.
    try {
        $processes = @(Get-CimInstance Win32_Process -ErrorAction Stop)

        foreach ($processInfo in $processes) {
            $path = [string]$processInfo.ExecutablePath
            if (-not $path) {
                continue
            }

            if ($path -notmatch '(?i)\\steamapps\\common\\') {
                continue
            }

            $baseName = [IO.Path]::GetFileNameWithoutExtension($path)

            if ($HllProcessNames -contains $baseName) {
                continue
            }

            try {
                $process = Get-Process -Id ([int]$processInfo.ProcessId) -ErrorAction Stop
            }
            catch {
                continue
            }

            if ($process.MainWindowHandle -eq [IntPtr]::Zero) {
                continue
            }

            return [PSCustomObject]@{
                ProcessName = $process.ProcessName
                ProcessId = $process.Id
                Path = $path
                WindowTitle = $process.MainWindowTitle
            }
        }

        return $null
    }
    catch {
        Write-Log "WARNING: Could not check for another active Steam game: $($_.Exception.Message)"
        Write-ErrorLog -Context "Checking for another active Steam game" -ErrorRecord $_
        return $null
    }
}


function Start-Hll {
    Write-Log "Launching Hell Let Loose."
    Write-Log "Target server: $ServerAddress"

    Start-Process -FilePath $SteamPath -ArgumentList @(
        "-applaunch",
        $HllAppId,
        "-dev",
        "+connect",
        $ServerAddress
    )
}

function Invoke-HllSplashBypass {
    param([int]$WaitSeconds)

    Write-Log "Waiting $WaitSeconds seconds for the HLL splash screen."
    Start-Sleep -Seconds $WaitSeconds

    $window = Wait-ForHllWindow -TimeoutSeconds 30
    if ($window -eq [IntPtr]::Zero) {
        Write-Log "ERROR: Could not find the HLL window."
        return $false
    }

    Write-Log "Sending SPACE directly to HLL."

    [void][OutpostWin32]::PostMessage($window, $WM_KEYDOWN, [IntPtr]$VK_SPACE, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 100
    [void][OutpostWin32]::PostMessage($window, $WM_KEYUP, [IntPtr]$VK_SPACE, [IntPtr]::Zero)

    Write-Log "SPACE sent successfully."
    return $true
}

function Stop-Hll {
    $window = Find-HllWindow
    if ($window -eq [IntPtr]::Zero) {
        Write-Log "HLL window was not found. It may already be closed."
        return $false
    }

    [uint32]$processId = 0
    [void][OutpostWin32]::GetWindowThreadProcessId($window, [ref]$processId)

    if ($processId -eq 0) {
        Write-Log "Could not determine the HLL process ID."
        return $false
    }

    Write-Log "Closing Hell Let Loose (PID $processId)."

    try {
        Stop-Process -Id $processId -Force -ErrorAction Stop
        Write-Log "Hell Let Loose closed successfully."
        return $true
    }
    catch {
        Write-Log "Problem closing HLL: $($_.Exception.Message)"
        Write-ErrorLog -Context "Closing Hell Let Loose" -ErrorRecord $_
        return $false
    }
}
function Start-PopulationMonitor {
    param(
        [int]$StopAbovePlayers,
        [int]$ShutdownChanceOneIn,
        [int]$CheckIntervalSeconds
    )

    while ($true) {
        # If the HLL process disappears (manual close, crash, Steam close, etc.)
        # there is nothing left for the seeder to monitor. End this session
        # rather than polling CRCON forever.
        if (-not (Test-HllRunning)) {
            Write-Log "Hell Let Loose is no longer running. Population monitoring has ended."
            return $false
        }

        try {
            $playerCount = Get-PlayerCount
            Write-Log "Current population: $playerCount; shutdown rolls begin above $StopAbovePlayers."

            if ($playerCount -gt $StopAbovePlayers) {
                # Each seeder makes its own independent random decision.
                # With SHUTDOWN_CHANCE_ONE_IN=10 this is exactly a 1-in-10
                # chance on every population check (normally once per minute).
                $roll = Get-Random -Minimum 1 -Maximum ($ShutdownChanceOneIn + 1)

                if ($roll -eq 1) {
                    Write-Log "Population is above $StopAbovePlayers. Shutdown roll: 1/$ShutdownChanceOneIn - closing HLL."
                    $closedBySeeder = Stop-Hll

                    if ($closedBySeeder) {
                        return $true
                    }

                    Write-Log "Shutdown roll succeeded, but HLL could not be confirmed closed. Automatic return-to-sleep will not occur."
                    return $false
                }
                else {
                    Write-Log "Population is above $StopAbovePlayers. Shutdown roll: $roll/$ShutdownChanceOneIn - staying connected."
                }
            }
        }
        catch {
            Write-Log "Could not read public CRCON: $($_.Exception.Message)"
            Write-ErrorLog -Context "Monitoring public CRCON population" -ErrorRecord $_
            Write-Log "HLL will remain running."
        }

        Start-Sleep -Seconds $CheckIntervalSeconds
    }
}


function Request-WindowsSleep {
    param(
        [int]$DelaySeconds
    )

    if ($DelaySeconds -gt 0) {
        Write-Log "Return-to-sleep enabled. Waiting $DelaySeconds second(s) before requesting Windows sleep."
        Start-Sleep -Seconds $DelaySeconds
    }
    else {
        Write-Log "Return-to-sleep enabled. Requesting Windows sleep now."
    }

    try {
        $ok = [OutpostWin32]::SetSuspendState($false, $false, $false)

        if (-not $ok) {
            $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "SetSuspendState failed. Windows error code: $code"
        }

        Write-Log "Windows sleep request was accepted."
        return $true
    }
    catch {
        Write-Log "WARNING: Could not put Windows to sleep: $($_.Exception.Message)"
        Write-ErrorLog -Context "Returning Windows to sleep" -ErrorRecord $_
        return $false
    }
}


function Invoke-SeedingCheck {
    param(
        [switch]$ManualRun
    )

    $config = Read-Config

    $result = [PSCustomObject]@{
        HllLaunched = $false
        HllClosedBySeeder = $false
        Reason = ""
    }

    # Fetch one narrowly-scoped public value: the current UTC seed start time.
    # A failure/invalid reply leaves the installed last-known-good value intact.
    $scheduleChanged = Update-SeedStartTimeFromWeb -Config $config

    $nowUtc = [DateTime]::UtcNow
    $parts = ([string]$config.StartTimeUtc).Split(":")
    $todayStartUtc = [DateTime]::new(
        $nowUtc.Year,
        $nowUtc.Month,
        $nowUtc.Day,
        [int]$parts[0],
        [int]$parts[1],
        0,
        [DateTimeKind]::Utc
    )

    if ($scheduleChanged -and $todayStartUtc -gt $nowUtc) {
        if ($ManualRun) {
            Write-Log "Remote daily seed time moved later to $($config.StartTimeUtc) UTC."
            Write-Log "Manual 'Run seeder now' was requested, so the population check will continue immediately."
        }
        else {
            Write-Log "New remote seeding time is later than now."
            Write-Log "The installed schedule has been updated; no seeding action will be taken now."
            Write-Log "The background scheduler will re-arm the wake timer from the new live config."
            $result.Reason = "Remote schedule moved later"
            return $result
        }
    }

    if ($scheduleChanged -and $todayStartUtc -le $nowUtc) {
        Write-Log "New remote seeding time has already arrived/passed. Checking server population immediately."
    }

    if (Test-HllRunning) {
        Write-Log ""
        Write-Log "THE OUTPOST HLL AUTO-SEEDER - DAILY RUN"
        Write-Log "Hell Let Loose is already running. Seeder will not interfere with an existing game session. Scheduled run cancelled."
        $result.Reason = "HLL already running"
        return $result
    }

    $otherSteamGame = Get-OtherSteamGameProcess
    if ($null -ne $otherSteamGame) {
        Write-Log ""
        Write-Log "THE OUTPOST HLL AUTO-SEEDER - DAILY RUN"
        Write-Log "Another Steam game appears to be running: $($otherSteamGame.ProcessName) (PID $($otherSteamGame.ProcessId))."
        if ($otherSteamGame.WindowTitle) {
            Write-Log "Detected game window: $($otherSteamGame.WindowTitle)"
        }
        Write-Log "Seeder cancelled. The existing game will not be interrupted."
        $result.Reason = "Another Steam game is running"
        return $result
    }

    Write-Log ""
    Write-Log "THE OUTPOST HLL AUTO-SEEDER - DAILY RUN"

    try {
        $data = Get-PublicServerInfo
        $playerCount = [int]$data.result.player_count
        $maxPlayerCount = [int]$data.result.max_player_count
    }
    catch {
        Write-Log "Unable to contact/read public CRCON: $($_.Exception.Message)"
        Write-ErrorLog -Context "Initial public CRCON population check" -ErrorRecord $_
        $result.Reason = "Initial CRCON check failed"
        return $result
    }

    Write-Log "$ServerName`: population $playerCount/$maxPlayerCount; start below $($config.StartBelowPlayers); shutdown rolls above $($config.StopAbovePlayers) at 1 in $($config.ShutdownChanceOneIn) per check."

    if ($playerCount -ge $config.StartBelowPlayers) {
        Write-Log "Population is high enough. HLL will not be launched."
        $result.Reason = "Population already high enough"
        return $result
    }

    Start-Hll
    $result.HllLaunched = $true

    if (-not (Invoke-HllSplashBypass -WaitSeconds $config.SplashWaitSeconds)) {
        Write-Log "Splash-screen bypass failed."
        $result.Reason = "Splash-screen bypass failed"
        return $result
    }

    $closedBySeeder = Start-PopulationMonitor `
        -StopAbovePlayers $config.StopAbovePlayers `
        -ShutdownChanceOneIn $config.ShutdownChanceOneIn `
        -CheckIntervalSeconds $config.CheckIntervalSeconds

    $result.HllClosedBySeeder = [bool]$closedBySeeder

    if ($result.HllClosedBySeeder) {
        Write-Log "Seeding session complete."
        $result.Reason = "Seeder closed HLL after shutdown roll"
    }
    else {
        Write-Log "Seeding monitor ended without a confirmed seeder-controlled HLL shutdown."
        $result.Reason = "HLL shutdown not confirmed"
    }

    return $result
}

function Get-SourceBatPath {
    # The downloaded pair may be versioned, for example:
    #   OutpostHLLSeeder_v0.24.bat
    #   OutpostHLLSeeder_v0.24.ps1
    #
    # Use the PowerShell file's own base name to locate its matching BAT.
    # The installed canonical pair therefore also works unchanged:
    #   OutpostHLLSeeder.bat
    #   OutpostHLLSeeder.ps1
    $sourceDirectory = Split-Path $PSCommandPath
    $sourceBaseName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
    return Join-Path $sourceDirectory ($sourceBaseName + ".bat")
}


function Test-RunningFromInstalledCopy {
    try {
        return (
            [System.IO.Path]::GetFullPath($PSCommandPath) -ieq
            [System.IO.Path]::GetFullPath($InstalledPs1)
        )
    }
    catch {
        return $false
    }
}


function Test-InstalledProgramMatchesCurrentSource {
    if (-not (Test-Path $InstalledPs1)) {
        return $false
    }

    if (Test-RunningFromInstalledCopy) {
        return $true
    }

    try {
        $sourceHash = (Get-FileHash -Path $PSCommandPath -Algorithm SHA256).Hash
        $installedHash = (Get-FileHash -Path $InstalledPs1 -Algorithm SHA256).Hash
        return ($sourceHash -eq $installedHash)
    }
    catch {
        return $false
    }
}


function Test-OutpostSeederInstalled {
    return (
        (Test-Path $InstalledPs1) -and
        (Test-Path $InstalledBat) -and
        (Test-Path $ConfigFile) -and
        (Test-Path $StartupFile)
    )
}


function Open-ConfigFile {
    if (-not (Test-Path $ConfigFile)) {
        Write-Host "Configuration file not found."
        return
    }

    Start-Process notepad.exe "`"$ConfigFile`""
}


function Open-ActivityLog {
    if (-not (Test-Path $LogFile)) {
        New-Item -ItemType File -Force -Path $LogFile | Out-Null
    }

    Start-Process notepad.exe "`"$LogFile`""
}


function Open-ErrorLog {
    if (-not (Test-Path $ErrorLogFile)) {
        New-Item -ItemType File -Force -Path $ErrorLogFile | Out-Null
    }

    Start-Process notepad.exe "`"$ErrorLogFile`""
}


function Show-MainMenu {
    while ($true) {
        Clear-Host

        Write-Host "======================================================================"
        Write-Host "THE OUTPOST HLL AUTO-SEEDER"
        Write-Host "Transparent PowerShell Edition v0.24"
        Write-Host "======================================================================"
        Write-Host ""

        if (Test-OutpostSeederInstalled) {
            Write-Host "Status: Installed"
        }
        else {
            Write-Host "Status: Not fully installed"
        }

        Write-Host ""
        Write-Host "1. Run seeder now"
        Write-Host "2. Open configuration"
        Write-Host "3. Open activity log"
        Write-Host "4. Open error log"
        Write-Host "5. Show wake timer status"
        Write-Host "6. Reinstall / repair setup"
        Write-Host "7. Disable automatic startup"
        Write-Host "8. REMOVE SEEDER COMPLETELY"
        Write-Host "9. Exit"
        Write-Host ""
        Write-Host "The seeder runs in the background. You can safely close this window at any time."
        Write-Host ""

        $choice = Read-Host "Choose an option"

        switch ($choice) {
            "1" {
                $null = Invoke-SeedingCheck -ManualRun
                Write-Host ""
                Read-Host "Press Enter to return to the menu"
            }

            "2" {
                Open-ConfigFile
            }

            "3" {
                Open-ActivityLog
            }

            "4" {
                Open-ErrorLog
            }

            "5" {
                Show-WakeTimerStatus
                Write-Host ""
                Read-Host "Press Enter to return to the menu"
            }

            "6" {
                Install-OutpostSeeder -PreserveExistingConfig
                Write-Host ""
                Read-Host "Press Enter to return to the menu"
            }

            "7" {
                Uninstall-OutpostSeeder
                Write-Host ""
                Read-Host "Press Enter to return to the menu"
            }

            "8" {
                Remove-OutpostSeederCompletely
                Write-Host ""
                Read-Host "Press Enter to close"
                return
            }

            "9" {
                return
            }

            default {
                Write-Host ""
                Write-Host "Please choose 1 to 9."
                Start-Sleep -Seconds 1
            }
        }
    }
}


function Ensure-InstalledThenMenu {
    $installed = Test-OutpostSeederInstalled

    if (-not $installed) {
        Clear-Host
        Write-Host "======================================================================"
        Write-Host "THE OUTPOST HLL AUTO-SEEDER"
        Write-Host "First-time setup - v$SeederVersion"
        Write-Host "======================================================================"
        Write-Host ""
        Write-Host "This appears to be the first run."
        Write-Host ""
        Write-Host "The seeder will now:"
        Write-Host "  - copy its readable files into your LocalAppData folder"
        Write-Host "  - copy the supplied config.txt"
        Write-Host "  - add one readable Startup .cmd file for this Windows user"
        Write-Host ""
        Write-Host "No administrator privileges are requested."
        Write-Host ""
        Read-Host "Press Enter to continue"

        Install-OutpostSeeder -PreserveExistingConfig

        Write-Host ""
        Write-Host "First-time setup is complete."
        Write-Host ""
        Read-Host "Press Enter to open the main menu"
    }
    elseif (
        -not (Test-RunningFromInstalledCopy) -and
        -not (Test-InstalledProgramMatchesCurrentSource)
    ) {
        # A newer/different downloaded copy has been launched while an older
        # installation already exists. Upgrade it automatically rather than
        # leaving the old scheduler/source in place.
        Clear-Host
        Write-Host "======================================================================"
        Write-Host "THE OUTPOST HLL AUTO-SEEDER"
        Write-Host "Automatic update to v$SeederVersion"
        Write-Host "======================================================================"
        Write-Host ""
        Write-Host "An existing installation was found."
        Write-Host "Its program files and Startup launcher will be refreshed automatically."
        Write-Host ""
        Write-Host "Your existing config.txt and log files will be preserved."
        Write-Host ""

        Install-OutpostSeeder -PreserveExistingConfig -IsUpgrade

        Write-Host ""
        Write-Host "Update complete."
        Write-Host ""
        Read-Host "Press Enter to open the main menu"
    }

    Show-MainMenu
}

function Show-LiveFileLocations {
    Write-Host ""
    Write-Host "INSTALLATION / UPDATE / REPAIR COMPLETE"
    Write-Host "The files below are the LIVE files currently used by the seeder:"
    Write-Host "  Configuration: $ConfigFile"
    Write-Host "  Activity log : $LogFile"
    Write-Host "  Error log    : $ErrorLogFile"
    Write-Host "  Installed PS1: $InstalledPs1"

    try {
        $liveConfig = Read-Config
        Write-Host ""
        Write-Host "Current seed start time (UTC): $($liveConfig.StartTimeUtc)"
        Write-Host "Remote source: $SeedStartTimeUrl"
    }
    catch {
        Write-Host ""
        Write-Host "Current seed start time could not be read from the live config."
    }

    Write-Host ""
    Write-Host "Only the installed configuration above is used by the running seeder."
    Write-Host "The setup-folder config.txt is removed after successful setup."
}


function Install-OutpostSeeder {
    param(
        [switch]$PreserveExistingConfig,
        [switch]$IsUpgrade
    )

    New-Item -ItemType Directory -Force -Path $AppDirectory | Out-Null
    New-Item -ItemType Directory -Force -Path $StartupDirectory | Out-Null

    $sourceDirectory = Split-Path $PSCommandPath
    $sourceBat = Get-SourceBatPath
    $sourceConfig = Join-Path $sourceDirectory "config.txt"

    if (-not (Test-Path $sourceBat)) {
        throw "Matching BAT file not found. Expected beside this file: $sourceBat"
    }

    $configAlreadyExists = Test-Path $ConfigFile

    # A fresh install needs the packaged config. A repair/update may legitimately
    # have no setup-folder config because successful setup removes that duplicate.
    if (-not $configAlreadyExists -and -not (Test-Path $sourceConfig)) {
        throw "First-time setup requires config.txt beside the downloaded seeder files."
    }

    Stop-OutpostSchedulerProcesses
    Start-Sleep -Milliseconds 300

    # When repair is launched from the already-installed copy, the source and
    # destination paths are identical. Skip self-copying in that case and carry
    # on with the rest of the repair (config preservation, Startup repair,
    # scheduler restart, etc.).
    $sourcePs1Full = [System.IO.Path]::GetFullPath($PSCommandPath)
    $installedPs1Full = [System.IO.Path]::GetFullPath($InstalledPs1)

    if ($sourcePs1Full -ine $installedPs1Full) {
        Copy-Item $PSCommandPath $InstalledPs1 -Force
    }
    else {
        Write-Host "Installed PowerShell file is already the active source; skipping self-copy."
    }

    $sourceBatFull = [System.IO.Path]::GetFullPath($sourceBat)
    $installedBatFull = [System.IO.Path]::GetFullPath($InstalledBat)

    if ($sourceBatFull -ine $installedBatFull) {
        Copy-Item $sourceBat $InstalledBat -Force
    }
    else {
        Write-Host "Installed BAT file is already the active source; skipping self-copy."
    }

    if (-not $configAlreadyExists) {
        Copy-Item $sourceConfig $ConfigFile -Force
    }
    elseif (Test-Path $sourceConfig) {
        # Preserve all current values, but append config keys introduced by a
        # newer downloaded release.
        $existingKeys = @{}

        foreach ($rawLine in Get-Content $ConfigFile) {
            $line = $rawLine.Trim()
            if (-not $line -or $line.StartsWith("#")) { continue }

            $parts = $line.Split("=", 2)
            if ($parts.Count -eq 2) {
                $existingKeys[$parts[0].Trim()] = $true
            }
        }

        $missingLines = @()

        foreach ($rawLine in Get-Content $sourceConfig) {
            $line = $rawLine.Trim()
            if (-not $line -or $line.StartsWith("#")) { continue }

            $parts = $line.Split("=", 2)
            if ($parts.Count -eq 2) {
                $key = $parts[0].Trim()
                if (-not $existingKeys.ContainsKey($key)) {
                    $missingLines += $line
                    $existingKeys[$key] = $true
                }
            }
        }

        if ($missingLines.Count -gt 0) {
            Add-Content -Path $ConfigFile -Value "" -Encoding UTF8
            Add-Content -Path $ConfigFile -Value "# Settings added automatically by v$SeederVersion upgrade:" -Encoding UTF8

            foreach ($line in $missingLines) {
                Add-Content -Path $ConfigFile -Value $line -Encoding UTF8
            }

            Write-Host "Added new v$SeederVersion configuration setting(s) while preserving existing values."
        }
    }

    if (-not (Test-Path $LogFile)) {
        New-Item -ItemType File -Force -Path $LogFile | Out-Null
    }

    if (-not (Test-Path $ErrorLogFile)) {
        New-Item -ItemType File -Force -Path $ErrorLogFile | Out-Null
    }

    # IMPORTANT: refresh the public schedule BEFORE starting the scheduler.
    # This means the very first armed wake timer uses the current remote time.
    try {
        $cfg = Read-Config
        [void](Update-SeedStartTimeFromWeb -Config $cfg -TargetConfigPath $ConfigFile)
        $cfg = Read-Config
    }
    catch {
        Write-Host "Remote seed time could not be applied during setup."
        Write-Host "Keeping the current installed START_TIME_UTC."
        $cfg = Read-Config
    }

    $startupContents = @"
@echo off
REM The Outpost HLL Auto-Seeder
REM Starts the installed background scheduler invisibly for this Windows user.
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$InstalledPs1" -Scheduler
"@

    Set-Content -Path $StartupFile -Value $startupContents -Encoding ASCII

    Write-Host ""
    if ($IsUpgrade) {
        Write-Host "Existing installation updated to v$SeederVersion."
        Write-Host "Configuration and logs were preserved."
    }
    else {
        Write-Host "Setup / repair complete."
    }

    Write-Host "Scheduled UTC time: $($cfg.StartTimeUtc)"
    Write-Host "Wake before:        $($cfg.WakeBeforeMinutes) minute(s)"
    Write-Host ""
    Write-Host "Starting the background scheduler now..."

    Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-WindowStyle", "Hidden",
            "-File", "`"$InstalledPs1`"",
            "-Scheduler"
        ) `
        -WindowStyle Hidden

    # The installed AppData config is now the only live configuration.
    # Delete the setup copy to avoid leaving two apparently-editable configs.
    try {
        if (
            (Test-Path -LiteralPath $sourceConfig) -and
            ([System.IO.Path]::GetFullPath($sourceConfig) -ine [System.IO.Path]::GetFullPath($ConfigFile))
        ) {
            Remove-Item -LiteralPath $sourceConfig -Force -ErrorAction SilentlyContinue
        }
    }
    catch { }

    Show-LiveFileLocations
}

function Uninstall-OutpostSeeder {
    # This deliberately only disables automatic startup. It leaves the
    # readable source, configuration and logs in place for inspection.
    if (Test-Path $StartupFile) {
        Remove-Item $StartupFile -Force
        Write-Host "Automatic startup disabled."
    } else {
        Write-Host "Automatic startup is not currently installed."
    }
}


function Stop-OutpostSchedulerProcesses {
    # Find only PowerShell processes whose command line explicitly references
    # our installed script AND the -Scheduler switch. We do not stop unrelated
    # PowerShell processes.
    try {
        $schedulerProcesses = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" |
            Where-Object {
                $_.CommandLine -and
                $_.CommandLine.IndexOf($InstalledPs1, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                $_.CommandLine -match '(?i)(^|\s)-Scheduler(\s|$)'
            }

        foreach ($process in $schedulerProcesses) {
            if ($process.ProcessId -ne $PID) {
                Write-Host "Stopping Outpost scheduler process PID $($process.ProcessId)..."
                Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-Host "Could not automatically stop the background scheduler."
        Write-ErrorLog -Context "Stopping scheduler during removal" -ErrorRecord $_
    }
}


function Remove-OutpostSeederCompletely {
    Clear-Host
    Write-Host "======================================================================"
    Write-Host "REMOVE THE OUTPOST HLL AUTO-SEEDER"
    Write-Host "======================================================================"
    Write-Host ""
    Write-Host "This removes ONLY items created by the seeder:"
    Write-Host "  - its Windows Startup launcher"
    Write-Host "  - its background scheduler process"
    Write-Host "  - its LocalAppData folder, including config and logs"
    Write-Host ""
    Write-Host "It does NOT remove or change:"
    Write-Host "  - Hell Let Loose"
    Write-Host "  - Steam"
    Write-Host "  - any other files or Windows settings"
    Write-Host ""
    $answer = Read-Host "Type REMOVE to continue"

    if ($answer -cne "REMOVE") {
        Write-Host ""
        Write-Host "Removal cancelled. Nothing was deleted."
        return
    }

    Write-Host ""

    # First prevent the seeder from starting again at the next login.
    if (Test-Path $StartupFile) {
        Remove-Item $StartupFile -Force -ErrorAction SilentlyContinue
        Write-Host "Removed Startup launcher."
    }
    else {
        Write-Host "Startup launcher was already absent."
    }

    # Stop the installed scheduler. When that process exits, its finally block
    # closes/cancels the wakeable timer handle, so no seeder wake timer remains.
    Stop-OutpostSchedulerProcesses

    # We may currently be running the installed copy from inside the directory
    # that needs deleting. A tiny temporary CMD is therefore written to TEMP.
    # It waits for this PowerShell process to exit and then removes ONLY the
    # known OutpostHLLSeeder LocalAppData directory. The helper deletes itself.
    if (Test-Path $AppDirectory) {
        $cleanupFile = Join-Path $env:TEMP ("OutpostHLLSeeder_cleanup_" + [guid]::NewGuid().ToString("N") + ".cmd")

        $cleanupContents = @"
@echo off
REM One-time cleanup created by The Outpost HLL Auto-Seeder uninstaller.
REM Wait for the PowerShell menu process to close before removing its folder.
timeout /t 2 /nobreak >nul
rmdir /s /q "$AppDirectory"
del /q "%~f0"
"@

        Set-Content -Path $cleanupFile -Value $cleanupContents -Encoding ASCII

        Write-Host "Scheduled removal of: $AppDirectory"
        Write-Host ""
        Write-Host "Seeder removal is complete."
        Write-Host "This window will now close; the temporary cleanup file will delete itself."

        Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", "`"$cleanupFile`"") -WindowStyle Hidden
    }
    else {
        Write-Host "Seeder LocalAppData folder was already absent."
        Write-Host ""
        Write-Host "Seeder removal is complete."
    }
}

function Start-OutpostScheduler {
    $config = Read-Config

    $createdNew = $false
    $mutex = New-Object System.Threading.Mutex(
        $true,
        "Local\OutpostHLLSeederScheduler",
        [ref]$createdNew
    )

    if (-not $createdNew) {
        Write-Log "Another scheduler instance is already running. Exiting."
        return
    }

    [IntPtr]$wakeTimer = [IntPtr]::Zero

    try {
        Write-Log "Scheduler started."
        Write-SchedulerStatus -State "STARTING"
        Write-Log "Configured daily UTC start time: $($config.StartTimeUtc)"

        Check-SeederVersionFromWeb

        try {
            $wakeTimer = Set-WakeTimer `
                -StartTimeUtc $config.StartTimeUtc `
                -WakeBeforeMinutes $config.WakeBeforeMinutes
            $armedWakeUtc = Get-NextWakeUtc `
                -StartTimeUtc $config.StartTimeUtc `
                -WakeBeforeMinutes $config.WakeBeforeMinutes
            Write-SchedulerStatus -State "ARMED" -ArmedWakeUtc $armedWakeUtc
        }
        catch {
            Write-Log "WARNING: Could not arm wake timer: $($_.Exception.Message)"
            Write-ErrorLog -Context "Arming Windows wake timer" -ErrorRecord $_
        }

        $parts = $config.StartTimeUtc.Split(":")
        $scheduledHour = [int]$parts[0]
        $scheduledMinute = [int]$parts[1]
        $lastRunUtcDate = $null

        while ($true) {
            $currentStatus = Read-SchedulerStatus
            if ($null -ne $currentStatus -and $currentStatus.ContainsKey("ArmedWakeUtc") -and $currentStatus["ArmedWakeUtc"]) {
                try {
                    $heartbeatWakeUtc = [DateTime]::SpecifyKind(
                        [DateTime]::ParseExact(
                            $currentStatus["ArmedWakeUtc"],
                            "yyyy-MM-dd HH:mm:ss",
                            [Globalization.CultureInfo]::InvariantCulture
                        ),
                        [DateTimeKind]::Utc
                    )
                    Write-SchedulerStatus -State $currentStatus["State"] -ArmedWakeUtc $heartbeatWakeUtc
                }
                catch {
                    Write-SchedulerStatus -State "RUNNING"
                }
            }
            else {
                Write-SchedulerStatus -State "RUNNING"
            }

            # Reload config so simple Notepad edits take effect without reboot.
            try {
                $latestConfig = Read-Config

                if (
                    $latestConfig.StartTimeUtc -ne $config.StartTimeUtc -or
                    $latestConfig.WakeBeforeMinutes -ne $config.WakeBeforeMinutes
                ) {
                    Write-Log "Schedule configuration changed. Re-arming wake timer."
                    $config = $latestConfig

                    $parts = $config.StartTimeUtc.Split(":")
                    $scheduledHour = [int]$parts[0]
                    $scheduledMinute = [int]$parts[1]

                    try {
                        $wakeTimer = Set-WakeTimer `
                            -StartTimeUtc $config.StartTimeUtc `
                            -WakeBeforeMinutes $config.WakeBeforeMinutes `
                            -ExistingTimer $wakeTimer
                        $armedWakeUtc = Get-NextWakeUtc `
                            -StartTimeUtc $config.StartTimeUtc `
                            -WakeBeforeMinutes $config.WakeBeforeMinutes
                        Write-SchedulerStatus -State "ARMED" -ArmedWakeUtc $armedWakeUtc
                    }
                    catch {
                        Write-Log "WARNING: Could not re-arm wake timer: $($_.Exception.Message)"
                        Write-ErrorLog -Context "Re-arming Windows wake timer" -ErrorRecord $_
                    }
                }
                else {
                    $config = $latestConfig
                }
            }
            catch {
                Write-Log "WARNING: Could not reload config: $($_.Exception.Message)"
                Write-ErrorLog -Context "Reloading scheduler configuration" -ErrorRecord $_
            }

            $nowUtc = [DateTime]::UtcNow
            $todayUtc = $nowUtc.Date

            # Delayed-wake grace window: automatic runs are allowed only from
            # the scheduled UTC time up to, but not including, 10 minutes later.
            # This protects against a slow Windows resume without creating a
            # general catch-up run when a PC is turned on much later.
            $scheduledTodayUtc = [DateTime]::new(
                $nowUtc.Year,
                $nowUtc.Month,
                $nowUtc.Day,
                $scheduledHour,
                $scheduledMinute,
                0,
                [DateTimeKind]::Utc
            )

            $latestAllowedUtc = $scheduledTodayUtc.AddMinutes(10)

            $withinStartWindow = (
                $nowUtc -ge $scheduledTodayUtc -and
                $nowUtc -lt $latestAllowedUtc
            )

            if ($withinStartWindow -and $lastRunUtcDate -ne $todayUtc) {
                $lastRunUtcDate = $todayUtc

                $runResult = $null

                try {
                    $runResult = Invoke-SeedingCheck
                }
                catch {
                    Write-Log "UNEXPECTED ERROR: $($_.Exception.Message)"
                    Write-ErrorLog -Context "Unexpected scheduler/daily-run error" -ErrorRecord $_
                }

                Write-Log "Scheduler returned to waiting mode."

                # Reload latest settings after a potentially long seeding run.
                try {
                    $config = Read-Config

                    # The web schedule may have changed during Invoke-SeedingCheck.
                    # Keep the scheduler's in-memory clock in sync immediately.
                    $parts = $config.StartTimeUtc.Split(":")
                    $scheduledHour = [int]$parts[0]
                    $scheduledMinute = [int]$parts[1]
                }
                catch {
                    Write-Log "WARNING: Could not reload config after seeding: $($_.Exception.Message)"
                    Write-ErrorLog -Context "Reloading post-seeding configuration" -ErrorRecord $_
                }

                # If today's remote schedule moved to a LATER time, this was not
                # today's actual seeding run. Allow the scheduler to trigger again
                # when that new time arrives later today.
                if (
                    $null -ne $runResult -and
                    $runResult.Reason -eq "Remote schedule moved later"
                ) {
                    $lastRunUtcDate = $null
                    Write-Log "Today's run marker cleared so the new later UTC time can still run today."
                }

                # Arm the next appropriate wake BEFORE any request to sleep.
                $nextWakeArmed = $false

                if ($wakeTimer -ne [IntPtr]::Zero) {
                    try {
                        $wakeTimer = Set-WakeTimer `
                            -StartTimeUtc $config.StartTimeUtc `
                            -WakeBeforeMinutes $config.WakeBeforeMinutes `
                            -ExistingTimer $wakeTimer

                        $armedWakeUtc = Get-NextWakeUtc `
                            -StartTimeUtc $config.StartTimeUtc `
                            -WakeBeforeMinutes $config.WakeBeforeMinutes

                        Write-SchedulerStatus -State "ARMED" -ArmedWakeUtc $armedWakeUtc
                        $nextWakeArmed = $true
                    }
                    catch {
                        Write-Log "WARNING: Could not arm next wake timer: $($_.Exception.Message)"
                        Write-ErrorLog -Context "Arming next wake timer" -ErrorRecord $_
                    }
                }

                if (
                    $null -ne $runResult -and
                    $runResult.HllLaunched -and
                    $runResult.HllClosedBySeeder -and
                    $config.ReturnToSleepAfterSeeding
                ) {
                    if ($nextWakeArmed) {
                        [void](Request-WindowsSleep -DelaySeconds $config.ReturnToSleepDelaySeconds)
                    }
                    else {
                        Write-Log "Return-to-sleep skipped because tomorrow's wake timer could not be confirmed armed."
                    }
                }
            }

            Start-Sleep -Seconds $SchedulerPollSeconds
        }
    }
    finally {
        if ($wakeTimer -ne [IntPtr]::Zero) {
            [void][OutpostWin32]::CancelWaitableTimer($wakeTimer)
            [void][OutpostWin32]::CloseHandle($wakeTimer)
        }

        if ($mutex) {
            $mutex.ReleaseMutex()
            $mutex.Dispose()
        }
    }
}

if ($Setup) {
    Install-OutpostSeeder -PreserveExistingConfig
    exit
}

if ($Scheduler) {
    Start-OutpostScheduler
    exit
}

if ($Uninstall) {
    Uninstall-OutpostSeeder
    exit
}

if ($RunNow) {
    $null = Invoke-SeedingCheck -ManualRun
    exit
}

# Normal double-click / no-argument behaviour:
#   - first run: perform setup automatically
#   - later runs: show a simple menu
Ensure-InstalledThenMenu