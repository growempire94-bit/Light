import Foundation
import QuartzCore
import SceneKit
import simd
import UIKit

final class Order {
    enum Stage { case queued, prepping, waitingOven, baking, ready, done }
    let pizza: String
    let isDelivery: Bool
    var stage: Stage = .queued
    var remaining = 0.0
    weak var customer: Customer?

    init(pizza: String, isDelivery: Bool) {
        self.pizza = pizza
        self.isDelivery = isDelivery
    }
}

final class Customer {
    enum Kind { case walker, guest, courier }
    enum Phase { case passing, entering, inQueue, ordering, toWait, waiting, toPickup, toSeat, eating, leaving, gone }

    let kind: Kind
    let person: PersonNode
    var pos: SIMD3<Float>
    var path: [SIMD3<Float>] = []
    var phase: Phase = .passing
    var decided = false
    var wantsIn = false
    var waitSpot = -1
    var seat = -1
    var dineIn = false
    var pizza = "margherita"
    var paysCard = false
    var enteredAt = 0.0
    var patience = 900.0
    var order: Order?
    var timer = 0.0
    var speed: Float

    init(kind: Kind, person: PersonNode, pos: SIMD3<Float>) {
        self.kind = kind
        self.person = person
        self.pos = pos
        speed = Float.random(in: 1.15...1.5)
    }

    var isInside: Bool {
        switch phase {
        case .passing, .gone: return false
        default: return true
        }
    }
}

final class Worker {
    enum Role { case owner, cook, cashier, cleaner }
    enum Task {
        case idle
        case takingOrder(Customer, Double)
        case prepping(Order, Double)
    }

    let role: Role
    let skill: Double
    let person: PersonNode
    var pos: SIMD3<Float>
    var target: SIMD3<Float>
    var task: Task = .idle
    var station: SIMD3<Float>
    var route = 0

    init(role: Role, skill: Double, person: PersonNode, station: SIMD3<Float>) {
        self.role = role
        self.skill = skill
        self.person = person
        self.station = station
        pos = station
        target = station
    }

    var isIdle: Bool {
        if case .idle = task { return true }
        return false
    }
}

struct HUDInfo {
    var money = 0.0
    var time = "10:00"
    var day = 1
    var rating: Double?
    var reviews = 0
    var queue = 0
    var inside = 0
    var outage: String?
    var revenueToday = 0.0
    var pizzasToday = 0
    var lostToday = 0
    var closing = false
}

final class Engine: NSObject, ObservableObject {
    @Published var state: GameState
    @Published var hud = HUDInfo()
    @Published var report: DayReport?
    @Published var toast: String?
    @Published var speed: Int = 1
    @Published var gameOver = false
    @Published var panel: Panel?

    let world = World()

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private(set) var minute = Econ.openMinute
    private var today = DayReport(day: 1)
    private var customers: [Customer] = []
    private var queue: [Customer] = []
    private var orders: [Order] = []
    private var ovenSlots: [Order?] = []
    private var workers: [Worker] = []
    private var seatTaken: [Bool] = []
    private var waitTaken = [Bool](repeating: false, count: Spot.waiting.count)
    private var nextWalker = 5.0
    private var nextGuest = 600.0
    private var nextDelivery = 900.0
    private var hudClock = 0.0
    private var cleanliness = 1.0
    private var closing = false
    private var dayOver = false
    private var kwh = 0.0
    private var fuel = 0.0
    private var wasOutage = false
    private var promoter: PersonNode?
    private var toastTimer: Timer?

