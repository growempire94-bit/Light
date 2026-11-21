import Foundation

struct PowerEvent: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case on   // свет появился (домашний Wi‑Fi снова виден)
        case off  // свет пропал (домашний Wi‑Fi исчез)
    }

    var id: UUID
    var kind: Kind
    var date: Date
    /// For `.on` events: how long there was no power.
    var outageDuration: TimeInterval?

    init(kind: Kind, date: Date, outageDuration: TimeInterval? = nil) {
        self.id = UUID()
        self.kind = kind
        self.date = date
        self.outageDuration = outageDuration
    }
}

/// Persistent journal of power on/off events (newest first).
final class EventLog: ObservableObject {
    static let shared = EventLog()

    @Published private(set) var events: [PowerEvent] = []

    private let storageKey = "power.events"
    private let maxEvents = 5000

    private init() {
        load()
    }

    func add(_ kind: PowerEvent.Kind, date: Date, outageDuration: TimeInterval? = nil) {
        events.append(PowerEvent(kind: kind, date: date, outageDuration: outageDuration))
        events.sort { $0.date > $1.date }
        if events.count > maxEvents {
            events.removeLast(events.count - maxEvents)
        }
        save()
    }

    func clear() {
        events.removeAll()
        save()
    }

    /// Outages that ended today: count and total duration.
    func todayStats() -> (count: Int, total: TimeInterval) {
        let calendar = Calendar.current
        let todays = events.filter { $0.kind == .on && calendar.isDateInToday($0.date) }
        let total = todays.reduce(0.0) { $0 + ($1.outageDuration ?? 0) }
        return (todays.count, total)
    }

    /// Plain-text export for sharing (Notes, Telegram, etc.).
    func exportText() -> String {
        var lines = ["Журнал света"]
        for event in events.reversed() {
            let time = Format.dateTime(event.date)
            switch event.kind {
            case .off:
                lines.append("\(time) — свет пропал")
            case .on:
                if let duration = event.outageDuration {
                    lines.append("\(time) — свет появился (не было \(Format.duration(duration)))")
                } else {
                    lines.append("\(time) — свет появился")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PowerEvent].self, from: data) else { return }
        events = decoded.sorted { $0.date > $1.date }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
