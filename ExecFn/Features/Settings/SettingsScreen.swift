import EFCore
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
            return "Calendar access is on."
        case .denied:
            return "Calendar access is off. The day still works without events."
        case .restricted:
            return "Calendar access is restricted on this Mac."
        case .writeOnly:
            return "Calendar access is write-only. Full access is what shows events."
        case .unknown, .notDetermined:
            return "Checking calendar access"
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
