import SwiftUI

// MARK: - Бумажное зерно

/// Однократно отрисованная плитка шума: смесь тёмных и светлых крапинок,
/// работает и в светлой, и в тёмной теме без блендов.
private enum PaperTexture {
    static let tile: UIImage = {
        let side: CGFloat = 128
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { ctx in
            for _ in 0..<1700 {
                let x = CGFloat.random(in: 0..<side)
                let y = CGFloat.random(in: 0..<side)
                let isLight = Bool.random()
                let alpha = CGFloat.random(in: 0.028...0.085)
                ctx.cgContext.setFillColor(UIColor(white: isLight ? 1 : 0, alpha: alpha).cgColor)
                ctx.cgContext.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
    }()
}

/// Слой фактуры бумаги/ткани. Накладывается поверх заливки.
struct PaperGrain: View {
    var opacity: Double = 1

    var body: some View {
        Image(uiImage: PaperTexture.tile)
            .resizable(resizingMode: .tile)
            .opacity(opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Фон экрана: бумага с зерном и мягкой виньеткой к краям.
    func paperBackground() -> some View {
        background(
            ZStack {
                Theme.paper
                RadialGradient(
                    colors: [.clear, Theme.paperDeep.opacity(0.55)],
                    center: .center,
                    startRadius: 180,
                    endRadius: 620
                )
                PaperGrain(opacity: 0.55)
            }
            .ignoresSafeArea()
        )
    }

    /// Лёгкое «тиснение» текста на тканевой обложке.
    func letterpress() -> some View {
        shadow(color: .black.opacity(0.35), radius: 0.5, y: -0.6)
    }
}

// MARK: - Разлиновка и разделитель

/// Горизонтальная разлиновка — как на чистом листе тетради.
struct RuledLines: View {
    var spacing: CGFloat = 24
    var opacity: Double = 1

    var body: some View {
        GeometryReader { geo in
            Path { path in
                var y = spacing
                while y < geo.size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    y += spacing
                }
            }
            .stroke(Theme.hairline.opacity(opacity), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Фирменный разделитель: волосяная линия с узлом-колечком по центру —
/// то же колечко, что связывает страницы в ленте.
struct InkDivider: View {
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
            Circle()
                .strokeBorder(Theme.inkSecondary.opacity(0.55), lineWidth: 1.2)
                .frame(width: 6, height: 6)
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

/// Капительная «бровь»: штрих-акцент и текст. Единая для всех экранов.
struct Eyebrow: View {
    let text: String
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(tint)
                .frame(width: 16, height: 2)
            Text(text)
                .font(Typo.eyebrow)
                .tracking(1.4)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Фирменная форма: страница с загнутым уголком

/// Скруглённый прямоугольник со «срезанным» правым верхним углом —
/// силуэт страницы с загнутым уголком (pagefold).
struct DogEarRect: InsettableShape {
    var cornerRadius: CGFloat = 20
    var fold: CGFloat = 30
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> DogEarRect {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    func path(in outerRect: CGRect) -> Path {
        let rect = outerRect.insetBy(dx: insetAmount, dy: insetAmount)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addArc(
            center: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
            radius: cornerRadius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
            radius: cornerRadius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
            radius: cornerRadius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// Сам «отогнутый» треугольник — накладывается в правый верхний угол
/// поверх DogEarRect.
struct FoldFlapShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct FoldCreaseLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

/// Готовая карточка-«страница»: обрезка по DogEarRect, зерно бумаги,
/// волосяная обводка, отогнутый уголок с тенью и двухслойная тень.
struct PageCardStyle: ViewModifier {
    var cornerRadius: CGFloat = 20
    var fold: CGFloat = 30
    /// Насколько «поднята» страница — для состояния нажатия и фокуса.
    var elevation: Double = 1

    func body(content: Content) -> some View {
        content
            .overlay(PaperGrain(opacity: 0.35))
            .clipShape(DogEarRect(cornerRadius: cornerRadius, fold: fold))
            .overlay(
                DogEarRect(cornerRadius: cornerRadius, fold: fold)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            // Тень, которую уголок отбрасывает на страницу и бумагу под срезом
            .overlay(alignment: .topTrailing) {
                FoldFlapShape()
                    .fill(.black.opacity(0.16))
                    .blur(radius: 4)
                    .offset(x: -2, y: 3)
                    .frame(width: fold, height: fold)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .topTrailing) {
                FoldFlapShape()
                    .fill(
                        LinearGradient(
                            colors: [Theme.foldFlap, Theme.foldFlap.opacity(0.72)],
                            startPoint: .topTrailing,
                            endPoint: .bottomLeading
                        )
                    )
                    .overlay(
                        FoldCreaseLine().stroke(Color.black.opacity(0.10), lineWidth: 1)
                    )
                    .frame(width: fold, height: fold)
                    .accessibilityHidden(true)
            }
            .shadow(color: .black.opacity(0.06 * elevation), radius: 3, y: 2)
            .shadow(color: .black.opacity(0.10 * elevation), radius: 20 * elevation, y: 13 * elevation)
    }
}

extension View {
    func pageCard(cornerRadius: CGFloat = 20, fold: CGFloat = 30, elevation: Double = 1) -> some View {
        modifier(PageCardStyle(cornerRadius: cornerRadius, fold: fold, elevation: elevation))
    }
}

// MARK: - Форма тетради

/// Форма обложки: у корешка углы почти прямые, у обреза — скруглённые,
/// как у настоящей тетради.
var notebookShape: UnevenRoundedRectangle {
    UnevenRoundedRectangle(
        topLeadingRadius: 5,
        bottomLeadingRadius: 5,
        bottomTrailingRadius: 16,
        topTrailingRadius: 16,
        style: .continuous
    )
}

// MARK: - Кнопки

/// Нажатие «вдавливает» элемент — как палец давит на бумагу.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Основная кнопка-«штамп»: чернильная плашка с капителью.
struct InkButtonStyle: ButtonStyle {
    var tint: Color = Theme.ink
    /// Бумажный цвет, а не фиксированная слоновая кость: в тёмной теме
    /// плашка светлеет, и текст должен темнеть вместе с ней.
    var textColor: Color = Theme.paper

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.subtitle.weight(.semibold))
            .tracking(1.1)
            .foregroundStyle(textColor)
            .padding(.horizontal, Space.lg)
            .padding(.vertical, 13)
            .background(
                Capsule().fill(tint)
                    .overlay(Capsule().fill(.white.opacity(configuration.isPressed ? 0.12 : 0)))
            )
            .overlay(
                Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: tint.opacity(0.28), radius: configuration.isPressed ? 4 : 12, y: configuration.isPressed ? 2 : 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Пустые состояния

/// Фирменное пустое состояние: нарисованная раскрытая тетрадь,
/// капительный заголовок, пояснение и действие.
struct PaperEmptyState<Action: View>: View {
    let title: String
    let message: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: 0) {
            OpenBookMark()
                .frame(width: 132, height: 104)
                .padding(.bottom, Space.lg)

            Text(title)
                .font(Font.system(.title2, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, Space.xs)
                .padding(.horizontal, Space.lg)

            action()
                .padding(.top, Space.lg)
        }
        .padding(Space.xl)
        .frame(maxWidth: 420)
    }
}

/// Декоративный знак: раскрытая тетрадь с загнутым уголком.
private struct OpenBookMark: View {
    var body: some View {
        ZStack {
            // Левая страница
            page
                .rotationEffect(.degrees(-7), anchor: .bottomTrailing)
                .offset(x: -26)
            // Правая страница
            page
                .rotationEffect(.degrees(7), anchor: .bottomLeading)
                .offset(x: 26)
            // Корешок
            Capsule()
                .fill(Theme.inkSecondary.opacity(0.35))
                .frame(width: 3, height: 86)
        }
        .accessibilityHidden(true)
    }

    private var page: some View {
        DogEarRect(cornerRadius: 6, fold: 14)
            .fill(Theme.surface)
            .overlay(
                DogEarRect(cornerRadius: 6, fold: 14)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .overlay(
                RuledLines(spacing: 13, opacity: 0.9)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 12)
            )
            .frame(width: 66, height: 92)
            .shadow(color: .black.opacity(0.08), radius: 8, y: 5)
    }
}

// MARK: - Чипсы и плашки

/// Капительный чипс: подсказка ИИ, тег, фильтр.
struct Chip: View {
    let text: String
    var icon: String?
    var tint: Color = Theme.ink

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon).font(.caption2.weight(.semibold))
            }
            Text(text)
                .font(.footnote.weight(.medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Theme.surface.opacity(0.9)))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

/// Маленькая метка-плашка на карточке: «черновик», «3 фото».
struct TagBadge: View {
    let text: String
    var icon: String?
    var tint: Color = Theme.inkSecondary

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(Typo.micro)
                .tracking(0.8)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(tint.opacity(0.10))
        )
        .overlay(Capsule().strokeBorder(tint.opacity(0.25), lineWidth: 0.75))
    }
}

// MARK: - Всплывающее уведомление

/// Ненавязчивая плашка снизу: ошибка, подтверждение, отмена действия.
struct ToastView: View {
    let message: String
    var icon: String = "exclamationmark.triangle.fill"
    var tint: Color = Theme.wax
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Divider().frame(height: 18)
                Button(actionTitle, action: action)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
