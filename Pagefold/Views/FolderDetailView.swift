import SwiftUI
import SwiftData

/// Экран тетради — вертикальная лента-роадмап из карточек-«страниц».
/// Карточка у центра экрана крупнее и ровная, уходящие — ложатся назад.
struct FolderDetailView: View {
    @Bindable var folder: Folder
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var allFolders: [Folder]

    @State private var focusedCardID: PersistentIdentifier?
    @State private var pushedCard: PushedCard?
    @State private var cardToDelete: Card?
    @State private var showCardsList = false
    @State private var showNotebookEditor = false
    @State private var showCleanupDrafts = false

    var body: some View {
        GeometryReader { geo in
            let cardHeight = min(geo.size.height * 0.58, 520)
            let cards = folder.orderedCards

            Group {
                if cards.isEmpty {
                    PaperEmptyState(
                        title: "Чистая тетрадь",
                        message: "Первая запись — точка отсчёта на роадмапе. Дальше лента будет расти вниз."
                    ) {
                        Button("Начать запись") { addCard() }
                            .buttonStyle(InkButtonStyle())
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    feed(cards: cards, cardHeight: cardHeight, containerHeight: geo.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .navigationDestination(item: $pushedCard) { pushed in
            CardEditorView(
                card: pushed.card,
                startEditing: pushed.isNew,
                isNewDraft: pushed.isNew
            )
        }
        .sheet(isPresented: $showCardsList) {
            CardsListSheet(folder: folder) { card in
                // Ждём закрытия листа, иначе переход перебьёт анимацию
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    pushedCard = PushedCard(card: card, isNew: false)
                }
            }
        }
        .sheet(isPresented: $showNotebookEditor) {
            NotebookEditorSheet(mode: .rename(folder), takenCoverIndexes: allFolders.map(\.colorIndex)) { name, colorIndex in
                folder.name = name
                folder.colorIndex = colorIndex
            }
        }
        .confirmationDialog(
            "Убрать пустые черновики?",
            isPresented: $showCleanupDrafts,
            titleVisibility: .visible
        ) {
            Button("Убрать \(RU.records(blankCards.count))", role: .destructive) { cleanupDrafts() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Исчезнут только записи без заголовка, текста и фотографий.")
        }
        .confirmationDialog(
            cardToDelete.map { "Удалить «\($0.displayTitle)»?" } ?? "Удалить запись?",
            isPresented: deleteDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Удалить запись", role: .destructive) { deleteCard() }
            Button("Отмена", role: .cancel) { cardToDelete = nil }
        } message: {
            Text("Запись и её фотографии исчезнут. Это действие не отменить.")
        }
    }

    // MARK: Лента

    private func feed(cards: [Card], cardHeight: CGFloat, containerHeight: CGFloat) -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(Array(cards.enumerated()), id: \.element.persistentModelID) { index, card in
                    VStack(spacing: 0) {
                        NavigationLink {
                            CardEditorView(card: card)
                        } label: {
                            CardPreviewView(card: card, index: index, height: cardHeight)
                        }
                        .buttonStyle(PressStyle(scale: 0.985))
                        .frame(height: cardHeight)
                        .contextMenu {
                            Button {
                                pushedCard = PushedCard(card: card, isNew: false)
                            } label: {
                                Label("Открыть", systemImage: "book.pages")
                            }
                            if cards.count > 1 {
                                Button { showCardsList = true } label: {
                                    Label("Все записи", systemImage: "list.bullet")
                                }
                            }
                            Divider()
                            Button(role: .destructive) {
                                cardToDelete = card
                            } label: {
                                Label("Удалить запись", systemImage: "trash")
                            }
                        }

                        // Связка между страницами: линия — узел — линия
                        RoadmapConnector()
                            .frame(height: 40)
                    }
                    // «Картотека»: карточка у центра выпрямляется и растёт,
                    // уходящие вверх ложатся назад, нижние — наклоняются вперёд.
                    .visualEffect { [reduceMotion] content, proxy in
                        let containerHeight = proxy.bounds(of: .scrollView(axis: .vertical))?.height ?? 800
                        let mid = containerHeight / 2
                        let signed = (proxy.frame(in: .scrollView(axis: .vertical)).midY - mid) / mid
                        let clamped = max(-1, min(1, signed))
                        let distance = abs(clamped)
                        return content
                            .scaleEffect(reduceMotion ? 1 : 1 - distance * 0.11)
                            .opacity(1 - distance * (reduceMotion ? 0.22 : 0.40))
                            .offset(y: reduceMotion ? 0 : clamped * 6)
                            .rotation3DEffect(
                                .degrees(reduceMotion ? 0 : clamped * -10),
                                axis: (x: 1, y: 0, z: 0),
                                perspective: 0.5
                            )
                    }
                }

                // Финальная «призрачная» страница — добавить запись, не уходя из ленты
                Button { addCard() } label: {
                    NewPageGhostTile()
                        .frame(height: min(cardHeight * 0.52, 240))
                }
                .buttonStyle(PressStyle(scale: 0.97))
                .accessibilityLabel("Новая запись")
            }
            .padding(.horizontal, 26)
            .scrollTargetLayout()
        }
        // Лента примагничивается так, чтобы карточка встала по центру
        .contentMargins(.vertical, max((containerHeight - cardHeight) / 2 - 20, 24), for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $focusedCardID)
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: focusedCardID)
        .overlay(alignment: .leading) {
            FeedRail(
                count: cards.count,
                focusedIndex: focusedIndex(in: cards),
                onSelect: { index in jump(to: index, in: cards) }
            )
            .padding(.leading, 3)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(folder.name)
                .font(Font.system(.headline, design: .serif))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { addCard() } label: {
                Image(systemName: "plus")
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityLabel("Новая запись")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if folder.cards.count > 1 {
                    Button { showCardsList = true } label: {
                        Label("Все записи", systemImage: "list.bullet")
                    }
                }
                if blankCards.count > 1 {
                    Button { showCleanupDrafts = true } label: {
                        Label("Убрать пустые черновики", systemImage: "eraser")
                    }
                }
                Divider()
                Button { showNotebookEditor = true } label: {
                    Label("Переименовать и обложка", systemImage: "pencil")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityLabel("Действия с тетрадью")
        }
    }

    // MARK: Данные и действия

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { cardToDelete != nil },
            set: { if !$0 { cardToDelete = nil } }
        )
    }

    private func focusedIndex(in cards: [Card]) -> Int {
        guard let focusedCardID else { return 0 }
        return cards.firstIndex { $0.persistentModelID == focusedCardID } ?? 0
    }

    private func jump(to index: Int, in cards: [Card]) {
        guard cards.indices.contains(index) else { return }
        Haptics.soft()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            focusedCardID = cards[index].persistentModelID
        }
    }

