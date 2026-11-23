# ExecFn — Architecture & Build Plan (v2)

Native macOS task, planning, and calendar app for people with ADHD / executive-function difficulties.
Single user for now; built so it can go public after testing.

- **Research basis:** `Research.md` (repo root). ADHD and executive-function pain points → features.
- **Decisions:** `DECISIONS.md`. Every behavior rule is referenced here by ID (D-xx). Code follows only Accepted decisions.

**Changes from v1:**
- Domain/persistence split
- Local-only activity log
- Carried-over row instead of silent rollover
- Rollover and the Today cap moved into Phase 2
- Phase 4 split into 4a/4b
- Calendar mirror cut
- Routines added
- If-then cues
- Presence logging to decide Phase 7
- Phase 0 spike
- Explicit not-in-v1 list

---

## 0. Assumptions

| # | Assumption | Notes |
|---|------------|-------|
| A-1 | iPhone (and maybe Watch) exist; iOS ships in Phase 7 | **Mac-only until Phase 7 is a weak test if failures happen away from the desk.** Presence logging (D-24) measures this; the result decides whether Phase 7 moves up. |
| A-2 | Standalone app; core and persistence are local Swift packages | Packages drop into a larger app unchanged (Q-3). |
| A-3 | Paid Apple Developer Program not needed before Phase 7 | Needed for iCloud/CloudKit and distribution. |
| A-4 | Calendar access may be denied | App must still work fully as a task manager (D-22). |

---

## 1. Design principles (from the research)

1. **Point of performance.** Help appears when and where the task happens → menu bar, hotkey, notifications, widgets.
2. **Externalize time.** Countdowns, a "now" line, estimate-vs-actual learning.
3. **One thing at a time.** The default view is one task (D-08). Today is capped (D-07). Backlog is hidden.
4. **Shrink the start.** First physical step, micro-steps, "just 5 minutes".
5. **Forgive, never punish.** No overdue state, no streaks, no red counts. Coming back is painless (D-06, D-15, D-18).
6. **Respect attention.** One budgeted notification planner; notifications are actionable, escalate, and rotate their wording.
7. **Near-zero upkeep.** Only a title is required. Rollover is automatic but visible. No mandatory rituals.
8. **Negotiate, don't enforce.** The app proposes; the user decides. Nothing is rewritten silently.
9. **Measure n=1.** Log interactions and presence so priorities come from data.

---

## 2. Stack

