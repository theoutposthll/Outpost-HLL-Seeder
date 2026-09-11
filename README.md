### v0.29 working-directory fix

The background scheduler and scheduled seeding worker now explicitly use the
installed Seeder directory under `%LOCALAPPDATA%\OutpostHLLSeeder` as their
working directory.

This prevents a background Seeder process from keeping the original extracted
download folder "in use" after installation. Once installation/update has
finished, the extracted release folder can be deleted normally.

No scheduling, seeding, settings-protection, shutdown, wake, or user-config
behaviour is changed by this fix.

### Corrected v0.29 repair behaviour
Fixed broken link on option 6

### Corrected v0.28 repair behaviour

Fixes Option 6 (`Reinstall / repair setup`) when it is run from the already-installed LocalAppData copy. The installer now detects that the packaged HLL default-reference source and installed destination are the same file and skips the unnecessary self-copy. Repair from an extracted release still refreshes the reference normally. Existing configuration and HLL settings backups are preserved.

# The Outpost HLL Auto-Seeder

A transparent Windows BAT/PowerShell tool that automatically helps seed **The Outpost Hell Let Loose server**.

**Current public test version: v0.28**

## What's changed in v0.28

### Visible seeding session, hidden scheduler

The scheduler still starts completely hidden at Windows login/reboot.

At the scheduled time it first performs the normal eligibility checks in the
background. If the server does not need seeding, nothing visible opens.

If seeding is required, v0.28 launches a separate **visible PowerShell worker**
for the actual HLL launch and population monitoring.

This lets a user who takes over and starts actively playing close the visible
worker window. That stops the current automated monitoring/shutdown session
without killing the hidden scheduler, which remains running for future days.

Menu option **1. Run seeder now** remains visible and interactive as before.

### Activity-log fix

Fixes the v0.27 bug where option **3. Open activity log** could execute
installer-only reference-file code and fail with a null `LiteralPath` error.

All existing settings protection, wake/scheduling, version notification and
configuration preservation are retained.


## What's changed in v0.28


### Initial backup created during setup

v0.28 now establishes protection immediately during install/update/repair.

If `PROTECT_HLL_SETTINGS=true` and the Seeder does not already have a local HLL
settings backup:

- live `GameUserSettings.ini` differs from the known-default reference
  -> create the first local backup immediately;
- live file matches the known-default/reset reference
  -> do **not** create a useless default-state backup;
- an existing local backup already exists
  -> leave it untouched.

The same protection check also runs immediately before every Seeder-controlled
HLL launch, whether the launch comes from the daily scheduler or from menu
option **1. Run seeder now**.



### Installation correction

The v0.28 installer now captures the extracted release folder at process startup
and copies `setup_files\HLL_GameUserSettings_DEFAULT_REFERENCE.ini` into the
installed `setup_files` directory immediately after that directory is created.
It then verifies the installed file exists before setup completes.

This avoids self-copy/repair execution changing the apparent script directory
before the reference file has been installed.


### Installed `setup_files` folder

v0.28 keeps the setup/reference/settings-protection files together after
installation as well as in the downloaded ZIP.

The installed layout is now:

```text
%LOCALAPPDATA%\OutpostHLLSeeder\
    OutpostHLLSeeder.ps1
    OutpostHLLSeeder.bat
    seeder.log
    errors.txt
    scheduler_status.txt

    setup_files\
        config.txt
        HLL_GameUserSettings_DEFAULT_REFERENCE.ini
        GameUserSettings.backup.ini
        GameUserSettings.backup.previous.ini
```

The live config is therefore:

```text
%LOCALAPPDATA%\OutpostHLLSeeder\setup_files\config.txt
```

On upgrade/repair, v0.28 automatically migrates existing v0.28-and-earlier
files from the old AppData root into `setup_files`. Existing user config values,
including `AUTO_UPDATE_SEED_TIME`, `START_TIME_UTC`,
`PROTECT_HLL_SETTINGS`, and `HLL_SETTINGS_FILE`, are preserved.

Existing local HLL settings backups are also moved rather than replaced.

The packaged `setup_files` folder is left intact after installation, while the
completion screen clearly identifies the separate installed/live config path.



### Reference-file installation fix

The shipped `HLL_GameUserSettings_DEFAULT_REFERENCE.ini` is now always copied
from the release package into:

```text
%LOCALAPPDATA%\OutpostHLLSeeder\setup_files\
```

on install/update. It is an Outpost-supplied reference file rather than user
data, so refreshing it does not overwrite any user settings. Existing
`config.txt` values and locally-created HLL settings backups remain preserved.


