import SwiftUI

/// Дизайн-система «переплётная мастерская»: прохладная бумага, чернила,
/// тканевые обложки, сургучный акцент. Все цвета адаптивны к тёмной теме.
enum Theme {

    // MARK: Бумага и чернила

    /// Фон экрана — бумага.
    static let paper = adaptive(0xF1EFE8, 0x101216)
    /// Более глубокий тон бумаги: подложка под страницами, «стол».
    static let paperDeep = adaptive(0xE6E2D7, 0x0A0C10)
    /// Сама страница — тёплый белый.
    static let surface = adaptive(0xFFFDF8, 0x232830)
    /// Второй уровень поверхности: панели, чипсы, поля ввода.
    static let surfaceAlt = adaptive(0xF8F6F0, 0x2B313B)

    static let ink = adaptive(0x21242C, 0xECEDEF)
    static let inkSecondary = adaptive(0x6F7480, 0x9BA0AB)
    static let inkTertiary = adaptive(0xA5A8B1, 0x6C7280)

    static let hairline = adaptive(0xE0DDD3, 0x363C47)
    /// Обрез страничного блока — чуть темнее волосяной линии.
    static let pageEdge = adaptive(0xD8D4C8, 0x3A404B)

    /// Чернильный акцент — навигация, ссылки, ИИ.
    static let accent = adaptive(0x334FAF, 0x8AA2F2)
    /// Сургуч — подтверждающие и опасные действия, запись голоса.
    static let wax = adaptive(0x9A3A31, 0xC9695B)
    /// Зелень аптечного стекла — успешные состояния.
    static let sage = adaptive(0x3E6B4E, 0x74B08A)

    static let foldFlap = adaptive(0xEBE8E0, 0x272B33)

    /// Слоновая кость — текст на тканевых обложках.
    static let ivory = Color(hex: 0xF3F1EA)

    // MARK: Тканевые обложки тетрадей

    static let covers: [Color] = [
        Color(hex: 0x35406B), // индиго
        Color(hex: 0x3E5747), // хвоя
        Color(hex: 0x8A5A44), // глина
        Color(hex: 0x5C4460), // слива
        Color(hex: 0x4A6470), // сланец
        Color(hex: 0x8F7134), // охра
        Color(hex: 0x6B3F4A), // вино
        Color(hex: 0x3E4553), // графит
    ]

    /// Названия тонов — для VoiceOver и выбора обложки.
    static let coverNames = [
        "индиго", "хвоя", "глина", "слива", "сланец", "охра", "вино", "графит",
    ]

    static func cover(at index: Int) -> Color {
        covers[((index % covers.count) + covers.count) % covers.count]
    }

    static func coverName(at index: Int) -> String {
        coverNames[((index % coverNames.count) + coverNames.count) % coverNames.count]
    }

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

// MARK: - Типографика

/// Шрифтовая шкала. Везде — семантические стили, поэтому текст
/// честно тянется вместе с Dynamic Type.
enum Typo {
    /// «Pagefold» на полке.
    static let display = Font.system(.largeTitle, design: .serif).weight(.bold)
    /// Заголовок открытой страницы.
    static let pageTitle = Font.system(.title, design: .serif).weight(.bold)
    /// Заголовок карточки в ленте.
    static let cardTitle = Font.system(.title2, design: .serif).weight(.semibold)
    /// Заголовок карточки с обложкой — на строку ниже.
    static let cardTitleTight = Font.system(.title3, design: .serif).weight(.semibold)
    /// Название на тканевой обложке.
    static let coverTitle = Font.system(.headline, design: .serif).weight(.semibold)
    /// Основной текст записи.
    static let body = Font.system(.body, design: .serif)
    /// Отрывок текста в ленте.
    static let excerpt = Font.system(.subheadline, design: .serif)
    /// Капительная «бровь» над заголовком.
    static let eyebrow = Font.caption.smallCaps()
    /// Мелкая капитель — счётчики, подписи.
    static let micro = Font.caption2.smallCaps()
    /// Подзаголовок экрана.
    static let subtitle = Font.subheadline.smallCaps()
}

// MARK: - Отступы

/// Единая сетка отступов.
enum Space {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 22
    static let xl: CGFloat = 30
    /// Боковые поля экрана.
    static let screen: CGFloat = 20
}

// MARK: - Тактильная отдача

/// Короткие обёртки над haptics — чтобы не плодить генераторы по вьюхам.
enum Haptics {
    @MainActor static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @MainActor static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
    }

    @MainActor static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @MainActor static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

// MARK: - Цвета из hex

extension Color {
    init(hex: UInt32) {
        self.init(UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