| Layer | Choice | Notes |
|-------|--------|-------|
| Language / UI | Swift 6 (strict concurrency), SwiftUI + thin AppKit bridges | Multiplatform Xcode project; macOS target now, iOS later |
| Min OS | macOS 26 (Tahoe) | Required for Foundation Models. Current release: macOS 27. |
| Domain | `EFCore` package: structs/enums only, `Sendable` | D-01 |
| Persistence | `EFPersistence` package: SwiftData `@Model` + mappers + repository | D-01 |
| Stores | **Main store** (synced later) + **Activity store** (local-only, `cloudKitDatabase: .none`) | Both in the App Group container (D-02) |
| Settings | `PlannerSettings` (`Codable`) in App Group `UserDefaults` | D-04 |
| Calendars | EventKit, read live; events never copied into SwiftData | Full access required to read |
| Notifications | UserNotifications | Actionable categories; time-sensitive level for transitions |
| AI | Foundation Models (on-device) behind `IntelligenceService` | Phase 6; manual fallback always |
| System surfaces | Menu bar item, NSPanel capture, WidgetKit, App Intents, Focus filters, Controls | §5 |
| Hotkey | [`sindresorhus/KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) | Only third-party dependency |
| Launch at login | `SMAppService.mainApp` | |
| Tests | Swift Testing (`@Test`) | `EFCore` is pure → unit-tested without SwiftData |
| Sync (Phase 7) | SwiftData + CloudKit (main store only) | Schema is CloudKit-compatible from day one |

---

## 3. Repository layout

```
ExecFn/
├─ ARCHITECTURE.md
├─ DECISIONS.md
├─ Research.md
├─ Packages/
│  ├─ EFCore/                        # pure domain — imports Foundation only
│  │  ├─ Sources/EFCore/
│  │  │  ├─ Domain/                  # TaskSnapshot, BlockSnapshot, SessionSnapshot, RoutineTemplate,
│  │  │  │                           # DayPlanSnapshot, EventSnapshot, EventAnnotation, IfThenPlan, PlanDay
│  │  │  ├─ Settings/                # PlannerSettings (+ defaults)
│  │  │  ├─ Time/                    # Clock protocol, DayBoundary, PlanDay math
│  │  │  ├─ Rollover/                # D-05, D-06, D-20 instance spawn/expiry
│  │  │  ├─ Now/                     # D-08 selection
│  │  │  ├─ Today/                   # D-07 cap, D-16 energy mapping
│  │  │  ├─ Calendar/                # free slots, D-09/D-10 busy rules, D-11 proposals, D-12 missed blocks
│  │  │  ├─ Sessions/                # D-14 check-ins, auto-end
│  │  │  ├─ Recovery/                # D-15 fresh start + undo snapshot, D-18 comeback detection
│  │  │  ├─ Estimator/               # multiplier from clean sessions
│  │  │  ├─ Notifications/           # NotificationPlanner (pure)
│  │  │  └─ Metrics/                 # Review metrics from activity events
│  │  └─ Tests/EFCoreTests/
│  └─ EFPersistence/                 # SwiftData — no UI
│     ├─ Sources/EFPersistence/
│     │  ├─ Models/                  # @Model classes + VersionedSchema + MigrationPlan
│     │  ├─ ActivityStore/           # local-only container, writer, CSV/JSONL export
│     │  ├─ Mapping/                 # @Model ⇄ snapshot
│     │  └─ Repository/              # commands: load snapshots → EFCore → apply changes
│     └─ Tests/EFPersistenceTests/
├─ ExecFn/                           # macOS app target
│  ├─ App/                           # @main, scenes, AppState, dependency container
│  ├─ Services/
│  │  ├─ CalendarService.swift       # EventKit → EventSnapshot; change debounce
│  │  ├─ NotificationService.swift   # applies planner diff; routes actions
│  │  ├─ PresenceService.swift       # wake/sleep, lock/unlock, idle → activity log (D-24)
│  │  ├─ CueService.swift            # wake / focus / event-end cues (D-19)
│  │  ├─ IntelligenceService.swift   # Foundation Models (Phase 6)
│  │  └─ HotkeyService.swift
│  ├─ Features/
│  │  ├─ Now/                        # Now + Next, Start, pin
│  │  ├─ Today/                      # musts, "From yesterday" row, energy check-in
│  │  ├─ Inbox/                      # derived list (D-03)
│  │  ├─ Buckets/
│  │  ├─ Routines/
│  │  ├─ Calendar/                   # Day (Phase 1–3), Week & Month (Phase 4b)
│  │  ├─ Capture/                    # NSPanel quick capture
│  │  ├─ MenuBar/                    # MenuBarExtra or NSStatusItem (decided by Phase 0 spike)
│  │  ├─ FocusTimer/                 # floating timer + check-ins
│  │  ├─ Recovery/                   # Fresh start, Welcome back
│  │  ├─ Review/                     # weekly review + metrics
│  │  └─ Settings/
│  ├─ Copy/Localizable.xcstrings     # ALL user-facing text (tone review)
│  ├─ ExecFn.entitlements
│  └─ Info.plist
├─ ExecFnWidgets/                    # Phase 5
└─ Spikes/MenuBarCountdown/          # Phase 0, throwaway
```

**Dependency rule:** `EFCore` ← `EFPersistence` ← App/Extensions. `EFCore` never imports SwiftUI, SwiftData, EventKit, UserNotifications, or FoundationModels.

---

## 4. Data

### 4.1 Domain types (`EFCore`)

```swift
import Foundation

public struct PlanDay: Hashable, Comparable, Codable, Sendable {   // calendar day under DayBoundary
    public let year: Int, month: Int, day: Int
    public static func < (a: Self, b: Self) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }
}

