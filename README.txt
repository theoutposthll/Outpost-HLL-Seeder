VERSION 0.23
============
v0.23 changes the DEFAULT for new installations to:

    AUTO_UPDATE_SEED_TIME=true

This means a new user automatically receives The Outpost's published daily UTC
seeding time without changing the config manually.

Users can opt out at any time by setting:

    AUTO_UPDATE_SEED_TIME=true

IMPORTANT: AUTO_UPDATE_SEED_TIME remains a persistent USER preference.
Reinstall, repair, and future-version updates preserve an existing installed
true/false value and do not reset it to the packaged default.

So:
    - new install with no existing setting -> true
    - existing user set to true           -> stays true
    - existing user set to false          -> stays false

All v0.22 behaviour is otherwise retained, including:
    - join below 60 players
    - staggered departure rolls above 80 players
    - 1-in-10 departure chance per minute
    - scheduler-status logging fix
    - RETURN_TO_SLEEP_AFTER_SEEDING=false by default

VERSION 0.22
============
v0.23 fixes a scheduler-status logging error reported by testers.

The wake timer itself could still work correctly, but Write-SchedulerStatus
could write this error to errors.txt:

    You cannot call a method on a null-valued expression

The armed wake time is now cast directly to DateTime before formatting rather
than using the nullable .Value property.

v0.23 carries forward the public tester thresholds:
    START_BELOW_PLAYERS=60
    STOP_ABOVE_PLAYERS=80
    SHUTDOWN_CHANCE_ONE_IN=10

No other scheduling, HLL/Steam protection, wake, shutdown or sleep behaviour is
changed by this release.

THE OUTPOST HLL AUTO-SEEDER
Transparent PowerShell Edition v0.23
===================================

PURPOSE
-------
The seeder helps populate The Outpost Hell Let Loose server automatically while
remaining readable, auditable and minimally intrusive.

It does not request administrator rights, collect credentials, send personal
data to The Outpost, or download/execute remote code.


WHAT IT DOES
------------
At the configured daily UTC time it:

1. Retrieves the current public seeding time from:
       https://the-outpost.ngrok.app/api/get_seed_start_time

2. Validates the returned value strictly as HH:MM UTC.
   A valid value is stored in the installed config as the last-known-good time.
   If the call fails or is invalid, the existing installed time is kept.

3. Checks the public Outpost CRCON population endpoint:
       https://op2.hlladmin.com/api/get_public_info

4. If population is STRICTLY BELOW 60, launches Hell Let Loose through Steam
   and connects directly to The Outpost server.

5. Waits for the HLL splash screen and sends Space directly to the HLL window.

6. Checks population once per minute while HLL remains running.

7. Once population is STRICTLY ABOVE 80, performs an independent 1-in-10
   shutdown roll on each population check. This staggers seeders leaving rather
   than having everyone disconnect at once.

8. When that client's roll succeeds, HLL is closed.

If HLL is manually closed, crashes, or otherwise disappears while being
monitored, v0.23 ends monitoring cleanly instead of continuing to poll forever.


PERSISTENCE ACROSS UPDATES
--------------------------
AUTO_UPDATE_SEED_TIME is a persistent user preference.

Once a user has set it to true or false in the installed config, reinstall,
repair, and later-version updates must preserve that existing value. A packaged
default is used only when the setting does not already exist (for example when
upgrading an installation created before this option was introduced).

AUTO-UPDATE OF DAILY SEED TIME
------------------------------
The installed config includes:

    AUTO_UPDATE_SEED_TIME=true

The packaged DEFAULT for a new installation is TRUE.

true:
    The seeder checks The Outpost public seed-time API. A valid HH:MM UTC value
    replaces START_TIME_UTC and becomes the last-known-good time. If the request
    fails or is invalid, the existing value is retained.

false:
    START_TIME_UTC is controlled entirely by the user. The seeder does not call
    The Outpost seed-time API and does not overwrite the configured time.

AUTO_UPDATE_SEED_TIME is a persistent user preference. Once a user has selected
true or false in the installed config, reinstall/repair and future updates
preserve that existing choice. The packaged default is used only when the
setting does not already exist.


