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
**Status:** Proposed
**Decision:** `EFCore` contains only structs and enums (`TaskSnapshot`, `PlanProposal`, `PlannedNotification`, `PlannerSettings`, …), which are `Sendable` and have no SwiftData, SwiftUI, EventKit, or UserNotifications imports. `EFPersistence` holds the `@Model` classes, mappers between models and snapshots, and a repository. Views may **read** via `@Query`. All **writes** go through repository commands: load snapshots → call `EFCore` → apply the returned changes.
**Why:** Pure functions need plain values. `@Model` classes are context-bound reference types and aren't `Sendable`, which fights Swift 6 strict concurrency, and tests would need a `ModelContainer`.
**Rejected:** `@Model` as the domain (conflicts with testability and concurrency). Dropping `@Query` entirely (forces hand-rolled observation for little gain).
**Revisit if:** mapping boilerplate becomes the main source of bugs.

### D-02 · Activity log lives in a local-only store
**Status:** Proposed
**Decision:** `ActivityEvent` goes in a second SwiftData `ModelContainer` with `cloudKitDatabase: .none`, in the App Group container (SQLite underneath, so app, widgets and intents can all write safely). Provide CSV/JSONL export for DuckDB or pandas. Each device keeps its own log.
**Why:** High-volume append-only events in the synced store bloat CloudKit, create conflicts, and complicate migrations. Per-device logs answer "where did I act?" in Phase 7.
**Rejected:** Same store as tasks. Raw JSONL file (multi-process appends need file coordination).

### D-03 · Task status is `open | done | dropped`; Inbox is derived
**Status:** Proposed
**Decision:** No `inbox` or `active` status. A task is **in the Inbox** when it is `open`, has no bucket, is not a Today must, has no time block, is not a routine instance, and is not Someday. `dropped` carries a reason (`user`, `routineExpired`).
**Why:** Removes the undefined "when does a task become active" transition. Fewer states, fewer rules to get wrong.
**Rejected:** Explicit `inbox → active` transition triggered by Today, Start, or a block (three triggers, easy to get inconsistent).

### D-04 · One `PlannerSettings` struct feeds every pure function
**Status:** Proposed
**Decision:** A single `Codable` struct holds all tunables (see the table at the end). It's stored in App Group `UserDefaults` and passed explicitly into every `EFCore` function. The UI edits it; nothing else does.
**Why:** Stops planner signatures changing every phase. Makes every test fully specified.

---

## Daily loop

### D-05 · Day boundary at 4:00 AM; rollover runs once per gap
**Status:** Proposed
**Decision:** The plan day starts at `dayBoundaryHour` (default 4). Rollover runs on launch, on wake, and at the boundary. It is **idempotent**, keyed by `lastRolloverDay`: after a 9-day absence it runs once from the last active day to today, not 9 times.
**Why:** Most adults with ADHD run on a delayed sleep cycle, so midnight splits real days. Multiple runs would inflate `rolloverCount` and create phantom carried rows.

### D-06 · Rollover shows a non-blocking "From yesterday" row
**Status:** Proposed
**Decision:** At rollover, unfinished Today musts become `isTodayMust = false`, `carriedFrom = previousActiveDay`, `rolloverCount += 1` (no increment if the previous day was a pause day). Today shows a **"From yesterday"** row at the top:
- Per item: **Today** · **Later** · **Drop**. One action: **Keep all as Later**.
- At most 3 visible, then "+N more". No red, no counts in a badge.
- Untouched items: at the *next* rollover, `carriedFrom` clears (they become Later). They never accumulate in this row.
- Hidden on pause days. Routine instances never appear here (D-20).

**Why:** The research asked for one-tap triage on rollover. Tasks silently leaving Today is a hidden rewrite, and it recreates out-of-sight-out-of-mind after a bad day.
**Rejected:** Silent removal from Today (v1 of the architecture). A modal triage on launch (puts a chore between you and capture, and hits hardest after a bad stretch).

