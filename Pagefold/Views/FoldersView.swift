import SwiftUI
import SwiftData

/// Главный экран — полка тетрадей-проектов.
struct FoldersView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: [SortDescriptor(\Folder.sortIndex), SortDescriptor(\Folder.createdAt)])
    private var folders: [Folder]
    @Query(sort: \Card.updatedAt, order: .reverse)
    private var cardsByDate: [Card]

    @State private var editorMode: NotebookEditorMode?
    @State private var folderToDelete: Folder?
    @State private var showSettings = false
    @State private var showReorder = false
    @State private var query = ""
    @State private var appeared = false
    @State private var hasAPIKey = true
    @AppStorage("aiHintDismissed") private var aiHintDismissed = false

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            content
                .paperBackground()
                .toolbar { toolbarContent }
                .sheet(item: $editorMode) { mode in
                    NotebookEditorSheet(mode: mode, takenCoverIndexes: folders.map(\.colorIndex)) { name, colorIndex in
                        apply(mode: mode, name: name, colorIndex: colorIndex)
                    }
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                        .onDisappear { hasAPIKey = KeychainStore.apiKey?.isEmpty == false }
                }
                .sheet(isPresented: $showReorder) {
                    ReorderNotebooksSheet(folders: folders)
                }
                .confirmationDialog(
                    folderToDelete.map { "Удалить «\($0.name)»?" } ?? "Удалить тетрадь?",
                    isPresented: deleteDialogBinding,
                    titleVisibility: .visible
                ) {
                    Button("Удалить тетрадь", role: .destructive) { deleteFolder() }
                    Button("Отмена", role: .cancel) { folderToDelete = nil }
                } message: {
                    if let folder = folderToDelete, !folder.cards.isEmpty {
                        let n = folder.cards.count
                        Text("Вместе с ней \(RU.plural(n, "исчезнет", "исчезнут", "исчезнут")) \(RU.records(n)). Это действие не отменить.")
                    } else {
                        Text("Это действие не отменить.")
                    }
                }
        }
        .tint(Theme.accent)
        .onChange(of: scenePhase) {
            // Уходим в фон — фиксируем всё на диск
            if scenePhase != .active { try? context.save() }
        }
        .onAppear {
            hasAPIKey = KeychainStore.apiKey?.isEmpty == false
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { appeared = true }
        }
    }

    // MARK: Содержимое

    @ViewBuilder
    private var content: some View {
        if folders.isEmpty {
            PaperEmptyState(
                title: "Полка пока пуста",
                message: "Тетрадь — это проект. Внутри — лента записей, которую можно листать как роадмап."
            ) {
                Button("Завести тетрадь") { startCreating() }
                    .buttonStyle(InkButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    header
                    if showsSearch {
                        SearchField(text: $query, placeholder: "Тетради и записи")
                    }
                    if visibleFolders.isEmpty && matchingCards.isEmpty {
                        nothingFound
                    } else {
                        if !visibleFolders.isEmpty {
                            grid
                        }
                        if !matchingCards.isEmpty {
                            foundInCardsSection
                        }
                    }
                    if showsAIHint {
                        aiHint
                    }
                    if query.trimmed.isEmpty && !recentCards.isEmpty {
                        recentSection
                    }
                }
                .padding(.horizontal, Space.screen)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.xl)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(Array(visibleFolders.enumerated()), id: \.element.persistentModelID) { index, folder in
                NavigationLink {
                    FolderDetailView(folder: folder)
                } label: {
                    FolderTile(folder: folder, matchedQuery: query.trimmed)
                }
                .buttonStyle(PressStyle(scale: 0.96))
                .contextMenu {
                    Button {
                        editorMode = .rename(folder)
                    } label: {
                        Label("Переименовать и обложка", systemImage: "pencil")
                    }
                    if folders.count > 1 {
                        Button {
                            showReorder = true
                        } label: {
                            Label("Порядок на полке", systemImage: "arrow.up.arrow.down")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        folderToDelete = folder
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(
                    .spring(response: 0.5, dampingFraction: 0.85).delay(Double(min(index, 8)) * 0.04),
                    value: appeared
                )
            }

            if query.trimmed.isEmpty {
                Button { startCreating() } label: {
                    NewFolderGhostTile()
                }
                .buttonStyle(PressStyle(scale: 0.96))
                .accessibilityLabel("Новая тетрадь")
            }
        }
    }

    /// Поиск нужен, когда полка перестаёт быть обозримой.
    private var showsSearch: Bool {
        folders.count >= 2 || cardsByDate.count >= 4
    }

    /// Записи, в которых нашлось искомое слово — чтобы попасть сразу в них.
    private var matchingCards: [Card] {
        let q = query.trimmed.lowercased()
        guard !q.isEmpty else { return [] }
        return Array(
            cardsByDate
                .filter { $0.folder != nil }
                .filter { $0.title.lowercased().contains(q) || $0.text.lowercased().contains(q) }
                .prefix(12)
        )
    }

    /// Результаты поиска внутри записей.
    private var foundInCardsSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Eyebrow(text: "Найдено в записях")
                .padding(.top, Space.xs)
            cardRows(matchingCards)
        }
    }

    private var showsAIHint: Bool {
        !hasAPIKey && !aiHintDismissed && query.trimmed.isEmpty
    }

    /// Ненавязчивая подсказка: ИИ-панель ждёт ключ.
    private var aiHint: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("ИИ-панель ждёт ключ")
                    .font(Font.system(.subheadline, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("С ключом Anthropic ИИ продолжит и причешет текст.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.sm) {
                    Button {
                        showSettings = true
                    } label: {
                        Text("Добавить ключ")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.paper)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Theme.ink))
                    }
                    .buttonStyle(PressStyle())
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) { aiHintDismissed = true }
                    } label: {
                        Text("Позже")
                            .font(.caption)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
                .padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1)
        )
    }

    /// «Продолжить» — последние записи из всех тетрадей, чтобы вернуться в работу одним касанием.
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Eyebrow(text: "Продолжить")
                .padding(.top, Space.xs)
            cardRows(recentCards)
        }
    }

    /// Список записей в бумажной «папке» — одна разметка на два раздела.
    private func cardRows(_ cards: [Card]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(cards.enumerated()), id: \.element.persistentModelID) { index, card in
                NavigationLink {
                    CardEditorView(card: card)
                } label: {
                    RecentCardRow(card: card)
                }
                .buttonStyle(PressStyle(scale: 0.985))
                if index < cards.count - 1 {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(height: 1)
                        .padding(.leading, 58)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Pagefold")
                .font(Typo.display)
                .foregroundStyle(Theme.ink)
            Text("дневник проектов")
                .font(Typo.subtitle)
                .tracking(2.0)
                .foregroundStyle(Theme.inkSecondary)
            InkDivider()
                .padding(.top, Space.sm)
            Text(shelfSummary)
                .font(Typo.micro)
                .tracking(1.0)
                .foregroundStyle(Theme.inkTertiary)
                .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
    }

    private var nothingFound: some View {
        VStack(spacing: Space.sm) {
            Image(systemName: "text.page.badge.magnifyingglass")
                .font(.title)
                .foregroundStyle(Theme.inkTertiary)
            Text("Ничего не нашлось")
                .font(Font.system(.headline, design: .serif))
                .foregroundStyle(Theme.ink)
            Text("Попробуй другое слово — я ищу и по названиям тетрадей, и внутри записей.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xl)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(3)
                    .overlay(alignment: .topTrailing) {
                        if !hasAPIKey {
                            Circle()
                                .fill(Theme.wax)
                                .frame(width: 6, height: 6)
                        }
                    }
            }
            .accessibilityLabel(hasAPIKey ? "Настройки" : "Настройки, нужен ключ ИИ")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                startCreating()
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityLabel("Новая тетрадь")
        }
    }

    // MARK: Данные

    private var visibleFolders: [Folder] {
        let q = query.trimmed.lowercased()
        guard !q.isEmpty else { return folders }
        return folders.filter { folder in
            if folder.name.lowercased().contains(q) { return true }
            return folder.cards.contains { card in
                card.title.lowercased().contains(q) || card.text.lowercased().contains(q)
            }
        }
    }

    /// Три последние непустые записи.
    private var recentCards: [Card] {
        Array(cardsByDate.filter { !$0.isBlank && $0.folder != nil }.prefix(3))
    }

    private var shelfSummary: String {
        let cards = folders.reduce(0) { $0 + $1.cards.count }
        return "\(RU.notebooks(folders.count)) · \(RU.records(cards))"
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { folderToDelete != nil },
            set: { if !$0 { folderToDelete = nil } }
        )
    }

    // MARK: Действия

    private func startCreating() {
        Haptics.tap()
        editorMode = .create(suggestedColorIndex: folders.count)
    }

    private func apply(mode: NotebookEditorMode, name: String, colorIndex: Int) {
        switch mode {
        case .create:
            let nextSort = (folders.map(\.sortIndex).max() ?? -1) + 1
            let folder = Folder(name: name, colorIndex: colorIndex, sortIndex: nextSort)
            context.insert(folder)
            Haptics.success()
        case .rename(let folder):
            folder.name = name
            folder.colorIndex = colorIndex
            Haptics.tap()
        }
    }

    private func deleteFolder() {
        guard let folder = folderToDelete else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            context.delete(folder)
        }
        folderToDelete = nil
        Haptics.warning()
    }
}

