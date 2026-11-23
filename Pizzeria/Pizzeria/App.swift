import SceneKit
import SwiftUI

@main
struct PizzeriaApp: App {
    @StateObject private var engine = Engine()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            GameScreen()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
                .onAppear {
                    Sound.shared.muted = engine.muted
                    Sound.shared.start()
                    ShotDirector.startIfRequested(engine)
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                if engine.state.started && engine.report == nil && !engine.gameOver { engine.openMenu() }
                engine.save()
            }
        }
    }
}

enum Fmt {
    private static let grouping: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        f.maximumFractionDigits = 0
        return f
    }()

    static func money(_ v: Double) -> String {
        let s = grouping.string(from: NSNumber(value: abs(v).rounded())) ?? "0"
        return (v < -0.5 ? "−₴" : "₴") + s
    }

    static func signed(_ v: Double) -> String {
        (v >= 0 ? "+" : "") + money(v)
    }

    static func percent(_ v: Double) -> String {
        "\(Int((v * 100).rounded()))%"
    }
}

struct SceneContainer: UIViewRepresentable {
    let world: World
    func makeUIView(context: Context) -> SCNView { world.view }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}

enum Panel: String, Identifiable, CaseIterable {
    case menu, kitchen, staff, ads, hall, finance
    var id: String { rawValue }
    var title: String {
        switch self {
        case .menu: return "Пиццы"
        case .kitchen: return "Кухня"
        case .staff: return "Персонал"
        case .ads: return "Реклама"
        case .hall: return "Зал"
        case .finance: return "Финансы"
        }
    }
    var icon: String {
        switch self {
        case .menu: return "list.bullet.rectangle"
        case .kitchen: return "flame"
        case .staff: return "person.2"
        case .ads: return "megaphone"
        case .hall: return "chair.lounge"
        case .finance: return "chart.bar"
        }
    }
}

struct GameScreen: View {
    @EnvironmentObject var engine: Engine

    private var overlayActive: Bool { engine.gameOver || !engine.state.started || engine.report != nil || engine.menuOpen }

    var body: some View {
        ZStack {
            SceneContainer(world: engine.world)
                .ignoresSafeArea()

            if !overlayActive {
                HUD()
                    .transition(.opacity)
            }

            if let p = engine.panel, !overlayActive {
                HStack(spacing: 0) {
                    Color.black.opacity(0.001)
                        .onTapGesture { withAnimation(.easeOut(duration: 0.22)) { engine.panel = nil } }
                    PanelView(panel: p) { withAnimation(.easeOut(duration: 0.22)) { engine.panel = nil } }
                        .frame(width: 440)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 18, x: -4)
                        .padding(.vertical, 8)
                        .padding(.trailing, 8)
                }
                .ignoresSafeArea(edges: .vertical)
                .transition(.move(edge: .trailing))
            }

            if overlayActive {
                Color.black.opacity(engine.state.started ? 0.45 : 0.25).ignoresSafeArea()
                Group {
                    if engine.gameOver {
                        GameOverView()
                    } else if engine.menuOpen {
                        PauseMenu()
                    } else if !engine.state.started {
                        IntroView()
                    } else {
                        ReportView()
                    }
                }
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: engine.toast)
        .animation(.easeInOut(duration: 0.25), value: overlayActive)
        .onAppear {
            engine.world.onTap = { [weak e = engine] name in
                guard let e, let p = Panel(rawValue: name) else { return }
                withAnimation(.easeOut(duration: 0.25)) { e.panel = p }
            }
        }
    }
}

struct HUD: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 760
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    MoneyCard(compact: compact)
                    Spacer(minLength: 6)
                    VStack(spacing: 6) {
                        if let o = engine.hud.outage {
                            Label(o, systemImage: "bolt.slash.fill")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.orange.opacity(0.9), in: Capsule())
                                .foregroundStyle(.black)
                        }
                        if let t = engine.toast {
                            Text(t)
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .frame(maxWidth: compact ? 260 : 420)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    Spacer(minLength: 6)
                    HStack(spacing: 6) {
                        SpeedControl(compact: compact)
                        HUDButton(icon: "camera.viewfinder") { engine.world.resetCamera() }
                        HUDButton(icon: "line.3.horizontal") {
                            withAnimation(.easeOut(duration: 0.2)) { engine.openMenu() }
                        }
                    }
                }
                Spacer()
                HStack(alignment: .bottom, spacing: 8) {
                    TodayCard(compact: compact)
                    Spacer(minLength: 6)
                    PanelBar(compact: compact)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct HUDButton: View {
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .foregroundStyle(.primary)
    }
}