REMOTE DAILY SCHEDULE
---------------------
The downloaded config contains an initial START_TIME_UTC value and defaults AUTO_UPDATE_SEED_TIME to false.

The installed live config is the persistent last-known-good schedule. Whenever
the public schedule endpoint returns a valid new time, START_TIME_UTC in the
installed config is updated.

If the new remote time is LATER than the time at which the scheduler has just
woken/run:
    - no seeding action is taken yet;
    - the wake/start schedule is re-armed;
    - the scheduler remains eligible to run again later on the SAME UTC day;
    - Windows may return to sleep normally under its own power settings.

If the new remote time is NOW or EARLIER:
    - the new time is saved;
    - the server population is checked immediately;
    - normal seeding criteria apply.

Menu option 1, "Run seeder now", is intentionally different:
    - it still retrieves and saves the current remote daily schedule;
    - but it ignores whether that daily time is later than now;
    - it performs the population/seeding check immediately because the user
      explicitly requested a manual run.


FILES
-----
The download contains:

    OutpostHLLSeeder_v0.23.bat
    OutpostHLLSeeder_v0.23.ps1
    config.txt
    README.txt

Keep them together for the initial setup and double-click the BAT file.

The BAT launches the matching PowerShell file with:
    -NoProfile
    -ExecutionPolicy Bypass

The Bypass applies only to that PowerShell process. It does not change the
computer's permanent execution policy.


INSTALLATION / UPDATE / REPAIR
------------------------------
Installed files live under:

    %LOCALAPPDATA%\OutpostHLLSeeder\

The live files include:

    config.txt
    OutpostHLLSeeder.ps1
    OutpostHLLSeeder.bat
    seeder.log
    errors.txt
    scheduler_status.txt

The Startup launcher is stored in the current Windows user's Startup folder.

On first install:
    - the supplied config is copied into AppData;
    - the remote daily start time is fetched immediately when available;
    - that value is saved before the background scheduler starts;
    - the first wake timer therefore uses the current remote schedule.

On update/repair:
    - existing config values and logs are preserved;
    - newly introduced config keys are added when necessary;
    - the current remote seed time is refreshed;
    - the background scheduler is restarted.

After successful setup the download-folder config.txt is removed so there is
only one configuration that is actually in use. The completion message shows
the live AppData paths.


CONFIGURATION
-------------
The supplied v0.23 defaults are:

    START_TIME_UTC=04:40
    START_BELOW_PLAYERS=60
    STOP_ABOVE_PLAYERS=80
    SHUTDOWN_CHANCE_ONE_IN=10
    CHECK_INTERVAL_SECONDS=60
    SPLASH_WAIT_SECONDS=60
    WAKE_BEFORE_MINUTES=2
    RETURN_TO_SLEEP_AFTER_SEEDING=false
    RETURN_TO_SLEEP_DELAY_SECONDS=60

START_TIME_UTC
    Initial / last-known-good daily UTC time.
    It is automatically updated from the public seed-time endpoint.

START_BELOW_PLAYERS
    HLL launches only when population is STRICTLY BELOW this number.

STOP_ABOVE_PLAYERS
    Random shutdown rolls begin only when population is STRICTLY ABOVE this
    number. With 80, rolls start at 81 players.

SHUTDOWN_CHANCE_ONE_IN
    Independent shutdown chance on each eligible population check.
    10 means 1-in-10.

CHECK_INTERVAL_SECONDS
    Population-monitor interval. Default 60 seconds.

SPLASH_WAIT_SECONDS
    Delay before sending Space to the HLL splash screen.

WAKE_BEFORE_MINUTES
    Minutes before START_TIME_UTC that Windows is asked to wake.

RETURN_TO_SLEEP_AFTER_SEEDING
    Default: false.

    false:
        Windows' normal power settings determine when the PC sleeps.

    true:
        after an eligible scheduled seeding session that this seeder launched
        and subsequently closed, the seeder may request Windows sleep.

RETURN_TO_SLEEP_DELAY_SECONDS
    Delay after HLL closes before an enabled return-to-sleep request.


WAKE FROM SLEEP
---------------
The background scheduler uses the Windows SetWaitableTimer API with wake/resume
enabled.

For example:

    START_TIME_UTC=12:30
    WAKE_BEFORE_MINUTES=2