public enum TaskStatus: String, Codable, Sendable { case open, done, dropped }          // D-03
public enum DropReason: String, Codable, Sendable { case user, routineExpired }          // D-20
public enum TaskEnergy: String, Codable, Sendable { case low, high }                     // D-16
public enum DayEnergy:  String, Codable, Sendable { case low, normal, high }             // D-16
public enum DayMode:    String, Codable, Sendable { case ideal, minimum, pause }

public struct EventRef: Hashable, Codable, Sendable {                // D-17: stable-ish key
    public var externalID: String          // calendarItemExternalIdentifier
    public var occurrenceStart: Date       // disambiguates recurring occurrences
}

public enum Cue: Hashable, Codable, Sendable {                        // D-19
    case atTime(Date)
    case afterEvent(EventRef)
    case onMacWake
    case focusChanged(String)
}

public struct IfThenPlan: Hashable, Codable, Sendable {
    public var text: String                // the plan itself (evidence-based part)
    public var cue: Cue?                   // optional external nudge
}

public struct TaskSnapshot: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String               // ONLY required input
    public var firstStep: String?
    public var notes: String?
    public var bucketID: UUID?
    public var status: TaskStatus
    public var dropReason: DropReason?
    public var estimateMinutes: Int?
    public var energy: TaskEnergy?
    public var dueDate: Date?
    public var ifThen: IfThenPlan?
    public var isTodayMust: Bool
    public var todayOrder: Int?
    public var isMinimum: Bool             // shows on minimum days
    public var isSomeday: Bool             // D-15
    public var carriedFrom: PlanDay?       // D-06
    public var rolloverCount: Int          // internal only
    public var routineID: UUID?            // D-20
    public var routineDay: PlanDay?
    public var createdAt: Date
    public var completedAt: Date?
    public var lastTouchedAt: Date
}

public enum BlockResolution: String, Codable, Sendable { case rescheduled, unscheduled, didIt }   // D-12
public struct BlockSnapshot: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var taskID: UUID
    public var start: Date
    public var end: Date
    public var resolution: BlockResolution?
}

public enum SessionKind: String, Codable, Sendable { case timed, unverified }           // D-12
public enum SessionEnd:  String, Codable, Sendable { case user, autoEnded, appQuit }     // D-14
public struct SessionSnapshot: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var taskID: UUID
    public var start: Date
    public var end: Date?
    public var kind: SessionKind
    public var endedBy: SessionEnd?
    public var isEstimatorEligible: Bool { kind == .timed && endedBy == .user && end != nil }
}

public enum RoutineSchedule: Hashable, Codable, Sendable {             // D-20
    case daily, weekdays
    case weekly(Set<Int>)                  // 1 = Sunday … 7 = Saturday (Calendar.weekday)
    case everyNDays(Int, anchor: PlanDay)
}
public struct RoutineTemplate: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var schedule: RoutineSchedule
    public var timeOfDayMinutes: Int?      // minutes after midnight
    public var estimateMinutes: Int?
    public var checklist: [String]
    public var bucketID: UUID?
    public var energy: TaskEnergy?
    public var isActive: Bool
}

public struct DayPlanSnapshot: Hashable, Sendable {
    public var day: PlanDay
    public var mode: DayMode
    public var energy: DayEnergy?
}

public enum EventAvailability: String, Sendable { case busy, free, tentative, unavailable, notSupported }
public struct EventSnapshot: Hashable, Sendable {                      // built by CalendarService
    public var ref: EventRef
    public var calendarID: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var availability: EventAvailability
    public var hasLocation: Bool
}

