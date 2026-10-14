// Внешность, характер и готовые коты. Всё это сохраняется в настройках macOS.

import AppKit

struct RGBA: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init(hex: UInt32) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    init(cg: CGColor) {
        let c = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) ?? .black
        self.init(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
    }

    var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

enum FurPattern: String, Codable, CaseIterable, Identifiable {
    case solid, stripes, spots, tuxedo, calico, pointed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .solid: return "Однотонный"
        case .stripes: return "Полоски"
        case .spots: return "Пятнышки"
        case .tuxedo: return "Смокинг"
        case .calico: return "Трёхцветный"
        case .pointed: return "Сиамский"
        }
    }
}

enum EarStyle: String, Codable, CaseIterable, Identifiable {
    case pointy, round, folded
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pointy: return "Острые"
        case .round: return "Круглые"
        case .folded: return "Вислоухие"
        }
    }
}

enum BodySize: String, Codable, CaseIterable, Identifiable {
    case kitten, normal, chubby
    var id: String { rawValue }
    var title: String {
        switch self {
        case .kitten: return "Котёнок"
        case .normal: return "Обычный"
        case .chubby: return "Толстячок"
        }
    }
    var scale: CGFloat {
        switch self {
        case .kitten: return 0.8
        case .normal: return 1
        case .chubby: return 1.05
        }
    }
    var widthFactor: CGFloat { self == .chubby ? 1.2 : 1 }
    var heightFactor: CGFloat { self == .chubby ? 1.1 : 1 }
    var headFactor: CGFloat { self == .kitten ? 1.15 : 1 }
}

enum Accessory: String, Codable, CaseIterable, Identifiable {
    case none, bow, collar, hat, glasses, crown, scarf
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "Без аксессуара"
        case .bow: return "Бантик"
        case .collar: return "Ошейник с колокольчиком"
        case .hat: return "Праздничный колпак"
        case .glasses: return "Очки"
        case .crown: return "Корона"
        case .scarf: return "Шарф"
        }
    }
}

// Насколько охотно кот делает то или иное, когда сам решает, чем заняться
struct Traits {
    let speed: CGFloat
    let walk: Double
    let sleep: Double
    let hop: Double
    let windowJump: Double
    let climb: Double
    let approach: Double
    let idle: Double
    let idleTime: ClosedRange<Double>
    let sleepTime: ClosedRange<Double>
    let hungerMinutes: Double
    let hissChance: Double
    let hearts: Int
}

struct Phrases {
    let greet: String
    let pet: [String]
    let wake: [String]
    let hungry: [String]
    let eat: [String]
    let drag: [String]
    let approach: [String]
    let hiss: [String]
}

enum Personality: String, Codable, CaseIterable, Identifiable {
    case playful, lazy, curious, affectionate, grumpy
    var id: String { rawValue }

    var title: String {
        switch self {
        case .playful: return "Игривый"
        case .lazy: return "Ленивый"
        case .curious: return "Любопытный"
        case .affectionate: return "Ласковый"
        case .grumpy: return "Ворчун"
        }
    }

    var summary: String {
        switch self {
        case .playful: return "Носится, прыгает по окнам и лазает по стенам."
        case .lazy: return "Много спит и ходит не спеша."
        case .curious: return "Всё исследует и часто приходит посмотреть, что ты делаешь."
        case .affectionate: return "Приходит к тебе, мурлычет и дарит сердечки."
        case .grumpy: return "Любит покой. Если приставать — может зашипеть."
        }
    }

    var traits: Traits {
        switch self {
        case .playful:
            return Traits(speed: 1.5, walk: 3, sleep: 0.4, hop: 2, windowJump: 2.5, climb: 2, approach: 0.6, idle: 0.5,
                          idleTime: 1...3, sleepTime: 8...15, hungerMinutes: 12, hissChance: 0, hearts: 3)
        case .lazy:
            return Traits(speed: 0.6, walk: 1.5, sleep: 4, hop: 0.2, windowJump: 0.3, climb: 0.2, approach: 0.3, idle: 2,
                          idleTime: 4...9, sleepTime: 30...70, hungerMinutes: 20, hissChance: 0, hearts: 2)
        case .curious:
            return Traits(speed: 1.1, walk: 3, sleep: 1, hop: 0.8, windowJump: 2, climb: 1.5, approach: 1.5, idle: 1,
                          idleTime: 2...4, sleepTime: 10...20, hungerMinutes: 15, hissChance: 0, hearts: 3)
        case .affectionate:
            return Traits(speed: 1, walk: 2, sleep: 1.2, hop: 0.6, windowJump: 0.8, climb: 0.5, approach: 3, idle: 1,
                          idleTime: 2...5, sleepTime: 12...25, hungerMinutes: 15, hissChance: 0, hearts: 6)
        case .grumpy:
            return Traits(speed: 0.9, walk: 2, sleep: 2, hop: 0.3, windowJump: 1, climb: 0.8, approach: 0.1, idle: 2,
                          idleTime: 3...7, sleepTime: 15...35, hungerMinutes: 10, hissChance: 0.4, hearts: 1)
        }
    }

