import Foundation

enum Format {
    private static let ru = Locale(identifier: "ru_RU")

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = ru
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = ru
        f.dateFormat = "d MMM, HH:mm"
        return f
    }()

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func dateTime(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "сегодня, " + timeFormatter.string(from: date)
        }
        if Calendar.current.isDateInYesterday(date) {
            return "вчера, " + timeFormatter.string(from: date)
        }
        return dateTimeFormatter.string(from: date)
    }

    /// "2 д 3 ч", "1 ч 05 мин", "12 мин", "40 сек"
    static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60

        if days > 0 {
            return "\(days) д \(hours) ч"
        }
        if hours > 0 {
            return String(format: "%d ч %02d мин", hours, minutes)
        }
        if minutes > 0 {
            return "\(minutes) мин"
        }
        return "\(seconds) сек"
    }
}