    /// Пустые черновики — кандидаты на уборку.
    private var blankCards: [Card] {
        folder.cards.filter(\.isBlank)
    }

    private func addCard() {
        let nextOrder = (folder.cards.map(\.order).max() ?? -1) + 1
        let card = Card(order: nextOrder)
        card.folder = folder
        context.insert(card)
        Haptics.tap()
        // Сразу открываем редактор: пустая карточка в ленте — тупик
        pushedCard = PushedCard(card: card, isNew: true)
    }

    private func deleteCard() {
        guard let card = cardToDelete else { return }
        let deletedID = card.persistentModelID
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            context.delete(card)
        }
        // Убираем дыры в нумерации, чтобы «Запись 04» не шла за «Запись 02»
        renumber(excluding: deletedID)
        cardToDelete = nil
        Haptics.warning()
    }

    private func cleanupDrafts() {
        let drafts = blankCards
        let removed = Set(drafts.map(\.persistentModelID))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            for card in drafts { context.delete(card) }
        }
        // Переномеровываем остаток, чтобы «Запись 04» не следовала за «Запись 01»
        for (index, card) in folder.orderedCards.filter({ !removed.contains($0.persistentModelID) }).enumerated() {
            card.order = index
        }
        Haptics.warning()
    }

    private func renumber(excluding deletedID: PersistentIdentifier) {
        for (index, card) in folder.orderedCards.filter({ $0.persistentModelID != deletedID }).enumerated() {
            card.order = index
        }
    }
}

/// Переход к записи: помним, создана ли она только что.
private struct PushedCard: Identifiable, Hashable {
    let card: Card
    let isNew: Bool

    var id: PersistentIdentifier { card.persistentModelID }

    static func == (lhs: PushedCard, rhs: PushedCard) -> Bool {
        lhs.id == rhs.id && lhs.isNew == rhs.isNew
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(isNew)
    }
}

