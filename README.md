# The Outpost HLL Auto-Seeder

A transparent Windows BAT/PowerShell tool that automatically helps seed **The Outpost Hell Let Loose server**.

**Current public test version: v0.23**

## What changed in v0.23

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
OutpostHLLSeeder_v0.23.bat
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