    var phrases: Phrases {
        switch self {
        case .playful:
            return Phrases(
                greet: "Привет! Я {name}, давай играть!",
                pet: ["Ещё! Ещё!", "Давай играть!", "Мяу! 🐾", "Догони меня!", "Ура-ура!"],
                wake: ["А? Что? Играем?", "Я уже не сплю!"],
                hungry: ["Есть хочу! Срочно! 🐟", "Покорми меня, и побежим дальше!"],
                eat: ["Ням-ням! 🐟 Побежали!", "Вкуснятина!"],
                drag: ["Ура, полёт!", "Выше! Выше!"],
                approach: ["Поиграешь со мной?", "Я тут! 🐾"],
                hiss: []
            )
        case .lazy:
            return Phrases(
                greet: "Привет… Я {name}… можно я посплю?",
                pet: ["Мрр… ещё чуть-чуть", "Хорошо-о-о…", "Только не буди…", "Мур…"],
                wake: ["Ну зачем…", "Ещё пять минуточек…"],
                hungry: ["Покорми… и я посплю 🐟", "Есть хочется… но вставать лень"],
                eat: ["Ням… теперь можно и поспать", "Спасибо… зевает"],
                drag: ["Эй, я же отдыхаю…", "Неси аккуратно…"],
                approach: ["Ты тут… хорошо", "Полежу рядом"],
                hiss: []
            )
        case .curious:
            return Phrases(
                greet: "Привет! Я {name}. А что тут у тебя?",
                pet: ["А что ты делаешь?", "Мяу? Что это?", "Интересно!", "Покажи ещё!"],
                wake: ["Что случилось? Что?", "Я что-то пропустил{а}?"],
                hungry: ["А что у нас на ужин? 🐟", "Чем это так вкусно пахнет?"],
                eat: ["Ням! А что ещё есть?", "Вкусно! А добавка?"],
                drag: ["Ого, как высоко!", "А куда мы?"],
                approach: ["Что ты там делаешь?", "Можно посмотреть?"],
                hiss: []
            )
        case .affectionate:
            return Phrases(
                greet: "Привет! Я {name}, я по тебе скучаю ❤",
                pet: ["Я тебя люблю ❤", "Мур-мур-мур", "Ты самый лучший!", "Не уходи!", "Ещё обнимашек ❤"],
                wake: ["Мрр… ты здесь ❤", "Это был поцелуйчик? ❤"],
                hungry: ["Покормишь меня? ❤", "Я проголодал{ся}… 🐟"],
                eat: ["Спасибо! Ты лучший ❤", "Ням-ням! Люблю тебя ❤"],
                drag: ["Обнимашки!", "На ручки ❤"],
                approach: ["Ты тут? ❤", "Можно к тебе?", "Соскучил{ся}!"],
                hiss: []
            )
        case .grumpy:
            return Phrases(
                greet: "Ну привет. Я {name}.",
                pet: ["Ну ладно, можно", "Хватит уже", "Я не мурлычу. Почти.", "Ладно, ещё раз"],
                wake: ["Кто посмел?!", "Я только уснул{а}!"],
                hungry: ["Где. Моя. Еда.", "Миска пустая. Опять."],
                eat: ["Сойдёт.", "Могло быть и вкуснее"],
                drag: ["Поставь. Немедленно.", "Это возмутительно!"],
                approach: ["Ну чего тебе?", "Просто проверяю"],
                hiss: ["Ш-ш-ш!", "Фр-р-р! Не трогай!", "Ш-ш-ш! Я занят{а}!"]
            )
        }
    }
}