## What's changed in v0.28

### Optional HLL settings protection

v0.28 can protect the user's plain-text HLL `GameUserSettings.ini` before the
Seeder launches Hell Let Loose.

The normal live file is:

```text
%LOCALAPPDATA%\HLL\Saved\Config\WindowsNoEditor\GameUserSettings.ini
```

This path is based on the Windows user profile, so it does not matter whether
the Steam game itself is installed on `C:`, `F:`, or another Steam library.

The release openly ships a clearly-labelled known-default comparison file:

```text
setup_files\HLL_GameUserSettings_DEFAULT_REFERENCE.ini
```

It is used **only as a comparison reference** and is never copied over a user's
settings.

Default behaviour:

```text
PROTECT_HLL_SETTINGS=true
HLL_SETTINGS_FILE=
```

With protection enabled, immediately before the Seeder launches HLL:

1. If the live settings file does **not** match the known-default reference, it
   is treated as the user's current settings and backed up locally.
2. If the live file **does** match the known-default reference and a previous
   non-default local backup exists, that local backup is restored.
3. If the live file matches the reference but no safe local backup exists,
   nothing is changed.
4. If the file/reference cannot be read, seeding continues normally and the
   problem is logged.

Backups live only under:

```text
%LOCALAPPDATA%\OutpostHLLSeeder\
```

The tool keeps the current backup plus one previous generation as an additional
safety net. It never uploads the settings file.

Users can opt out with:

```text
PROTECT_HLL_SETTINGS=false
```

For unusual installations, `HLL_SETTINGS_FILE=` may contain an explicit full
path. Leaving it blank uses the normal `%LOCALAPPDATA%` location.

### Cleaner download layout

v0.28 keeps setup/reference inputs together:

```text
OutpostHLLSeeder_v0.28.bat
OutpostHLLSeeder_v0.28.ps1
README.md

setup_files\
    config.txt
    HLL_GameUserSettings_DEFAULT_REFERENCE.ini
```

