import SwiftUI
import SwiftData
import PhotosUI

/// Открытая страница: заголовок, текст, фотографии. Снизу — ИИ-панель.
struct CardEditorView: View {
    @Bindable var card: Card
    /// Сразу поднять клавиатуру на заголовке.
    var startEditing: Bool = false
    /// Запись создана только что: если пользователь ничего не написал,
    /// убираем её из ленты, чтобы не плодить пустые черновики.
    var isNewDraft: Bool = false

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case title, body }

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var viewerIndex: Int?
    @State private var imageToDelete: CardImage?
    @State private var showDeleteCard = false
    @State private var didDeleteCard = false
    @State private var savedFlash = false
    @State private var saveTask: Task<Void, Never>?
    @State private var isImportingPhotos = false
    @State private var photoImportFailed = false
    @State private var isAIStreaming = false
    @FocusState private var focus: Field?

    private let bottomAnchor = "page-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            scrollBody(proxy: proxy)
        }
    }

    private func scrollBody(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                page
                Color.clear
                    .frame(height: 1)
                    .id(bottomAnchor)
            }
            .padding(.horizontal, Space.md)
            .padding(.top, Space.sm)
            // Запас снизу: подпись страницы не должна уходить под ИИ-панель
            .padding(.bottom, Space.xl)
        }
        .paperBackground()
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            AIPromptBar(card: card, isStreaming: $isAIStreaming)
        }
        .toolbar { toolbarContent }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if !card.text.isBlank {
                    Text(RU.words(card.text.wordCount))
                        .font(Typo.micro)
                        .tracking(0.8)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                Button("Готово") { focus = nil }
                    .fontWeight(.semibold)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: viewerIndexBinding) { index in
            PhotoViewerView(card: card, startIndex: index.value)
        }
        .alert("Не удалось добавить фото", isPresented: $photoImportFailed) {
            Button("Ок", role: .cancel) {}
        } message: {
            Text("Файл не прочитался. Попробуй другое изображение.")
        }
        .confirmationDialog("Удалить запись?", isPresented: $showDeleteCard, titleVisibility: .visible) {
            Button("Удалить запись", role: .destructive) { deleteCard() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Текст и фотографии этой записи исчезнут. Это действие не отменить.")
        }
        .confirmationDialog(
            "Удалить фото?",
            isPresented: imageDeleteBinding,
            titleVisibility: .visible
        ) {
            Button("Удалить фото", role: .destructive) {
                if let image = imageToDelete { delete(image: image) }
                imageToDelete = nil
            }
            Button("Отмена", role: .cancel) { imageToDelete = nil }
        }
        .onChange(of: photoItems) { importPhotos() }
        .onChange(of: card.title) { touch() }
        .onChange(of: card.text) {
            touch()
            // Пока ИИ пишет — держим конец текста в кадре
            if isAIStreaming {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        }
        .onChange(of: isAIStreaming) {
            // Пока текст меняется сам, каретка в поле только мешает
            if isAIStreaming { focus = nil }
        }
        .onAppear {
            if startEditing && card.isBlank {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { focus = .title }
            }
        }
        .onDisappear {
            saveTask?.cancel()
            // Брошенный пустой черновик не оставляем мусором в ленте.
            // Только для только что созданных: открытую вручную пустую
            // запись пользователь удаляет сам.
            if isNewDraft && !didDeleteCard && card.isBlank {
                context.delete(card)
            }
        }
    }

    // MARK: Страница

    private var page: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: eyebrowText)
                Spacer(minLength: Space.sm)
                savedIndicator
            }

            TextField("Заголовок", text: $card.title, axis: .vertical)
                .font(Typo.pageTitle)
                .foregroundStyle(Theme.ink)
                .lineLimit(1...3)
                .focused($focus, equals: .title)
                .submitLabel(.next)
                .accessibilityLabel("Заголовок записи")

            InkDivider()

            if !card.images.isEmpty || isImportingPhotos {
                imagesStrip
            }

            ZStack(alignment: .topLeading) {
                if card.text.isEmpty {
                    Text("Пиши здесь — или попроси ИИ снизу")
                        .font(Typo.body)
                        .foregroundStyle(Theme.inkTertiary)
                        .allowsHitTesting(false)
                        .padding(.top, 1)
                }
                TextField("", text: $card.text, axis: .vertical)
                    .font(Typo.body)
                    .lineSpacing(7)
                    .foregroundStyle(Theme.ink)
                    .focused($focus, equals: .body)
                    .accessibilityLabel("Текст записи")
            }
            .frame(minHeight: 220, alignment: .topLeading)

            Spacer(minLength: Space.lg)

            footer
        }
        .padding(.leading, 26)
        .padding(.trailing, 22)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(minHeight: 470, alignment: .topLeading)
        .background(
            ZStack(alignment: .leading) {
                Theme.surface
                // Поле-маргиналия: вертикальная линейка у корешка
                Rectangle()
                    .fill(Theme.wax.opacity(0.22))
                    .frame(width: 1)
                    .padding(.leading, 17)
                    .padding(.vertical, 6)
            }
        )
        .pageCard(cornerRadius: 22, fold: 34)
        .contentShape(Rectangle())
        .onTapGesture {
            if focus == nil { focus = .body }
        }
    }

    private var footer: some View {
        HStack(spacing: Space.sm) {
            Text(statusLine)
                .font(Typo.micro)
                .tracking(0.8)
                .foregroundStyle(Theme.inkTertiary)
            Spacer()
            Text("— \(positionInFeed) —")
                .font(Typo.micro)
                .foregroundStyle(Theme.inkTertiary)
        }
        .padding(.top, Space.xs)
    }

    @ViewBuilder
    private var savedIndicator: some View {
        if savedFlash {
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                Text("сохранено")
                    .font(Typo.micro)
                    .tracking(0.8)
            }
            .foregroundStyle(Theme.sage)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    /// Фотографии — как отпечатки в альбоме: белая рамка и мягкая тень.
    private var imagesStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(Array(card.orderedImages.enumerated()), id: \.element.persistentModelID) { index, image in
                    if let uiImage = UIImage(data: image.data) {
                        Button {
                            Haptics.tap()
                            viewerIndex = index
                        } label: {
                            photoPrint(uiImage)
                        }
                        .buttonStyle(PressStyle(scale: 0.95))
                        .contextMenu {
                            Button {
                                viewerIndex = index
                            } label: {
                                Label("Открыть", systemImage: "arrow.up.left.and.arrow.down.right")
                            }
                            if index > 0 {
                                Button {
                                    makeCover(image)
                                } label: {
                                    Label("Сделать обложкой", systemImage: "rectangle.on.rectangle")
                                }
                            }
                            Button(role: .destructive) {
                                imageToDelete = image
                            } label: {
                                Label("Удалить фото", systemImage: "trash")
                            }
                        }
                        .accessibilityLabel("Фото \(index + 1) из \(card.images.count)")
                    }
                }

                if isImportingPhotos {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.surfaceAlt)
                        .frame(width: 160, height: 160)
                        .overlay(ProgressView())
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Theme.hairline, lineWidth: 1)
                        )
                }

                PhotosPicker(selection: $photoItems, maxSelectionCount: 8, matching: .images) {
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.title3.weight(.medium))
                        Text("Фото")
                            .font(.footnote.smallCaps())
                            .tracking(1.1)
                    }
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 108, height: 160)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.surfaceAlt.opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                Theme.inkSecondary.opacity(0.4),
                                style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
                            )
                    )
                }
                .accessibilityLabel("Добавить фото")
            }
            .padding(.vertical, 6)
            .padding(.trailing, 2)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    /// Отпечаток: кадр в белой рамке с тенью.
    private func photoPrint(_ uiImage: UIImage) -> some View {
        Image(uiImage: uiImage)
            .resizable()
            .scaledToFill()
            .frame(width: 148, height: 148)
            .clipped()
            .padding(6)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.10), radius: 8, y: 5)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section {
                    if !shareText.isEmpty {
                        ShareLink(item: shareText) {
                            Label("Поделиться текстом", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            UIPasteboard.general.string = shareText
                            Haptics.success()
                        } label: {
                            Label("Скопировать текст", systemImage: "doc.on.doc")
                        }
                    }
                }
                Section {
                    Button(role: .destructive) {
                        showDeleteCard = true
                    } label: {
                        Label("Удалить запись", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityLabel("Действия с записью")
        }
        ToolbarItem(placement: .topBarTrailing) {
            PhotosPicker(selection: $photoItems, maxSelectionCount: 8, matching: .images) {
                Image(systemName: "photo.badge.plus")
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityLabel("Добавить фото")
        }
    }

    // MARK: Данные

    /// Место записи в ленте — после удалений в `order` остаются дыры.
    private var positionInFeed: Int {
        (card.folder?.orderedCards.firstIndex(where: { $0.persistentModelID == card.persistentModelID }) ?? card.order) + 1
    }

    private var eyebrowText: String {
        "Запись \(String(format: "%02d", positionInFeed)) · \(DateText.full(card.createdAt))"
    }

    private var statusLine: String {
        var parts: [String] = []
        if !card.text.isBlank { parts.append(RU.words(card.text.wordCount)) }
        if !card.images.isEmpty { parts.append(RU.photos(card.images.count)) }
        parts.append("изменено " + DateText.relative(card.updatedAt))
        return parts.joined(separator: " · ")
    }

    private var shareText: String {
        [card.title.trimmed, card.text.trimmed]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private var imageDeleteBinding: Binding<Bool> {
        Binding(
            get: { imageToDelete != nil },
            set: { if !$0 { imageToDelete = nil } }
        )
    }

    /// fullScreenCover(item:) требует Identifiable — оборачиваем индекс.
    private struct ViewerIndex: Identifiable {
        let value: Int
        var id: Int { value }
    }

    private var viewerIndexBinding: Binding<ViewerIndex?> {
        Binding(
            get: { viewerIndex.map(ViewerIndex.init) },
            set: { viewerIndex = $0?.value }
        )
    }

    // MARK: Действия

    /// Отмечает правку и через паузу сохраняет — с короткой отметкой «сохранено».
    private func touch() {
        card.updatedAt = .now
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            try? context.save()
            withAnimation(.easeOut(duration: 0.2)) { savedFlash = true }
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.35)) { savedFlash = false }
        }
    }

    /// Первая картинка — обложка записи в ленте, поэтому «поднимаем» выбранную.
    private func makeCover(_ image: CardImage) {
        let minOrder = card.images.map(\.order).min() ?? 0
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            image.order = minOrder - 1
        }
        card.updatedAt = .now
        Haptics.success()
    }

    private func delete(image: CardImage) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            context.delete(image)
        }
        card.updatedAt = .now
        Haptics.warning()
    }

    private func deleteCard() {
        didDeleteCard = true
        Haptics.warning()
        let folder = card.folder
        let deletedID = card.persistentModelID
        dismiss()
        // Удаляем после закрытия, чтобы экран не дёрнулся на исчезнувшей модели
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            context.delete(card)
            let remaining = (folder?.orderedCards ?? []).filter { $0.persistentModelID != deletedID }
            for (index, card) in remaining.enumerated() {
                card.order = index
            }
        }
    }

    /// Импорт выбранных фото: сжимаем и сохраняем в карточку.
    private func importPhotos() {
        let items = photoItems
        guard !items.isEmpty else { return }
        photoItems = []
        isImportingPhotos = true
        Task {
            var nextOrder = (card.images.map(\.order).max() ?? -1) + 1
            var imported = 0
            for item in items {
                guard
                    let data = try? await item.loadTransferable(type: Data.self),
                    let uiImage = UIImage(data: data),
                    let jpeg = uiImage.downscaledJPEG()
                else { continue }
                let image = CardImage(data: jpeg, order: nextOrder)
                image.card = card
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    context.insert(image)
                }
                nextOrder += 1
                imported += 1
            }
            if imported > 0 {
                card.updatedAt = .now
                Haptics.success()
            } else {
                // Ни одно фото не прочиталось — не делаем вид, что всё хорошо
                photoImportFailed = true
                Haptics.warning()
            }
            isImportingPhotos = false
        }
    }
}