// MARK: - Тетрадь на полке

/// Тетрадь: тканевая обложка с корешком, резинкой-застёжкой, тиснёным
/// названием и выглядывающим страничным блоком.
private struct FolderTile: View {
    let folder: Folder
    var matchedQuery: String = ""

    @Environment(\.dynamicTypeSize) private var typeSize

    private var cover: Color { Theme.cover(at: folder.colorIndex) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            pagesBlock
            coverBody
        }
        .aspectRatio(0.76, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(folder.name), \(RU.records(folder.cards.count))")
        .accessibilityHint("Открыть тетрадь")
    }

    /// Страничный блок, выглядывающий из-под обложки справа и снизу.
    private var pagesBlock: some View {
        notebookShape
            .fill(Theme.surface)
            .overlay(notebookShape.strokeBorder(Theme.pageEdge, lineWidth: 0.75))
            .overlay(alignment: .trailing) {
                // Обрез: несколько тонких линий-листов
                HStack(spacing: 1.5) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle().fill(Theme.pageEdge.opacity(0.55)).frame(width: 0.75)
                    }
                }
                .padding(.trailing, 1.5)
                .padding(.vertical, 8)
            }
            .padding(.leading, 18)
            .offset(x: 5, y: 3)
            .accessibilityHidden(true)
    }

    private var coverBody: some View {
        ZStack(alignment: .bottomLeading) {
            // Ткань обложки: диагональный свет + зерно
            LinearGradient(
                colors: [cover, cover.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            PaperGrain(opacity: 0.7)

            // Корешок переплёта с бликом у сгиба
            HStack(spacing: 0) {
                Rectangle()
                    .fill(.black.opacity(0.26))
                    .frame(width: 14)
                Rectangle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 1)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name)
                    .font(Typo.coverTitle)
                    .foregroundStyle(Theme.ivory)
                    .letterpress()
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                Text(RU.records(folder.cards.count))
                    .font(Typo.micro)
                    .tracking(1.0)
                    .foregroundStyle(Theme.ivory.opacity(0.68))
                if !folder.cards.isEmpty && !typeSize.isAccessibilitySize {
                    Text(DateText.short(folder.lastActivityAt))
                        .font(Typo.micro)
                        .tracking(0.6)
                        .foregroundStyle(Theme.ivory.opacity(0.42))
                }
            }
            .padding(.leading, 27)
            .padding(.trailing, 42)
            .padding(.bottom, 14)

            if matchesInsideCards {
                // Ляссе-закладка: найдено внутри записей
                VStack {
                    RibbonBookmark()
                        .frame(width: 12, height: 34)
                        .offset(y: -3)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 44)
            }
        }
        .overlay(alignment: .trailing) {
            // Резинка-застёжка
            Rectangle()
                .fill(.black.opacity(0.32))
                .overlay(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.14)).frame(width: 1)
                }
                .frame(width: 9)
                .padding(.trailing, 24)
                .shadow(color: .black.opacity(0.25), radius: 2, x: -1.5)
        }
        .clipShape(notebookShape)
        .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
        .shadow(color: .black.opacity(0.18), radius: 16, y: 10)
    }

    private var matchesInsideCards: Bool {
        let q = matchedQuery.lowercased()
        guard !q.isEmpty, !folder.name.lowercased().contains(q) else { return false }
        return true
    }
}