struct MoneyCard: View {
    @EnvironmentObject var engine: Engine
    var compact = false

    var body: some View {
        let h = engine.hud
        HStack(spacing: compact ? 10 : 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Fmt.money(h.money))
                    .font(.system(size: compact ? 20 : 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(h.money < 0 ? Color.red : Color.primary)
                HStack(spacing: 6) {
                    Text("День \(h.day)")
                    Text(h.time).monospacedDigit()
                    if h.closing { Text("закрываемся").foregroundStyle(.orange) }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            Divider().frame(height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Stars(rating: h.rating)
                Text(h.rating.map { String(format: compact ? "%.1f" : "%.1f · %d отз.", $0, h.reviews) } ?? "нет отзывов")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, compact ? 11 : 14).padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct TodayCard: View {
    @EnvironmentObject var engine: Engine
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 10 : 14) {
            stat("person.3.sequence.fill", "\(engine.hud.queue)", "очередь")
            stat("circle.circle.fill", "\(engine.hud.pizzasToday)", "пицц")
            stat("banknote.fill", Fmt.money(engine.hud.revenueToday), "выручка")
            if engine.hud.lostToday > 0 && !compact {
                stat("figure.walk.departure", "\(engine.hud.lostToday)", "ушли", tint: .orange)
            }
        }
        .padding(.horizontal, compact ? 10 : 14).padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stat(_ icon: String, _ value: String, _ label: String, tint: Color = .primary) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint.opacity(0.8))
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: compact ? 13 : 14, weight: .bold, design: .rounded)).monospacedDigit()
                if !compact {
                    Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct PanelBar: View {
    @EnvironmentObject var engine: Engine
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(Panel.allCases) { p in
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { engine.panel = engine.panel == p ? nil : p }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: p.icon).font(.system(size: compact ? 15 : 17, weight: .semibold))
                        Text(p.title).font(.system(size: compact ? 8.5 : 10, weight: .semibold)).lineLimit(1)
                    }
                    .frame(width: compact ? 50 : 62, height: compact ? 44 : 50)
                    .background(engine.panel == p ? AnyShapeStyle(Color.orange.opacity(0.9)) : AnyShapeStyle(.ultraThinMaterial),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(engine.panel == p ? Color.black : Color.primary)
                }
            }
        }
    }
}

/// Pause menu: continue, help, sound, graphics quality, new game.
struct PauseMenu: View {
    @EnvironmentObject var engine: Engine
    @State private var showHelp = false
    @State private var confirmRestart = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 10) {
                Text("Пауза").font(.system(size: 28, weight: .heavy, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { engine.closeMenu() }
                } label: {
                    Label("Продолжить", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.black)
                }
                menuRow(showHelp ? "Скрыть подсказки" : "Как играть", icon: "questionmark.circle") { showHelp.toggle() }
                menuRow(engine.muted ? "Звук: выключен" : "Звук: включён", icon: engine.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                    engine.muted.toggle()
                }
                menuRow(engine.ecoGraphics ? "Графика: экономная" : "Графика: высокая", icon: engine.ecoGraphics ? "leaf" : "sparkles") {
                    engine.ecoGraphics.toggle()
                }
                menuRow("Начать заново", icon: "arrow.counterclockwise", role: .destructive) { confirmRestart = true }
            }
            .frame(width: 290)
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            if showHelp {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Как играть").font(.headline)
                        Label("Гости приходят с улицы. Цена, отзывы, вывеска и реклама решают, сколько их зайдёт", systemImage: "figure.walk")
                        Label("Вы принимаете заказы и печёте сами. Наймите кассира и пиццайоло, чтобы не было очереди", systemImage: "person.2")
                        Label("Печь, холодильный стол и тестомес ускоряют кухню и делают пиццу лучше", systemImage: "flame")
                        Label("Каждый вечер — аренда, зарплаты, электричество и налог. Три дня в минусе — банкротство", systemImage: "chart.bar")
                        Label("Отключения света по графику: без генератора электропечь стоит", systemImage: "bolt.slash")
                        Divider()
                        Label("Палец — двигать камеру, щипок — зум, два пальца — наклон и поворот", systemImage: "hand.draw")
                        Label("Нажмите на печь, столы, меню на стене или вывеску — откроется нужный раздел", systemImage: "hand.tap")
                        Label("⏸ ×1 ×2 ×4 сверху — скорость времени", systemImage: "speedometer")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .frame(width: 330)
                .padding(18)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.2), value: showHelp)
        .confirmationDialog("Начать заново? Весь прогресс будет удалён.", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Начать заново", role: .destructive) { engine.restart() }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func menuRow(_ title: String, icon: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 24)
                Text(title)
                Spacer()
            }
            .font(.body.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(role == .destructive ? Color.red : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

struct Stars: View {
    let rating: Double?
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { i in
                let r = rating ?? 0
                Image(systemName: r >= Double(i) + 0.75 ? "star.fill" : (r >= Double(i) + 0.25 ? "star.leadinghalf.filled" : "star"))
                    .font(.caption2)
                    .foregroundStyle(rating == nil ? Color.secondary : Color.yellow)
            }
        }
    }
}

