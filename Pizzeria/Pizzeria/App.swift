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
                .onAppear { ShotDirector.startIfRequested(engine) }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { engine.save() }
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
        case .menu: return "Меню"
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

    private var overlayActive: Bool { engine.gameOver || !engine.state.started || engine.report != nil }

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
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                MoneyCard()
                Spacer(minLength: 8)
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
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .frame(maxWidth: 420)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    SpeedControl()
                    Button {
                        engine.world.resetCamera()
                    } label: {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .foregroundStyle(.primary)
                }
            }
            Spacer()
            HStack(alignment: .bottom, spacing: 10) {
                TodayCard()
                Spacer(minLength: 8)
                PanelBar()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct MoneyCard: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        let h = engine.hud
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Fmt.money(h.money))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
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
            Divider().frame(height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Stars(rating: h.rating)
                Text(h.rating.map { String(format: "%.1f · %d отз.", $0, h.reviews) } ?? "нет отзывов")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct TodayCard: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        HStack(spacing: 14) {
            stat("person.3.sequence.fill", "\(engine.hud.queue)", "очередь")
            stat("circle.circle.fill", "\(engine.hud.pizzasToday)", "пицц")
            stat("banknote.fill", Fmt.money(engine.hud.revenueToday), "выручка")
            if engine.hud.lostToday > 0 {
                stat("figure.walk.departure", "\(engine.hud.lostToday)", "ушли", tint: .orange)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stat(_ icon: String, _ value: String, _ label: String, tint: Color = .primary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint.opacity(0.8))
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit()
                Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            }
        }
    }
}

struct PanelBar: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Panel.allCases) { p in
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { engine.panel = engine.panel == p ? nil : p }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: p.icon).font(.system(size: 17, weight: .semibold))
                        Text(p.title).font(.system(size: 10, weight: .semibold))
                    }
                    .frame(width: 62, height: 50)
                    .background(engine.panel == p ? AnyShapeStyle(Color.orange.opacity(0.9)) : AnyShapeStyle(.ultraThinMaterial),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(engine.panel == p ? Color.black : Color.primary)
                }
            }
        }
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
                    .frame(width: 34, height: 32)
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
        FileManager.default.createFile(atPath: docs.appendingPathComponent("done").path, contents: Data())
    }
}
