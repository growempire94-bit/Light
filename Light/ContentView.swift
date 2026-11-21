import CoreLocation
import UIKit
import SwiftUI

struct ContentView: View {
    @ObservedObject private var audio = AudioManager.shared

    var body: some View {
        ZStack {
            TabView {
                StatusView()
                    .tabItem { Label("Статус", systemImage: "lightbulb") }
                HistoryView()
                    .tabItem { Label("Журнал", systemImage: "list.bullet") }
                SettingsView()
                    .tabItem { Label("Настройки", systemImage: "gearshape") }
            }

            if audio.isAlarmPlaying {
                AlarmOverlay()
                    .transition(.opacity)
            }
        }
        .background(HiddenVolumeView().frame(width: 1, height: 1))
        .animation(.easeInOut, value: audio.isAlarmPlaying)
    }
}

struct AlarmOverlay: View {
    @EnvironmentObject var monitor: PowerMonitor

    var body: some View {
        ZStack {
            Color.yellow.ignoresSafeArea()
            VStack(spacing: 28) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 110))
                    .foregroundColor(.black)
                Text("СВЕТ ПОЯВИЛСЯ!")
                    .font(.system(size: 38, weight: .heavy))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                Button {
                    monitor.stopAlarm()
                } label: {
                    Text("Выключить сигнал")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(Color.black)
                        .foregroundColor(.yellow)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                .padding(.horizontal, 32)
            }
        }
    }
}

// MARK: - Status

struct StatusView: View {
    @EnvironmentObject var monitor: PowerMonitor
    @ObservedObject private var audio = AudioManager.shared
    @AppStorage(SettingsKey.homeSSID) private var homeSSID = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StatusCard(state: monitor.state, since: monitor.stateSince)

                    VStack(spacing: 0) {
                        InfoRow(icon: "wifi", title: "Wi‑Fi", value: wifiText)
                        Divider()
                        InfoRow(icon: "house", title: "Домашняя сеть",
                                value: homeSSID.isEmpty ? "любая Wi‑Fi" : homeSSID)
                        Divider()
                        InfoRow(icon: audio.keepAliveActive ? "checkmark.circle" : "exclamationmark.triangle",
                                title: "Слежение в фоне",
                                value: audio.keepAliveActive ? "работает" : "остановлено")
                    }
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    Button {
                        monitor.testAlarm()
                    } label: {
                        Label("Проверить сигнал (5 сек)", systemImage: "speaker.wave.3.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Text("Не закрывайте приложение смахиванием вверх — тогда iOS остановит слежение. Просто сверните его. Мобильный интернет можно не выключать.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle("Свет")
        }
    }

    private var wifiText: String {
        guard monitor.wifiConnected else { return "нет (мобильная сеть)" }
        if let ssid = monitor.currentSSID {
            return monitor.onHomeNetwork ? ssid : "\(ssid) (чужая)"
        }
        return "подключён"
    }
}

struct StatusCard: View {
    let state: PowerState
    let since: Date

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 72))
                .foregroundColor(color)
            Text(title)
                .font(.largeTitle.bold())
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(subtitle(now: context.date))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal)
        .background(RoundedRectangle(cornerRadius: 24).fill(color.opacity(0.15)))
    }

    private var icon: String {
        switch state {
        case .on: return "lightbulb.fill"
        case .off: return "lightbulb.slash"
        case .pendingOff: return "wifi.exclamationmark"
        case .unknown: return "questionmark.circle"
        }
    }

    private var color: Color {
        switch state {
        case .on: return .yellow
        case .off: return .gray
        case .pendingOff: return .orange
        case .unknown: return .blue
        }
    }

    private var title: String {
        switch state {
        case .on: return "Свет есть"
        case .off: return "Света нет"
        case .pendingOff: return "Wi‑Fi пропал…"
        case .unknown: return "Проверка…"
        }
    }

    private func subtitle(now: Date) -> String {
        let elapsed = Format.duration(now.timeIntervalSince(since))
        switch state {
        case .on: return "с \(Format.dateTime(since)) · уже \(elapsed)"
        case .off: return "с \(Format.dateTime(since)) · уже \(elapsed)"
        case .pendingOff: return "Проверяю, не отключили ли свет (\(elapsed))"
        case .unknown: return "Жду данные о Wi‑Fi"
        }
    }
}

struct InfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.accentColor)
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding()
    }
}

// MARK: - History