// MARK: - Карточка в ленте

/// Страница в ленте: шапка-«бровь» с номером записи и датой, заголовок,
/// отрывок текста; при наличии фото — обложка сверху. Правый верхний угол загнут.
struct CardPreviewView: View {
    let card: Card
    let index: Int
    let height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasCover: Bool { card.coverImageData != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let data = card.coverImageData, let uiImage = UIImage(data: data) {
                coverImage(uiImage)
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 1)
            }

            VStack(alignment: .leading, spacing: Space.sm) {
                Eyebrow(text: eyebrow)

                Text(card.displayTitle)
                    .font(hasCover ? Typo.cardTitleTight : Typo.cardTitle)
                    .foregroundStyle(card.hasTitle ? Theme.ink : Theme.inkSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.leading)

                if card.text.isBlank {
                    // Чистый лист — разлиновка вместо текста-заглушки
                    RuledLines()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 4)
                        .overlay(alignment: .topLeading) {
                            Text("Ещё ни строчки")
                                .font(.footnote)
                                .foregroundStyle(Theme.inkTertiary)
                                .padding(.top, 2)
                        }
                } else {
                    Text(card.text)
                        .font(Typo.excerpt)
                        .lineSpacing(5)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(hasCover ? 3 : 8)
                        .multilineTextAlignment(.leading)
                    // Разлиновка продолжается под текстом до конца страницы
                    RuledLines()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay(alignment: .bottomTrailing) {
            stamp.padding(16)
        }
        .background(Theme.surface)
        .pageCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Запись \(index + 1). \(card.displayTitle)")
        .accessibilityHint("Открыть запись")
    }

