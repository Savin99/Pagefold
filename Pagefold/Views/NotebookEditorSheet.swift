import SwiftUI

/// Что делает лист: заводит новую тетрадь или правит существующую.
enum NotebookEditorMode: Identifiable {
    case create(suggestedColorIndex: Int)
    case rename(Folder)

    var id: String {
        switch self {
        case .create: return "create"
        case .rename(let folder): return "rename-\(folder.persistentModelID.hashValue)"
        }
    }

    var isCreating: Bool {
        if case .create = self { return true }
        return false
    }
}

/// Лист создания и правки тетради: имя, обложка и живой предпросмотр.
struct NotebookEditorSheet: View {
    let mode: NotebookEditorMode
    /// Уже занятые тона — чтобы подсветить их точкой и предложить свободный.
    let takenCoverIndexes: [Int]
    let onSave: (String, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var colorIndex = 0
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.lg) {
                    preview
                        .padding(.top, Space.sm)

                    VStack(alignment: .leading, spacing: Space.sm) {
                        Eyebrow(text: "Название")
                        TextField("Например, «Роман» или «Ремонт»", text: $name)
                            .font(Font.system(.title3, design: .serif))
                            .foregroundStyle(Theme.ink)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit(save)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Theme.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(nameFocused ? Theme.accent.opacity(0.55) : Theme.hairline, lineWidth: 1)
                            )
                            .animation(.easeOut(duration: 0.18), value: nameFocused)
                    }

                    VStack(alignment: .leading, spacing: Space.sm) {
                        Eyebrow(text: "Обложка")
                        coverPicker
                    }
                }
                .padding(.horizontal, Space.screen)
                .padding(.bottom, Space.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
            .paperBackground()
            .navigationTitle(mode.isCreating ? "Новая тетрадь" : "Тетрадь")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.isCreating ? "Создать" : "Сохранить", action: save)
                        .fontWeight(.semibold)
                        .disabled(name.isBlank)
                }
            }
            .onAppear(perform: prepare)
        }
        .presentationDetents([.large])
    }

    // MARK: Предпросмотр

    private var preview: some View {
        ZStack(alignment: .topLeading) {
            notebookShape
                .fill(Theme.surface)
                .overlay(notebookShape.strokeBorder(Theme.pageEdge, lineWidth: 0.75))
                .padding(.leading, 10)
                .offset(x: 5, y: 5)

            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [Theme.cover(at: colorIndex), Theme.cover(at: colorIndex).opacity(0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                PaperGrain(opacity: 0.7)
                HStack(spacing: 0) {
                    Rectangle().fill(.black.opacity(0.26)).frame(width: 17)
                    Rectangle().fill(.white.opacity(0.18)).frame(width: 1)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(name.isBlank ? "Без названия" : name)
                        .font(Font.system(.title3, design: .serif).weight(.semibold))
                        .foregroundStyle(Theme.ivory.opacity(name.isBlank ? 0.45 : 1))
                        .letterpress()
                        .lineLimit(3)
                    Text(mode.isCreating ? "новая" : RU.records(existingCardsCount))
                        .font(Typo.micro)
                        .tracking(1.0)
                        .foregroundStyle(Theme.ivory.opacity(0.6))
                }
                .padding(.leading, 32)
                .padding([.bottom, .trailing], 18)
            }
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(.black.opacity(0.32))
                    .overlay(alignment: .leading) {
                        Rectangle().fill(.white.opacity(0.14)).frame(width: 1)
                    }
                    .frame(width: 11)
                    .padding(.trailing, 30)
                    .shadow(color: .black.opacity(0.25), radius: 2, x: -1.5)
            }
            .clipShape(notebookShape)
            .shadow(color: .black.opacity(0.10), radius: 4, y: 3)
            .shadow(color: .black.opacity(0.20), radius: 20, y: 12)
        }
        .frame(width: 168, height: 221)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: colorIndex)
        .accessibilityHidden(true)
    }

    // MARK: Выбор обложки

    private var coverPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
            ForEach(Theme.covers.indices, id: \.self) { index in
                Button {
                    colorIndex = index
                    Haptics.soft()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.cover(at: index))
                            .overlay(PaperGrain(opacity: 0.6).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)))
                            .overlay(alignment: .leading) {
                                Rectangle().fill(.black.opacity(0.22)).frame(width: 5)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .frame(height: 52)
                        if colorIndex == index {
                            Image(systemName: "checkmark")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Theme.ivory)
                                .letterpress()
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(colorIndex == index ? Theme.ink : Theme.hairline, lineWidth: colorIndex == index ? 2 : 1)
                    )
                    .overlay(alignment: .topTrailing) {
                        if takenCoverIndexes.contains(index) && colorIndex != index {
                            Circle()
                                .fill(Theme.ivory.opacity(0.6))
                                .frame(width: 5, height: 5)
                                .padding(6)
                        }
                    }
                }
                .buttonStyle(PressStyle(scale: 0.94))
                .accessibilityLabel(Theme.coverName(at: index))
                .accessibilityAddTraits(colorIndex == index ? .isSelected : [])
            }
        }
    }

    // MARK: Данные

    private var existingCardsCount: Int {
        if case .rename(let folder) = mode { return folder.cards.count }
        return 0
    }

    private func prepare() {
        switch mode {
        case .create(let suggested):
            name = ""
            colorIndex = freeCoverIndex(startingAt: suggested)
        case .rename(let folder):
            name = folder.name
            colorIndex = folder.colorIndex
        }
        // Клавиатуру поднимаем чуть позже, чтобы лист успел выехать
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            nameFocused = true
        }
    }

    /// Ищет незанятый тон, чтобы новые тетради не сливались на полке.
    private func freeCoverIndex(startingAt start: Int) -> Int {
        let count = Theme.covers.count
        for offset in 0..<count {
            let candidate = (start + offset) % count
            if !takenCoverIndexes.contains(candidate) { return candidate }
        }
        return start % count
    }

    private func save() {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty else { return }
        onSave(trimmed, colorIndex)
        dismiss()
    }
}