    override init() {
        state = GameState.load() ?? GameState()
        super.init()
        today = DayReport(day: state.day)
        world.apply(state)
        rebuildStaff()
        resetOvens()
        seatTaken = Array(repeating: false, count: world.seats.count)
        if state.outages.isEmpty && state.started { rollOutages() }
        if !state.started { speed = 0 }
        let l = CADisplayLink(target: self, selector: #selector(frame(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    // MARK: derived values

    var clock: Double { minute * 60 }
    var oven: OvenDef { Catalog.oven(state.oven) }
    func has(_ id: String) -> Bool { state.equipment.contains(id) || state.building.contains(id) }

    var outageNow: Bool { state.outages.contains { minute >= $0.start && minute < $0.end } }
    var interiorPowered: Bool { !outageNow || has("generator") }
    var canBake: Bool { !oven.needsPower || interiorPowered }

    var priceIndex: Double {
        let ids = Array(state.unlockedPizzas)
        guard !ids.isEmpty else { return 1 }
        return ids.reduce(0) { $0 + state.price($1) / Catalog.pizza($1).marketPrice } / Double(ids.count)
    }
    var priceFactor: Double { min(2.5, max(0.12, pow(1 / priceIndex, 1.7))) }
    var ratingFactor: Double {
        guard let r = state.rating else { return 1 }
        return pow(1.45, r - 3.8)
    }

    var cookSkill: Double {
        let cooks = workers.filter { $0.role == .cook || ($0.role == .owner) }
        guard !cooks.isEmpty else { return 0.9 }
        return cooks.reduce(0) { $0 + $1.skill } / Double(cooks.count)
    }

    /// Food quality ≈ 0.5 (poor) … 2.3 (excellent).
    var quality: Double {
        state.tier.quality * oven.quality * cookSkill * (has("mixer") ? 1.06 : 1)
    }

    var visibility: Double {
        var v = 1.0
        if has("sign") { v *= minute >= 18 * 60 ? 1.6 : 1.3 }
        if has("windows") { v *= 1.1 }
        if has("renovation") { v *= 1.1 }
        if state.adsBought.contains("maps") { v *= 1.2 }
        if state.adsOn.contains("instagram") { v *= 1.25 }
        if state.adsOn.contains("billboard") { v *= 1.3 }
        let flyerAge = Double(state.day - state.flyersDay)
        if flyerAge >= 0 && flyerAge < 3 { v *= 1 + 0.4 * (1 - flyerAge / 3) }
        if state.day <= state.bloggerUntilDay { v *= 1.3 }
        if has("terrace") && minute < 21 * 60 { v *= 1.08 }
        return v
    }

    func hourCurve(_ m: Double) -> Double {
        let pts: [(Double, Double)] = [(9, 0.4), (10, 0.55), (11, 0.75), (12, 1.25), (13, 1.45), (14, 1.05), (15, 0.75), (16, 0.7),
                                       (17, 0.9), (18, 1.25), (19, 1.5), (20, 1.35), (21, 0.95), (22, 0.6), (24, 0.3)]
        let h = m / 60
        for i in 1..<pts.count where h <= pts[i].0 {
            let (h0, v0) = pts[i - 1], (h1, v1) = pts[i]
            let t = max(0, min(1, (h - h0) / (h1 - h0)))
            return v0 + (v1 - v0) * t
        }
        return 0.3
    }

    var shopOpen: Bool { minute >= Econ.openMinute && !closing }

    func enterProbability() -> Double {
        guard shopOpen else { return 0 }
        var p = 0.045 * priceFactor * ratingFactor * visibility * (0.85 + 0.05 * Double(state.unlockedPizzas.count))
        if queue.count >= 7 { p *= 0.12 } else if queue.count >= 4 { p *= 0.5 }
        if !canBake { p *= 0.15 } else if !interiorPowered { p *= 0.6 }
        return min(0.6, p)
    }

    var walkersPerHour: Double { 120 * hourCurve(minute) }

    var guestsPerHour: Double {
        var g = 0.0
        if state.adsOn.contains("instagram") { g += 2.0 }
        if state.adsOn.contains("billboard") { g += 2.5 }
        if state.adsBought.contains("maps") { g += 1.5 * ratingFactor }
        if state.day <= state.bloggerUntilDay { g += 9 }
        return g * hourCurve(minute) * min(2, 1 / priceIndex)
    }

    var deliveriesPerHour: Double {
        guard state.adsOn.contains("delivery"), canBake else { return 0 }
        return 5.5 * hourCurve(minute) * ratingFactor * pow(1 / priceIndex, 0.8)
    }

    // MARK: frame loop

    @objc private func frame(_ link: CADisplayLink) {
        let now = link.timestamp
        let realDt = lastTimestamp == 0 ? 0 : min(0.1, now - lastTimestamp)
        lastTimestamp = now
        let running = speed > 0 && report == nil && !gameOver && state.started
        if world.showcase != !state.started {
            world.showcase = !state.started
            if state.started { world.resetCamera() }
        }
        let visualDt = running ? realDt * Double(speed) : 0
        if running { step(game: visualDt * Econ.gameSecondsPerRealSecond, visual: Float(visualDt)) }
        world.update(dt: Float(realDt), visualSpeed: Float(running ? speed : 0), World.Ambience(
            minute: minute, interiorPowered: interiorPowered, streetPowered: !outageNow,
            ovenBusy: Float(ovenSlots.compactMap { $0 }.count) / Float(max(1, ovenSlots.count)),
            ovenWorking: canBake && (minute < Econ.closeMinute + 30),
            ovenPizzas: ovenSlots.compactMap { $0 }.count,
            prepping: prepStations(),
            readyBoxes: orders.filter { $0.stage == .ready }.count))
        hudClock += realDt
        if hudClock > 0.25 {
            hudClock = 0
            publishHUD()
        }
    }

    /// Which cook stations have a pizza being assembled right now.
    private func prepStations() -> [Bool] {
        var out = [Bool](repeating: false, count: Spot.cooks.count)
        for w in workers {
            guard case .prepping = w.task, simd_distance(w.pos, w.target) < 0.3 else { continue }
            if let i = Spot.cooks.firstIndex(where: { simd_distance($0, w.station) < 0.05 || simd_distance($0, w.target) < 0.05 }) {
                out[i] = true
            }
        }
        return out
    }

    private func step(game dt: Double, visual vdt: Float) {
        minute += dt / 60
        if minute >= Econ.closeMinute && !closing {
            closing = true
            showToast("22:00 — закрываемся. Обслуживаем тех, кто уже внутри")
        }
        let outage = outageNow
        if outage != wasOutage {
            wasOutage = outage
            if outage {
                showToast(has("generator") ? "Отключение света. Запустили генератор" :
                            (oven.needsPower ? "Отключение света! Печь и свет не работают" : "Отключение света. Дровяная печь работает"))
            } else {
                showToast("Свет дали")
            }
        }

        spawn(dt)
        updateCustomers(dt: dt, vdt: vdt)
        updateWorkers(dt: dt, vdt: vdt)
        updateOven(dt)
        accountEnergy(dt)

        if state.hasCleaner {
            cleanliness = min(1, cleanliness + dt * 0.00035)
        }

        if closing && !dayOver {
            let anyoneInside = customers.contains { $0.isInside }
            let pendingDelivery = orders.contains { $0.isDelivery && $0.stage != .done }
            if (!anyoneInside && !pendingDelivery) || minute > 23.5 * 60 {
                endDay()
            }
        }
    }

    // MARK: spawning

    private func expo(_ perHour: Double) -> Double {
        guard perHour > 0.001 else { return 1e9 }
        return -log(Double.random(in: 0.0001...1)) / (perHour / 3600)
    }

    private func spawn(_ dt: Double) {
        nextWalker -= dt
        if nextWalker <= 0 {
            nextWalker = expo(walkersPerHour)
            spawnWalker(wantsIn: false, kind: .walker)
        }
        if shopOpen {
            nextGuest -= dt
            if nextGuest <= 0 {
                nextGuest = expo(guestsPerHour)
                if guestsPerHour > 0 { spawnWalker(wantsIn: true, kind: .guest) }
            }
            nextDelivery -= dt
            if nextDelivery <= 0 {
                nextDelivery = expo(deliveriesPerHour)
                if deliveriesPerHour > 0 { spawnCourier() }
            }
        }
    }

    private func spawnWalker(wantsIn: Bool, kind: Customer.Kind) {
        let visible = customers.filter { $0.phase == .passing }.count
        let fromLeft = Bool.random()
        var startX = fromLeft ? Spot.leftEnd : Spot.rightEnd
        if visible > 22 {
            // Street is crowded on screen: only show the ones who will actually come in.
            guard wantsIn || Double.random(in: 0...1) < enterProbability() else { return }
            startX = Spot.doorX + (fromLeft ? -7 : 7)
        }
        let p = PersonNode()
        let c = Customer(kind: kind, person: p, pos: SIMD3(startX, 0, Spot.walkZ + Float.random(in: -0.35...0.35)))
        c.wantsIn = wantsIn || visible > 22
        c.path = [SIMD3(fromLeft ? Spot.rightEnd : Spot.leftEnd, 0, c.pos.z)]
        world.add(p, at: c.pos)
        customers.append(c)
    }

    private func spawnCourier() {
        let o = Order(pizza: choosePizza(), isDelivery: true)
        orders.append(o)
        let pizza = Catalog.pizza(o.pizza)
        let gross = state.price(o.pizza) * 1.1   // в сервисе цена выше
        let payout = gross * (1 - Econ.deliveryCommission)
        let ingredients = pizza.cost * state.tier.costMultiplier
        state.money += payout - ingredients - Econ.boxCost
        today.revenue += payout
        today.commission += gross * Econ.deliveryCommission
        today.ingredients += ingredients
        today.packaging += Econ.boxCost
        today.pizzas += 1
        today.deliveryOrders += 1
        world.floatText("Доставка +" + Fmt.money(payout), at: SIMD3(0.6, 2.2, -4.0), color: UIColor(red: 0.5, green: 0.85, blue: 1, alpha: 1), size: 15)

        let fromLeft = Bool.random()
        let p = PersonNode(outfit: .courier)
        let start = SIMD3<Float>(fromLeft ? Spot.leftEnd : Spot.rightEnd, 0, Spot.walkZ)
        let c = Customer(kind: .courier, person: p, pos: start)
        c.speed = 1.7
        c.order = o
        o.customer = c
        c.phase = .entering
        c.enteredAt = clock
        c.path = [Spot.doorOut, Spot.doorIn, SIMD3(0.9, 0, -2.6)]
        world.add(p, at: start)
        customers.append(c)
    }

    private func choosePizza() -> String {
        let menu = Catalog.pizzas.filter { state.unlockedPizzas.contains($0.id) }
        let weights = menu.map { $0.popularity * pow($0.marketPrice / state.price($0.id), 1.2) }
        var r = Double.random(in: 0..<max(0.0001, weights.reduce(0, +)))
        for (i, w) in weights.enumerated() {
            r -= w
            if r <= 0 { return menu[i].id }
        }
        return menu.first?.id ?? "margherita"
    }

    // MARK: customers

    @discardableResult
    private func walk(_ c: Customer, _ vdt: Float) -> Bool {
        guard let target = c.path.first else {
            c.person.animate(dt: vdt, moving: 0, working: false)
            return false
        }
        let d = target - c.pos
        let dist = sqrt(d.x * d.x + d.z * d.z)
        let stepLen = c.speed * vdt
        if dist <= stepLen {
            c.pos = target
            c.path.removeFirst()
        } else {
            c.pos += d / dist * stepLen
        }
        c.person.node.position = SCNVector3(c.pos.x, c.pos.y, c.pos.z)
        if dist > 0.001 { c.person.face(d) }
        c.person.animate(dt: vdt, moving: c.speed, working: false)
        return true
    }

    private func updateCustomers(dt: Double, vdt: Float) {
        for c in customers {
            let moving = walk(c, vdt)
            switch c.phase {
            case .passing:
                if !c.decided && abs(c.pos.x - Spot.doorX) < 0.4 {
                    c.decided = true
                    let p: Double = c.wantsIn ? (shopOpen && queue.count < Spot.queue.count ? 1.0 : 0.0) : enterProbability()
                    if Double.random(in: 0...1) < p, queue.count < Spot.queue.count { enter(c) }
                }
                if !moving && c.phase == .passing { c.phase = .gone }
            case .entering:
                if !moving {
                    if c.kind == .courier { c.phase = .waiting } else { c.phase = .inQueue }
                }
            case .inQueue:
                if !moving, let i = queue.firstIndex(where: { $0 === c }) {
                    c.person.faceToward(i == 0 ? SIMD3<Float>(1.4, 0, -4.5) : Spot.queue[i - 1])
                }
                if clock - c.enteredAt > c.patience {
                    leaveQueue(c)
                }
            case .ordering:
                break
            case .toWait:
                if !moving {
                    c.phase = .waiting
                    c.person.faceToward(SIMD3(0.6, 0, -4))
                }
            case .waiting:
                if let o = c.order, o.stage == .ready {
                    c.phase = .toPickup
                    c.path = [Spot.pickup]
                    if c.waitSpot >= 0 { waitTaken[c.waitSpot] = false; c.waitSpot = -1 }
                }
            case .toPickup:
                if !moving {
                    c.order?.stage = .done
                    c.person.carrying = true
                    if let o = c.order { orders.removeAll { $0 === o } }
                    if c.kind == .courier {
                        c.phase = .leaving
                        c.path = exitPath(from: c.pos)
                    } else if c.dineIn, c.seat >= 0, c.seat < world.seats.count {
                        c.phase = .toSeat
                        let s = world.seats[c.seat]
                        c.path = s.position.z > 0 ? [Spot.doorIn, Spot.doorOut, SIMD3(s.position.x, 0, 1.9), s.position] : [s.position]
                    } else {
                        review(c, dineIn: false)
                        c.phase = .leaving
                        c.path = exitPath(from: c.pos)
                    }
                }
            case .toSeat:
                if !moving, c.seat >= 0, c.seat < world.seats.count {
                    c.phase = .eating
                    c.person.faceToward(world.seats[c.seat].facing)
                    c.person.carrying = false
                    c.person.sit(true)
                    world.setEating(seat: c.seat, true)
                    c.timer = Double.random(in: 900...1500)
                }
            case .eating:
                c.timer -= dt
                if c.timer <= 0 {
                    c.person.sit(false)
                    world.setEating(seat: c.seat, false)
                    review(c, dineIn: true)
                    cleanliness = max(0, cleanliness - 0.035)
                    if c.seat >= 0 && c.seat < seatTaken.count { seatTaken[c.seat] = false }
                    let outside = c.seat >= 0 && c.seat < world.seats.count && world.seats[c.seat].position.z > 0
                    c.seat = -1
                    c.phase = .leaving
                    c.path = outside ? [SIMD3(c.pos.x, 0, 1.9), SIMD3(c.pos.x + 1, 0, Spot.walkZ), awayPoint()] : exitPath(from: c.pos)
                }
            case .leaving:
                if !moving { c.phase = .gone }
            case .gone:
                break
            }
        }
        let gone = customers.filter { $0.phase == .gone }
        if !gone.isEmpty {
            gone.forEach { $0.person.node.removeFromParentNode() }
            customers.removeAll { $0.phase == .gone }
        }
    }

    private func awayPoint() -> SIMD3<Float> {
        SIMD3(Bool.random() ? Spot.leftEnd : Spot.rightEnd, 0, Spot.walkZ + Float.random(in: -0.3...0.3))
    }

    private func exitPath(from p: SIMD3<Float>) -> [SIMD3<Float>] {
        [SIMD3(min(p.x + 0.6, 2.6), 0, -1.2), Spot.doorIn, Spot.doorOut, SIMD3(Spot.doorX + 0.5, 0, Spot.walkZ), awayPoint()]
    }

    private func enter(_ c: Customer) {
        c.phase = .entering
        c.enteredAt = clock
        c.pizza = choosePizza()
        c.paysCard = Double.random(in: 0...1) < Econ.cardShare
        c.patience = Double.random(in: 600...1100) * (c.kind == .guest ? 1.4 : 1)
        queue.append(c)
        let i = queue.count - 1
        c.path = i >= 6 ? [Spot.doorOut, Spot.queue[i]] : [Spot.doorOut, Spot.doorIn, Spot.queue[i]]
        today.guests += 1
    }

    private func leaveQueue(_ c: Customer) {
        queue.removeAll { $0 === c }
        today.lostGuests += 1
        world.floatText("Долго!", at: c.pos + SIMD3(0, 2.0, 0), color: UIColor(red: 1, green: 0.45, blue: 0.35, alpha: 1), size: 15)
        if Double.random(in: 0...1) < 0.25 { state.addReview(Int.random(in: 1...2)) }
        c.phase = .leaving
        c.path = exitPath(from: c.pos)
        reflowQueue()
    }

    private func reflowQueue() {
        for (i, c) in queue.enumerated() where c.phase == .inQueue || c.phase == .entering {
            if c.phase == .inQueue { c.path = [Spot.queue[i]] }
            else if let last = c.path.last, last != Spot.queue[i] {
                c.path = Array(c.path.dropLast()) + [Spot.queue[i]]
            }
        }
    }

    // MARK: workers

    func rebuildStaff() {
        workers.forEach { $0.person.node.removeFromParentNode() }
        workers.removeAll()
        let ownerStation = state.hasCashier ? Spot.cooks[0] : Spot.cashier
        let owner = Worker(role: .owner, skill: 0.9, person: PersonNode(outfit: .apron, seed: 7), station: ownerStation)
        workers.append(owner)
        var cookIndex = state.hasCashier ? 1 : 0
        for def in state.staff.compactMap(Catalog.staffMember) {
            let role: Worker.Role
            let station: SIMD3<Float>
            switch def.role {
            case .cook:
                role = .cook
                station = Spot.cooks[min(cookIndex, Spot.cooks.count - 1)]
                cookIndex += 1
            case .cashier:
                role = .cashier
                station = Spot.cashier
            case .cleaner:
                role = .cleaner
                station = Spot.cleanerRoute[0]
            }
            let outfit: PersonNode.Outfit
            switch def.role {
            case .cleaner: outfit = .cleaner
            case .cashier: outfit = .cashier
            case .cook: outfit = .apron
            }
            let seed = def.id.unicodeScalars.reduce(17) { $0 &* 31 &+ Int($1.value) }
            workers.append(Worker(role: role, skill: def.skill, person: PersonNode(outfit: outfit, seed: seed), station: station))
        }
        for w in workers {
            world.add(w.person, at: w.pos)
            w.person.face(SIMD3(0, 0, -1))
        }
        if state.flyersDay == state.day, promoter == nil {
            let p = PersonNode(outfit: .promoter, seed: 99)
            world.add(p, at: Spot.promoter)
            p.face(SIMD3(-1, 0, 0))
            promoter = p
        } else if state.flyersDay != state.day {
            promoter?.node.removeFromParentNode()
            promoter = nil
        }
    }

    private func takesOrders(_ w: Worker) -> Bool { w.role == .cashier || (w.role == .owner && !state.hasCashier) }
    private func cooksPizza(_ w: Worker) -> Bool { w.role == .cook || w.role == .owner }

    private func updateWorkers(dt: Double, vdt: Float) {
        for w in workers {
            switch w.task {
            case .takingOrder(let c, let left):
                let rest = left - dt
                if rest <= 0 {
                    finishOrder(c)
                    w.task = .idle
                } else {
                    w.task = .takingOrder(c, rest)
                }
            case .prepping(let o, let left):
                let rest = left - dt
                if rest <= 0 {
                    o.stage = .waitingOven
                    w.task = .idle
                } else {
                    w.task = .prepping(o, rest)
                }
            case .idle:
                break
            }

            if w.isIdle {
                if takesOrders(w), let c = queue.first, c.phase == .inQueue, c.path.isEmpty {
                    c.phase = .ordering
                    w.task = .takingOrder(c, (w.role == .cashier ? 45 : 70) / w.skill)
                    w.target = Spot.cashier
                } else if cooksPizza(w), let o = orders.first(where: { $0.stage == .queued }),
                          !(w.role == .owner && !state.hasCashier && queue.first?.phase == .inQueue && queue.first?.path.isEmpty == true) {
                    o.stage = .prepping
                    var speedUp = 1.0
                    if has("prepFridge") { speedUp *= 1.25 }
                    if has("mixer") { speedUp *= 1.18 }
                    w.task = .prepping(o, 300 / (w.skill * speedUp))
                    w.target = w.role == .owner ? (state.hasCashier ? w.station : Spot.cooks[0]) : w.station
                } else if w.role == .cleaner {
                    if simd_distance(w.pos, w.target) < 0.1 {
                        w.route = (w.route + 1) % Spot.cleanerRoute.count
                        w.target = Spot.cleanerRoute[w.route]
                    }
                } else if w.role == .owner && !state.hasCashier {
                    w.target = Spot.cashier
                }
            }

            // Move toward the work spot.
            let d = w.target - w.pos
            let dist = simd_length(d)
            let speed: Float = w.role == .cleaner ? 0.6 : 1.3
            if dist > 0.02 {
                let stepLen = min(dist, speed * vdt)
                w.pos += d / dist * stepLen
                w.person.node.position = SCNVector3(w.pos.x, 0, w.pos.z)
                w.person.face(d)
                w.person.animate(dt: vdt, moving: speed, working: false)
            } else {
                let working: Bool
                switch w.task {
                case .idle: working = w.role == .cleaner
                default: working = true
                }
                if w.role != .cleaner { w.person.face(SIMD3(0, 0, takesOrders(w) && isOrderTask(w) ? 1 : -1)) }
                w.person.animate(dt: vdt, moving: 0, working: working)
            }
        }
        if let p = promoter { p.animate(dt: vdt, moving: 0, working: true) }
    }

    private func isOrderTask(_ w: Worker) -> Bool {
        if case .takingOrder = w.task { return true }
        return w.role == .cashier
    }

    private func finishOrder(_ c: Customer) {
        queue.removeAll { $0 === c }
        reflowQueue()
        // Payment.
        if c.paysCard && !has("terminal") && Double.random(in: 0...1) < 0.6 {
            today.lostGuests += 1
            if Double.random(in: 0...1) < 0.2 { state.addReview(2) }
            c.phase = .leaving
            c.path = exitPath(from: c.pos)
            world.floatText("Нет терминала", at: c.pos + SIMD3(0, 2.0, 0), color: UIColor(red: 1, green: 0.45, blue: 0.35, alpha: 1), size: 14)
            if !hasShownCardHint {
                hasShownCardHint = true
                showToast("Гость хотел оплатить картой, а терминала нет. Ушёл")
            }
            return
        }
        let pizza = Catalog.pizza(c.pizza)
        let price = state.price(c.pizza)
        let freeSeats = seatTaken.indices.filter { $0 < world.seats.count && !seatTaken[$0] && (world.seats[$0].position.z < 0 || minute < 21 * 60) }
        c.dineIn = !freeSeats.isEmpty && Double.random(in: 0...1) < 0.45
        if c.dineIn, let s = freeSeats.randomElement() {
            seatTaken[s] = true
            c.seat = s
        }
        var paid = price
        let ingredients = pizza.cost * state.tier.costMultiplier
        var cost = ingredients
        if !c.dineIn {
            cost += Econ.boxCost
            today.packaging += Econ.boxCost
        }
        if has("coffee") && Double.random(in: 0...1) < 0.3 {
            paid += Econ.coffeePrice
            cost += Econ.coffeeCost
            today.ingredients += Econ.coffeeCost
            today.coffees += 1
        }
        if c.paysCard && has("terminal") {
            let fee = paid * Econ.acquiringRate
            cost += fee
            today.acquiring += fee
        }
        state.money += paid - cost
        today.revenue += paid
        today.ingredients += ingredients
        today.pizzas += 1
        world.floatText("+" + Fmt.money(paid), at: Spot.cashier + SIMD3(0, 2.1, 0.4), color: UIColor(red: 0.45, green: 1, blue: 0.5, alpha: 1))
        Sound.shared.play("cash", volume: 0.5)

        let o = Order(pizza: c.pizza, isDelivery: false)
        o.customer = c
        c.order = o
        orders.append(o)
        if let spot = waitTaken.firstIndex(of: false) {
            waitTaken[spot] = true
            c.waitSpot = spot
            c.path = [Spot.waiting[spot]]
        } else {
            c.path = [SIMD3(Float.random(in: -1.5...0.5), 0, -2.6)]
        }
        c.phase = .toWait
    }

    private var hasShownCardHint = false

    // MARK: kitchen

    func resetOvens() {
        ovenSlots = Array(repeating: nil, count: oven.slots)
    }

    private func updateOven(_ dt: Double) {
        guard canBake else { return }
        for i in ovenSlots.indices {
            guard let o = ovenSlots[i] else { continue }
            o.remaining -= dt
            if o.remaining <= 0 {
                o.stage = .ready
                ovenSlots[i] = nil
            }
        }
        for o in orders where o.stage == .waitingOven {
            guard let free = ovenSlots.firstIndex(where: { $0 == nil }) else { break }
            o.stage = .baking
            o.remaining = oven.bakeMinutes * 60
            ovenSlots[free] = o
        }
    }

    private func accountEnergy(_ dt: Double) {
        let hours = dt / 3600
        let busy = Double(ovenSlots.compactMap { $0 }.count) / Double(max(1, ovenSlots.count))
        var load = oven.kW * (0.35 + 0.45 * busy) + 1.0 + 0.6
        if has("prepFridge") { load += 0.5 }
        if has("coffee") { load += 0.6 }
        if outageNow {
            if has("generator") { fuel += Econ.generatorFuelPerHour * hours }
            today.outageHours += hours
        } else {
            kwh += load * hours
        }
    }

    // MARK: reviews

    private func review(_ c: Customer, dineIn: Bool) {
        let qN = max(0, min(1, (quality - 0.55) / 1.0))
        let waitMin = (clock - c.enteredAt) / 60
        let waitS = max(0, min(1, 1 - (waitMin - 9) / 22))
        let pi = state.price(c.pizza) / Catalog.pizza(c.pizza).marketPrice
        let worth = 0.75 + 0.45 * qN
        let priceS = max(0, min(1, 1 - (pi - worth) * 1.6))
        var amb = dineIn ? 0.55 + (has("renovation") ? 0.25 : 0) + 0.2 * cleanliness : 0.8
        if dineIn && !interiorPowered { amb -= 0.2 }
        let sat = 0.42 * qN + 0.30 * waitS + 0.18 * priceS + 0.10 * amb
        let stars = max(1, min(5, Int((1 + 4 * sat + Double.random(in: -0.6...0.6)).rounded())))
        let chance = state.day <= state.bloggerUntilDay ? 0.55 : 0.33
        if Double.random(in: 0...1) < chance {
            state.addReview(stars)
            let text = String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars)
            let color = stars >= 4 ? UIColor(red: 1, green: 0.85, blue: 0.2, alpha: 1) : (stars == 3 ? UIColor(white: 0.9, alpha: 1) : UIColor(red: 1, green: 0.4, blue: 0.3, alpha: 1))
            world.floatText(text, at: c.pos + SIMD3(0, 2.0, 0), color: color, size: 16)
        }
    }

    // MARK: day cycle

    private func endDay() {
        dayOver = true
        world.clearPlates()
        for c in customers {
            c.person.node.removeFromParentNode()
        }
        customers.removeAll()
        queue.removeAll()
        orders.removeAll()
        resetOvens()
        seatTaken = Array(repeating: false, count: world.seats.count)
        waitTaken = Array(repeating: false, count: Spot.waiting.count)

        var r = today
        r.wages = state.monthlyWages / 30
        r.rent = Econ.rentPerMonth / 30 + (has("terrace") ? Econ.terracePermitPerMonth / 30 : 0)
        var nightKWh = 0.6 * 12
        if has("prepFridge") { nightKWh += 0.5 * 12 }
        r.electricity = (kwh + nightKWh) * Econ.electricityPerKWh
        r.fuel = fuel + (state.oven == "wood" ? Econ.firewoodPerDay : 0)
        r.utilities = Econ.utilitiesPerDay
        if state.adsOn.contains("instagram") { r.ads += 1_200 }
        if state.adsOn.contains("billboard") { r.ads += 800 }
        r.tax = r.revenue * Econ.singleTaxRate + Econ.esvPerDay
        r.rating = state.rating ?? 0
        let fixed = r.wages + r.rent + r.electricity + r.fuel + r.utilities + r.tax
            + (state.adsOn.contains("instagram") ? 1_200 : 0) + (state.adsOn.contains("billboard") ? 800 : 0)
        state.money -= fixed
        state.history.append(r)
        if state.history.count > 90 { state.history.removeFirst(state.history.count - 90) }
        state.bestDayProfit = max(state.bestDayProfit, r.profit)
        state.negativeDays = state.money < 0 ? state.negativeDays + 1 : 0
        report = r
        if state.negativeDays >= 3 { gameOver = true }
        state.save()
    }

    func startNextDay() {
        state.day += 1
        minute = Econ.openMinute - 15
        today = DayReport(day: state.day)
        kwh = 0
        fuel = 0
        cleanliness = 1
        closing = false
        dayOver = false
        nextWalker = 2
        nextGuest = expo(guestsPerHour)
        nextDelivery = expo(max(0.01, deliveriesPerHour))
        rollOutages()
        rebuildStaff()
        state.save()
        report = nil
        if !state.outages.isEmpty {
            showToast("График отключений на сегодня: " + state.outages.map { "\(hm($0.start))–\(hm($0.end))" }.joined(separator: ", "))
        }
    }

    private func rollOutages() {
        state.outages = []
        guard state.day > 2, Double.random(in: 0...1) < 0.4 else { return }
        let count = Double.random(in: 0...1) < 0.3 ? 2 : 1
        var startHour = Double(Int.random(in: 10...14))
        for _ in 0..<count {
            let len = Double(Int.random(in: 2...4))
            state.outages.append(Outage(start: startHour * 60, end: min(23, startHour + len) * 60))
            startHour += len + Double(Int.random(in: 2...4))
            if startHour >= 21 { break }
        }
    }

    func startGame() {
        state.started = true
        speed = 1
        seatTaken = Array(repeating: false, count: world.seats.count)
        state.save()
        showToast("Пиццерия открыта! Нажмите «Меню», чтобы проверить цены")
    }

    func restart() {
        GameState.wipe()
        world.clearPlates()
        for c in customers { c.person.node.removeFromParentNode() }
        customers.removeAll()
        queue.removeAll()
        orders.removeAll()
        state = GameState()
        minute = Econ.openMinute
        today = DayReport(day: 1)
        closing = false
        dayOver = false
        gameOver = false
        report = nil
        world.apply(state)
        rebuildStaff()
        resetOvens()
        seatTaken = Array(repeating: false, count: world.seats.count)
        speed = 0
    }

    // MARK: purchases

    private func pay(_ amount: Double, investment: Bool = true) -> Bool {
        guard state.money >= amount else {
            showToast("Не хватает денег: нужно \(Fmt.money(amount))")
            return false
        }
        Sound.shared.play("coins", volume: 0.7)
        state.money -= amount
        if investment { today.investments += amount }
        return true
    }

    private func changed(staff: Bool = false) {
        world.apply(state)
        if staff { rebuildStaff() }
        if seatTaken.count != world.seats.count {
            let old = seatTaken
            seatTaken = (0..<world.seats.count).map { $0 < old.count ? old[$0] : false }
        }
        state.save()
    }

    func buyOven(_ id: String) {
        let def = Catalog.oven(id)
        guard id != state.oven, pay(def.price) else { return }
        let baking = ovenSlots.compactMap { $0 }
        state.oven = id
        resetOvens()
        for (i, o) in baking.enumerated() where i < ovenSlots.count { ovenSlots[i] = o }
        showToast("Установили: \(def.name)")
        changed()
    }

    func buyEquipment(_ id: String) {
        guard !state.equipment.contains(id), let def = Catalog.equipment.first(where: { $0.id == id }), pay(def.price) else { return }
        state.equipment.insert(id)
        showToast("Куплено: \(def.name)")
        changed()
    }

    func buyBuilding(_ id: String) {
        guard !state.building.contains(id), let def = Catalog.building.first(where: { $0.id == id }), pay(def.price) else { return }
        state.building.insert(id)
        showToast("Готово: \(def.name)")
        changed()
    }

    func buyTable() {
        guard state.tables < state.maxTables, pay(Econ.tablePrice) else { return }
        state.tables += 1
        changed()
    }

    func hire(_ id: String) {
        guard let def = Catalog.staffMember(id), !state.staff.contains(id) else { return }
        let staff = state.staff.compactMap(Catalog.staffMember)
        switch def.role {
        case .cook where staff.filter({ $0.role == .cook }).count >= Econ.maxCooks:
            showToast("На кухне места для двух пиццайоло и вас"); return
        case .cashier where staff.contains(where: { $0.role == .cashier }):
            showToast("Кассир уже есть"); return
        case .cleaner where staff.contains(where: { $0.role == .cleaner }):
            showToast("Уборщица уже есть"); return
        default: break
        }
        state.staff.append(id)
        showToast("\(def.name) выходит на работу. Зарплата \(Fmt.money(def.salary)) в месяц")
        changed(staff: true)
    }

    func fire(_ id: String) {
        state.staff.removeAll { $0 == id }
        changed(staff: true)
    }

    func unlockPizza(_ id: String) {
        let def = Catalog.pizza(id)
        guard !state.unlockedPizzas.contains(id), pay(def.unlockCost) else { return }
        state.unlockedPizzas.insert(id)
        showToast("\(def.name) теперь в меню")
        changed()
    }

    func setPrice(_ id: String, _ value: Double) {
        state.prices[id] = value
    }

    func commitPrices() { changed() }

    func setTier(_ t: IngredientTier) {
        state.tier = t
        state.save()
    }

    func buyAd(_ id: String) {
        guard let def = Catalog.ads.first(where: { $0.id == id }) else { return }
        switch def.kind {
        case .oneTime:
            if id == "maps" && state.adsBought.contains("maps") { return }
            guard pay(def.price, investment: false) else { return }
            today.ads += def.price
            state.adsBought.insert(id)
            if id == "flyers" { state.flyersDay = state.day; rebuildStaff() }
            if id == "blogger" { state.bloggerUntilDay = state.day + 1 }
            showToast("Запущено: \(def.name)")
        case .daily, .toggle:
            if state.adsOn.contains(id) { state.adsOn.remove(id) } else { state.adsOn.insert(id) }
        }
        changed()
    }

    // MARK: debug / screenshots

    /// Sets up a known state for scripted screenshots.
    func debugPreset(upgraded: Bool) {
        for c in customers { c.person.node.removeFromParentNode() }
        customers.removeAll()
        queue.removeAll()
        orders.removeAll()
        world.clearPlates()
        var s = GameState()
        s.started = true
        if upgraded {
            s.day = 12
            s.money = 412_000
            s.oven = "wood"
            s.equipment = ["terminal", "prepFridge", "mixer", "coffee", "generator"]
            s.building = ["sign", "windows", "renovation", "terrace"]
            s.tables = 6
            s.staff = ["andrey", "marco", "katya", "galina"]
            s.unlockedPizzas = Set(Catalog.pizzas.map(\.id))
            s.adsOn = ["billboard", "delivery", "instagram"]
            s.adsBought = ["maps"]
            s.flyersDay = 12
            s.recentReviews = [5, 5, 4, 5, 4, 5, 5, 4, 5, 3, 5, 4]
            s.totalReviews = 214
        } else {
            s.recentReviews = [4, 5, 3, 4]
            s.totalReviews = 4
        }
        state = s
        today = DayReport(day: s.day)
        closing = false
        dayOver = false
        report = nil
        gameOver = false
        world.apply(state)
        promoter?.node.removeFromParentNode()
        promoter = nil
        rebuildStaff()
        resetOvens()
        seatTaken = Array(repeating: false, count: world.seats.count)
        waitTaken = Array(repeating: false, count: Spot.waiting.count)
        speed = 1
    }

    func debugSetTime(_ m: Double) {
        minute = m
    }

    /// Runs the simulation for `seconds` of real time at ×4 without rendering in between.
    func fastForward(seconds: Double) {
        let steps = Int(seconds * 30)
        for _ in 0..<steps {
            let vdt = 1.0 / 30 * 4
            step(game: vdt * Econ.gameSecondsPerRealSecond, visual: Float(vdt))
        }
        publishHUD()
    }

    func debugShowReport() {
        var r = today
        r.revenue = max(r.revenue, 38_450)
        r.pizzas = max(r.pizzas, 168)
        r.guests = max(r.guests, 181)
        r.ingredients = 14_200
        r.packaging = 1_340
        r.acquiring = 310
        r.wages = state.monthlyWages / 30
        r.rent = Econ.rentPerMonth / 30
        r.electricity = 820
        r.fuel = 650
        r.utilities = Econ.utilitiesPerDay
        r.ads = 2_000
        r.tax = r.revenue * Econ.singleTaxRate + Econ.esvPerDay
        r.rating = state.rating ?? 0
        report = r
    }

    // MARK: HUD

    private func hm(_ m: Double) -> String {
        let total = Int(m)
        return String(format: "%02d:%02d", (total / 60) % 24, total % 60)
    }

    private func publishHUD() {
        var h = HUDInfo()
        h.money = state.money
        h.time = hm(minute)
        h.day = state.day
        h.rating = state.rating
        h.reviews = state.totalReviews
        h.queue = queue.count
        h.inside = customers.filter { $0.isInside && $0.kind != .courier }.count
        if let o = state.outages.first(where: { minute < $0.end }) {
            h.outage = outageNow ? "Нет света до \(hm(o.end))" : "Отключение в \(hm(o.start))"
        }
        h.revenueToday = today.revenue
        h.pizzasToday = today.pizzas
        h.lostToday = today.lostGuests
        h.closing = closing
        hud = h
    }

    func showToast(_ text: String) {
        toast = text
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            self?.toast = nil
        }
    }

    func save() { state.save() }

    /// Rough forecast for the finances screen.
    var dailyFixedCosts: Double {
        state.monthlyWages / 30 + Econ.rentPerMonth / 30 + Econ.utilitiesPerDay + Econ.esvPerDay
            + (has("terrace") ? Econ.terracePermitPerMonth / 30 : 0)
            + (state.adsOn.contains("instagram") ? 1_200 : 0) + (state.adsOn.contains("billboard") ? 800 : 0)
    }
}