public struct EventAnnotation: Hashable, Codable, Sendable {           // D-17
    public var ref: EventRef
    public var travelMinutes: Int?
    public var transitionAlerts: Bool
}
```

**Derived, never stored:** Inbox membership (D-03), Today list, Now/Next (D-08), free slots, missed blocks, estimator multiplier, metrics.

**Not stored at all:** calendar events (read live from EventKit).

### 4.2 Persistence (`EFPersistence`)

- `@Model` classes mirror the snapshots (`TaskModel`, `BlockModel`, `SessionModel`, `SubtaskModel`, `BucketModel`, `RoutineModel`, `DayPlanModel`, `EventAnnotationModel`), with relationships where useful.
- **CloudKit rules (main store, from v1 of the schema):** every property optional or defaulted; no `@Attribute(.unique)`; all relationships optional; `VersionedSchema` + `SchemaMigrationPlan`; the app owns migrations, and extensions only read.
- **Activity store:** separate `ModelContainer`, `cloudKitDatabase: .none`. `ActivityEventModel { at, kind, taskID?, payload: Data? }`. Export to CSV/JSONL.

### 4.3 Activity events

```
taskCreated(source: hotkey|app|intent|widget), taskEdited, taskCompleted, taskDropped(reason),
mustSet, mustCleared, carriedTriaged(action), rolloverRan(from, to, carried, expiredRoutines),
sessionStarted, sessionEnded(endedBy), checkInShown, checkInAnswered(yes|done|none),
blockCreated(source: tapGap|drag|proposal), blockResolved(resolution),
notificationPlanned(category, fireDate), notificationActed(category, action),
cueFired(kind), freshStart(snapshot), freshStartUndone, comebackShown(gapDays),
dayModeSet(mode), energyCheckIn(level), presence(state: active|idle|locked|asleep)
```

### 4.4 Data-quality rules

| Issue | Rule |
|-------|------|
| Runaway sessions | D-14 check-in → `autoEnded`, excluded from estimator |
| Untimed work | "I did it" → `unverified` session, excluded from estimator (D-12) |
| Estimator sample size | No multiplier until ≥ `estimatorMinSamples` eligible sessions in the bucket |
| Day boundary | All "today" logic uses `DayBoundary` + injected `Clock`; never `Calendar.startOfDay` |
| Rollover gaps | Idempotent, keyed by `lastRolloverDay` = latest `DayPlanModel.rolledOverAt`, saved in the same `save()` as the rollover changes (D-05) |
| Settings compatibility | `PlannerSettings` decodes field-by-field with defaults; adding a field never discards saved settings (D-04) |
| App state vs settings | Pin (D-08) on its own UserDefaults key; rollover marker in the main store (D-05); neither in `PlannerSettings` |
| Event identity | Annotations keyed by external ID + occurrence start, not `eventIdentifier` (D-17) |
| Calendar identity | Calendar modes keyed by `calendarIdentifier` with title fallback (D-09) |
| Presence signals | Lock/unlock notifications are undocumented; idle API to be verified in the sandbox (D-24) |

---

## 5. Research → macOS surfaces

| Research problem | Surface | Implementation |
|------------------|---------|----------------|
| Out of sight, out of mind | **Menu bar item**: current task + time | Phase 0 spike decides `MenuBarExtra(.window)` vs `NSStatusItem` (D-25). Minute resolution in the bar. A session counts down to the check-in; otherwise the bar counts down to the next event (D-25). |
| Frictionless capture | **Global hotkey → floating panel** | `NSPanel` subclass: `.nonactivatingPanel`, `.floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, `canBecomeKey = true`. Title only; Enter → Inbox. |
| Time blindness | **Floating focus timer**, now line, countdowns | `TimelineView`; seconds only in the timer/popover |
| Hyperfocus | **Check-ins** during sessions | D-14 |
| Transitions | **Escalating time-sensitive notifications** | Per-event opt-in via `EventAnnotation.transitionAlerts` |
| Cue → action | **If-then cues** | `CueService`: wake/unlock, Focus change, event end → planner (D-19) |
| Routines | **Daily instances + optional time cue** | D-20 |
| Notification fatigue | **Actionable, budgeted notifications** | Start · +10 min · Reschedule; only `NotificationService` talks to `UNUserNotificationCenter` |
| Context | **Focus filters** | `SetFocusFilterIntent`: Focus → bucket filter (Phase 5) |
| Not opening the app | **Widgets**, launch at login | Phase 5 |
| Hands-free | **App Intents** | Add task, What's next, Start 5 minutes (Phase 5) |
| Reward | **Completion feedback** | D-21 |

