# ExecFn — Product & Technical Decisions

This file holds every decision that shapes behavior. `ARCHITECTURE.md` refers to these by ID.

**How to use:** each decision starts as **Proposed**. Change it to **Accepted**, edit it, or mark it **Rejected** with a note. Code follows only Accepted decisions; anything still Proposed when its phase starts gets settled before that phase is coded.

Default numbers are starting points, not research findings. Tune them with ActivityLog data.

---

## Open questions (blocking prioritization, not Phase 1)

| ID | Question | Current assumption | What changes |
|----|----------|--------------------|--------------|
| Q-1 | Do you have an iPhone / Apple Watch? | Yes | If no: Phase 7 becomes sync-only or is dropped; D-24 metric is moot. |
| Q-2 | Swift / SwiftUI experience? | Unknown | Pacing and how much code arrives per step. |
| Q-3 | Standalone app, or the task/calendar module of a larger life app? | Standalone, but `EFCore` + `EFPersistence` are packages | If module: packages move into the larger app unchanged. |
| Q-4 | When to join the paid Apple Developer Program? | At Phase 7 | Needed for iCloud/CloudKit and public distribution. |

---

## Architecture

### D-01 · Domain is value types; persistence is a separate adapter
**Status:** Accepted (2026-11-20; in use since Phase 1)
**Decision:** `EFCore` contains only structs and enums (`TaskSnapshot`, `PlanProposal`, `PlannedNotification`, `PlannerSettings`, …), which are `Sendable` and have no SwiftData, SwiftUI, EventKit, or UserNotifications imports. `EFPersistence` holds the `@Model` classes, mappers between models and snapshots, and a repository. Views may **read** via `@Query`. All **writes** go through repository commands: load snapshots → call `EFCore` → apply the returned changes.
**Why:** Pure functions need plain values. `@Model` classes are context-bound reference types and aren't `Sendable`, which fights Swift 6 strict concurrency, and tests would need a `ModelContainer`.
**One context:** the app reads and writes the main store through a single `ModelContext`, `container.mainContext`. The repository is handed that context; it does not create its own. Views (`@Query`), the focus timer, and repository commands therefore see the same objects. The activity store keeps its own context (different container).
**Rejected:** `@Model` as the domain (conflicts with testability and concurrency). Dropping `@Query` entirely (forces hand-rolled observation for little gain). A private context per repository (drifts from `@Query` as soon as the view and the timer both touch a session).
**Revisit if:** mapping boilerplate becomes the main source of bugs.

### D-02 · Activity log lives in a local-only store
**Status:** Accepted (2026-11-20; in use since Phase 1)
**Decision:** `ActivityEvent` goes in a second SwiftData `ModelContainer` with `cloudKitDatabase: .none`, in the App Group container (SQLite underneath, so app, widgets and intents can all write safely). Provide CSV/JSONL export for DuckDB or pandas. Each device keeps its own log.
**Why:** High-volume append-only events in the synced store bloat CloudKit, create conflicts, and complicate migrations. Per-device logs answer "where did I act?" in Phase 7.
**Rejected:** Same store as tasks. Raw JSONL file (multi-process appends need file coordination).

### D-03 · Task status is `open | done | dropped`; Inbox is derived
**Status:** Accepted (2026-11-20; in use since Phase 1)
**Decision:** No `inbox` or `active` status. A task is **in the Inbox** when it is `open`, has no bucket, is not a Today must, has no time block, is not a routine instance, is not Someday, and is not carried (`carriedFrom == nil`). A carried task shows only in the "From yesterday" row (D-06); once `carriedFrom` clears it can appear in the Inbox. `dropped` carries a reason (`user`, `routineExpired`).
**Why:** Removes the undefined "when does a task become active" transition. Fewer states, fewer rules to get wrong.
**Rejected:** Explicit `inbox → active` transition triggered by Today, Start, or a block (three triggers, easy to get inconsistent).

