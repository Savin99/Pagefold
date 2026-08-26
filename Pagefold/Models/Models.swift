import Foundation
import SwiftData
import SwiftUI

/// Папка-проект — верхний уровень иерархии дневника.
@Model
final class Folder {
    var name: String
    var createdAt: Date
    var colorIndex: Int
    /// Позиция на полке: пользователь может переставлять тетради.
    var sortIndex: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \Card.folder)
    var cards: [Card] = []

    init(name: String, colorIndex: Int, sortIndex: Int = 0) {
        self.name = name
        self.createdAt = .now
        self.colorIndex = colorIndex
        self.sortIndex = sortIndex
    }

    /// Карточки в порядке роадмапа.
    var orderedCards: [Card] {
        cards.sorted { $0.order < $1.order }
    }

    /// Когда в тетради последний раз что-то менялось.
    var lastActivityAt: Date {
        cards.map(\.updatedAt).max() ?? createdAt
    }

    /// Заполненные записи — для подписи «3 из 6 начаты».
    var filledCardsCount: Int {
        cards.filter { !$0.isBlank }.count
    }
}

/// Карточка-запись внутри папки.
@Model
final class Card {
    var title: String
    var text: String
    var order: Int
    var createdAt: Date
    var updatedAt: Date
    var folder: Folder?

    @Relationship(deleteRule: .cascade, inverse: \CardImage.card)
    var images: [CardImage] = []

    init(title: String = "", text: String = "", order: Int) {
        self.title = title
        self.text = text
        self.order = order
        self.createdAt = .now
        self.updatedAt = .now
    }

    var orderedImages: [CardImage] {
        images.sorted { $0.order < $1.order }
    }

    /// Первая картинка — обложка для превью в ленте.
    var coverImageData: Data? {
        orderedImages.first?.data
    }

    /// Совсем пустая запись — ни заголовка, ни текста, ни фото.
    var isBlank: Bool {
        title.trimmed.isEmpty && text.trimmed.isEmpty && images.isEmpty
    }

    /// Отображаемый заголовок: если пусто — первая строка текста, иначе прочерк.
    var displayTitle: String {
        if !title.trimmed.isEmpty { return title }
        if let firstLine = text.split(separator: "\n").first.map({ String($0).trimmed }), !firstLine.isEmpty {
            return String(firstLine.prefix(60))
        }
        return "Без названия"
    }

    var hasTitle: Bool { !title.trimmed.isEmpty }
}

/// Картинка, прикреплённая к карточке. Данные лежат вне базы (external storage).
@Model
final class CardImage {
    @Attribute(.externalStorage) var data: Data
    var order: Int
    var card: Card?

    init(data: Data, order: Int) {
        self.data = data
        self.order = order
    }
}
