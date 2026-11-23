import Foundation

/// All economic constants, in hryvnias. Numbers are close to a small pizzeria
/// in Odesa: rent for ~60 m², commercial electricity tariff, FOP (3rd group) tax, etc.
enum Econ {
    static let startMoney: Double = 250_000
    static let openMinute: Double = 10 * 60
    static let closeMinute: Double = 22 * 60
    /// Game seconds per real second at speed ×1 (a 12-hour day lasts 24 real minutes).
    static let gameSecondsPerRealSecond: Double = 30

    static let rentPerMonth: Double = 38_000
    static let terracePermitPerMonth: Double = 6_000
    static let utilitiesPerDay: Double = 260          // вода, вывоз мусора, интернет
    static let electricityPerKWh: Double = 9.6         // коммерческий тариф
    static let singleTaxRate: Double = 0.05            // единый налог ФОП 3 группы
    static let esvPerDay: Double = 1_902.34 / 30       // ЕСВ
    static let boxCost: Double = 14                    // коробка на вынос
    static let acquiringRate: Double = 0.013           // комиссия банка за карту
    static let cardShare: Double = 0.62                // гости, которые платят картой
    static let deliveryCommission: Double = 0.30       // сервис доставки
    static let generatorFuelPerHour: Double = 2.4 * 58 // литры в час × цена литра
    static let firewoodPerDay: Double = 650
    static let coffeePrice: Double = 55
    static let coffeeCost: Double = 14
    static let tablePrice: Double = 7_800
    static let baseTables = 2
    static let maxTablesInside = 5
    static let maxTablesRenovated = 6
    static let terraceTables = 3
    static let maxCooks = 2
}

struct PizzaDef: Identifiable {
    let id: String
    let name: String
    let marketPrice: Double   // средняя цена такой пиццы 30 см в городе
    let cost: Double          // продукты на одну пиццу (стандартные)
    let unlockCost: Double    // проработка рецепта, закупка, тестовые выпечки
    let popularity: Double
}

enum IngredientTier: Int, CaseIterable, Codable {
    case economy, standard, premium

    var title: String {
        switch self {
        case .economy: return "Эконом"
        case .standard: return "Стандарт"
        case .premium: return "Премиум"
        }
    }
    var detail: String {
        switch self {
        case .economy: return "Сырный продукт, дешёвая колбаса. Себестоимость −20%, качество заметно ниже"
        case .standard: return "Обычная моцарелла и нормальные продукты"
        case .premium: return "Итальянская мука, фиор ди латте, томаты San Marzano. Себестоимость +35%"
        }
    }
    var costMultiplier: Double { [0.8, 1.0, 1.35][rawValue] }
    var quality: Double { [0.72, 1.0, 1.28][rawValue] }
}

struct OvenDef: Identifiable {
    let id: String
    let name: String
    let price: Double
    let slots: Int
    let bakeMinutes: Double
    let kW: Double
    let quality: Double
    let needsPower: Bool
    let detail: String
}

struct ItemDef: Identifiable {
    let id: String
    let name: String
    let price: Double
    let detail: String
}

enum StaffRole: String, Codable {
    case cook, cashier, cleaner

    var title: String {
        switch self {
        case .cook: return "Пиццайоло"
        case .cashier: return "Кассир"
        case .cleaner: return "Уборка"
        }
    }
}

struct StaffDef: Identifiable {
    let id: String
    let name: String
    let role: StaffRole
    let salary: Double   // в месяц
    let skill: Double
    let detail: String
}

enum AdKind {
    case oneTime, daily, toggle
}

struct AdDef: Identifiable {
    let id: String
    let name: String
    let kind: AdKind
    let price: Double     // разово или в день
    let detail: String
}

enum Catalog {
    static let pizzas: [PizzaDef] = [
        PizzaDef(id: "margherita", name: "Маргарита", marketPrice: 195, cost: 58, unlockCost: 0, popularity: 1.0),
        PizzaDef(id: "pepperoni", name: "Пепперони", marketPrice: 235, cost: 82, unlockCost: 0, popularity: 1.3),
        PizzaDef(id: "ham", name: "Ветчина и грибы", marketPrice: 225, cost: 76, unlockCost: 5_000, popularity: 0.9),
        PizzaDef(id: "cheese", name: "Четыре сыра", marketPrice: 265, cost: 104, unlockCost: 6_000, popularity: 0.8),
        PizzaDef(id: "bbq", name: "Барбекю с курицей", marketPrice: 245, cost: 88, unlockCost: 6_500, popularity: 1.0),
        PizzaDef(id: "diavola", name: "Дьявола", marketPrice: 249, cost: 86, unlockCost: 6_000, popularity: 0.7),
    ]