/// Строка «Продолжить»: мини-страница, заголовок, тетрадь и дата.
private struct RecentCardRow: View {
    let card: Card

    var body: some View {
        HStack(spacing: 12) {
            miniPage
            VStack(alignment: .leading, spacing: 2) {
                Text(card.displayTitle)
                    .font(Font.system(.subheadline, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if let folder = card.folder {
                        Circle()
                            .fill(Theme.cover(at: folder.colorIndex))
                            .frame(width: 6, height: 6)
                        Text(folder.name)
                            .lineLimit(1)
                    }
                    Text("·")
                    Text(DateText.short(card.updatedAt))
                }
                .font(Typo.micro)
                .tracking(0.6)
                .foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.inkTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.displayTitle), \(card.folder?.name ?? ""), \(DateText.short(card.updatedAt))")
        .accessibilityHint("Открыть запись")
    }

    private var miniPage: some View {
        Group {
            if let data = card.coverImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Theme.surface
                    RuledLines(spacing: 7)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 6)
                }
            }
        }
        .frame(width: 32, height: 42)
        .clipShape(DogEarRect(cornerRadius: 5, fold: 9))
        .overlay(
            DogEarRect(cornerRadius: 5, fold: 9)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
        .accessibilityHidden(true)
    }
}

/// Ляссе — тканевая закладка, торчащая из тетради.
private struct RibbonBookmark: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 12, y: 0))
            path.addLine(to: CGPoint(x: 12, y: 34))
            path.addLine(to: CGPoint(x: 6, y: 28))
            path.addLine(to: CGPoint(x: 0, y: 34))
            path.closeSubpath()
        }
        .fill(Theme.wax)
        .overlay(
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 34))
            }
            .stroke(.black.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        .accessibilityHidden(true)
    }
}

