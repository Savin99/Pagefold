import Foundation

/// Русские склонения и человеческие даты — в одном месте,
/// чтобы подписи по всему приложению звучали одинаково.
enum RU {

    /// Выбор формы слова по числу: 1 запись, 2 записи, 5 записей.
    static func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod10 = abs(count) % 10
        let mod100 = abs(count) % 100
        if mod10 == 1 && mod100 != 11 { return one }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
        return many
    }

    static func records(_ count: Int) -> String {
        "\(count) \(plural(count, "запись", "записи", "записей"))"
    }

    static func photos(_ count: Int) -> String {
        "\(count) \(plural(count, "фото", "фото", "фото"))"
    }

    static func words(_ count: Int) -> String {
        "\(count) \(plural(count, "слово", "слова", "слов"))"
    }

    static func notebooks(_ count: Int) -> String {
        "\(count) \(plural(count, "тетрадь", "тетради", "тетрадей"))"
    }
}

/// Даты в подписях: «сегодня, 19:15», «вчера», «25 августа».
enum DateText {

    static func relative(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "сегодня, " + date.formatted(.dateTime.hour().minute())
        }
        if calendar.isDateInYesterday(date) {
            return "вчера, " + date.formatted(.dateTime.hour().minute())
        }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7, days >= 0 {
            return date.formatted(.dateTime.weekday(.wide)) + ", " + date.formatted(.dateTime.hour().minute())
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.day().month(.wide))
        }
        return date.formatted(.dateTime.day().month(.wide).year())
    }

    /// Короткая форма для «брови» карточки: «25 августа».
    static func short(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "сегодня" }
        if calendar.isDateInYesterday(date) { return "вчера" }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.day().month(.wide))
        }
        return date.formatted(.dateTime.day().month(.wide).year())
    }

    static func full(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year())
    }
}

extension String {

    /// Количество слов — для счётчика в редакторе.
    var wordCount: Int {
        split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
            .count
    }

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isBlank: Bool { trimmed.isEmpty }
}