### D-04 · One `PlannerSettings` struct feeds every pure function
**Status:** Accepted (2026-11-20; in use since Phase 1)
**Decision:** A single `Codable` struct holds all tunables (see the table at the end). It's stored in App Group `UserDefaults` and passed explicitly into every `EFCore` function. The UI edits it; nothing else does.
**Settings only, not app state:** the pinned task (D-08) and the rollover marker (D-05) are not settings and do not go in this struct.
**Decoding is tolerant:** `PlannerSettings` has a hand-written `init(from:)` that reads every field with `decodeIfPresent` and keeps the default when a field is missing. The synthesized decoder fails on any missing non-optional field, and `SettingsStore.load()` then falls back to `.standard`, silently discarding saved calendar modes. A test decodes the Phase 1 JSON shape after every field addition.
**Why:** Stops planner signatures changing every phase. Makes every test fully specified.

---

## Daily loop

### D-05 · Day boundary at 4:00 AM; rollover runs once per gap
**Status:** Accepted (2026-11-20)
**Decision:** The plan day starts at `dayBoundaryHour` (default 4). Rollover runs on launch, on wake, and at the boundary. It is **idempotent**, keyed by `lastRolloverDay`: after a 9-day absence it runs once from the last active day to today, not 9 times.
- **Where the marker lives:** in the main store, written in the **same `save()`** as the rollover changes. Implemented as `DayPlanModel.rolledOverAt` on the new day's `DayPlanModel` (schema v2, lightweight migration); `lastRolloverDay` = the latest day with `rolledOverAt != nil`. Rollover fetches the day's `DayPlanModel` before inserting one (no unique constraints under CloudKit rules). Not in UserDefaults: a crash between a store save and a defaults write would run rollover twice (double `rolloverCount`, a second carried row), and in Phase 7 a per-device marker would re-roll synced tasks.
- **Boundary trigger:** nothing in the system fires at 4 AM. A one-shot timer is scheduled for the next boundary and re-armed after each rollover, on wake (`NSWorkspace.didWakeNotification`), and on time-zone / clock changes (`NSSystemTimeZoneDidChange`, `NSSystemClockDidChange`).
- **Pause days:** day modes arrive in Phase 4a. Until then every previous day counts as non-pause.
**Why:** Most adults with ADHD run on a delayed sleep cycle, so midnight splits real days. Multiple runs would inflate `rolloverCount` and create phantom carried rows.

### D-06 · Rollover shows a non-blocking "From yesterday" row
**Status:** Accepted (2026-11-20)
**Decision:** At rollover, unfinished Today musts become `isTodayMust = false`, `carriedFrom = previousActiveDay`, `rolloverCount += 1` (no increment if the previous day was a pause day). Today shows a **"From yesterday"** row at the top:
- Per item: **Today** · **Later** · **Drop**. One action: **Keep all as Later**.
  - **Today** → `isTodayMust = true`, `carriedFrom = nil` (goes through the D-07 cap prompt).
  - **Later** → `carriedFrom = nil`; the task is now in the Inbox (D-03).
  - **Drop** → `dropped(.user)`, `carriedFrom = nil`.
- Carried tasks are not in the Inbox while `carriedFrom` is set (D-03), so nothing appears in two places.
- At most 3 visible, then "+N more". No red, no counts in a badge.
- Untouched items: at the *next* rollover, `carriedFrom` clears (they become Later). They never accumulate in this row.
- Hidden on pause days. Routine instances never appear here (D-20).

**Why:** The research asked for one-tap triage on rollover. Tasks silently leaving Today is a hidden rewrite, and it recreates out-of-sight-out-of-mind after a bad day.
**Rejected:** Silent removal from Today (v1 of the architecture). A modal triage on launch (puts a chore between you and capture, and hits hardest after a bad stretch).

