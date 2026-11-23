import EFCore
import Foundation
import SwiftData

@MainActor
public final class ActivityLog {
    private let context: ModelContext
    private let container: ModelContainer   // keep alive for the context's lifetime

    public init(container: ModelContainer) {
        self.container = container
        self.context = ModelContext(container)
    }

    public func append(_ event: ActivityEvent) throws {
        let model = ActivityEventModel()
        model.id = event.id
        model.at = event.at
        model.kindRaw = event.kind.rawValue
        model.taskID = event.taskID
        model.payload = event.payload.isEmpty ? nil : try JSONCoders.encode(event.payload)
        context.insert(model)
        try context.save()
    }

    public func latest(kind: ActivityKind) throws -> ActivityEvent? {
        let raw = kind.rawValue
        var descriptor = FetchDescriptor<ActivityEventModel>(
            predicate: #Predicate { $0.kindRaw == raw },
            sortBy: [SortDescriptor(\.at, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first.map(decode)
    }

    public func events() throws -> [ActivityEvent] {
        let descriptor = FetchDescriptor<ActivityEventModel>(
            sortBy: [SortDescriptor(\.at)]
        )
        return try context.fetch(descriptor).map(decode)
    }

    public func exportJSONL() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try events().map { event in
            let data = try encoder.encode(event)
            return String(decoding: data, as: UTF8.self)
        }.joined(separator: "\n")
    }

    public func exportCSV() throws -> String {
        var lines = ["id,at,kind,taskID,payload"]
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for event in try events() {
            let payload = try JSONCoders.encode(event.payload)
            let payloadText = String(decoding: payload, as: UTF8.self)
            let task = event.taskID?.uuidString ?? ""
            lines.append(
                [
                    event.id.uuidString,
                    formatter.string(from: event.at),
                    event.kind.rawValue,
                    task,
                    csvField(payloadText),
                ].joined(separator: ",")
            )
        }
        return lines.joined(separator: "\n")
    }

    private func decode(_ model: ActivityEventModel) -> ActivityEvent {
        let payload: [String: String]
        if let data = model.payload, let decoded = try? JSONCoders.decode([String: String].self, from: data) {
            payload = decoded
        } else {
            payload = [:]
        }
        return ActivityEvent(
            id: model.id,
            at: model.at,
            kind: ActivityKind(rawValue: model.kindRaw) ?? .presence,
            taskID: model.taskID,
            payload: payload
        )
    }

    private func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
