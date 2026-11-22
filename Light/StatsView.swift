import Charts
import SwiftUI

struct StatsView: View {
    @EnvironmentObject var monitor: PowerMonitor
    @ObservedObject private var log = EventLog.shared
    @State private var days = 7

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Период", selection: $days) {
                        Text("7 дней").tag(7)
                        Text("30 дней").tag(30)
                    }
                    .pickerStyle(.segmented)

                    let intervals = Stats.intervals(events: log.events, ongoingSince: ongoingSince)
                    let summary = Stats.summary(intervals, days: days)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatTile(title: "Без света", value: Format.duration(summary.totalOff), icon: "lightbulb.slash")
                        StatTile(title: "Отключений", value: "\(summary.count)", icon: "bolt.slash")
                        StatTile(title: "В среднем", value: summary.average > 0 ? Format.duration(summary.average) : "—", icon: "clock")
                        StatTile(title: "Самое долгое", value: summary.longest > 0 ? Format.duration(summary.longest) : "—", icon: "hourglass")
                    }

                    ChartCard(title: "Часов без света по дням") {
                        Chart(Stats.perDay(intervals, days: days)) { day in
                            BarMark(x: .value("День", day.day, unit: .day),
                                    y: .value("Часы", day.hours))
                                .foregroundStyle(Color.orange.gradient)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: days == 7 ? 1 : 5)) { _ in
                                AxisGridLine()
                                AxisValueLabel(format: .dateTime.day().month(.defaultDigits))
                            }
                        }
                        .chartYAxis {
                            AxisMarks { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let hours = value.as(Double.self) {
                                        Text("\(Int(hours)) ч")
                                    }
                                }
                            }
                        }
                        .frame(height: 200)
                    }

                    ChartCard(title: "Когда чаще нет света (по часам суток)") {
                        Chart(Stats.perHour(intervals, days: days)) { item in
                            BarMark(x: .value("Час", item.hour),
                                    y: .value("Без света, %", item.percent))
                                .foregroundStyle(Color.gray.gradient)
                        }
                        .chartXAxis {
                            AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21]) { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let hour = value.as(Int.self) {
                                        Text("\(hour):00")
                                    }
                                }
                            }
                        }
                        .chartYScale(domain: 0.0...100.0)
                        .chartYAxis {
                            AxisMarks(values: [0.0, 50.0, 100.0]) { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let percent = value.as(Double.self) {
                                        Text("\(Int(percent))%")
                                    }
                                }
                            }
                        }
                        .frame(height: 180)
                    }

                    if log.events.isEmpty {
                        Text("Графики заполнятся после первых отключений.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Статистика")
        }
        .environment(\.locale, Locale(identifier: "ru_RU"))
    }

    private var ongoingSince: Date? {
        monitor.state == .off ? monitor.stateSince : nil
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct ChartCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
