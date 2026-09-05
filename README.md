# The Outpost HLL Auto-Seeder

A transparent Windows BAT/PowerShell tool that automatically helps seed **The Outpost Hell Let Loose server**.

**Current public test version: v0.22**

The aim is simple: make helping with morning seeding as effortless as possible, while keeping the tool open, readable and easy to audit.

## 🌱 What is seeding?

Hell Let Loose community servers often empty overnight and need a group of players online the next day before normal traffic begins to build.

The more people who help seed, the faster the server fills — and the less time any individual person needs to spend sitting on a quiet server.

The Outpost HLL Auto-Seeder automates that process.

## ⚙️ What does it do?

Once installed, the seeder can:

- Wake your PC shortly before the daily seeding time, where supported
- Retrieve the current daily seeding time from The Outpost
- Check whether the server actually needs seeding
- Launch Hell Let Loose through Steam and connect directly to The Outpost
- Leave an existing Hell Let Loose session alone
- Leave you alone if you are actively playing another Steam game
- Monitor server population while seeding
- Stagger seeders leaving so everyone does not disconnect at once
- Close Hell Let Loose automatically when that client's seeding job is complete
- Allow Windows' normal power settings to put the PC back to sleep afterward
- Optionally request sleep after a completed automated seeding session

In other words, your PC can help seed The Outpost while you're making breakfast, walking the dog, at work, or still asleep.

## 🚦 Current seeding behaviour

The supplied v0.22 defaults are:

| Setting | Default |
| --- | ---: |
| Join when population is below | 60 players |
| Begin departure rolls above | 80 players |
| Departure chance per check | 1 in 10 |
| Population check interval | 60 seconds |
| Wake before seeding | 2 minutes |
| Force return to sleep | Disabled |

Once the server is above 80 players, each seeder independently gets a **1-in-10 chance per population check** of closing HLL. This deliberately staggers departures instead of having every automated seeder disappear simultaneously.

## 🕐 Daily start time

The seeder retrieves the current UTC seeding time from The Outpost's public schedule endpoint.

The downloaded `config.txt` contains an initial fallback time. A valid time received from The Outpost becomes the installed **last-known-good** setting.

If the web request fails or returns an invalid value, the seeder simply keeps its existing time.

The remote endpoint provides **only a UTC time in `HH:MM` format**. It is not used to download scripts, commands or executable code.

## 🔒 Transparency and privacy

This was an important part of the design.

The seeder is deliberately distributed as ordinary, readable `.bat`, `.ps1` and `.txt` files. The complete source is here in this repository.

The tool:

- does **not** ask for your Steam password
- does **not** ask for RCON credentials
- does **not** collect banking or personal information
- does **not** include telemetry
- does **not** download and execute remote code
- does **not** require administrator rights for normal operation

It uses public server information to obtain the player count and a small public Outpost endpoint to retrieve the daily UTC seeding time.

**You don't have to take our word for any of this.** The source is provided so you, a technically minded friend, or an AI/code-analysis tool can inspect it and determine exactly what it does before you run it.

## 🛡️ Windows / antivirus warning

This is an unsigned community-made PowerShell utility.

The BAT file starts the supplied PowerShell script using:

```text
-NoProfile -ExecutionPolicy Bypass
```

That bypass applies **only to the PowerShell process started by the BAT file**. It does not permanently change the computer's PowerShell execution policy.

The tool also installs a launcher in the current user's Windows Startup folder so its scheduler can start automatically after login.

Those behaviours can look suspicious to heuristic antivirus software even when the underlying code is benign. During development, Norton has flagged test builds heuristically.

That is one of the reasons the project is distributed with the complete readable source rather than asking users to trust an opaque executable.

If your antivirus reports something, please **do not blindly disable your antivirus**. Review the source, submit the exact detection as tester feedback, and decide whether you are comfortable running it.

## 📦 Installation

Download the latest release ZIP from the **Releases** section of this repository.

Extract the files together:

