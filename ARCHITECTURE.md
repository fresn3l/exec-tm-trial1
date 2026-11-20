# ExecFn — Architecture & Build Plan

Native macOS task, planning, and calendar app for people with ADHD / executive-function difficulties.
Single user for now; built so it can go public after testing.

> Research basis: `docs/RESEARCH.md` (ADHD & executive function pain points → features). Every design rule below traces back to it.

---

## 0. Assumptions & open decisions

| # | Decision | Assumed for now | Impact if different |
|---|----------|-----------------|---------------------|
| 1 | iPhone / Apple Watch available? | Yes, iOS ships in Phase 7 | If iOS matters sooner, move Phase 7 up. iPhone is the only path to Live Activities (Mac apps can't show them; macOS shows the iPhone's Live Activities in the menu bar). |
| 2 | Standalone app or module of a larger life app? | Standalone, but core logic lives in a local Swift package (`EFCore`) | If it becomes a module, `EFCore` drops into the larger app unchanged. |
| 3 | Swift / SwiftUI experience | Unknown | Affects pacing only. |
| 4 | Apple Developer Program (paid) | Not required until Phase 7 | Needed for iCloud/CloudKit sync and public distribution. |

---

## 1. Design principles (from the research)

1. **Point of performance.** Help appears when and where the task happens. The user must not have to remember to open the app → menu bar, hotkey, notifications, widgets.
2. **Externalize time.** Countdowns, a "now" line, estimate-vs-actual learning. Never rely on an internal clock.
3. **One thing at a time.** The default view is one task. Backlog hidden. Today capped.
4. **Shrink the start.** First physical step, micro-step breakdown, "just 5 minutes".
5. **Forgive, never punish.** No overdue state, no breakable streaks, no red counts. Coming back after a bad week is painless.
6. **Respect attention.** All notifications go through one budgeted planner, are actionable, escalate, and vary their wording.
7. **Near-zero upkeep.** Only a title is required. Rollover is automatic. No mandatory daily planning ritual.
8. **Negotiate, don't enforce.** The app proposes; the user confirms. It never silently rewrites the plan.
9. **Measure n=1.** Log every interaction, so features are judged on real data, not vibes.

---

## 2. Stack