struct HistoryView: View {
    @EnvironmentObject var monitor: PowerMonitor
    @ObservedObject private var log = EventLog.shared
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List {
                Section("Сегодня") {
                    let stats = log.todayStats()
                    HStack {
                        Text("Отключений")
                        Spacer()
                        Text("\(stats.count)").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Без света")
                        Spacer()
                        Text(Format.duration(stats.total)).foregroundColor(.secondary)
                    }
                }

                Section("События") {
                    if log.events.isEmpty {
                        Text("Пока нет событий")
                            .foregroundColor(.secondary)
                    }
                    ForEach(log.events) { event in
                        EventRow(event: event)
                    }
                }
            }
            .navigationTitle("Журнал")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ShareLink(item: log.exportText()) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        confirmClear = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(log.events.isEmpty)
                }
            }
            .confirmationDialog("Очистить журнал?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Очистить", role: .destructive) { log.clear() }
            }
        }
    }
}

struct EventRow: View {
    let event: PowerEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.kind == .on ? "lightbulb.fill" : "lightbulb.slash")
                .font(.title2)
                .foregroundColor(event.kind == .on ? Color.yellow : Color.gray)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.kind == .on ? "Свет появился" : "Свет пропал")
                    .font(.headline)
                if let duration = event.outageDuration {
                    Text("не было \(Format.duration(duration))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Text(Format.dateTime(event.date))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var monitor: PowerMonitor
    @ObservedObject private var location = LocationPermission.shared

    @AppStorage(SettingsKey.homeSSID) private var homeSSID = ""
    @AppStorage(SettingsKey.alarmEnabled) private var alarmEnabled = true
    @AppStorage(SettingsKey.alarmDuration) private var alarmDuration = 60.0
    @AppStorage(SettingsKey.minOutage) private var minOutage = 30.0
    @AppStorage(SettingsKey.maxVolume) private var maxVolume = true
    @AppStorage(SettingsKey.vibrate) private var vibrate = true
    @AppStorage(SettingsKey.notifyOnOff) private var notifyOnOff = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Имя сети (SSID)", text: $homeSSID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let ssid = monitor.currentSSID, ssid != homeSSID {
                        Button("Использовать «\(ssid)»") { homeSSID = ssid }
                    }
                    if !location.isAuthorized {
                        Button("Разрешить видеть имя Wi‑Fi") {
                            if location.status == .notDetermined {
                                location.request()
                            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    } else if !location.isPrecise {
                        Text("Включите «Точная геопозиция» в настройках iOS, иначе имя сети недоступно.")
                            .font(.footnote)
                            .foregroundColor(.orange)
                    }
                } header: {
                    Text("Домашняя сеть Wi‑Fi")
                } footer: {
                    Text("Можно вписать примерно: регистр, пробелы и знаки не важны, 1–2 ошибки в буквах допускаются. Если пусто — любая Wi‑Fi сеть считается домашней. iOS показывает имя сети только приложениям с доступом к геопозиции; само местоположение не используется.")
                }

                Section("Сигнал, когда свет появился") {
                    Toggle("Громкий сигнал", isOn: $alarmEnabled)
                    Picker("Длительность", selection: $alarmDuration) {
                        Text("15 сек").tag(15.0)
                        Text("30 сек").tag(30.0)
                        Text("1 мин").tag(60.0)
                        Text("2 мин").tag(120.0)
                        Text("5 мин").tag(300.0)
                        Text("Пока не выключу").tag(0.0)
                    }
                    Toggle("Максимальная громкость", isOn: $maxVolume)
                    Toggle("Вибрация", isOn: $vibrate)
                    Button("Проверить сигнал") { monitor.testAlarm() }
                }

                Section {
                    Picker("Не считать отключением обрывы короче", selection: $minOutage) {
                        Text("Считать все").tag(0.0)
                        Text("15 сек").tag(15.0)
                        Text("30 сек").tag(30.0)
                        Text("1 мин").tag(60.0)
                        Text("2 мин").tag(120.0)
                        Text("5 мин").tag(300.0)
                    }
                    Toggle("Уведомлять, когда свет пропал", isOn: $notifyOnOff)
                } header: {
                    Text("Отключения")
                } footer: {
                    Text("Короткие пропадания Wi‑Fi (перезагрузка роутера, помехи) не попадут в журнал.")
                }

                Section("Как это работает") {
                    Text("Роутер питается от сети. Свет пропал → роутер выключился → домашний Wi‑Fi исчез. Свет дали → роутер включился → iPhone сам подключается к знакомой сети, даже если включён мобильный интернет. Приложение это замечает и включает сирену.")
                        .font(.footnote)
                    Text("Подстраховка: «Команды» → «Автоматизация» → «Wi‑Fi» → выберите домашнюю сеть, «Запускать сразу» → действие «Проверить свет» (приложение «Свет»).")
                        .font(.footnote)
                }
            }
            .navigationTitle("Настройки")
            .onChange(of: homeSSID) { _ in
                monitor.refresh()
            }
        }
    }
}
