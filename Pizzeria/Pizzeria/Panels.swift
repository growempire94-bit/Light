import Charts
import SwiftUI

struct PanelView: View {
    @EnvironmentObject var engine: Engine
    @Environment(\.dismiss) private var dismiss
    let panel: Panel

    var body: some View {
        NavigationStack {
            Group {
                switch panel {
                case .menu: MenuPanel()
                case .kitchen: KitchenPanel()
                case .staff: StaffPanel()
                case .ads: AdsPanel()
                case .hall: HallPanel()
                case .finance: FinancePanel()
                }
            }
            .navigationTitle(panel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text(Fmt.money(engine.state.money)).monospacedDigit().font(.subheadline.weight(.semibold))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

/// Row with a title, description and a trailing action.
struct ShopRow<Trailing: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            trailing
        }
        .padding(.vertical, 2)
    }
}

struct BuyButton: View {
    @EnvironmentObject var engine: Engine
    let price: Double
    var label: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label ?? Fmt.money(price))
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(engine.state.money >= price ? Color.orange : Color.gray.opacity(0.35), in: Capsule())
                .foregroundStyle(engine.state.money >= price ? Color.black : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

struct OwnedTag: View {
    var text = "Есть"
    var body: some View {
        Text(text).font(.caption.weight(.bold)).foregroundStyle(.green)
    }
}

// MARK: - Menu & prices

struct MenuPanel: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        List {
            Section {
                Picker("Продукты", selection: Binding(get: { engine.state.tier }, set: { engine.setTier($0) })) {
                    ForEach(IngredientTier.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(engine.state.tier.detail).font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Продукты")
            }

            Section {
                ForEach(Catalog.pizzas) { p in
                    if engine.state.unlockedPizzas.contains(p.id) {
                        PriceRow(pizza: p)
                    } else {
                        ShopRow(title: p.name, detail: "Средняя цена в городе \(Fmt.money(p.marketPrice)). Нужна проработка рецепта и закупка") {
                            BuyButton(price: p.unlockCost) { engine.unlockPizza(p.id) }
                        }
                    }
                }
            } header: {
                Text("Пиццы и цены")
            } footer: {
                Text("Цены выше рынка отпугивают прохожих и портят отзывы, если качество не дотягивает. Ниже рынка: больше гостей, но меньше маржа.")
            }
        }
        .onDisappear { engine.commitPrices() }
    }
}

struct PriceRow: View {
    @EnvironmentObject var engine: Engine
    let pizza: PizzaDef

    var body: some View {
        let price = engine.state.price(pizza.id)
        let cost = pizza.cost * engine.state.tier.costMultiplier
        let margin = (price - cost) / price
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(pizza.name).font(.subheadline.weight(.semibold))
                Spacer()
                Text(Fmt.money(price)).font(.headline).monospacedDigit()
            }
            Stepper(value: Binding(get: { price }, set: { engine.setPrice(pizza.id, $0) }), in: 90...520, step: 5) {
                Text("Рынок \(Fmt.money(pizza.marketPrice)) · продукты \(Fmt.money(cost)) · маржа \(Fmt.percent(margin))")
                    .font(.caption)
                    .foregroundStyle(margin < 0.5 ? Color.orange : Color.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Kitchen

struct KitchenPanel: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        List {
            Section {
                LabeledContent("Качество пиццы", value: String(format: "%.1f из 10", min(10, engine.quality / 2.2 * 10)))
                LabeledContent("Печь", value: engine.oven.name)
            } footer: {
                Text("Качество зависит от продуктов, печи, мастерства пиццайоло и тестомеса.")
            }

            Section("Печь") {
                ForEach(Catalog.ovens) { o in
                    ShopRow(title: o.name, detail: o.detail) {
                        if engine.state.oven == o.id {
                            OwnedTag(text: "Стоит")
                        } else if o.price == 0 {
                            EmptyView()
                        } else {
                            BuyButton(price: o.price) { engine.buyOven(o.id) }
                        }
                    }
                }
            }

            Section("Оборудование") {
                ForEach(Catalog.equipment) { e in
                    ShopRow(title: e.name, detail: e.detail) {
                        if engine.state.equipment.contains(e.id) {
                            OwnedTag()
                        } else {
                            BuyButton(price: e.price) { engine.buyEquipment(e.id) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Staff

struct StaffPanel: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        List {
            Section {
                ShopRow(title: "Вы, владелец", detail: engine.state.hasCashier ? "Работаете пиццайоло" : "Принимаете заказы и сами готовите") {
                    Text("без зарплаты").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(engine.state.staff.compactMap(Catalog.staffMember)) { s in
                    ShopRow(title: "\(s.name) · \(s.role.title)", detail: "\(Fmt.money(s.salary)) в месяц · \(s.detail)") {
                        Button("Уволить", role: .destructive) { engine.fire(s.id) }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Команда")
            } footer: {
                Text("Фонд оплаты труда: \(Fmt.money(engine.state.monthlyWages)) в месяц, \(Fmt.money(engine.state.monthlyWages / 30)) в день.")
            }

            Section {
                ForEach(Catalog.staff.filter { !engine.state.staff.contains($0.id) }) { s in
                    ShopRow(title: "\(s.name) · \(s.role.title)", detail: "\(Fmt.money(s.salary)) в месяц · \(s.detail)") {
                        Button("Нанять") { engine.hire(s.id) }
                            .font(.caption.weight(.bold))
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                    }
                }
            } header: {
                Text("Кандидаты")
            } footer: {
                Text("Кассир освобождает вас для кухни. Пиццайоло ускоряют выдачу. Уборщица держит зал чистым, гости это замечают.")
            }
        }
    }
}

// MARK: - Ads

struct AdsPanel: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        List {
            Section {
                LabeledContent("Заметность", value: Fmt.percent(engine.visibility))
                LabeledContent("Прохожих сейчас", value: "\(Int(engine.walkersPerHour)) в час")
                LabeledContent("Заходят", value: String(format: "%.1f%%", engine.enterProbability() * 100))
            } footer: {
                Text("Заходят чаще, если вас видно, цены разумные, рейтинг высокий и нет толпы в очереди.")
            }
            Section("Каналы") {
                ForEach(Catalog.ads) { ad in
                    ShopRow(title: ad.name, detail: ad.detail) {
                        switch ad.kind {
                        case .oneTime:
                            if ad.id == "maps" && engine.state.adsBought.contains("maps") {
                                OwnedTag(text: "Работает")
                            } else if ad.id == "flyers" && engine.state.flyersDay == engine.state.day {
                                OwnedTag(text: "Сегодня")
                            } else if ad.id == "blogger" && engine.state.day <= engine.state.bloggerUntilDay {
                                OwnedTag(text: "Идёт")
                            } else {
                                BuyButton(price: ad.price) { engine.buyAd(ad.id) }
                            }
                        case .daily, .toggle:
                            Toggle("", isOn: Binding(get: { engine.state.adsOn.contains(ad.id) }, set: { _ in engine.buyAd(ad.id) }))
                                .labelsHidden()
                                .tint(.orange)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Hall

struct HallPanel: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        List {
            Section {
                ShopRow(title: "Столики: \(engine.state.tables) из \(engine.state.maxTables)",
                        detail: "Стол и два стула \(Fmt.money(Econ.tablePrice)). Около 45% гостей едят на месте") {
                    if engine.state.tables < engine.state.maxTables {
                        BuyButton(price: Econ.tablePrice, label: "+1 стол") { engine.buyTable() }
                    } else {
                        OwnedTag(text: "Мест нет")
                    }
                }
            } header: {
                Text("Зал")
            }
            Section("Помещение") {
                ForEach(Catalog.building) { b in
                    ShopRow(title: b.name, detail: b.detail) {
                        if engine.state.building.contains(b.id) {
                            OwnedTag()
                        } else {
                            BuyButton(price: b.price) { engine.buyBuilding(b.id) }
                        }
                    }
                }
            }
            Section {
                LabeledContent("Аренда", value: "\(Fmt.money(Econ.rentPerMonth)) в месяц")
                LabeledContent("Площадь", value: "60 м², первая линия от тротуара")
            } footer: {
                Text("Аренда, коммуналка, электричество и налоги списываются в конце каждого дня.")
            }
        }
    }
}

// MARK: - Finance

struct FinancePanel: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        let days = Array(engine.state.history.suffix(14))
        List {
            Section("Сегодня") {
                LabeledContent("Выручка", value: Fmt.money(engine.hud.revenueToday))
                LabeledContent("Продано пицц", value: "\(engine.hud.pizzasToday)")
                LabeledContent("Ушли без покупки", value: "\(engine.hud.lostToday)")
                LabeledContent("Постоянные расходы за день", value: Fmt.money(engine.dailyFixedCosts))
            }
            if !days.isEmpty {
                Section("Прибыль по дням") {
                    Chart(days) { d in
                        BarMark(x: .value("День", d.day), y: .value("Прибыль", d.profit))
                            .foregroundStyle(d.profit >= 0 ? Color.green : Color.red)
                    }
                    .frame(height: 160)
                    ForEach(Array(days.reversed())) { d in
                        HStack {
                            Text("День \(d.day)")
                            Spacer()
                            Text("\(d.pizzas) пицц").foregroundStyle(.secondary)
                            Text(Fmt.signed(d.profit))
                                .monospacedDigit()
                                .foregroundStyle(d.profit >= 0 ? Color.green : Color.red)
                                .frame(minWidth: 96, alignment: .trailing)
                        }
                        .font(.subheadline)
                    }
                }
            }
            Section {
                Button("Начать бизнес заново", role: .destructive) { engine.restart() }
            }
        }
    }
}

// MARK: - Overlays

struct IntroView: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.12, green: 0.07, blue: 0.05), Color(red: 0.05, green: 0.05, blue: 0.06)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Своя пиццерия").font(.system(size: 34, weight: .heavy, design: .rounded))
                    Text("Вы арендовали помещение 60 м² на тихой улице в центре Одессы. Аренда \(Fmt.money(Econ.rentPerMonth)) в месяц. На счету \(Fmt.money(Econ.startMoney)) сбережений.")
                    Text("Пока вы один: принимаете заказы и сами печёте в простой электропечи. Каждая пицца стоит денег: продукты, коробка, электричество. В конце дня приходят аренда, налог 5% и зарплаты.")
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Следите за ценами: дорого = мало гостей", systemImage: "tag")
                        Label("Длинная очередь = гости уходят", systemImage: "person.3.sequence")
                        Label("Отзывы решают, сколько людей зайдёт", systemImage: "star")
                        Label("Бывают отключения света по графику", systemImage: "bolt.slash")
                        Label("Три дня подряд в минусе = банкротство", systemImage: "exclamationmark.triangle")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    Text("Покрутите камеру пальцем, щипок — приблизить. Скорость времени — сверху справа.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button {
                        engine.startGame()
                    } label: {
                        Text("Открыть пиццерию")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.orange, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.black)
                    }
                    .padding(.top, 8)
                }
                .padding(24)
            }
        }
    }
}

struct ReportView: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        if let r = engine.report {
            NavigationStack {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Fmt.signed(r.profit))
                                .font(.system(size: 40, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(r.profit >= 0 ? Color.green : Color.red)
                            Text(r.profit >= 0 ? "Чистая прибыль за день" : "Убыток за день").foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        LabeledContent("На счету", value: Fmt.money(engine.state.money))
                        if engine.state.negativeDays > 0 {
                            Text("Счёт в минусе \(engine.state.negativeDays) дн. На третий день пиццерия закроется.")
                                .font(.footnote).foregroundStyle(.red)
                        }
                    }
                    Section("Гости") {
                        LabeledContent("Зашли", value: "\(r.guests)")
                        LabeledContent("Продано пицц", value: "\(r.pizzas)")
                        if r.deliveryOrders > 0 { LabeledContent("Из них доставка", value: "\(r.deliveryOrders)") }
                        if r.coffees > 0 { LabeledContent("Кофе", value: "\(r.coffees)") }
                        LabeledContent("Ушли без покупки", value: "\(r.lostGuests)")
                        LabeledContent("Рейтинг", value: r.rating > 0 ? String(format: "%.1f ★", r.rating) : "нет отзывов")
                        if r.outageHours > 0 { LabeledContent("Без света", value: String(format: "%.0f ч", r.outageHours)) }
                    }
                    Section("Деньги") {
                        line("Выручка", r.revenue, positive: true)
                        line("Продукты", r.ingredients)
                        line("Упаковка", r.packaging)
                        line("Эквайринг", r.acquiring)
                        line("Зарплаты", r.wages)
                        line("Аренда", r.rent)
                        line("Электричество", r.electricity)
                        if r.fuel > 0 { line("Топливо и дрова", r.fuel) }
                        line("Вода, интернет, мусор", r.utilities)
                        if r.ads > 0 { line("Реклама", r.ads) }
                        line("Налог 5% и ЕСВ", r.tax)
                        if r.commission > 0 {
                            Text("Сервис доставки удержал \(Fmt.money(r.commission)) комиссии").font(.caption).foregroundStyle(.secondary)
                        }
                        if r.investments > 0 {
                            Text("Вложения в бизнес сегодня: \(Fmt.money(r.investments)). Они не входят в прибыль").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        Button {
                            engine.startNextDay()
                        } label: {
                            Text("Открыть день \(r.day + 1)")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .navigationTitle("Итоги дня \(r.day)")
            }
        }
    }

    private func line(_ title: String, _ value: Double, positive: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(positive ? Fmt.money(value) : "−" + Fmt.money(value))
                .monospacedDigit()
                .foregroundStyle(positive ? Color.primary : Color.secondary)
        }
    }
}

struct GameOverView: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "door.left.hand.closed").font(.system(size: 56))
            Text("Пиццерия закрылась").font(.title.weight(.heavy))
            Text("Три дня подряд счёт был в минусе. Аренду и зарплаты платить нечем.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if let best = engine.state.history.map(\.profit).max() {
                Text("Лучший день: \(Fmt.signed(best)) · продержались \(engine.state.day) дн.").font(.subheadline)
            }
            Button {
                engine.restart()
            } label: {
                Text("Попробовать снова")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.black)
            }
        }
        .padding(28)
    }
}
