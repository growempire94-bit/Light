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

enum Overlay: String, Identifiable {
    case intro, report, gameOver
    var id: String { rawValue }
}

struct GameScreen: View {
    @EnvironmentObject var engine: Engine
    @State private var panel: Panel?

    private var overlay: Binding<Overlay?> {
        Binding(get: {
            if engine.gameOver { return .gameOver }
            if !engine.state.started { return .intro }
            if engine.report != nil { return .report }
            return nil
        }, set: { _ in })
    }

    var body: some View {
        ZStack {
            SceneContainer(world: engine.world)
                .ignoresSafeArea()
            VStack(spacing: 8) {
                TopBar()
                if let o = engine.hud.outage {
                    Label(o, systemImage: "bolt.slash.fill")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.orange.opacity(0.85), in: Capsule())
                }
                if let t = engine.toast {
                    Text(t)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
                BottomBar { panel = $0 }
            }
            .padding(.horizontal, 10)
            .animation(.easeInOut(duration: 0.25), value: engine.toast)
        }
        .sheet(item: $panel) { p in
            PanelView(panel: p)
                .environmentObject(engine)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: overlay) { o in
            Group {
                switch o {
                case .intro: IntroView()
                case .report: ReportView()
                case .gameOver: GameOverView()
                }
            }
            .environmentObject(engine)
        }
    }
}

struct TopBar: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        let h = engine.hud
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.money(h.money))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(h.money < 0 ? Color.red : Color.primary)
                HStack(spacing: 6) {
                    Text("День \(h.day) · \(h.time)").monospacedDigit()
                    if h.closing { Text("закрываемся").foregroundStyle(.orange) }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Stars(rating: h.rating)
                Text(h.rating.map { String(format: "%.1f · %d отзывов", $0, h.reviews) } ?? "нет отзывов")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            SpeedControl()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
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
                    .frame(width: 30, height: 28)
                    .background(engine.speed == s ? Color.orange : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    .foregroundStyle(engine.speed == s ? Color.black : Color.primary)
                }
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct BottomBar: View {
    @EnvironmentObject var engine: Engine
    let open: (Panel) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Label("\(engine.hud.queue) в очереди", systemImage: "person.3.sequence")
                Label("\(engine.hud.pizzasToday) пицц", systemImage: "circle.circle")
                Label(Fmt.money(engine.hud.revenueToday), systemImage: "banknote")
                Spacer()
                Button {
                    engine.world.resetCamera()
                } label: {
                    Image(systemName: "scope").font(.body.weight(.semibold))
                }
            }
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 6) {
                ForEach(Panel.allCases) { p in
                    Button { open(p) } label: {
                        VStack(spacing: 3) {
                            Image(systemName: p.icon).font(.system(size: 18, weight: .semibold))
                            Text(p.title).font(.system(size: 10, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .padding(.bottom, 4)
    }
}