| Layer | Choice | Notes |
|-------|--------|-------|
| Language / UI | Swift 6, SwiftUI (+ thin AppKit bridges) | Multiplatform Xcode project: macOS target now, iOS later |
| Min OS | macOS 26 (Tahoe) | Required for the Foundation Models framework. Current release is macOS 27. |
| Persistence | SwiftData | Store in an App Group container, shared by app, widgets, and intents |
| Calendars | EventKit | Read live. Never copy events into SwiftData. |
| Notifications | UserNotifications | Categories with actions; time-sensitive interruption level for transitions |
| AI | Foundation Models (on-device) | Behind a protocol. On-device, free, offline. Swappable for bigger models later. |
| System surfaces | MenuBarExtra, WidgetKit, App Intents, Focus filters, Controls | See §5 |
| Hotkey | [`sindresorhus/KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) | Sandbox-safe global shortcut |
| Launch at login | `SMAppService.mainApp` | |
| Tests | Swift Testing (`@Test`) | Core logic is pure functions → fully unit-testable |
| Sync (later) | SwiftData + CloudKit | Deferred. The schema is CloudKit-compatible from day one (§4.3). |

**Third-party dependencies:** one (KeyboardShortcuts). Everything else is first-party.

---

## 3. Repository layout

```
ExecFn/
├─ ARCHITECTURE.md
├─ docs/
│  └─ RESEARCH.md
├─ Packages/
│  └─ EFCore/                      # local Swift package — NO UI, NO system frameworks except Foundation/SwiftData
│     ├─ Package.swift
│     ├─ Sources/EFCore/
│     │  ├─ Models/                # @Model types + VersionedSchema
│     │  ├─ Planner/               # today cap, rollover, back-planning, pick-for-me
│     │  ├─ Estimator/             # estimate vs actual → personal multiplier
│     │  ├─ NotificationPlanner/   # budgeted, escalating schedule (pure function)
│     │  ├─ ActivityLog/           # append-only event logging + metrics queries
│     │  └─ Support/               # Clock protocol, DayBoundary, ID types
│     └─ Tests/EFCoreTests/
├─ ExecFn/                         # macOS app target
│  ├─ App/                         # @main, scenes, AppState, dependency container
│  ├─ Services/                    # protocol + live implementation per system framework
│  │  ├─ CalendarService.swift     # EventKit
│  │  ├─ NotificationService.swift # UserNotifications
│  │  ├─ IntelligenceService.swift # Foundation Models
│  │  └─ HotkeyService.swift       # KeyboardShortcuts
│  ├─ Features/
│  │  ├─ Now/                      # one task + next, start button, timer
│  │  ├─ Inbox/
│  │  ├─ Buckets/
│  │  ├─ Calendar/                 # Day, Week, Month, unscheduled sidebar
│  │  ├─ Capture/                  # floating NSPanel quick-capture
│  │  ├─ MenuBar/                  # MenuBarExtra (.window style)
│  │  ├─ FocusTimer/               # floating always-on-top mini timer
│  │  ├─ DayPlan/                  # ideal / minimum / pause, energy check-in
│  │  ├─ Review/                   # weekly review + personal metrics
│  │  └─ Settings/
│  ├─ Copy/
│  │  └─ Localizable.xcstrings     # ALL user-facing text in one place (tone review)
│  ├─ ExecFn.entitlements
│  └─ Info.plist
├─ ExecFnWidgets/                  # WidgetKit extension (Now/Next, Today) + Controls
└─ ExecFnIntents/                  # App Intents (if split from the app target)
```

**Rule:** `EFCore` never imports SwiftUI, EventKit, UserNotifications, or FoundationModels. Services adapt those frameworks to plain `EFCore` types. That keeps the core testable and portable to iOS.

---

## 4. Data model

### 4.1 Entities (SwiftData)

```swift
// Sketch — field-level intent, not final code.

@Model final class TaskItem {
    var id: UUID = UUID()
    var title: String = ""                 // ONLY required user input
    var firstStep: String?                 // "first physical step"
    var notes: String?
    var bucket: Bucket?
    var status: TaskStatus = .inbox        // inbox | active | done | dropped  (NO overdue)
    var estimateMinutes: Int?
    var energy: Energy?                    // low | high
    var dueDate: Date?
    var ifThenTrigger: String?             // "When ___, I will ___"
    var isTodayMust: Bool = false
    var createdAt: Date = Date()
    var completedAt: Date?
    var rolloverCount: Int = 0             // internal only — drives resurfacing, never shown as a count
    @Relationship(deleteRule: .cascade) var subtasks: [Subtask]? = []
    @Relationship(deleteRule: .cascade) var blocks: [TimeBlock]? = []
    @Relationship(deleteRule: .cascade) var sessions: [WorkSession]? = []
}

@Model final class Subtask {
    var id: UUID = UUID()
    var title: String = ""
    var order: Int = 0
    var isDone: Bool = false
    var task: TaskItem?
}

@Model final class Bucket {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#8E8E93"
    var order: Int = 0
    var focusFilterID: String?             // links a Focus mode → bucket
    var tasks: [TaskItem]? = []
}

@Model final class TimeBlock {             // a task placed on the calendar
    var id: UUID = UUID()
    var start: Date = Date()
    var end: Date = Date()
    var ekEventID: String?                 // set only if mirrored to Apple Calendar (Phase 5+)
    var task: TaskItem?
}

@Model final class WorkSession {           // actual time spent → estimator
    var id: UUID = UUID()
    var start: Date = Date()
    var end: Date?
    var endedBy: SessionEnd?               // user | autoCapped | appQuit
    var task: TaskItem?
}

@Model final class DayPlan {
    var id: UUID = UUID()
    var day: Date = Date()                 // normalized via DayBoundary, not midnight
    var mode: DayMode = .ideal             // ideal | minimum | pause
    var energyCheckIn: Int?                // 1–5, optional
}

@Model final class ActivityEvent {         // append-only log
    var id: UUID = UUID()
    var at: Date = Date()
    var kind: ActivityKind = .taskCreated
    var taskID: UUID?
    var payload: Data?                     // small JSON blob (e.g., notification id, action taken)
}
```

### 4.2 Not stored

- **Calendar events.** Always read from EventKit for the visible date range.
- **Derived values** (multiplier, today list, pick-for-me score). Computed on demand by `EFCore`.

### 4.3 CloudKit-compatibility rules (apply now, sync later)

- Every property optional or defaulted.
- No `@Attribute(.unique)`.
- All relationships optional.
- `VersionedSchema` + `SchemaMigrationPlan` from v1.
- The app owns migrations; widgets and intents only read (an extension must never drive a migration).

### 4.4 Data-quality flags (built in)

- **Runaway sessions:** a timer left running. Auto-cap at `max(estimate × 3, 120 min)`; mark `endedBy = .autoCapped`; exclude from estimator stats.
- **Estimator sample size:** don't apply a multiplier until ≥5 clean sessions exist in the bucket.
- **Day boundary:** the "day" starts at a user-set hour (default **4:00 AM**, not midnight; most adults with ADHD run on a delayed sleep cycle). All rollover and "today" logic uses `DayBoundary`, never `Calendar.startOfDay`.
- **Time-dependent logic** takes an injected `Clock`/`Calendar`, so DST, sleep/wake and midnight cases are testable.

---

## 5. Research → macOS surfaces

| Research problem | Surface | Implementation notes |
|------------------|---------|----------------------|
| Out of sight, out of mind | **Menu bar item** shows the current task + countdown in the menu bar text | `MenuBarExtra` with **`.window` style**. Menu-style extras don't run a timer runloop, so timers won't tick there. Use `TimelineView` for the countdown. |
| Frictionless capture | **Global hotkey → floating capture panel** (Spotlight-style) | `NSPanel` (`.nonactivatingPanel`, `.floating` level) hosting SwiftUI. Title only; Enter → Inbox. Optional NL parsing (Phase 6). |
| Frictionless capture | **Control** in Control Center / menu bar | macOS 26 Controls API (`ControlWidget`) |
| Time blindness | **Floating focus timer** (always on top, small) | Visible countdown for the active task; "just 5 minutes" entry point |
| Time blindness | **Now line + countdowns** in all calendar views | `TimelineView(.periodic(from:by: 30))` |
| Transitions / hyperfocus | **Escalating, time-sensitive notifications** | Time Sensitive Notifications entitlement; opt-in per event |
| Notification fatigue | **Actionable notifications** | Category actions: Start · +10 min · Reschedule. All scheduled by `NotificationPlanner`. |
| Context switching | **Focus filters** | `SetFocusFilterIntent`: Work Focus → show only the Work bucket |
| Not opening the app | **Desktop / Notification Center widgets** | Now/Next + Today; interactive "Done"/"Start" via App Intents |
| Hands-free | **App Intents → Siri, Shortcuts, Spotlight** | `AddTaskIntent`, `WhatsNextIntent`, `StartFiveMinutesIntent` |
| Always available | **Launch at login** | `SMAppService.mainApp.register()` |
| iPhone visibility before iOS app (optional) | **Mirror TimeBlocks to a dedicated "ExecFn" calendar** | One-way: the app owns blocks; edits made in Calendar.app are ignored/overwritten. Gives iPhone/Watch alerts for free. |

---

## 6. Core logic (`EFCore`)

All pure functions over plain values, with an injected `Clock` and `DayBoundary`.

### 6.1 Planner

- **Today list:** `isTodayMust` tasks (cap **3**, configurable) + timeboxed blocks for today + optional extras. Above the cap → suggest moving one to tomorrow; never block the user.
- **Rollover (runs at day boundary + on app launch/wake):** unfinished today tasks → stay `active`, `isTodayMust = false`, `rolloverCount += 1`. No "overdue" state exists anywhere.
- **Resurfacing:** tasks with `rolloverCount ≥ 3`, or untouched for 14 days, appear in the weekly review with one-tap: do this week / someday / drop.
- **Fresh start:** bulk action: everything non-done → Inbox, all `isTodayMust = false`. Logged, reversible for 24h.
- **Back-planning:** given `dueDate` + `estimate × multiplier`, propose `TimeBlock`s in free calendar slots before the due date, preferring the user's energy windows. **Proposal only**; the user accepts or adjusts.
- **Pick-for-me:** deterministic score that always shows its reason ("due tomorrow · fits in 25 min · low energy"):
  `score = w1·deadlineUrgency + w2·fitsAvailableTime + w3·energyMatch + w4·ageBoost − w5·recentlySkipped`
- **Minimum day:** `DayPlan.mode = .minimum` → Today shows only tasks the user flagged as "minimum"; notifications drop to essentials.
- **Pause day:** `DayPlan.mode = .pause` → no rollover increments, no nudges, nothing breaks.

### 6.2 Estimator

- Per bucket (fallback: global): `multiplier = median(actual / estimate)` over the last 20 clean sessions, clamped to `[0.5, 3.0]`, applied only when n ≥ 5.
- Surfaced as a suggestion: "You usually take ~1.6× on Admin. Plan 40 min?"
- Exposes estimate error over time for the Review screen.

### 6.3 NotificationPlanner

- **Input:** today's events, blocks, tasks, `DayPlan`, budget, quiet hours, current time.
- **Output:** a list of `PlannedNotification` (id, fireDate, category, copyKey, priority).
- **Rules:**
  - Daily budget (default **10**, configurable); allocate by priority: transition alerts > block starts > due-soon > nudges.
  - Escalation for flagged events: T−15 heads-up → T−5 wrap up → T−0 go (+ "leave by" if the event has a location and travel buffer).
  - Ignored notification → **one** follow-up after 10 min, then stop.
  - Copy rotates through a pool per category (slows habituation).
  - Keep pending count well under the system limit (iOS caps at 64; treat macOS the same).
- `NotificationService` diffs planned vs. pending and applies only the changes.

### 6.4 ActivityLog & metrics

Events: `taskCreated, captured(source), started, sessionEnded, completed, dropped, rolledOver, snoozed, notificationDelivered, notificationActed(action), freshStart, dayModeSet, breakdownGenerated, breakdownAccepted`.

Review-screen metrics (n=1 evaluation):
- Estimate error ratio (median, trend)
- Rollover rate (% of today musts that roll)
- Notification action rate (acted ÷ delivered, per category)
- Capture → done latency
- Active days / month (no streaks)
- Feature usage: hotkey captures, 5-min starts, breakdowns accepted

---

## 7. Services

| Service | Responsibilities | Gotchas |
|---------|------------------|---------|
| `CalendarService` | Request **full** access (there is no read-only option); fetch events for a visible range; list calendars incl. subscribed (read-only); observe `.EKEventStoreChanged` → refetch visible range only; optional block mirroring | Sandboxed app needs the calendars entitlement + `NSCalendarsFullAccessUsageDescription` |
| `NotificationService` | Register categories/actions; apply planner diff; route action responses back into `EFCore` + ActivityLog | Time-sensitive level requires its entitlement; user can disable it in Settings |
| `IntelligenceService` | Protocol: `breakdown(task) -> [String]`, `parseCapture(text) -> CaptureDraft`, `suggestEstimate(task) -> Int?` | Check `SystemLanguageModel.default.availability` (Apple silicon + Apple Intelligence on). Always have a manual fallback. Small model: keep prompts narrow; use `@Generable` structs for guided output. |
| `HotkeyService` | Register/rebind global capture shortcut | Default ⌥Space conflicts with some launchers; let the user rebind |

---

## 8. Guardrails enforced in code

- [ ] `TaskItem.title` is the only required input (initializer + capture UI).
- [ ] No `overdue` case exists in `TaskStatus`. No red badges. No missed-task counts in UI.
- [ ] Today cap enforced in `Planner`, not in views.
- [ ] Every notification flows through `NotificationPlanner`. Direct `UNUserNotificationCenter.add` calls outside `NotificationService` fail code review.
- [ ] All user-facing strings live in `Localizable.xcstrings`. Tone rule: neutral, no "failed", "missed", "behind", "you should".
- [ ] Planner proposals never auto-apply.
- [ ] Every user action writes an `ActivityEvent`.

---

## 9. Build order

Each phase ends with something usable. **Use it daily after Phase 2** and reorder later phases based on real use.

### Phase 1 — Skeleton
- Xcode multiplatform project (macOS target only enabled), `EFCore` package, App Group, entitlements.
- SwiftData models + `VersionedSchema` v1, `DayBoundary`, `Clock`.
- `CalendarService` full-access flow → **Day view** showing today's events with a now line.
- **Done when:** app launches, asks for calendar access, shows today's events including subscribed calendars; EFCore tests run green.

### Phase 2 — Capture & Now *(start daily use here)*
- Global hotkey → floating capture panel → Inbox.
- **Now** view: one task + next, first-step field, Start → focus timer → `WorkSession`.
- `MenuBarExtra` (.window) with current task + countdown.
- Launch at login. ActivityLog wired.
- **Done when:** you can capture from anywhere in <3s and see your current task in the menu bar without opening a window.

### Phase 3 — Buckets & scheduling
- Buckets CRUD (optional at capture; assign later).
- Unscheduled sidebar → drag onto Day view → `TimeBlock`; resize/move blocks.
- Manual subtask breakdown; "just 5 minutes" start.
- Missed block → one-tap reschedule prompt (no stale blocks).
- **Done when:** a day can be planned by dragging tasks between events.

### Phase 4 — Week/Month + Planner + Notifications
- Week view (7 columns, drag across days), Month view (density + tap → day).
- Rollover job, Today cap, Fresh start, ideal/minimum/pause day modes.
- `NotificationPlanner` + actionable categories + escalation + budget.
- **Done when:** a full week runs with no manual cleanup and no notification spam.

### Phase 5 — System surfaces
- Widgets (Now/Next, Today) with interactive buttons.
- App Intents: Add task, What's next, Start 5 minutes. Siri/Shortcuts/Spotlight.
- Focus filters ↔ buckets. Control for quick capture.
- Optional: mirror TimeBlocks to the dedicated Apple Calendar.
- **Done when:** a typical day needs the main window only for planning.

### Phase 6 — Intelligence & learning
- `IntelligenceService`: AI breakdown (accept/edit before saving), natural-language capture parsing, estimate suggestions.
- Estimator multiplier surfaced in scheduling.
- Energy windows + energy tags → back-planning + pick-for-me.
- Energy check-in → scales Today.
- Weekly Review screen with metrics (§6.4).
- **Done when:** the app proposes realistic plans from your own data, and you can see estimate error trending down.

### Phase 7 — iOS, Live Activity, sync
- Enable iOS target; reuse `EFCore` + services.
- Live Activity for the active task (shows on Lock Screen, Dynamic Island, and the Mac menu bar via iPhone).
- Watch complication.
- SwiftData + CloudKit sync (paid Developer Program).
- **Done when:** capture on phone → appears on Mac; active task visible on the phone's Lock Screen.

### Later (only if data says it's worth it)
- Focus sessions / virtual body doubling
- Accountability-partner sharing
- Swap in a larger model via the Foundation Models provider abstraction

---

## 10. Risks

| Risk | Why | Mitigation |
|------|-----|------------|
| Calendar UI effort | SwiftUI has no calendar grid; Week view with drag-and-drop is the hardest single component | Build Day view first and reuse its column for Week; budget the most time here |
| EventKit change storms | `.EKEventStoreChanged` fires often and coarsely | Debounce (≈500 ms); refetch visible range only |
| Time edge cases | Sleep/wake, DST, day boundary ≠ midnight | Injected `Clock`; dedicated tests; run rollover on wake + launch, not just on a timer |
| Notification over/under delivery | Pending limits; the user disables time-sensitive alerts | Planner diffing; graceful degradation; Settings shows the current authorization state |
| On-device model quality | Device-scale model; may be unavailable | Narrow prompts, guided generation, always a manual path |
| Schema changes after sync | CloudKit schema is append-only in production | CloudKit-compatible rules + versioned schema from v1 |
| Scope creep / abandonment | Builder + user are the same person | Phase 2 daily use; ship small; let ActivityLog decide priorities |

---

## 11. Info.plist & entitlements checklist

- `NSCalendarsFullAccessUsageDescription`: "Shows your calendar alongside your tasks so you can plan around real commitments."
- Entitlements:
  - App Sandbox
  - `com.apple.security.personal-information.calendars`
  - App Groups (shared container for app + widgets + intents; macOS group ID format differs from iOS, so set it via Signing & Capabilities)
  - Time Sensitive Notifications
  - iCloud / CloudKit (Phase 7)
- `LSUIElement`: **NO**. Keep the Dock icon; the menu bar item is additive, not a replacement.

---

## 12. Testing

- **EFCore:** Swift Testing unit tests for Planner, Estimator, NotificationPlanner, DayBoundary, all with fixed clocks. Required cases: DST forward/back, 3:59 vs 4:01 AM rollover, sleep across the boundary, budget exhaustion, zero-estimate tasks, runaway sessions.
- **Services:** protocol fakes for EventKit/notifications/intelligence; one manual test checklist per phase for real-device permission flows.
- **Dogfooding:** weekly 5-minute look at the Review metrics. Kill or change any feature whose usage or effect stays flat for 3 weeks.
