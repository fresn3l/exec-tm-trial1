import EFCore
import ServiceManagement
import SwiftUI

struct SettingsScreen: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                Text(accessCopy)
                accessButtons
                if let exportMessage = model.exportMessage {
                    Text(exportMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let storeProblem = model.storeProblem {
                    Text(storeProblem)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("Busy calendars reserve time. Visible calendars stay on the day and leave time open. Hidden calendars stay off the day.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Birthdays, holidays, and subscribed calendars start out Visible.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if model.calendar.calendars.isEmpty {
                    Text("No calendars yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.calendar.calendars) { descriptor in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(descriptor.title)
                                Spacer()
                                if model.hasOverride(for: descriptor) {
                                    Button("Default") { model.clearMode(for: descriptor) }
                                        .buttonStyle(.borderless)
                                }
                            }
                            Picker(
                                descriptor.title,
                                selection: Binding(
                                    get: { model.mode(for: descriptor) },
                                    set: { model.setMode($0, for: descriptor) }
                                )
                            ) {
                                Text("Hidden").tag(CalendarMode.hidden)
                                Text("Visible").tag(CalendarMode.visible)
                                Text("Busy").tag(CalendarMode.busy)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Calendars")
            }

            Section {
                LaunchAtLoginToggle()
            } header: {
                Text("General")
            }

            Section {
                Button("Export activity log") { model.exportActivityLog() }
            } header: {
                Text("Activity log")
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 520)
    }

    private var accessCopy: String {
        switch model.calendar.access {
        case .full:
            return String(localized: "Calendar access is on.")
        case .denied:
            return String(localized: "Calendar access is off. The day still works without events.")
        case .restricted:
            return String(localized: "Calendar access is restricted on this Mac.")
        case .writeOnly:
            return String(localized: "Calendar access is write-only. Full access is what shows events.")
        case .unknown, .notDetermined:
            return String(localized: "Checking calendar access")
        }
    }

    @ViewBuilder
    private var accessButtons: some View {
        switch model.calendar.access {
        case .notDetermined:
            Button("Allow Calendar Access") { Task { await model.requestAccess() } }
        case .denied, .restricted, .writeOnly:
            Button("Open System Settings") { model.openCalendarSettings() }
        case .unknown, .full:
            EmptyView()
        }
    }
}

/// Phase 2: launch at login via `SMAppService.mainApp`.
struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var note: String?

    var body: some View {
        Toggle("Open ExecFn at login", isOn: Binding(
            get: { enabled },
            set: { newValue in
                do {
                    if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    note = nil
                } catch {
                    note = String(localized: "macOS didn't accept that change. You can set it in System Settings → General → Login Items.")
                }
                enabled = SMAppService.mainApp.status == .enabled
            }
        ))
        if SMAppService.mainApp.status == .requiresApproval {
            Text("Waiting for approval in System Settings → General → Login Items.")
                .font(.caption).foregroundStyle(.secondary)
        }
        if let note {
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
    }
}