/// «Призрачная» тетрадь — пунктирный силуэт, создающий новую тетрадь.
private struct NewFolderGhostTile: View {
    var body: some View {
        ZStack {
            notebookShape
                .fill(Theme.surface.opacity(0.35))
            notebookShape
                .strokeBorder(
                    Theme.inkSecondary.opacity(0.45),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                )
            VStack(spacing: Space.sm) {
                Image(systemName: "plus")
                    .font(.title3.weight(.medium))
                Text("Новая тетрадь")
                    .font(.footnote.smallCaps())
                    .tracking(1.2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Theme.inkSecondary)
            .padding(Space.sm)
        }
        .aspectRatio(0.76, contentMode: .fit)
    }
}

// MARK: - Поиск

/// Поле поиска в бумажной стилистике.
struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkTertiary)
            TextField(placeholder, text: $text)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button {
                    text = ""
                    Haptics.soft()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkTertiary)
                }
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Capsule().fill(Theme.surfaceAlt))
        .overlay(
            Capsule().strokeBorder(focused ? Theme.accent.opacity(0.5) : Theme.hairline, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}

// MARK: - Порядок на полке

/// Перестановка тетрадей перетаскиванием.
private struct ReorderNotebooksSheet: View {
    let folders: [Folder]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(folders, id: \.persistentModelID) { folder in
                    HStack(spacing: 12) {
                        notebookShape
                            .fill(Theme.cover(at: folder.colorIndex))
                            .frame(width: 22, height: 29)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(.black.opacity(0.25)).frame(width: 3)
                            }
                            .clipShape(notebookShape)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(folder.name)
                                .font(Font.system(.body, design: .serif).weight(.medium))
                                .foregroundStyle(Theme.ink)
                            Text(RU.records(folder.cards.count))
                                .font(.caption)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(Theme.surface.opacity(0.75))
                }
                .onMove(perform: move)
            }
            .scrollContentBackground(.hidden)
            .paperBackground()
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Порядок на полке")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = folders
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, folder) in reordered.enumerated() {
            folder.sortIndex = index
        }
        Haptics.soft()
    }
}