---

## 6. Core logic (`EFCore`)

All functions are pure: `(snapshots, settings, clock) → result or [Change]`. The repository applies changes.

### 6.1 Rollover (D-05, D-06, D-20)
Runs on launch, wake, the boundary timer, and time-zone/clock changes; no-op if `lastRolloverDay == today`. From `previousActiveDay` → `today`, in order:
1. Open routine instances with `routineDay < today` → `dropped(.routineExpired)`.
2. Tasks with `carriedFrom != nil` (untouched carried items) → `carriedFrom = nil`.
3. Open tasks with `isTodayMust` → `isTodayMust = false`, `carriedFrom = previousActiveDay`, `rolloverCount += (previousMode == .pause ? 0 : 1)` (no pause days before Phase 4a).
4. Spawn today's routine instances from active templates.
5. Clear the pin (D-08).
6. Mark today's `DayPlanModel.rolledOverAt` — same `save()` as steps 1–4.
7. Emit `rolloverRan` with counts.

The pure function returns `[Change]` plus `clearPin: Bool`; the repository applies the changes and the marker in one save, then the app clears the pin key. Afterwards the boundary timer is re-armed for the next `dayBoundaryHour`.

### 6.2 Today & Now
- **Today** = musts (ordered) + today's routine instances + today's blocks + the "From yesterday" row. Cap from settings, adjusted by day energy (D-16) and mode (`minimum` → `isMinimum` tasks only).
- **Inbox** = D-03 rule, which excludes carried tasks (`carriedFrom != nil`).
- **Now/Next** = D-08 rule, with `pinnedTaskID` passed in as an input.

### 6.3 Calendar logic
- **Busy intervals** = Busy-mode calendars, D-10 availability rule, all-day exclusion, plus `defaultBufferMinutes` / per-event travel around each (D-17).
- **Free slots** = 5:00–21:00 minus busy intervals (buffer and travel included) minus unresolved blocks; snapped to `proposalSnapMinutes`. Dragging may leave the window (D-11).
- **Tap-a-gap proposal** (D-11): gap + task → ghost block sized to the estimate, or 30 min, snapped to 15 and clipped to the gap. Saved only when accepted.
- **Back-planning** (Phase 6): due date + estimate → proposed blocks in free slots, preferring energy windows. Proposals only.
- **Missed blocks** (D-12): `end < now ∧ task.open ∧ no overlapping session ∧ resolution == nil`.

### 6.4 Sessions (D-14)
- `nextCheckIn = start + (estimate × checkInMultiplier ?? checkInNoEstimateMinutes)`.
- "Just 5 minutes" (D-27): first check-in at `start + fiveMinuteStartMinutes`; "Keep going" → D-14 schedule from then.
- Unanswered for `checkInGraceMinutes` → end at check-in time, `autoEnded`.
- Evaluated from timestamps on launch and wake as well as by timer, so sleep can't leave a session running.
- Menu bar text is a pure function of (session, task, next check-in, next event, now) → label (D-25).

### 6.5 Recovery
- **Fresh start** (D-15): returns changes + an undo snapshot; undo valid for 24 h.
- **Comeback** (D-18): `now − lastActivity ≥ comebackGapDays` → show Welcome back once.

### 6.6 Estimator
Per bucket (fallback global): `median(actual / estimate)` over the last `estimatorWindow` eligible sessions, clamped, applied only when n ≥ `estimatorMinSamples`. Surfaced as a suggestion.