struct SpeedControl: View {
    @EnvironmentObject var engine: Engine
    var compact = false
    var body: some View {
        HStack(spacing: 2) {
            ForEach([0, 1, 2, 4], id: \.self) { s in
                Button {
                    engine.speed = s
                } label: {
                    Group {
                        if s == 0 { Image(systemName: "pause.fill") } else { Text("×\(s)") }
                    }
                    .font(.caption.weight(.bold))
                    .frame(width: compact ? 30 : 34, height: 32)
                    .background(engine.speed == s ? Color.orange : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(engine.speed == s ? Color.black : Color.primary)
                }
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Scripted screenshots for CI (launch argument `-shots`). Writes `ready-N` into Documents,
/// waits for the runner to take a screenshot and answer with `go-N`.
enum ShotDirector {
    static func startIfRequested(_ engine: Engine) {
        guard ProcessInfo.processInfo.arguments.contains("-shots") else { return }
        Task { @MainActor in await run(engine) }
    }

    @MainActor
    private static func run(_ engine: Engine) async {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var n = 0
        func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
        func shot() async {
            await wait(3)
            n += 1
            FileManager.default.createFile(atPath: docs.appendingPathComponent("ready-\(n)").path, contents: Data())
            let go = docs.appendingPathComponent("go-\(n)").path
            for _ in 0..<300 where !FileManager.default.fileExists(atPath: go) { await wait(0.2) }
        }

        // 1–2: a fresh pizzeria at lunchtime.
        engine.debugPreset(upgraded: false)
        engine.debugSetTime(12 * 60 + 40)
        engine.fastForward(seconds: 25)
        await shot()
        engine.world.setCamera(yaw: 0.35, pitch: 0.62, distance: 8.5, target: SIMD3(-1.0, 0.6, -4.2))
        await shot()
        // 3–5: fully upgraded, busy evening.
        engine.debugPreset(upgraded: true)
        engine.debugSetTime(13 * 60 + 10)
        engine.fastForward(seconds: 30)
        engine.world.resetCamera()
        await shot()
        engine.world.setCamera(yaw: -0.3, pitch: 0.5, distance: 7.5, target: SIMD3(-1.2, 0.6, -1.6))
        await shot()
        engine.world.setCamera(yaw: 0.25, pitch: 0.42, distance: 15, target: SIMD3(0, 2.0, -1.0))
        await shot()
        engine.debugSetTime(20 * 60 + 30)
        engine.fastForward(seconds: 10)
        engine.world.resetCamera()
        await shot()
        // 7: a side panel open.
        engine.panel = .kitchen
        await shot()
        engine.panel = nil
        // 8: end of day report.
        engine.debugShowReport()
        await shot()
        // 9: pause menu.
        engine.report = nil
        engine.openMenu()
        await shot()
        FileManager.default.createFile(atPath: docs.appendingPathComponent("done").path, contents: Data())
    }
}