struct CatLook: Codable, Equatable {
    var fur: RGBA
    var pattern: FurPattern
    var patternColor: RGBA
    var belly: RGBA
    var eyes: RGBA
    var ears: EarStyle
    var size: BodySize
    var tail: Double
    var accessory: Accessory
    var accessoryColor: RGBA
}

struct CatConfig: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var female: Bool
    var personality: Personality
    var look: CatLook

    // Подставляет имя и окончания по полу: {а} — «уснул/уснула», {ся} — «проголодался/проголодалась»
    func line(_ text: String) -> String {
        text.replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{а}", with: female ? "а" : "")
            .replacingOccurrences(of: "{ся}", with: female ? "ась" : "ся")
    }

    // Копия с новым id — чтобы можно было завести двух одинаковых котов
    func copy() -> CatConfig {
        var c = self
        c.id = UUID()
        return c
    }
}

enum Presets {
    static let murka = CatConfig(
        id: UUID(), name: "Мурка", female: true, personality: .playful,
        look: CatLook(fur: RGBA(hex: 0xFA9E45), pattern: .stripes, patternColor: RGBA(hex: 0xD96E24),
                      belly: RGBA(hex: 0xFFD9B0), eyes: RGBA(hex: 0x6BBF59), ears: .pointy, size: .normal,
                      tail: 1, accessory: .none, accessoryColor: RGBA(hex: 0xFF5C8A))
    )
    static let ugolek = CatConfig(
        id: UUID(), name: "Уголёк", female: false, personality: .curious,
        look: CatLook(fur: RGBA(hex: 0x2B2B30), pattern: .solid, patternColor: RGBA(hex: 0x1A1A1E),
                      belly: RGBA(hex: 0x3C3C43), eyes: RGBA(hex: 0xF2C230), ears: .pointy, size: .normal,
                      tail: 1.15, accessory: .collar, accessoryColor: RGBA(hex: 0xE23B3B))
    )
    static let snezhok = CatConfig(
        id: UUID(), name: "Снежок", female: false, personality: .affectionate,
        look: CatLook(fur: RGBA(hex: 0xF7F7F7), pattern: .solid, patternColor: RGBA(hex: 0xE6E6E6),
                      belly: RGBA(hex: 0xFFFFFF), eyes: RGBA(hex: 0x6EB8FF), ears: .round, size: .kitten,
                      tail: 0.9, accessory: .bow, accessoryColor: RGBA(hex: 0xFF7EB3))
    )
    static let sima = CatConfig(
        id: UUID(), name: "Сима", female: true, personality: .lazy,
        look: CatLook(fur: RGBA(hex: 0xF2E3C9), pattern: .pointed, patternColor: RGBA(hex: 0x5A3E2B),
                      belly: RGBA(hex: 0xFAF1E0), eyes: RGBA(hex: 0x4FA3FF), ears: .pointy, size: .normal,
                      tail: 1.2, accessory: .none, accessoryColor: RGBA(hex: 0x4FA3FF))
    )
    static let baron = CatConfig(
        id: UUID(), name: "Барон", female: false, personality: .grumpy,
        look: CatLook(fur: RGBA(hex: 0x8E949C), pattern: .solid, patternColor: RGBA(hex: 0x767C84),
                      belly: RGBA(hex: 0xA3A9B0), eyes: RGBA(hex: 0xE89A2E), ears: .folded, size: .chubby,
                      tail: 0.8, accessory: .glasses, accessoryColor: RGBA(hex: 0x333333))
    )
    static let pyatnashka = CatConfig(
        id: UUID(), name: "Пятнашка", female: true, personality: .affectionate,
        look: CatLook(fur: RGBA(hex: 0xFFFFFF), pattern: .calico, patternColor: RGBA(hex: 0xE8913A),
                      belly: RGBA(hex: 0xFFFFFF), eyes: RGBA(hex: 0x8BC34A), ears: .pointy, size: .normal,
                      tail: 1, accessory: .crown, accessoryColor: RGBA(hex: 0xF5C542))
    )

    static let all: [CatConfig] = [murka, ugolek, snezhok, sima, baron, pyatnashka]
}

enum CatStore {
    static let key = "cats.v1"

    static func load() -> [CatConfig] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cats = try? JSONDecoder().decode([CatConfig].self, from: data),
              !cats.isEmpty
        else { return [Presets.murka.copy()] }
        return cats
    }

    static func save(_ cats: [CatConfig]) {
        if let data = try? JSONEncoder().encode(cats) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
