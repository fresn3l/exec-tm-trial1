import AppKit
import EFCore
import EventKit
import Foundation
import os

@MainActor
@Observable
final class CalendarService {
    enum Access: String, Equatable {
        case unknown
        case notDetermined
        case full
        case denied
        case restricted
        case writeOnly
    }

    private let store = EKEventStore()
    private let changes = ChangeBox()
    private var reloadTask: Task<Void, Never>?
    private var range: DateInterval?
    private var isWatching = false

    private(set) var access: Access = .unknown
    private(set) var calendars: [CalendarDescriptor] = []
    private(set) var events: [EventSnapshot] = []

    init() {
        changes.service = self
    }

    func prepare(requestingIfNeeded: Bool) async {
        watchStore()
        refreshAccess()
        if access == .notDetermined, requestingIfNeeded {
            await requestAccess()
        } else if access == .full {
            reloadCalendars()
            reloadEvents()
        }
    }

    func requestAccess() async {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            refreshAccess()
            return
        }
        refreshAccess()
        if access == .full {
            reloadCalendars()
            reloadEvents()
        }
    }

    func setRange(start: Date, end: Date) {
        range = DateInterval(start: start, end: end)
        reloadEvents()
    }

    func refreshAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            access = .notDetermined
        case .restricted:
            access = .restricted
        case .denied:
            access = .denied
        case .fullAccess, .authorized:
            access = .full
        case .writeOnly:
            access = .writeOnly
        @unknown default:
            access = .denied
        }
    }

    private func watchStore() {
        guard !isWatching else { return }
        isWatching = true
        let exposed = EKEvent.instancesRespond(to: NSSelectorFromString("travelTime"))
        Logger(subsystem: "com.execfn.macos", category: "calendar")
            .info("EventKit travelTime exposed: \(exposed, privacy: .public)")
        let box = changes
        _ = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { _ in
            Task { @MainActor in
                box.service?.scheduleReload()
            }
        }
    }

    fileprivate func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.reloadCalendars()
            self?.reloadEvents()
        }
    }

    private func reloadCalendars() {
        guard access == .full else {
            calendars = []
            events = []
            return
        }
        calendars = store.calendars(for: .event).map { calendar in
            CalendarDescriptor(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                isBirthday: calendar.type == .birthday,
                isSubscribed: calendar.type == .subscription
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func reloadEvents() {
        guard access == .full, let range else {
            events = []
            return
        }
        let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
        events = store.events(matching: predicate).compactMap(snapshot(from:))
    }

    private func snapshot(from event: EKEvent) -> EventSnapshot? {
        guard event.status != .canceled else { return nil }
        guard let start = event.startDate, let end = event.endDate, end > start else { return nil }
        let external = nonEmpty(event.calendarItemExternalIdentifier)
            ?? nonEmpty(event.eventIdentifier)
            ?? "\(start.timeIntervalSince1970)-\(event.title ?? "")"
        let title = nonEmpty(event.title) ?? String(localized: "Event")
        let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return EventSnapshot(
            ref: EventRef(externalID: external, occurrenceStart: event.occurrenceDate ?? start),
            calendarID: event.calendar?.calendarIdentifier ?? "",
            title: title,
            start: start,
            end: end,
            isAllDay: event.isAllDay,
            availability: mapAvailability(event.availability),
            hasLocation: event.structuredLocation != nil || !location.isEmpty
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func mapAvailability(_ value: EKEventAvailability) -> EventAvailability {
        switch value {
        case .notSupported: .notSupported
        case .busy: .busy
        case .free: .free
        case .tentative: .tentative
        case .unavailable: .unavailable
        @unknown default: .notSupported
        }
    }
}

/// Lets the EventKit callback hop back to the main actor without capturing the service in a sendable closure.
private final class ChangeBox: @unchecked Sendable {
    weak var service: CalendarService?
}
