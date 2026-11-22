import Foundation

struct Outage: Codable, Equatable {
    var start: Double   // minute of day
    var end: Double
}

struct DayReport: Codable, Identifiable {
    var day: Int
    var revenue: Double = 0          // всё, что получили (зал + доставка после комиссии + кофе)
    var pizzas: Int = 0
    var deliveryOrders: Int = 0
    var coffees: Int = 0
    var guests: Int = 0
    var lostGuests: Int = 0          // ушли из очереди или не смогли оплатить
    var ingredients: Double = 0
    var packaging: Double = 0
    var acquiring: Double = 0
    var commission: Double = 0
    var wages: Double = 0
    var rent: Double = 0
    var electricity: Double = 0
    var fuel: Double = 0
    var utilities: Double = 0
    var ads: Double = 0
    var tax: Double = 0
    var investments: Double = 0      // покупки оборудования, ремонт (не входят в прибыль)
    var rating: Double = 0
    var outageHours: Double = 0

    var id: Int { day }
    var expenses: Double {
        ingredients + packaging + acquiring + wages + rent + electricity + fuel + utilities + ads + tax
    }
    /// Деньги за доставку приходят уже за вычетом комиссии, поэтому комиссия здесь только для справки.
    var profit: Double { revenue - expenses }
}

struct GameState: Codable {
    var money: Double = Econ.startMoney
    var day: Int = 1
    var started = false
    var oven = "convection"
    var equipment: Set<String> = []
    var building: Set<String> = []
    var tables: Int = Econ.baseTables
    var staff: [String] = []
    var unlockedPizzas: Set<String> = ["margherita", "pepperoni"]
    var prices: [String: Double] = [:]
    var tier: IngredientTier = .standard
    var adsOn: Set<String> = []
    var adsBought: Set<String> = []
    var flyersDay: Int = -100
    var bloggerUntilDay: Int = 0
    var recentReviews: [Int] = []
    var totalReviews: Int = 0
    var history: [DayReport] = []
    var outages: [Outage] = []
    var negativeDays = 0
    var bestDayProfit: Double = 0

    func price(_ pizzaID: String) -> Double {
        prices[pizzaID] ?? Catalog.pizza(pizzaID).marketPrice
    }

    var rating: Double? {
        guard !recentReviews.isEmpty else { return nil }
        return Double(recentReviews.reduce(0, +)) / Double(recentReviews.count)
    }

    var cooks: [StaffDef] { staff.compactMap(Catalog.staffMember).filter { $0.role == .cook } }
    var hasCashier: Bool { staff.compactMap(Catalog.staffMember).contains { $0.role == .cashier } }
    var hasCleaner: Bool { staff.compactMap(Catalog.staffMember).contains { $0.role == .cleaner } }
    var monthlyWages: Double { staff.compactMap(Catalog.staffMember).reduce(0) { $0 + $1.salary } }

    var maxTables: Int { building.contains("renovation") ? Econ.maxTablesRenovated : Econ.maxTablesInside }
    var totalTables: Int { tables + (building.contains("terrace") ? Econ.terraceTables : 0) }

    mutating func addReview(_ stars: Int) {
        recentReviews.append(stars)
        if recentReviews.count > 150 { recentReviews.removeFirst(recentReviews.count - 150) }
        totalReviews += 1
    }

    // MARK: persistence

    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pizzeria-save.json")
    }

    static func load() -> GameState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GameState.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: GameState.url, options: .atomic)
        }
    }

    static func wipe() {
        try? FileManager.default.removeItem(at: url)
    }
}