requests a wake at 12:28 UTC and the actual seeding check at 12:30 UTC.

Wake capability ultimately depends on Windows, hardware, firmware, the current
sleep state and local power settings.

The seeder does not create an administrator Scheduled Task.


RETURN TO SLEEP
---------------
RETURN_TO_SLEEP_AFTER_SEEDING is FALSE by default.

This is deliberately opt-in because Windows' own power policy is the normal
sleep behaviour.

When enabled, automatic return-to-sleep is restricted:
    - manual "Run seeder now" does not trigger it;
    - HLL must have been launched by this scheduled seeding session;
    - HLL must later have been successfully closed by this seeder;
    - an existing HLL session is never used for this;
    - another active Steam game cancels the run;
    - the next wake timer is armed before a sleep request is made.

The sleep request uses Windows SetSuspendState with:
    hibernate = false
    forceCritical = false
    disableWakeEvent = false


EXISTING GAME PROTECTION
------------------------
Before launching HLL, the seeder checks:

Hell Let Loose already running
    Exact known HLL process names are used. Browser tabs, Discord channels or
    other windows merely containing "HLL" in their title do not count.

    If HLL is already running, the seeder cancels the run and leaves it alone.

Another Steam game active
    The seeder looks for an active executable inside a Steam library's
    steamapps\common folder that owns a visible main window.

    If detected, the run is cancelled. The other game is not interrupted and
    the PC is not automatically put to sleep by that cancelled run.

Steam itself being open is normal and does not block the seeder.


MENU
----
    1. Run seeder now
    2. Open configuration
    3. Open activity log
    4. Open error log
    5. Show wake timer status
    6. Reinstall / repair setup
    7. Disable automatic startup
    8. REMOVE SEEDER COMPLETELY
    9. Exit

The menu window is not the scheduler. It is safe to close the menu at any time.


BACKGROUND PROCESS
------------------
While automatic startup is installed, a small hidden PowerShell scheduler runs
for the logged-in Windows user.

It sleeps/waits between checks and owns the wakeable timer.

The seeder does not intentionally make a system-required "keep awake" request,
so the scheduler itself is not intended to prevent Windows sleeping normally.


LOGS / STATUS
-------------
Installed under:

    %LOCALAPPDATA%\OutpostHLLSeeder\

seeder.log
    Normal activity, schedule changes, population checks, random shutdown rolls,
    wake-timer activity and sleep decisions.

errors.txt
    Plain-text troubleshooting errors.

scheduler_status.txt
    Scheduler version, PID, heartbeat, state and currently armed wake time.


COMPLETE REMOVAL
----------------
Menu option 8 removes items created by the seeder:
    - Startup launcher
    - background scheduler process
    - LocalAppData seeder files/config/log/status

It does not remove or modify Steam or Hell Let Loose.

The user must type:

    REMOVE

before deletion proceeds.


TESTER CHECKLIST
----------------
Please report:

    - Windows version
    - first-run setup success/failure
    - exact antivirus warning/detection if any
    - whether setup reports the correct live AppData paths
    - whether the remote UTC time is applied on first setup
    - whether option 5 reports RUNNING / ARMED
    - whether sleep -> scheduled wake works
    - whether a remote time moved later re-arms and still runs later that day
    - whether a remote time moved earlier triggers the immediate population check
    - whether manual "Run seeder now" really runs immediately
    - whether the public CRCON population check succeeds
    - whether HLL launches/connects below 60
    - whether an already-open HLL session is left alone
    - whether another active Steam game cleanly cancels the run
    - whether monitoring ends if HLL is manually closed/crashes
    - whether shutdown rolls appear above 80
    - whether HLL closes after a successful roll
    - errors.txt if anything fails


KNOWN LIMITATIONS
-----------------
The splash bypass currently uses the proven fixed delay plus a direct Space
message to the HLL window. Very unusual PC/load conditions may need further
timing adjustment.

Wake/resume support is dependent on the individual PC and Windows power state.

Some antivirus products may object heuristically to a transparent PowerShell
script using process-scoped ExecutionPolicy Bypass and Startup-folder
persistence. The complete readable BAT/PowerShell source is supplied so users
can inspect what it does.