### 6.7 NotificationPlanner
- **Input:** events, annotations, blocks, tasks, routines, cues, `DayPlan`, settings, now, current pending set.
- **Output:** planned notifications + diff (add/remove).
- **Priority:** transition alerts > block starts > routine times > if-then cues > due-soon > nudges.
- **Budget:** `notificationBudget` per plan day; low day energy (D-16) or `minimum` mode → essentials only (transitions + routine times).
- **Escalation** for annotated events: T−15 heads-up → T−5 wrap up → T−0 go; "leave by" = start − travel − buffer.
- **Ignored notification:** one follow-up after 10 min, then stop.
- **Quiet hours** respected; copy rotates per category.
- **Pending set:** keep well under the system limit (iOS caps at 64; assume the same on macOS).
- **Logging:** every planned fire time is logged (`notificationPlanned`) for the presence join (D-24).

### 6.8 Metrics (Review screen)
Estimate error (median, trend) · carried-over rate · triage action mix · notification action rate per category · **% notifications due while away** (D-24) · capture → done latency · active days / month · feature usage (hotkey captures, 5-min starts, check-in answers, routine completion rate).

---

## 7. Services

| Service | Responsibilities | Gotchas |
|---------|------------------|---------|
| `CalendarService` | Full-access request; calendars list; events for visible range → `EventSnapshot`; observe `.EKEventStoreChanged` (debounce ~500 ms, refetch visible range) | Read requires full access; sandbox entitlement + `NSCalendarsFullAccessUsageDescription`; never write in the change handler; denied → D-22 |
| `NotificationService` | Register categories/actions; apply planner diff; route actions → repository + activity log. **Phase 2:** check-in category only (D-14), scheduled straight from the session's next check-in | Time-sensitive needs its entitlement; the user can revoke it |
| `PresenceService` | `NSWorkspace` will-sleep/did-wake, screen lock/unlock (distributed notifications, undocumented), idle via `CGEventSource.secondsSinceLastEventType` | Verify the idle API in the sandbox; log transitions only |
| `CueService` | Detect wake/unlock, Focus changes, event ends → fire if-then cues through the planner budget | Debounce wake (multiple notifications per wake) |
| `IntelligenceService` | `breakdown`, `parseCapture`, `suggestEstimate` via Foundation Models `@Generable` | Check availability; narrow prompts; manual fallback (Phase 6) |
| `HotkeyService` | Register/rebind capture shortcut | Default may conflict with launchers |

---

## 8. Guardrails enforced in code

- [ ] `title` is the only required input.
- [ ] No overdue status; no red badges; no missed counts anywhere in the UI.
- [ ] Rollover never hides work silently: carried tasks are visible for one day with triage (D-06).
- [ ] Routine instances expire; they never accumulate (D-20).
- [ ] Today cap is a suggestion with an override (D-07).
- [ ] Only `NotificationService` calls `UNUserNotificationCenter`; it only applies `NotificationPlanner` output.
- [ ] The `CalendarService` change handler never writes to EventKit.
- [ ] Planner proposals never auto-apply.
- [ ] All user-facing strings live in `Localizable.xcstrings`. Banned words: failed, missed, behind, overdue, should.
- [ ] Every user action and presence transition writes an activity event.

---

## 9. Build order

**Use it daily from the end of Phase 2.** Reorder later phases based on the Review metrics.

### Phase 0 — Spike (≤ 1 day, throwaway; first day of Phase 2)
Not run before Phase 1. It runs on Phase 2's first day; the menu bar and presence logger are not designed until its results are in D-25.
- Menu bar label that updates every minute: `MenuBarExtra(.window)` first, `NSStatusItem` fallback (D-25).
- Capture `NSPanel` over a full-screen app via global hotkey; accepts typing without activating the app.
- Idle-time and lock/unlock signals readable from a sandboxed app (D-24).
- **Done when:** all three work, or the fallback is chosen and noted in `DECISIONS.md`.

