import Foundation

struct OutageInterval {
    let start: Date
    let end: Date
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct DayStat: Identifiable {
    let day: Date
    let hours: Double
    let count: Int
    var id: Date { day }
}

struct HourStat: Identifiable {
    let hour: Int
    /// Share of time without light at this hour of day, 0…100.
    let percent: Double
    var id: Int { hour }
}

struct PeriodSummary {
    let totalOff: TimeInterval
    let count: Int
    let average: TimeInterval
    let longest: TimeInterval
}

enum Stats {
    /// All outages from the journal; an ongoing outage ends "now".
    static func intervals(events: [PowerEvent], ongoingSince: Date?, now: Date = Date()) -> [OutageInterval] {
        var result: [OutageInterval] = events.compactMap { event in
            guard event.kind == .on, let duration = event.outageDuration, duration > 0 else { return nil }
            return OutageInterval(start: event.date.addingTimeInterval(-duration), end: event.date)
        }
        if let since = ongoingSince, since < now {
            result.append(OutageInterval(start: since, end: now))
        }
        return result
    }

    /// Hours without light for each of the last `days` days (oldest first).
    static func perDay(_ intervals: [OutageInterval], days: Int, now: Date = Date()) -> [DayStat] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var result: [DayStat] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let dayStart = calendar.date(byAdding: .day, value: -offset, to: today),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            var seconds = 0.0
            var count = 0
            for interval in intervals {
                let start = max(interval.start, dayStart)
                let end = min(interval.end, dayEnd)
                if end > start { seconds += end.timeIntervalSince(start) }
                if interval.start >= dayStart && interval.start < dayEnd { count += 1 }
            }
            result.append(DayStat(day: dayStart, hours: seconds / 3600, count: count))
        }
        return result
    }

    /// For each hour of the day: how often there was no light at that hour.
    static func perHour(_ intervals: [OutageInterval], days: Int, now: Date = Date()) -> [HourStat] {
        let calendar = Calendar.current
        let periodStart = periodStartDate(days: days, now: now)
        var seconds = [Double](repeating: 0, count: 24)

        for interval in intervals {
            var t = max(interval.start, periodStart)
            let end = min(interval.end, now)
            while t < end {
                let hourEnd = calendar.dateInterval(of: .hour, for: t)?.end ?? t.addingTimeInterval(3600)
                let next = min(end, max(hourEnd, t.addingTimeInterval(1)))
                let hour = calendar.component(.hour, from: t)
                seconds[hour] += next.timeIntervalSince(t)
                t = next
            }
        }
        let perHourTotal = Double(days) * 3600
        return (0..<24).map { HourStat(hour: $0, percent: min(100, seconds[$0] / perHourTotal * 100)) }
    }

    static func summary(_ intervals: [OutageInterval], days: Int, now: Date = Date()) -> PeriodSummary {
        let periodStart = periodStartDate(days: days, now: now)
        var total = 0.0
        var count = 0
        var finished: [TimeInterval] = []
        var longest = 0.0

        for interval in intervals where interval.end > periodStart {
            let clipped = min(interval.end, now).timeIntervalSince(max(interval.start, periodStart))
            total += max(0, clipped)
            if interval.start >= periodStart { count += 1 }
            finished.append(interval.duration)
            longest = max(longest, interval.duration)
        }
        let average = finished.isEmpty ? 0 : finished.reduce(0, +) / Double(finished.count)
        return PeriodSummary(totalOff: total, count: count, average: average, longest: longest)
    }

    static func periodStartDate(days: Int, now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
    }
}