### D-07 · Today cap = 3 musts, suggested not enforced
**Status:** Proposed
**Decision:** Marking a 4th must shows "Today already has 3. Swap one?" with the option to proceed anyway. The cap is adjusted by energy (D-16) and day mode.
**Why:** One-thing-at-a-time without blocking the user (negotiate, don't enforce).

### D-08 · "Now" selection is deterministic
**Status:** Proposed
**Decision:** First match wins:
1. Task with a running work session
2. Pinned task (user tapped "Make this Now")
3. Current time block or timed routine instance covering *now*
4. First unfinished Today must (by order)
5. Time block or timed routine starting within 60 min
6. Empty state: "Pick one" with up to 3 candidates (musts, then due-soonest, then oldest)

"Next" = the next match after excluding the Now task.
**Why:** Phases 2–5 need a fixed rule. Scored pick-for-me (Phase 6) only replaces step 6.

---

## Calendar

### D-09 · Per-calendar mode: Hidden / Visible / Busy
**Status:** Proposed
**Decision:** Each EventKit calendar has a mode. **Busy** events block free-slot logic. **Visible** events render but don't block. **Hidden** events aren't shown. Defaults: Birthdays, holiday calendars, and subscribed calendars → Visible; everything else → Busy. Stored in `PlannerSettings` keyed by `calendarIdentifier`, with calendar title as a fallback match (identifiers can change after a full resync).
**Why:** Without it, birthdays and holidays fill every day and back-planning finds no free time. It must exist before any free-slot logic, so it ships in Phase 1.

### D-10 · All-day events never occupy time slots by default
**Status:** Proposed
**Decision:** All-day events render in an all-day strip and don't block time, **unless** `availability` is `.busy` or `.unavailable` (e.g., "Out of office"). If the source reports `.notSupported`, treat as free. Timed events block if their calendar is Busy and `availability != .free`.
**Why:** Otherwise one all-day event blocks the entire day for proposals and the now line.

### D-11 · Scheduling: tap-a-gap first, day-column drag, cross-day drag last
**Status:** Proposed
**Decision:**
- Phase 3: tap a free gap → proposed block for a chosen task (snap 15 min) → accept or adjust. Drag within the Day column (move and resize).
- Phase 4b: Week view starts read-only + tap-a-gap. Cross-day drag comes after. Month view is density + tap-to-day.

**Why:** Tap-a-gap is the same code as back-planning proposals and the keyboard-accessible path. The hard UI is cross-day drag, resize and overlap layout on a 7-column grid, so it goes last.

### D-12 · Missed blocks get a one-tap prompt
**Status:** Proposed
**Decision:** A block is **missed** when its end has passed, its task isn't done, no work session overlaps it, and it has no resolution. Prompt: **Reschedule** · **Unschedule** · **I did it**. "I did it" records an **unverified** session (excluded from the estimator). The resolution is stored on the block so it never prompts twice.
**Why:** "No stale blocks" needs a detector. Unverified sessions keep estimator data clean.

### D-13 · Overlap is allowed when you create it; proposals never create it
**Status:** Proposed
**Decision:** User-placed blocks may overlap events or other blocks (rendered side by side). Planner proposals only use free time per D-09/D-10.
**Why:** The app proposes, the user decides.

### D-17 · Travel and buffers
**Status:** Proposed
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
**Status:** Proposed
**Decision:** During a work session, ask "Still on this?" at `estimate × 1.5`, or 45 min when there's no estimate. **Yes** → next check-in after the same interval. No answer within 45 min of a check-in → session auto-ends, `end = check-in time`, `endedBy = autoEnded`, excluded from the estimator.
**Why:** Restores the research's hyperfocus check-in and closes the nil-estimate hole in the runaway cap with one mechanism.

### D-21 · Completion feedback is in v1
**Status:** Proposed
**Decision:** On completion: a short animation, a haptic via `NSHapticFeedbackManager` (only felt on a Force Touch trackpad with a finger on it), and an optional sound (off by default).
**Why:** Cheap, and it matches the reward-sensitivity evidence better than themes or gamification.

---

## Recovery

### D-15 · Fresh start is barely destructive; undo for 24 h
**Status:** Proposed
**Decision:** Fresh start clears `isTodayMust` and `carriedFrom` on all open tasks. An optional checkbox also moves tasks untouched for 30+ days to **Someday** (hidden from default lists, surfaced in the weekly review). It does not touch blocks or completed tasks. A snapshot `[taskID: (isTodayMust, carriedFrom, isSomeday)]` is stored with the activity event; Undo is available for 24 h.
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
**Status:** Proposed
**Decision:** `RoutineTemplate { title, schedule, timeOfDay?, checklist[], bucket?, energy? }`, where schedule is `.daily | .weekdays | .weekly(days) | .everyNDays(n, anchor)`. At rollover, create today's instance as a task (`routineID`, `routineDay`). Open instances from earlier days become `dropped(.routineExpired)`. They never roll over, never appear in "From yesterday", and are never shown as missed. Basic routines in Phase 3; time cues in Phase 4a. No RRULE.
**Why:** Routines are a large share of daily ADHD failure. Accumulating missed instances recreates the red pile.

---

## Platform

### D-22 · Calendar access denied → full task-manager mode
**Status:** Proposed
**Decision:** If EventKit access is denied or restricted, everything except calendar events still works: capture, Now, Today, blocks on an empty timeline, notifications. Settings shows the access state and a button to open System Settings.

### D-24 · Phase 7 priority is decided by measured presence
**Status:** Proposed
**Decision:** Log presence intervals (`active | idle >5 min | locked | asleep`) from wake/sleep, lock/unlock, and idle-time checks. Log every planned notification's fire time. After 2–3 weeks of Phase 4a, compute **% of notifications due while away from the Mac**. A high share moves Phase 7 up.
**Caveat:** the screen lock/unlock notifications are undocumented distributed notifications, and idle-time APIs must be verified inside the sandbox.
**Why:** The Mac-only build is a weak test if failures happen away from the desk. This turns "move iOS up?" into a number.
**Known cost:** an iPhone app without sync is an island, so iOS earlier means CloudKit and the paid program earlier.

### D-25 · Menu-bar countdown is a Phase 0 spike
**Status:** Proposed
**Decision:** Before Phase 2, prototype a live-updating menu bar label. Try `MenuBarExtra` (`.window` style) with a minute-resolution label first; fall back to AppKit `NSStatusItem` if the label doesn't update reliably. Minutes in the bar; seconds only in the popover/timer. Same spike: the capture `NSPanel` with `.nonactivatingPanel`, `.floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, and a subclass overriding `canBecomeKey` so it accepts typing over full-screen apps.

---

## Scope

### D-26 · Not in v1
**Status:** Proposed
**Decision:** Explicitly out until data says otherwise: reward pairing, novelty/quest themes, wind-down reminders, body doubling / focus rooms, accountability partners, Apple Calendar mirror (D-23), streaks of any kind, iOS/Watch (Phase 7), CloudKit sync (Phase 7).
**In v1 despite being small:** hyperfocus check-in (D-14), completion feedback (D-21), routines (D-20).

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
| `nowLookaheadMinutes` | 60 | D-08 |
| `checkInMultiplier` | 1.5 | D-14 |
| `checkInNoEstimateMinutes` | 45 | D-14 |
| `checkInGraceMinutes` | 45 | D-14 |
| `comebackGapDays` | 3 | D-18 |
| `somedayAfterDays` | 30 | D-15 |
| `estimatorMinSamples` | 5 | Estimator |
| `estimatorWindow` | 20 sessions | Estimator |
| `estimatorClamp` | 0.5–3.0 | Estimator |
| `idleThresholdMinutes` | 5 | D-24 |
| `calendarModes` | per D-09 | D-09 |
| `energyWindows` | none | Phase 6 |