```text
OutpostHLLSeeder_v0.22.bat
OutpostHLLSeeder_v0.22.ps1
config.txt
README.txt
```

Then double-click:

```text
OutpostHLLSeeder_v0.22.bat
```

The first run installs the working copy under:

```text
%LOCALAPPDATA%\OutpostHLLSeeder\
```

The setup screen shows the locations of the files actually being used.

After installation, the seeder runs in the background. The menu window itself does **not** need to remain open.

## 🎮 Existing-game protection

The seeder is designed not to interfere with what you're already doing.

If **Hell Let Loose is already running**, the scheduled seeding attempt is cancelled and the existing game is left alone.

If **another Steam game is actively being played**, the seeder cancels the attempt rather than trying to launch HLL alongside it.

Steam itself being open is completely normal and does not block the seeder.

## 💤 Sleep and wake behaviour

The scheduler can request a Windows wake shortly before the configured seeding time using the Windows wakeable-timer API.

Actual wake behaviour depends on the individual PC, Windows power state, firmware and hardware support.

By default:

```text
RETURN_TO_SLEEP_AFTER_SEEDING=false
```

So the seeder normally leaves post-seeding sleep behaviour to your existing Windows power settings.

There is an optional setting to request sleep after a completed automated seeding session, but this is deliberately **disabled by default**.

## 🧰 Seeder menu

Double-clicking the BAT after installation gives you:

```text
1. Run seeder now
2. Open configuration
3. Open activity log
4. Open error log
5. Show wake timer status
6. Reinstall / repair setup
7. Disable automatic startup
8. REMOVE SEEDER COMPLETELY
9. Exit
```

The background scheduler is independent of this menu, so the menu can safely be closed.

## 🗑️ Removing it

Choose `8. REMOVE SEEDER COMPLETELY`.

The seeder requires you to type `REMOVE` before deletion proceeds.

This removes the files, Startup launcher, scheduler process, logs and configuration created by the seeder. It does **not** remove or modify Steam or Hell Let Loose.

## 🆕 What's changed in v0.22

v0.22 is a maintenance update following initial public testing.

- Fixed a scheduler-status logging error when formatting the armed wake time
- The reported error affected status/error logging; the wake timer itself could still operate correctly
- Carries forward the current seeding thresholds: join below **60**, begin staggered departure rolls above **80**
- Keeps the **1-in-10 departure chance per minute**
- Keeps `RETURN_TO_SLEEP_AFTER_SEEDING=false` as the default

## 🧪 v0.22 public test

v0.22 is currently being put out for wider testing.

Useful feedback includes:

- Windows version and antivirus product
- whether first-time installation worked
- the exact antivirus warning/detection, if any
- whether the correct remote UTC seeding time appeared
- whether the wake timer was armed and the PC woke successfully
- whether HLL launched and joined correctly
- whether an existing HLL session was left alone
- whether another active Steam game prevented the seeder launching
- whether monitoring stopped cleanly if HLL was manually closed or crashed
- whether staggered shutdown worked once the server was live
- the contents of `errors.txt` if something failed

## 📋 Logs

The installed working directory is:

```text
%LOCALAPPDATA%\OutpostHLLSeeder\
```

Useful ordinary text files include:

```text
seeder.log
errors.txt
scheduler_status.txt
config.txt
```

## ⚠️ Known limitations

The current splash-screen bypass uses a fixed wait followed by a direct Space message to the HLL window. Very unusual PC/load conditions may require further timing adjustment.

Wake-from-sleep support ultimately depends on Windows, hardware, firmware and the current sleep state.

This project currently targets the **Steam version of Hell Let Loose on Windows**.

## ❤️ Why we're doing this

A healthy server shouldn't depend on the same handful of people sitting in an empty lobby every morning.

**The more seeders we have, the less actual seeding anybody has to do.**

If you're willing to let your PC lend The Outpost a hand, thank you.

---

**The Outpost — Hell Let Loose**