    private func coverImage(_ uiImage: UIImage) -> some View {
        Image(uiImage: uiImage)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: height * 0.46)
            .scaleEffect(1.15)
            // Лёгкий параллакс обложки при прокрутке
            .visualEffect { [reduceMotion] content, proxy in
                guard !reduceMotion else { return content.offset(y: 0) }
                let containerHeight = proxy.bounds(of: .scrollView(axis: .vertical))?.height ?? 800
                let mid = containerHeight / 2
                let signed = (proxy.frame(in: .scrollView(axis: .vertical)).midY - mid) / mid
                return content.offset(y: max(-1, min(1, signed)) * -16)
            }
            .clipped()
            .overlay(alignment: .bottom) {
                // Мягкая тень под обрезом, чтобы текст не «отрывался»
                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.10)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 28)
                .allowsHitTesting(false)
            }
    }

    /// «Штамп» в нижнем углу страницы: фото, черновик, объём текста.
    @ViewBuilder
    private var stamp: some View {
        HStack(spacing: 6) {
            if card.images.count > 1 {
                TagBadge(text: "\(card.images.count)", icon: "photo.on.rectangle")
            }
            if card.isBlank {
                TagBadge(text: "черновик", tint: Theme.wax)
            } else if !card.text.isBlank {
                Text(RU.words(card.text.wordCount))
                    .font(Typo.micro)
                    .tracking(0.8)
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
    }

    private var eyebrow: String {
        let number = String(format: "%02d", index + 1)
        return "Запись \(number) · \(DateText.short(card.updatedAt))"
    }
}

/// «Призрачная» страница в конце ленты — создать запись.
private struct NewPageGhostTile: View {
    var body: some View {
        ZStack {
            DogEarRect(cornerRadius: 20, fold: 32)
                .fill(Theme.surface.opacity(0.35))
            DogEarRect(cornerRadius: 20, fold: 32)
                .strokeBorder(
                    Theme.inkSecondary.opacity(0.42),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                )
            VStack(spacing: Space.sm) {
                Image(systemName: "plus")
                    .font(.title3.weight(.medium))
                Text("Новая запись")
                    .font(.footnote.smallCaps())
                    .tracking(1.2)
            }
            .foregroundStyle(Theme.inkSecondary)
        }
    }
}

// MARK: - Узел роадмапа

/// Узел роадмапа между страницами: тонкая линия с маленьким кольцом.
private struct RoadmapConnector: View {
    var body: some View {
        VStack(spacing: 4) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 1, height: 12)
            Circle()
                .strokeBorder(Theme.inkSecondary.opacity(0.55), lineWidth: 1.5)
                .frame(width: 7, height: 7)
            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 1, height: 12)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

// MARK: - Рейка ленты

/// Насечки у левого края: где мы в ленте. По насечке можно прыгнуть.
private struct FeedRail: View {
    let count: Int
    let focusedIndex: Int
    let onSelect: (Int) -> Void

    /// Больше насечек уже не читается — показываем полосу прогресса.
    private var showsTicks: Bool { count <= 16 }

    var body: some View {
        Group {
            if showsTicks {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(width: 1)
                        .padding(.vertical, 2)
                    VStack(spacing: 4) {
                    ForEach(0..<count, id: \.self) { index in
                        Button { onSelect(index) } label: {
                            Capsule()
                                .fill(index == focusedIndex ? Theme.ink : Theme.inkTertiary.opacity(0.5))
                                .frame(width: index == focusedIndex ? 15 : 8, height: 2.5)
                                .frame(width: 18, height: 15, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Запись \(index + 1)")
                    }
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: focusedIndex)
            } else {
                VStack(spacing: 6) {
                    Text(String(format: "%02d", focusedIndex + 1))
                        .font(Typo.micro)
                        .foregroundStyle(Theme.ink)
                    Capsule()
                        .fill(Theme.inkTertiary.opacity(0.3))
                        .frame(width: 2.5, height: 120)
                        .overlay(alignment: .top) {
                            Capsule()
                                .fill(Theme.ink)
                                .frame(width: 2.5, height: 22)
                                .offset(y: 98 * CGFloat(focusedIndex) / CGFloat(max(count - 1, 1)))
                                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: focusedIndex)
                        }
                    Text(String(format: "%02d", count))
                        .font(Typo.micro)
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Навигация по ленте")
    }
}

// MARK: - Порядок записей

/// Все записи тетради: поиск, переход к записи и перестановка.
private struct CardsListSheet: View {
    let folder: Folder
    let onSelect: (Card) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var isReordering = false

    private var cards: [Card] { folder.orderedCards }

    private var filtered: [(offset: Int, element: Card)] {
        let q = query.trimmed.lowercased()
        let all = Array(cards.enumerated()).map { (offset: $0.offset, element: $0.element) }
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.element.title.lowercased().contains(q) || $0.element.text.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isReordering {
                    reorderList
                } else {
                    browseList
                }
            }
            .navigationTitle(isReordering ? "Порядок записей" : "Все записи")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isReordering ? "Готово" : "Порядок") {
                        withAnimation { isReordering.toggle() }
                        Haptics.soft()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    private var browseList: some View {
        List {
            if !filtered.isEmpty {
                ForEach(filtered, id: \.element.persistentModelID) { item in
                    Button {
                        dismiss()
                        onSelect(item.element)
                    } label: {
                        CardListRow(card: item.element, number: item.offset + 1)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.surface.opacity(0.75))
                }
            } else {
                Text("Ничего не нашлось")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Space.lg)
            }
        }
        .scrollContentBackground(.hidden)
        .paperBackground()
        .searchable(text: $query, prompt: "Поиск по записям")
    }

    private var reorderList: some View {
        List {
            ForEach(Array(cards.enumerated()), id: \.element.persistentModelID) { index, card in
                CardListRow(card: card, number: index + 1)
                    .listRowBackground(Theme.surface.opacity(0.75))
            }
            .onMove(perform: move)
        }
        .scrollContentBackground(.hidden)
        .paperBackground()
        .environment(\.editMode, .constant(.active))
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = cards
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, card) in reordered.enumerated() {
            card.order = index
        }
        Haptics.soft()
    }
}

/// Строка записи в списке.
private struct CardListRow: View {
    let card: Card
    let number: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", number))
                .font(Typo.micro)
                .foregroundStyle(Theme.inkTertiary)
                .frame(width: 22, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.displayTitle)
                    .font(Font.system(.body, design: .serif).weight(.medium))
                    .foregroundStyle(card.hasTitle ? Theme.ink : Theme.inkSecondary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(DateText.short(card.updatedAt))
                    if !card.text.isBlank {
                        Text("·")
                        Text(RU.words(card.text.wordCount))
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 4)
            if !card.images.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "photo")
                    Text("\(card.images.count)")
                }
                .font(.caption)
                .foregroundStyle(Theme.inkTertiary)
            }
            if card.isBlank {
                TagBadge(text: "черновик", tint: Theme.wax)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