    static let ovens: [OvenDef] = [
        OvenDef(id: "convection", name: "Конвекционная электропечь", price: 0, slots: 2, bakeMinutes: 8,
                kW: 6, quality: 0.8, needsPower: true,
                detail: "2 пиццы за раз, 8 минут. Корж сухой, бортик бледный"),
        OvenDef(id: "deck", name: "Подовая печь, 2 камеры", price: 145_000, slots: 4, bakeMinutes: 6,
                kW: 12, quality: 1.0, needsPower: true,
                detail: "4 пиццы за раз, 6 минут, камень в поду. Потребляет 12 кВт"),
        OvenDef(id: "wood", name: "Дровяная неаполитанская печь", price: 420_000, slots: 4, bakeMinutes: 1.5,
                kW: 0, quality: 1.3, needsPower: false,
                detail: "485 °C, пицца за 90 секунд. Работает без света. Дрова ≈ ₴650 в день"),
    ]

    static let equipment: [ItemDef] = [
        ItemDef(id: "terminal", name: "Кассовый терминал и эквайринг", price: 9_000,
                detail: "62% гостей платят картой. Без терминала часть из них уходит. Комиссия банка 1,3%"),
        ItemDef(id: "prepFridge", name: "Холодильный стол для пиццы", price: 48_000,
                detail: "Всё под рукой: пиццайоло собирают пиццу на 25% быстрее"),
        ItemDef(id: "mixer", name: "Спиральный тестомес", price: 32_000,
                detail: "Ещё на 18% быстрее, тесто стабильнее, качество выше"),
        ItemDef(id: "coffee", name: "Кофемашина", price: 55_000,
                detail: "30% гостей берут кофе за ₴55, себестоимость ₴14"),
        ItemDef(id: "generator", name: "Генератор 7 кВт", price: 68_000,
                detail: "Работаете при отключениях света. Топливо ≈ ₴140 в час работы"),
    ]

    static let staff: [StaffDef] = [
        StaffDef(id: "oleg", name: "Олег", role: .cook, salary: 24_000, skill: 0.85, detail: "Стажёр, полгода опыта"),
        StaffDef(id: "andrey", name: "Андрей", role: .cook, salary: 29_000, skill: 1.05, detail: "Пиццайоло, 3 года в сетевой пиццерии"),
        StaffDef(id: "marco", name: "Марко", role: .cook, salary: 48_000, skill: 1.35, detail: "Неаполитанец, работал в Италии"),
        StaffDef(id: "katya", name: "Катя", role: .cashier, salary: 19_000, skill: 1.0, detail: "Кассир-бариста, быстро принимает заказы"),
        StaffDef(id: "galina", name: "Галина Петровна", role: .cleaner, salary: 13_500, skill: 1.0, detail: "Чистый зал и посуда весь день"),
    ]

    static let ads: [AdDef] = [
        AdDef(id: "flyers", name: "Листовки и промоутер", kind: .oneTime, price: 4_500,
              detail: "1000 листовок у входа. +40% заметности, эффект уходит за 3 дня"),
        AdDef(id: "maps", name: "Профиль на картах с фото", kind: .oneTime, price: 3_500,
              detail: "Навсегда +20% заметности и гости, которые ищут пиццу рядом. Важен рейтинг"),
        AdDef(id: "instagram", name: "Таргет в Instagram", kind: .daily, price: 1_200,
              detail: "₴1 200 в день, пока включено: +25% заметности и гости по рекламе"),
        AdDef(id: "billboard", name: "Билборд на перекрёстке", kind: .daily, price: 800,
              detail: "₴24 000 в месяц: +30% заметности и гости с района"),
        AdDef(id: "delivery", name: "Сервис доставки", kind: .toggle, price: 0,
              detail: "Курьеры забирают заказы. Сервис берёт 30% с каждого заказа"),
        AdDef(id: "blogger", name: "Обзор у фуд-блогера", kind: .oneTime, price: 15_000,
              detail: "2 дня наплыва гостей. Если пицца так себе, полетят плохие отзывы"),
    ]

    static let building: [ItemDef] = [
        ItemDef(id: "sign", name: "Световая вывеска", price: 28_000,
                detail: "Вас видно с улицы: +30% заметности днём, +60% вечером"),
        ItemDef(id: "windows", name: "Оклейка витрины", price: 12_000,
                detail: "Меню и фото пиццы на стекле: +10% заметности"),
        ItemDef(id: "renovation", name: "Ремонт зала", price: 95_000,
                detail: "Паркет, кирпичная стена, подвесные лампы, деревянные стулья, растения. Гостям приятнее, +1 место под стол"),
        ItemDef(id: "terrace", name: "Летняя терраса", price: 55_000,
                detail: "3 столика на улице. Разрешение ₴6 000 в месяц"),
    ]

    static func pizza(_ id: String) -> PizzaDef { pizzas.first { $0.id == id } ?? pizzas[0] }
    static func oven(_ id: String) -> OvenDef { ovens.first { $0.id == id } ?? ovens[0] }
    static func staffMember(_ id: String) -> StaffDef? { staff.first { $0.id == id } }
}