### Phase 1 — Skeleton
- Xcode project (macOS target), `EFCore` + `EFPersistence` packages, App Group, entitlements.
- Domain types, `PlannerSettings`, `Clock`, `DayBoundary`, `PlanDay`.
- Main store (`VersionedSchema` v1) + local-only activity store + export.
- `CalendarService` with full-access flow, **denied-access mode** (D-22), **calendar modes** (D-09), **all-day/availability rule** (D-10).
- Day view: events (all-day strip + timed), now line.
- Verify whether EventKit exposes travel time (D-17).
- **Done when:** today's events render with correct busy/visible/hidden behavior; the app is usable with access denied; `EFCore` tests are green.

### Phase 2 — Capture, Now, and a day that survives *(start daily use)*
Order: Phase 0 spike → foundations → `EFCore` logic + tests → UI.
- **Foundations:** tolerant `PlannerSettings` decoding (D-04); repository on `mainContext` (D-01); schema v2 with `DayPlanModel.rolledOverAt` (D-05).
- **Pure logic first, tested before any window:** rollover, Inbox, Today cap, Now/Next with pin, session check-ins (incl. 5 min), menu bar label.
- Hotkey capture panel → Inbox (derived, D-03). Fixed ⌃⌥Space via Carbon `RegisterEventHotKey` (proven in the Phase 0 spike, no dependency). `KeyboardShortcuts` comes in when rebinding is needed; `HotkeyService` hides the swap.
- Today: musts with cap (D-07); Now/Next with pin (D-08); first-step field; Start / **Just 5 minutes** (D-27) → focus timer → session.
- **Rollover with "From yesterday" row** (D-05, D-06), boundary timer.
- Check-ins / auto-end (D-14) via the minimal `NotificationService`. Completion feedback (D-21).
- Menu bar item per D-25.
- Launch at login. Activity log + presence logging wired (sleep/wake only if the spike says so).
- **Done when:** a full week of use produces no stale Today and no Inbox you avoid.

### Phase 3 — Buckets, scheduling, routines
- Buckets (optional at capture).
- Tap-a-gap proposals + Day-column drag/resize (D-11); overlap rendering (D-13).
- Missed-block prompt (D-12). Manual subtasks.
- Routines: templates + daily instances + expiry (D-20), no time cues yet.
- Fresh start + undo (D-15). Someday view.
- **Done when:** a day is planned by tapping gaps or dragging, and routines show up daily without piling up.

### Phase 4a — Planner & notifications
- `NotificationPlanner` + actionable categories + budget + escalation + follow-up.
- Event annotations: travel, transition alerts (D-17).
- Routine time cues; if-then cue binding (D-19) via `CueService`.
- Day modes (ideal/minimum/pause) + energy check-in mapping (D-16).
- Welcome back screen (D-18).
- **Done when:** a week runs with timely, non-duplicated, budgeted notifications; the presence metric starts accumulating.

### Phase 4b — Week & Month views
- Week: 7 columns reusing the Day column, read-only + tap-a-gap → then cross-day drag.
- Month: density + tap → Day.
- **Done when:** next week can be planned from the Week view.

### Phase 5 — System surfaces
- Widgets (Now/Next, Today) with interactive Done/Start.
- App Intents: Add task, What's next, Start 5 minutes → Siri / Shortcuts / Spotlight.
- Focus filters ↔ buckets. Capture Control.
- **Done when:** the main window is needed only for planning.

### Phase 6 — Intelligence & learning
- `IntelligenceService`: AI breakdown (accept/edit), natural-language capture, estimate suggestions.
- Estimator multiplier in proposals; energy windows; back-planning; scored pick-for-me (replaces D-08 step 6).
- Weekly Review with metrics (§6.8).
- **Done when:** proposals use your own data and estimate error trends down.