### D-07 · Today cap = 3 musts, suggested not enforced
**Status:** Accepted (2026-11-20)
**Decision:** Marking a 4th must shows "Today already has 3. Swap one?" with the option to proceed anyway. The cap is adjusted by energy (D-16) and day mode.
**Why:** One-thing-at-a-time without blocking the user (negotiate, don't enforce).

### D-08 · "Now" selection is deterministic
**Status:** Accepted (2026-11-20)
**Decision:** First match wins:
1. Task with a running work session
2. Pinned task (user tapped "Make this Now")
3. Current time block or timed routine instance covering *now*
4. First unfinished Today must (by order)
5. Time block or timed routine starting within 60 min
6. Empty state: "Pick one" with up to 3 candidates (musts, then due-soonest, then oldest)

"Next" = the next match after excluding the Now task.

**The pin:** one `pinnedTaskID: UUID?` stored on its own UserDefaults key in the App Group (not in `PlannerSettings`, not a flag on every task). Set by "Make this Now". Cleared by Done, Drop, an explicit Unpin, and **rollover** (yesterday's pin must not outrank today's musts). Survives relaunch within the same plan day. A pin to a task that is no longer open is ignored and cleared. A running session (step 1) still outranks it.
**Why:** Phases 2–5 need a fixed rule. Scored pick-for-me (Phase 6) only replaces step 6.

---

## Calendar

### D-09 · Per-calendar mode: Hidden / Visible / Busy
**Status:** Accepted (2026-11-20; in use since Phase 1)
**Decision:** Each EventKit calendar has a mode. **Busy** events block free-slot logic. **Visible** events render but don't block. **Hidden** events aren't shown. Defaults: Birthdays, holiday calendars, and subscribed calendars → Visible; everything else → Busy. Stored in `PlannerSettings` keyed by `calendarIdentifier`, with calendar title as a fallback match (identifiers can change after a full resync).
**Why:** Without it, birthdays and holidays fill every day and back-planning finds no free time. It must exist before any free-slot logic, so it ships in Phase 1.

### D-10 · All-day events never occupy time slots by default
**Status:** Accepted (2026-11-20; in use since Phase 1)
**Decision:** All-day events render in an all-day strip and don't block time, **unless** `availability` is `.busy` or `.unavailable` (e.g., "Out of office"). If the source reports `.notSupported`, treat as free. Timed events block if their calendar is Busy and `availability != .free`.
**Why:** Otherwise one all-day event blocks the entire day for proposals and the now line.

### D-11 · Scheduling: tap-a-gap first, day-column drag, cross-day drag last
**Status:** Accepted (2026-11-22)
**Decision:**
- Free time for proposals is **5:00–21:00** on the plan day's civil date (`planningWindowStartMinutes` / `planningWindowEndMinutes`). The timeline still draws the whole plan day. Dragging a block may leave that window.
- Phase 3: tap a free gap → a ghost block. If something is Now, the ghost is for that task; otherwise a short picker lists today's musts, then the Inbox. Length is the estimate, or 30 minutes when there is none, rounded to the nearest 15 and clipped to the gap. Nothing is saved until **Place it**. "Place on today" drafts the next free gap the same way.
- Drag within the Day column moves and resizes, snapped to 15 minutes. That is the user deciding, so it saves immediately and may overlap (D-13).
- Phase 4b: Week view starts read-only + tap-a-gap. Cross-day drag comes after. Month view is density + tap-to-day.

**Why:** Tap-a-gap is the same code as back-planning proposals and the keyboard-accessible path. The hard UI is cross-day drag, resize and overlap layout on a 7-column grid, so it goes last. The check-in multiplier and the estimator are not a block length.

### D-12 · A passed block gets one prompt
**Status:** Accepted (2026-11-22)
**Decision:** A block is waiting when its end has passed, its task is still open, no session overlaps it, and it has no resolution. Show one at a time, earliest first. The words are **"This time has passed."** Actions: **Reschedule** · **Leave it** · **I did it**. Reschedule marks the old block resolved and drafts the next free gap today that can hold it; if today has no gap long enough, the prompt says **"The day is full."** and Leave it is the way out. Leave it and I did it free the task to return to the Inbox. "I did it" records an **unverified** session over the block's own start and end (excluded from the estimator) and does not start a live timer. The resolution is stored on the block so it never prompts twice.
**Why:** "No stale blocks" needs a detector. Unverified sessions keep estimator data clean. The UI never says "missed".

### D-13 · Overlap is allowed when you create it; proposals never create it
**Status:** Accepted (2026-11-22)
**Decision:** User-placed blocks may overlap events or other blocks (rendered side by side). Planner proposals only use free time per D-09/D-10.
**Why:** The app proposes, the user decides.

### D-17 · Travel and buffers
**Status:** Accepted (2026-11-20; in use since Phase 1)
**Decision:** `defaultBufferMinutes` (10) in settings, applied between busy items for proposals and transition alerts. Per-event overrides (travel minutes, transition alerts on/off) live in `EventAnnotation`, keyed by `calendarItemExternalIdentifier` + occurrence start date. **Not** keyed by `eventIdentifier`, which can change when an event moves calendars. Verify in Phase 1 whether EventKit exposes Calendar.app's travel time (assumed not).
**Why:** "Leave by" and auto-buffers were in the research but had nowhere to live.

**Phase 1 check (macOS 26.5 SDK, `EKEvent.h`):** EventKit does not expose Calendar travel time. `EKEvent` has `structuredLocation` and `location`, plus `availability` (`notSupported`, `busy`, `free`, `tentative`, `unavailable`). There is no travel-time property. A runtime check for a `travelTime` selector stays in `CalendarService` so a future SDK is noticeable. Travel minutes stay user-entered on `EventAnnotation`.

### D-23 · Apple Calendar mirror: cut from v1
**Status:** Proposed
**Decision:** Don't write time blocks into Apple Calendar in v1.
**Why:**
- Your own calendar view would show mirrored blocks twice unless it excludes that calendar.
- Alarms on mirrored events also fire Calendar.app alerts on the Mac, duplicating ExecFn notifications and bypassing the budget. Without alarms, the iPhone gets nothing, which was the point.
- Writing in response to `.EKEventStoreChanged` is a feedback loop.

**If revived later:** write-only projection; events tagged `execfn://block/<id>`; the change handler never writes; the ExecFn calendar is excluded from reads; outside edits are ignored, never "fixed"; ExecFn suppresses its own notification for mirrored blocks.

---

## Focus & sessions

### D-14 · Hyperfocus check-in doubles as the runaway-session cap
**Status:** Accepted (2026-11-20)
**Decision:** During a work session, ask "Still on this?" at `estimate × 1.5`, or 45 min when there's no estimate. **Yes** → next check-in after the same interval. No answer within 45 min of a check-in → session auto-ends, `end = check-in time`, `endedBy = autoEnded`, excluded from the estimator.
**Delivery (Phase 2):** a check-in is shown in the floating timer **and** as a local notification ("Still on this?" with Yes · Done · Stop actions). Someone in hyperfocus is not looking at the ExecFn window; an in-app-only prompt would auto-end real work and drop it from the estimator. Phase 2 ships a minimal `NotificationService` that handles only the check-in category; it is still the only code that calls `UNUserNotificationCenter`. The full `NotificationPlanner` (budget, escalation, quiet hours) arrives in Phase 4a; check-ins are exempt from quiet hours and the budget because the user started the session.
**Sleep and quit:** deadlines are evaluated from timestamps on wake and launch, not only by timers. If the Mac slept past check-in + grace, the session ends at the check-in time as `autoEnded`. A session still open at quit ends as `appQuit` at quit time.
**Why:** Restores the research's hyperfocus check-in and closes the nil-estimate hole in the runaway cap with one mechanism.

### D-27 · "Just 5 minutes" ships in Phase 2
**Status:** Accepted (2026-11-20)
**Decision:** Next to **Start**, a **Just 5 minutes** action starts a normal timed session whose first check-in comes at 5 minutes instead of the D-14 interval. The 5-minute prompt is "Keep going?" with **Keep going** (the check-in schedule then follows D-14 from that point) and **Stop here**, which ends it as `endedBy = user`, with no follow-up nudge. Logged as `sessionStarted(mode: fiveMinutes)`.
**Why:** Daily use starts at the end of Phase 2, and a session you are allowed to stop is the research's cheapest way to start. Without it, Start is open-ended and the first help comes at a 45-minute check-in. Moved forward from Phase 3; subtasks and drag-scheduling stay there.

### D-21 · Completion feedback is in v1
**Status:** Accepted (2026-11-20)
**Decision:** On completion: a short animation, a haptic via `NSHapticFeedbackManager` (only felt on a Force Touch trackpad with a finger on it), and an optional sound (off by default).
**Why:** Cheap, and it matches the reward-sensitivity evidence better than themes or gamification.

---

## Recovery

### D-15 · Fresh start is barely destructive; undo for 24 h
**Status:** Accepted (2026-11-22)
**Decision:** Fresh start clears `isTodayMust`, `todayOrder`, and `carriedFrom` on all open tasks. An optional checkbox also moves tasks untouched for 30+ days to **Someday**. Someday is also a manual move, and bringing a task back clears `isSomeday` so it can return to the Inbox. Fresh start does not touch blocks, the running session, the pin, or completed tasks. A snapshot of those fields is stored with the activity event; Undo is available for 24 h and only restores tasks that are still open.
**Why:** If it barely destroys anything, undo is trivial and the button is safe to press on a bad day.

### D-18 · Comeback screen after ≥ 3 days away
**Status:** Proposed
**Decision:** When the gap since the last activity is ≥ `comebackGapDays` (3), the first launch shows **Welcome back**: today's calendar, up to 3 suggested tasks, and a **Fresh start** button. No backlog, no counts, no list of what was missed. Dismissing it goes to Now.
**Why:** Absence is the main abandonment risk. The first screen after a gap decides whether you come back.

### D-16 · One energy vocabulary
**Status:** Proposed
**Decision:** Tasks: `low | high` (optional). Daily check-in: `low | normal | high` (optional).
- `low` → Today cap 1; Now/pick-for-me prefer low-energy tasks; notifications reduced to essentials.
- `normal` → defaults.
- `high` → Today cap +1; high-energy tasks preferred in energy windows.

**Why:** v1 had two unrelated scales (low/high vs 1–5) and no mapping.

---

## Cues & routines

### D-19 · If-then plans: keep the text, optionally bind a cue
**Status:** Proposed
**Decision:** `IfThenPlan { text, cue? }`. The text is the plan itself: in the studies, forming the plan was the intervention, and the real-world situation was the cue (nothing fired a reminder). The optional `cue` adds an external nudge through the NotificationPlanner:
- `.atTime(Date)`
- `.afterEvent(EventRef)` (fires at event end + buffer)
- `.onMacWake` (wake/unlock)
- `.focusChanged(focusID)`

**Why:** Weak working memory benefits from an outside nudge, and a Mac can detect these cues. "When I open my laptop" is a cue the Mac can see.
**Rejected:** Text only (no external support). Renaming it to notes (throws away the evidence-based part).

### D-20 · Routines: templates spawn daily instances that expire
**Status:** Accepted (2026-11-22)
**Decision:** `RoutineTemplate { title, schedule, timeOfDay?, checklist[], bucket?, energy? }`, where schedule is `.daily | .weekdays | .weekly(days) | .everyNDays(n, anchor)`. At rollover, in the same save, create today's instance as a task (`routineID`, `routineDay`) unless one already exists for that day. The template's checklist becomes subtasks. Open instances from earlier days become `dropped(.routineExpired)`. They never roll over, never appear in "From yesterday", and are never shown as passed. Today shows them in their own row; they do not count toward the cap of 3. Editing a template changes future instances. Turning it off stops future days. `timeOfDay` is stored and does nothing until Phase 4a: no alarm, no automatic block. A routine created during the day spawns today's instance immediately when it is due. No RRULE.
**Why:** Routines are a large share of daily ADHD failure. Accumulating skipped instances recreates the red pile.

---

## Platform

### D-22 · Calendar access denied → full task-manager mode
**Status:** Accepted (2026-11-20; in use since Phase 1)
**Decision:** If EventKit access is denied or restricted, everything except calendar events still works: capture, Now, Today, blocks on an empty timeline, notifications. Settings shows the access state and a button to open System Settings.

### D-24 · Phase 7 priority is decided by measured presence
**Status:** Accepted (2026-11-20)
**Decision:** Log presence intervals (`active | idle >5 min | locked | asleep`) from wake/sleep, lock/unlock, and idle-time checks. Log every planned notification's fire time. After 2–3 weeks of Phase 4a, compute **% of notifications due while away from the Mac**. A high share moves Phase 7 up.
**Caveat:** the screen lock/unlock notifications are undocumented distributed notifications, and idle-time APIs must be verified inside the sandbox.
**Why:** The Mac-only build is a weak test if failures happen away from the desk. This turns "move iOS up?" into a number.
**Known cost:** an iPhone app without sync is an island, so iOS earlier means CloudKit and the paid program earlier.

### D-25 · Menu-bar countdown is a Phase 0 spike
**Status:** Accepted (2026-11-20)
**Decision:** On the first day of Phase 2, before the menu bar or presence logger is designed, prototype a live-updating menu bar label. Try `MenuBarExtra` (`.window` style) with a minute-resolution label first; fall back to AppKit `NSStatusItem` if the label doesn't update reliably. Minutes in the bar; seconds only in the popover/timer. Same spike: the capture `NSPanel` with `.nonactivatingPanel`, `.floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, and a subclass overriding `canBecomeKey` so it accepts typing over full-screen apps; and the D-24 presence signals from inside the sandbox. Results are recorded under **Phase 0 results** below. Capture, Now, and rollover don't depend on the spike and can be built either way.

**What the menu bar shows** (minute resolution, never red). A running session counts down to its next check-in. With no session, the bar counts down to the next calendar event. The popover shows the session clock in seconds and the next event together.
| State | Label | Popover |
|-------|-------|---------|
| Session running, check-in still ahead | Task title · minutes until the check-in | Elapsed timer in seconds, "check-in in Nm", next event |
| Session running, check-in waiting for an answer | Task title · check-in | The prompt: Yes / Done / Stop, or Keep going / Stop here |
| No session, Now task, an event still today | Now task · minutes until that event | Now / Next, next event |
| No session, Now task, no event | Now task title | Now / Next |
| Nothing in Now | App icon only | "Pick one" (D-08 step 6) |

**Phase 0 results** (spike: `Spikes/MenuBarCountdown`, run `./build.sh` then `open Spike.app`; it's sandboxed, ad-hoc signed, and logs to `~/Library/Containers/com.execfn.spike/Data/Library/Application Support/spike.log`):
- Menu bar label ticks with `MenuBarExtra(.window)`: **yes (2026-11-20, macOS 26)**. A label driven by a published counter updated in step with an `NSStatusItem` across app switches, with the popover closed. Still to check: it keeps ticking after the popover has been opened and closed. → using `MenuBarExtra` unless that fails.
- Global hotkey registers from the sandbox (Carbon `RegisterEventHotKey`, ⌃⌥Space): **yes**.
- Capture panel accepts typing over a full-screen app without activating ExecFn: ☐ yes ☐ no → notes: ____
- Idle seconds readable in the sandbox (`CGEventSource.secondsSinceLastEventType`): returns a value; ☐ confirmed it rises past 60 s when idle.
- Sandboxed app sees lock/unlock (`com.apple.screenIsLocked` / `…Unlocked`): ☐ yes ☐ no → if no, D-24 logs sleep/wake (+ idle if readable) only.

---

## Scope

### D-26 · Not in v1
**Status:** Proposed
**Decision:** Explicitly out until data says otherwise: reward pairing, novelty/quest themes, wind-down reminders, body doubling / focus rooms, accountability partners, Apple Calendar mirror (D-23), streaks of any kind, iOS/Watch (Phase 7), CloudKit sync (Phase 7).
**In v1 despite being small:** hyperfocus check-in (D-14), completion feedback (D-21), routines (D-20), "just 5 minutes" (D-27).

---

## Default values (all in `PlannerSettings`)

| Setting | Default | Used by |
|---------|---------|---------|
| `dayBoundaryHour` | 4 | D-05 |
| `todayCap` | 3 | D-07, D-16 |
| `notificationBudget` (per day) | 10 | NotificationPlanner |
| `quietHours` | 22:00–08:00 | NotificationPlanner |
| `defaultBufferMinutes` | 10 | D-17 |
| `proposalSnapMinutes` | 15 | D-11 |
| `planningWindowStartMinutes` | 5:00 | D-11 |
| `planningWindowEndMinutes` | 21:00 | D-11 |
| `defaultBlockMinutes` | 30 | D-11 |
| `nowLookaheadMinutes` | 60 | D-08 |
| `checkInMultiplier` | 1.5 | D-14 |
| `checkInNoEstimateMinutes` | 45 | D-14 |
| `checkInGraceMinutes` | 45 | D-14 |
| `fiveMinuteStartMinutes` | 5 | D-27 |
| `comebackGapDays` | 3 | D-18 |
| `somedayAfterDays` | 30 | D-15 |
| `estimatorMinSamples` | 5 | Estimator |
| `estimatorWindow` | 20 sessions | Estimator |
| `estimatorClamp` | 0.5–3.0 | Estimator |
| `idleThresholdMinutes` | 5 | D-24 |
| `calendarModes` | per D-09 | D-09 |
| `energyWindows` | none | Phase 6 |
