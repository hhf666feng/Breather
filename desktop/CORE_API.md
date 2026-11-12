# Desktop core API

Pure JavaScript CommonJS for Node 22+. No Electron import, filesystem access, timers, permission prompts, network calls or global input hooks. The native macOS application remains the existing Swift implementation. The runtime supplies timestamps, system idle time and screen/session availability.

## Execution and verification

Implementation followed the shared desktop contract and the Swift `MonitorEngine` behavior. The test-first steps were: write deterministic core and optional contract tests; run them red; implement the engine and validation; run green; add failing self-review regressions for active-rest resume and bounded statistics; fix and rerun the suite. Run from the repository root:

```sh
node --test desktop/test/*.test.cjs
```

## Required core exports

```js
const { Monitor, defaultSettings, validateSettings, validateState, csv, dayKey } = require('./core.cjs');
const monitor = new Monitor({ settings: {}, records: [] });
monitor.tick(Date.now(), 0, true);
```

`defaultSettings()` returns a fresh object and a fresh weekdays array:

| Field | Default / accepted values |
| --- | --- |
| language | `zh-Hans`; also `en` |
| monitoringMode | `smart`; also `continuous` (reading/video) |
| workSeconds | `1200`, clamped to 10–14400 |
| restSeconds | `20`, clamped to 5–3600 |
| idleSeconds | `60`, clamped to 5–600 |
| fatigueThreshold | `100`, clamped to 10–100 |
| strictMode | `false` |
| skipChallengeEnabled | `false` |
| soundEnabled | `true` |
| reminderStyle | `fullscreen`; also `mini`, `notification` |
| scheduleEnabled | `false` |
| scheduleStartHour / scheduleEndHour | `9` / `18`, integers clamped to 0–23 |
| weekdays | `[2,3,4,5,6]`, Sunday = 1; unique valid values 1–7 |
| restMessage | `望向远处，暂时离开屏幕` |
| wallpaperPath | `null`; also string (runtime validates and imports the file) |
| showDockIcon | `true`; runtime maps this to Windows taskbar visibility |
| showMenuBarTime | `true`; runtime maps this to tray UI |
| dailyLimitEnabled | `false` |
| dailyLimitHours | `8`, clamped to 0.5–24 |
| advanceNoticeEnabled | `false` |

`validateSettings(input)` is a forgiving sanitizer returning complete, detached settings. Invalid types, nonfinite numbers and unsupported enums use defaults. Unknown properties are discarded. A complete settings assignment is sanitized automatically. For a partial update, merge first:

```js
monitor.settings = validateSettings({ ...monitor.settings, ...patch });
```

Use assignment rather than mutating the settings object to retain validation. Changes to strict mode affect the next rest; changes to rest duration do not move the current deadline.

## Monitor instance

Constructor: `new Monitor({settings, records} = {})`. Missing arguments use defaults. Records are validated, copied and sorted. A malformed supplied records array throws `TypeError` with an `Invalid backup:` message.

Public fields:

| Field | Meaning |
| --- | --- |
| settings | Assignable complete sanitized settings |
| records | Array of daily aggregates, sorted ascending by day |
| phase | `monitoring`, `idle`, `resting`, `paused`, `snoozed`, `outsideSchedule` |
| fatigue | Percentage, 0–100 |
| workElapsed | Fatigue scaled to the configured work interval, in seconds |
| breakRemaining | Seconds until the current rest deadline, or 0 |
| breakIsStrict | Strictness captured when the current/most recent round began |
| notificationCount | Monotonic session notification counter; runtime watches increments |
| snoozeEnd | Timestamp in **milliseconds**, or `null` |

Only settings is intended for runtime assignment; treat all other fields and the contents of records as read-only. No function returns presentation text, opens windows or emits OS notifications.

| Method | Result / behavior |
| --- | --- |
| `tick(nowMs, idleSeconds, available = true)` | Updates state. First sample establishes the clock. Intervals of at most 15 seconds count; longer intervals recover fatigue without adding usage. |
| `startBreak(nowMs)` | Starts a manual rest, clears pause/snooze and records an offer. No-op during a current rest. Returns `undefined`. |
| `skipBreak(nowMs)` | Boolean. Rejects outside rest or during strict rest; otherwise records a skip and snoozes for 300 seconds. |
| `snooze(nowMs, seconds = 300)` | Boolean. Rejects strict rest; normal rest becomes a skip. Continues active monitoring while reminders are suppressed. |
| `setPaused(value, nowMs)` | Boolean. Strict rest rejects pause. Normal rest pause counts as skip. Paused ticks neither count use nor recover fatigue. Resume during an active rest preserves its phase and deadline. |
| `resetClock(nowMs)` | Sets the last sample time without counting the preceding interval. Returns `undefined`. |

Timestamps are finite JavaScript milliseconds within the Date range. Invalid timestamps, negative/nonfinite snooze durations, and nonboolean pause values throw `TypeError` before changing state. Idle seconds and availability are trusted adapter inputs; runtime must supply an OS idle number and boolean availability.

Smart mode treats `idleSeconds >= settings.idleSeconds` as idle. Continuous mode ignores input idle, but unavailable/locked/asleep sessions always exclude active usage. An idle interval reduces fatigue by `seconds * 100 / restSeconds`. Active use adds `seconds * 100 / workSeconds` up to 100. Like Swift, `workElapsed` follows fatigue during monitoring/recovery; while resting it remains the prior work value until completion resets both to zero.