### Phase 7 — iOS, Live Activity, sync
- **Trigger:** move this earlier if "% notifications due while away" is high after 2–3 weeks of Phase 4a (D-24).
- iOS target reusing both packages; Live Activity for the active task (appears on Lock Screen, Dynamic Island, and the Mac menu bar via iPhone); Watch complication.
- SwiftData + CloudKit for the main store only; the activity store stays per device.
- **Done when:** capture on phone → Mac; the active task is visible on the phone's Lock Screen.

### Not in v1
See D-26: reward pairing, themes, wind-down reminders, body doubling, accountability partners, Apple Calendar mirror (D-23), streaks.

---

## 10. Risks

| Risk | Mitigation |
|------|------------|
| Menu bar label doesn't update | Phase 0 spike; `NSStatusItem` fallback |
| New settings field wipes saved settings | Tolerant decoder + Phase 1 JSON test (D-04) |
| Check-in unseen during hyperfocus → real work auto-ended | Check-in notification from Phase 2 (D-14) |
| Week view drag-and-drop effort | Split into 4b; tap-a-gap first; reuse the Day column |
| Mapping boilerplate (D-01) | Generate mappers per model; tests per mapper |
| EventKit change storms | Debounce; refetch the visible range only; never write in the handler |
| Event/calendar identifier churn | External ID + occurrence keys; title fallback for calendars |
| Time edge cases (DST, sleep, 4 AM boundary, long absences) | Injected `Clock`; idempotent rollover; dedicated tests |
| Presence signals undocumented / sandboxed | Phase 0 verification; degrade to sleep/wake only |
| Notification duplicates / over-budget | Single service, planner diff, no calendar mirror |
| On-device model quality | Narrow prompts, guided generation, manual path |
| CloudKit schema lock-in | CloudKit rules from v1; activity store excluded from sync |
| Scope creep / abandonment | Daily use from Phase 2; metrics decide priorities; D-26 cut list |

---

## 11. Info.plist & entitlements

- `NSCalendarsFullAccessUsageDescription`: "Shows your calendar alongside your tasks so you can plan around real commitments."
- Entitlements:
  - App Sandbox
  - `com.apple.security.personal-information.calendars`
  - App Groups (main store, activity store, settings; set via Signing & Capabilities, since the macOS group ID format differs from iOS)
  - Time Sensitive Notifications
  - iCloud / CloudKit (Phase 7)
- `LSUIElement`: **NO**. Keep the Dock icon; the menu bar item is additive.

---

## 12. Testing

**`EFCore` unit tests** (fixed `Clock`), including:
- Rollover: 3:59 vs 4:01 AM; DST forward/back; sleep across the boundary; a 9-day absence runs once; pause-day no increment; carried items clear after one day; routine instances expire and never carry; pin cleared
- Inbox: carried tasks excluded until `carriedFrom` clears
- Now rule: each precedence step; pin outranked by a running session; stale pin ignored; ties; empty state
- Menu bar label: each D-25 state; a running session counts down to the check-in, and past the check-in the label reads "check-in"
- Calendar: all-day + availability matrix; Busy/Visible/Hidden; buffers/travel; proposal clipping; missed-block detection incl. unverified sessions
- Sessions: check-in with and without an estimate; 5-minute start; auto-end timing; sleep past the grace period; estimator eligibility
- Settings: Phase 1 JSON (no new fields) decodes with calendar modes intact
- Fresh start + undo round-trip; comeback threshold
- Notifications: budget exhaustion by priority; minimum/low-energy filtering; quiet hours; escalation times; follow-up once; diff correctness
- Energy mapping; Today cap override

**`EFPersistence` tests:** mapper round-trips; migration v1 → v2 smoke test; activity store isolation (no CloudKit); rollover changes and marker land in one save.

**Manual checklist per phase:** permission flows (granted / denied / revoked), full-screen capture, sleep/wake behavior.

**Dogfooding:** weekly 5-minute Review. Change or cut any feature whose usage or effect stays flat for 3 weeks.
