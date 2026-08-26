import SwiftUI
import SwiftData

/// Фото на весь экран: листание, зум щипком и двойным тапом,
/// закрытие свайпом вниз.
struct PhotoViewerView: View {
    /// Читаем фото прямо из карточки: после удаления список сам обновится,
    /// и мы не держим ссылки на исчезнувшие объекты.
    @Bindable var card: Card
    let startIndex: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var index: Int
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGFloat = 0
    @State private var showDeleteConfirm = false
    @State private var chromeVisible = true

    init(card: Card, startIndex: Int) {
        self.card = card
        self.startIndex = startIndex
        _index = State(initialValue: startIndex)
    }

    private var images: [CardImage] { card.orderedImages }

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - min(abs(dragOffset) / 400, 0.55))
                .ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(images.enumerated()), id: \.element.persistentModelID) { position, image in
                    Group {
                        if let uiImage = UIImage(data: image.data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .scaleEffect(position == index ? scale : 1)
                                .offset(position == index ? offset : .zero)
                                .gesture(zoomGesture)
                                // Тянуть увеличенное фото можно, а вот отбирать
                                // горизонтальный свайп у листания — нельзя
                                .gesture(panGesture, including: isZoomed ? .all : .subviews)
                                .onTapGesture(count: 2) { toggleZoom() }
                                .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { chromeVisible.toggle() } }
                        } else {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(y: dragOffset)
            // Одновременный жест: листание страниц продолжает работать
            .simultaneousGesture(dismissGesture)

            if chromeVisible {
                chrome
            }
        }
        .statusBarHidden(true)
        .animation(.easeOut(duration: 0.2), value: chromeVisible)
        .onChange(of: index) { resetZoom(animated: false) }
        .confirmationDialog("Удалить фото?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Удалить фото", role: .destructive) { deleteCurrent() }
            Button("Отмена", role: .cancel) {}
        }
    }

    // MARK: Оформление

    private var chrome: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(.white.opacity(0.16)))
                }
                .accessibilityLabel("Закрыть")

                Spacer()

                if images.count > 1 {
                    Text("\(index + 1) / \(images.count)")
                        .font(Typo.micro)
                        .tracking(1.0)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.white.opacity(0.16)))
                }

                Spacer()

                Button { showDeleteConfirm = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(.white.opacity(0.16)))
                }
                .accessibilityLabel("Удалить фото")
            }
            .padding(.horizontal, Space.md)
            Spacer()
        }
        .transition(.opacity)
    }

    // MARK: Жесты

    private var isZoomed: Bool { scale > 1.02 }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(lastScale * value.magnification, 1), 5)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.02 { resetZoom(animated: true) }
            }
    }

    /// Перемещение увеличенного фото.
    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard isZoomed else { return }
                offset = value.translation
            }
            .onEnded { _ in
                guard isZoomed else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { offset = .zero }
            }
    }

    /// Свайп вниз закрывает — только когда фото не увеличено
    /// и движение явно вертикальное (иначе это листание).
    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard !isZoomed, abs(value.translation.height) > abs(value.translation.width) * 1.6 else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                guard !isZoomed else { return }
                if abs(value.translation.height) > 140,
                   abs(value.translation.height) > abs(value.translation.width) * 1.6 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { dragOffset = 0 }
                }
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            if scale > 1.02 {
                scale = 1
                offset = .zero
            } else {
                scale = 2.5
            }
            lastScale = scale
        }
        Haptics.soft()
    }

    private func resetZoom(animated: Bool) {
        if animated {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                scale = 1
                offset = .zero
            }
        } else {
            scale = 1
            offset = .zero
        }
        lastScale = 1
    }

    private func deleteCurrent() {
        guard images.indices.contains(index) else { return }
        let image = images[index]
        let wasLast = images.count == 1
        let newIndex = max(min(index, images.count - 2), 0)
        if wasLast {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { remove(image) }
        } else {
            index = newIndex
            remove(image)
        }
        Haptics.warning()
    }

    private func remove(_ image: CardImage) {
        context.delete(image)
        card.updatedAt = .now
        try? context.save()
    }
}