The installed live config remains in `%LOCALAPPDATA%\OutpostHLLSeeder\` and
existing user settings are preserved during upgrades.


## What's changed in v0.28

### Startup scheduler is now truly hidden

v0.28 replaces the Windows Startup `.cmd` launcher with a tiny `.vbs` launcher.

The VBS starts the installed PowerShell scheduler with a hidden window and does
**not** wait for it to finish. The VBS then exits immediately, leaving the
scheduler running independently in the background.

This fixes the remaining v0.25 issue where a visible `powershell.exe` window
could still remain after login/reboot. Closing that window terminated the
scheduler and prevented the scheduled seeding event from firing.

During upgrade/repair, v0.28 also removes the old
`Outpost HLL Auto-Seeder.cmd` Startup launcher so only the new VBS launcher
remains.

The normal Seeder **menu** may still be opened whenever needed and is safe to
close; it is separate from the hidden scheduler.

All v0.25 functionality is retained, including:

- 10-minute delayed-wake grace window
- read-only newer-version notification
- repair-from-installed-copy protection
- persistent `AUTO_UPDATE_SEED_TIME`
- join below 60 players
- staggered departure rolls above 80 players
- 1-in-10 departure chance per minute
- `RETURN_TO_SLEEP_AFTER_SEEDING=false`

## What's changed in v0.28

### Hidden/detached Windows startup scheduler

The Windows Startup launcher now starts the background scheduler as a **detached
hidden PowerShell process** and then immediately exits.

Previously, the Startup `.cmd` waited for the scheduler process to finish. That
left a visible Command Prompt window open for as long as the scheduler was
running. Closing that window also terminated the scheduler, which meant the
daily seeding event could never fire.

With v0.28:

- the temporary Startup command window exits immediately;
- the scheduler continues running independently in the background;
- closing the normal seeder menu does not affect the scheduler;
- the existing wake timer and daily schedule continue to be owned by the hidden
  scheduler process.

All v0.24 scheduling behavior is retained, including the 10-minute delayed-wake
grace window and read-only update notification.

The existing config defaults are unchanged.

## What's changed in v0.28

- **10-minute delayed-wake grace window:** automatic seeding can start at the
  scheduled UTC time or during the following 9 minutes 59 seconds. At 10 minutes
  late or more, it does nothing automatically.
- **Read-only update notice:** on scheduler startup the tool checks the existing
  Outpost public JSON endpoint for an optional `latest_seeder_version` field.
  If a newer version is advertised, Windows tells the user to download it from
  the link in The Outpost Discord.
- **No automatic software updating:** the seeder never downloads, installs or
  executes a new version itself.
- Existing `AUTO_UPDATE_SEED_TIME` choices remain preserved across updates.

### Repair-from-installed-copy fix

Option **6. Reinstall / repair setup** can now be run from the already-installed
BAT under `%LOCALAPPDATA%\OutpostHLLSeeder\`.

v0.23 could try to copy the installed PS1/BAT onto themselves and stop with:

```text
Cannot overwrite the item ... with itself.
```

v0.28 detects identical source/destination paths, skips the self-copy, and
continues the rest of the repair normally. Existing config values are preserved,
including `AUTO_UPDATE_SEED_TIME` and a user-controlled `START_TIME_UTC`.

The API change is backward compatible: older versions continue reading
`start_time_utc` and ignore the extra version field.

## What changed in v0.28

The default for new installations is now:

```text
AUTO_UPDATE_SEED_TIME=true
```

That means new users automatically receive The Outpost's published daily UTC
seeding time.

Anyone who prefers to control the time manually can set:

```text
AUTO_UPDATE_SEED_TIME=false
```

That choice is **persistent**: repair, reinstall, and later-version updates
preserve the existing installed true/false value rather than resetting it to the
new-version default.

Current seeding defaults:

| Setting | Default |
| --- | ---: |
| Join when population is below | 60 players |
| Begin departure rolls above | 80 players |
| Departure chance per check | 1 in 10 |
| Population check interval | 60 seconds |
| Wake before seeding | 2 minutes |
| Auto-update daily seed time | Enabled |
| Force return to sleep | Disabled |

## What it does

Once installed, the seeder can:

- retrieve the current daily seeding time from The Outpost
- wake the PC shortly beforehand where Windows/hardware support it
- check whether the server actually needs seeding
- launch Hell Let Loose through Steam and connect to The Outpost
- leave an existing HLL session alone
- leave you alone if another Steam game is active
- monitor server population while seeding
- stagger seeders leaving once population is above 80
- close HLL when that client's seeding job is complete
- leave normal post-seeding sleep behaviour to Windows by default

## Transparency and privacy

The project is distributed as readable BAT/PowerShell/text source.

It does not require RCON credentials, does not ask for your Steam password, does
not include telemetry, and does not download and execute remote code.

The only remote scheduling value it reads is a validated UTC time in `HH:MM`
format from The Outpost's public endpoint.

You do not have to take our word for that: the full source is available in this
repository for inspection.

## Installation

Download the latest release ZIP, extract all files together, then double-click:

```text
OutpostHLLSeeder_v0.28.bat
```

The live installed copy is stored under:

```text
%LOCALAPPDATA%\OutpostHLLSeeder\
```

The menu can safely be closed after setup because the scheduler runs separately
in the background.

## Manual schedule control

Open the installed `config.txt`.

Automatic daily schedule:

```text
AUTO_UPDATE_SEED_TIME=true
```

Manual daily schedule:

```text
AUTO_UPDATE_SEED_TIME=false
START_TIME_UTC=12:30
```

`START_TIME_UTC` is UTC, not local time.

Once you set `AUTO_UPDATE_SEED_TIME` yourself, future updates preserve your
choice.

## Current thresholds

HLL launches only when population is **strictly below 60**.

Once population is **strictly above 80** (81+), each seeder independently makes
a **1-in-10 shutdown roll once per minute**. This staggers departures rather
than disconnecting every seeder at once.

## Existing-game protection

If HLL is already running, the seeder leaves it alone.

If another Steam game is actively being played, the seeder cancels its run
rather than interrupting the user.

Steam itself being open does not block seeding.

## Sleep / wake

The scheduler uses a Windows wakeable timer where supported.

`RETURN_TO_SLEEP_AFTER_SEEDING=false` is the default, so Windows' normal power
settings determine post-seeding sleep behaviour unless the user explicitly opts
in to the seeder requesting sleep.

## Antivirus note

This is an unsigned PowerShell utility and uses a process-scoped
`-ExecutionPolicy Bypass` plus a user Startup entry. Heuristic antivirus tools
may object to those behaviours.

Do not blindly disable antivirus software. The complete readable source is
provided so users can inspect exactly what the tool does before deciding whether
to run it.

## Removing it

Open the BAT and choose:

```text
8. REMOVE SEEDER COMPLETELY
```

The tool requires the user to type `REMOVE` before deleting the files and
Startup entry it created.

It does not remove Steam or Hell Let Loose.