Rest completion follows the fixed wall-clock deadline, including a sleep gap, and counts exactly once against the day the rest began. It never records elapsed break time as active usage. Notification style keeps monitoring and usage running at peak; it increments `notificationCount` at most once per 300 seconds and never creates offered/completed rest records. Notification throttling resets after a monitoring tick observes fatigue below threshold minus one, matching Swift.

A selected schedule gates reminders only. Use/fatigue continue outside its hours. Start inclusive/end exclusive; equal hours select the whole weekday. For overnight schedules, the after-midnight portion belongs to the preceding weekday. Snooze temporarily suppresses reminders while use/fatigue continue. Pausing and restarting sampling exclude their intervening interval.

## Records, restore validation and CSV

Each record is:

```js
{
  day: '2025-01-01',
  activeSeconds: 0,
  peakFatigueSeconds: 0,
  breaksOffered: 0,
  breaksCompleted: 0,
  breaksSkipped: 0,
  hourlySeconds: Array(24).fill(0)
}
```

`dayKey(Date)` uses the local calendar and returns `YYYY-MM-DD`; invalid dates throw `TypeError`. Usage splits at local hour and midnight boundaries. Peak usage counts only intervals whose preceding sample was already at 100% fatigue, independent of a lower reminder threshold. Repeated daylight-saving hours share their local hour bucket.

`validateState(input)` accepts the parsed object `{settings, records}`, returns a detached sanitized object, and throws `TypeError('Invalid backup: ...')` for malformed backup data. The runtime owns JSON parsing, atomic writes and preservation of unreadable originals. Missing settings fields merge current defaults, preserving old preferences. Daily record fields are required, as in the Swift storage schema. Unknown settings fields are ignored so native backups can be imported without exposing unsupported features.

Validation rejects invalid known settings types/enums, nonfinite values, missing root fields, impossible/duplicate calendar days, invalid daily/hourly totals, and unsafe/fractional counters. Numeric settings in valid types are clamped to the documented ranges. Daily active seconds must be 0–90000; peak must be 0–active; all counters are safe integers 0–1000000, and `completed + skipped <= offered`; hourly arrays must contain exactly 24 finite values each 0–7200. Hourly sums are not required to equal daily totals, matching native validation and preserving older records.

Accumulation preserves those storage bounds: usage and hour totals saturate; once a day's offers reach 1000000, another real rest remains usable but its offer/outcome is not added. This avoids creating data that cannot be reloaded. Compared with the Swift reference, the JS core additionally rejects impossible calendar dates and protects an active rest from a redundant resume command. Normal timing, fatigue, recovery, notification and statistics behavior match Swift.

`csv(records)` returns a string with CRLF line endings including a final CRLF, ascending days, integer-truncated usage values, and a four-decimal POSIX-style completion ratio (zero if no offers):

```text
date,active_seconds,peak_fatigue_seconds,breaks_offered,breaks_completed,breaks_skipped,completion_rate
```

It does not mutate input or write a file. Unexpected day strings are CSV-quoted with embedded quotes escaped, like Swift; runtime should export validated engine records.

## Optional contracts exports

```js
const { COMMANDS, isAllowedCommand, shortcutMap, closePolicy } = require('./contracts.cjs');
```

These helpers are available for runtime selection; equivalent runtime-owned code is valid and no additional integration names are required by the shared contract.

`COMMANDS` is a frozen array: `get-state`, `settings`, `pause`, `rest`, `snooze`, `skip`, `quit`, `export-csv`, `export-backup`, `restore-backup`, `choose-wallpaper`, `clear-wallpaper`, `launch-at-login`, `dismiss-error`, `answer-challenge`, `cancel-challenge`. `isAllowedCommand(name)` returns a boolean; sender authentication and payload validation remain runtime duties.

`shortcutMap(platform = 'win32')` returns `{close,minimize,preferences,showMain,rest,quit}` with `Ctrl+W`, `Ctrl+M`, `Ctrl+,`, `Ctrl+0`, `Ctrl+Shift+R`, `Ctrl+Q`; `darwin` uses `Command` instead of `Ctrl`. Windows `Alt+F4` is handled through native close events, and standard editing uses Electron roles. These shortcuts are app-scoped, never global keyboard hooks.

`closePolicy({view = 'main', phase, breakIsStrict = false, action = 'close', quitting = false} = {})` returns:

| Condition | Result |
| --- | --- |
| Explicit quit | `allow` |
| Active strict rest close/minimize | `block` |
| Active normal rest close/minimize | `skip` |
| Main close | `hide` |
| Main minimize or inactive rest | `allow` |

The runtime must act on the result, call skip/challenge semantics for normal dismissal, and enforce the guard in actual native window events. A pure helper test does not verify real OS shortcuts.

## Platform boundaries

The desktop core supports the local primary features: smart/continuous use detection from runtime signals, fatigue recovery, fullscreen/mini/notification reminder decisions, strict rest, snooze/pause, schedules, daily/hourly statistics and portable validated backup/CSV data. Runtime owns notification permission, arithmetic challenge, advance/daily-limit notices, wallpaper import, tray, taskbar, login, sound and secure IPC.

Windows does not claim the Mac-specific enhanced input/accessibility or screen-content activity sampling permissions. Those optional fields are deliberately absent from desktop defaults and are discarded during import. The existing native macOS application and its enhancements are preserved independently. Node tests validate portable domain behavior, not a Windows binary or actual Electron event handling; those require runtime smoke/Windows CI.
