import SwiftUI
import SwiftData

/// Куда ИИ пишет ответ.
enum AITarget {
    /// Дописать в конец текста записи.
    case appendText
    /// Перезаписать текст записи целиком.
    case replaceText
    /// Заполнить заголовок.
    case setTitle
}

/// Готовое действие ИИ — чипс над панелью.
struct AIAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let instruction: String
    let target: AITarget
}

/// Нижняя панель: чипсы-действия, «таблетка» с промптом и кнопка микрофона.
/// Ответ ИИ пишется прямо в карточку — с возможностью отменить.
struct AIPromptBar: View {
    @Bindable var card: Card
    @Binding var isStreaming: Bool

    @State private var prompt = ""
    @State private var toast: BarToast?
    @State private var showSettings = false
    @State private var speech = SpeechRecognizer()
    @State private var promptBeforeDictation = ""
    @State private var streamTask: Task<Void, Never>?
    @State private var toastTask: Task<Void, Never>?
    @State private var undoSnapshot: Snapshot?
    @FocusState private var promptFocused: Bool

    /// Что показываем плашкой над панелью.
    private struct BarToast: Identifiable {
        let id = UUID()
        let message: String
        var icon: String = "exclamationmark.triangle.fill"
        var tint: Color = Theme.wax
        var actionTitle: String?
        var action: (() -> Void)?
    }

    /// Состояние карточки до вмешательства ИИ — для отмены.
    private struct Snapshot {
        let title: String
        let text: String
    }

    var body: some View {
        VStack(spacing: 8) {
            if let toast {
                ToastView(
                    message: toast.message,
                    icon: toast.icon,
                    tint: toast.tint,
                    actionTitle: toast.actionTitle,
                    action: toast.action
                )
                .id(toast.id)
            }

            if showsActions {
                actionChips
            }

            HStack(spacing: 10) {
                promptPill
                micButton
            }
        }
        .padding(.horizontal, Space.screen)
        .padding(.top, Space.sm)
        .padding(.bottom, Space.sm)
        .background(
            LinearGradient(
                colors: [Theme.paper.opacity(0), Theme.paper.opacity(0.92), Theme.paper],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showsActions)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toast?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isStreaming)
        .onChange(of: speech.transcript) { applyDictation() }
        .onChange(of: speech.errorMessage) {
            if let message = speech.errorMessage {
                show(BarToast(message: message), duration: 9)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onDisappear {
            speech.stop()
            streamTask?.cancel()
            toastTask?.cancel()
        }
    }

    // MARK: Панель промпта

    private var promptPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.subheadline)
                .foregroundStyle(Theme.accent)
                .symbolEffect(.variableColor.iterative, isActive: isStreaming)

            if isStreaming {
                Text("ИИ пишет…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                Spacer(minLength: 0)
                Button {
                    streamTask?.cancel()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.surface)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.inkSecondary))
                }
                .accessibilityLabel("Остановить генерацию")
            } else {
                TextField("Попроси ИИ написать…", text: $prompt, axis: .vertical)
                    .lineLimit(1...4)
                    .foregroundStyle(Theme.ink)
                    .focused($promptFocused)
                    .submitLabel(.send)
                    .onSubmit { sendCustomPrompt() }

                if !prompt.isBlank {
                    Button(action: sendCustomPrompt) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Theme.accent))
                    }
                    .accessibilityLabel("Отправить запрос ИИ")
                }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(
            Capsule().strokeBorder(
                promptFocused || isStreaming ? Theme.accent.opacity(0.45) : Theme.hairline,
                lineWidth: 1
            )
        )
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
    }

    private var micButton: some View {
        Button(action: toggleMic) {
            Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.paper)
                .frame(width: 48, height: 48)
                .background(Circle().fill(speech.isRecording ? Theme.wax : Theme.ink))
                .symbolEffect(.pulse, isActive: speech.isRecording)
                .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
                .overlay {
                    if speech.isRecording {
                        Circle()
                            .strokeBorder(Theme.wax.opacity(0.35), lineWidth: 2)
                            .scaleEffect(1.25)
                    }
                }
        }
        .disabled(isStreaming)
        .opacity(isStreaming ? 0.4 : 1)
        .accessibilityLabel(speech.isRecording ? "Остановить диктовку" : "Диктовать запрос")
    }

    // MARK: Чипсы-действия

    private var showsActions: Bool {
        !isStreaming && prompt.isEmpty
    }

    private var actionChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(availableActions) { action in
                    Button {
                        run(action)
                    } label: {
                        Chip(text: action.title, icon: action.icon)
                    }
                    .buttonStyle(PressStyle(scale: 0.95))
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// Набор действий зависит от того, есть ли уже текст.
    private var availableActions: [AIAction] {
        if card.text.isBlank {
            var actions = [
                AIAction(
                    title: "Начни за меня",
                    icon: "pencil.line",
                    instruction: "Напиши начало записи дневника по теме заголовка — 2–3 абзаца живого текста.",
                    target: .appendText
                ),
                AIAction(
                    title: "О чём написать",
                    icon: "lightbulb",
                    instruction: "Предложи 5 коротких идей, о чём можно написать в этой записи. Список без вступления.",
                    target: .appendText
                ),
            ]
            if !card.hasTitle {
                actions.append(
                    AIAction(
                        title: "Заголовок",
                        icon: "textformat",
                        instruction: "Придумай короткий заголовок записи дневника (до 6 слов) на тему проекта. Ответь только заголовком.",
                        target: .setTitle
                    )
                )
            }
            return actions
        }
        return [
            AIAction(
                title: "Продолжи",
                icon: "text.append",
                instruction: "Продолжи текст с того места, где он оборвался: тот же тон, язык и время. Только продолжение, без повторов.",
                target: .appendText
            ),
            AIAction(
                title: "Итог",
                icon: "list.bullet.rectangle",
                instruction: "Добавь короткий блок «Итог»: 2–3 предложения выводов по тексту записи.",
                target: .appendText
            ),
            AIAction(
                title: "Что дальше",
                icon: "arrow.turn.down.right",
                instruction: "Предложи 3–5 следующих шагов по этому проекту. Короткий список без вступления.",
                target: .appendText
            ),
            AIAction(
                title: "Причесать",
                icon: "wand.and.sparkles",
                instruction: "Перепиши текст записи: исправь ошибки, убери повторы и канцелярит. Сохрани смысл, тон, язык и структуру. Ответь только готовым текстом записи.",
                target: .replaceText
            ),
            AIAction(
                title: "Заголовок",
                icon: "textformat",
                instruction: "Придумай короткий заголовок (до 6 слов) для этой записи. Ответь только заголовком, без кавычек и точки в конце.",
                target: .setTitle
            ),
        ]
    }

    // MARK: Диктовка

    private func toggleMic() {
        if speech.isRecording {
            speech.stop()
            Haptics.soft()
        } else {
            promptBeforeDictation = prompt
            Haptics.tap()
            Task { await speech.start() }
        }
    }

    private func applyDictation() {
        guard speech.isRecording else { return }
        // Диктовка дописывается к тому, что уже было набрано
        if promptBeforeDictation.isEmpty {
            prompt = speech.transcript
        } else {
            prompt = promptBeforeDictation + " " + speech.transcript
        }
    }

    // MARK: Запросы к ИИ

    private func sendCustomPrompt() {
        let question = prompt.trimmed
        guard !question.isEmpty else { return }
        let action = AIAction(
            title: "Запрос",
            icon: "sparkles",
            instruction: question,
            target: .appendText
        )
        prompt = ""
        promptFocused = false
        run(action)
    }

    private func run(_ action: AIAction) {
        guard !isStreaming else { return }
        guard let apiKey = KeychainStore.apiKey, !apiKey.isEmpty else {
            show(BarToast(
                message: "Чтобы ИИ заработал, нужен ключ Anthropic.",
                icon: "key",
                tint: Theme.accent,
                actionTitle: "Настроить",
                action: { showSettings = true }
            ), duration: 12)
            return
        }

        speech.stop()
        promptFocused = false
        dismissToast()
        undoSnapshot = Snapshot(title: card.title, text: card.text)
        isStreaming = true
        Haptics.tap()

        let client = AnthropicClient(apiKey: apiKey)
        let userMessage = Self.composeUserMessage(card: card, instruction: action.instruction)

        streamTask = Task {
            var isFirstChunk = true
            var produced = 0
            do {
                let stream = client.streamText(system: Self.systemPrompt, userMessage: userMessage)
                for try await chunk in stream {
                    if isFirstChunk {
                        prepareTarget(action.target)
                        isFirstChunk = false
                    }
                    append(chunk, to: action.target)
                    produced += chunk.count
                }
                finish(action.target)
                card.updatedAt = .now
                Haptics.success()
                offerUndo(charactersAdded: produced)
            } catch is CancellationError {
                finish(action.target)
                card.updatedAt = .now
                offerUndo(charactersAdded: produced)
            } catch {
                restoreSnapshot()
                show(BarToast(message: error.localizedDescription), duration: 9)
                Haptics.warning()
            }
            isStreaming = false
        }
    }

    /// Готовит цель под запись: чистит поле там, где ответ его заменяет.
    private func prepareTarget(_ target: AITarget) {
        switch target {
        case .appendText:
            if !card.text.isEmpty { card.text += "\n\n" }
        case .replaceText:
            card.text = ""
        case .setTitle:
            card.title = ""
        }
    }

    private func append(_ chunk: String, to target: AITarget) {
        switch target {
        case .appendText, .replaceText:
            card.text += chunk
        case .setTitle:
            card.title += chunk
        }
    }

    /// Подчищает результат: заголовок должен остаться одной строкой.
    private func finish(_ target: AITarget) {
        switch target {
        case .setTitle:
            let firstLine = card.title
                .split(separator: "\n")
                .first
                .map { String($0).trimmed } ?? card.title.trimmed
            card.title = String(firstLine.trimmingCharacters(in: CharacterSet(charactersIn: "«»\"'. ")).prefix(80))
        case .replaceText:
            card.text = card.text.trimmed
        case .appendText:
            break
        }
    }

    // MARK: Отмена и плашки

    private func offerUndo(charactersAdded: Int) {
        guard charactersAdded > 0 else { return }
        show(BarToast(
            message: "ИИ написал \(charactersAdded) \(RU.plural(charactersAdded, "знак", "знака", "знаков")).",
            icon: "sparkles",
            tint: Theme.accent,
            actionTitle: "Отменить",
            action: restoreSnapshot
        ), duration: 10)
    }

    private func restoreSnapshot() {
        guard let snapshot = undoSnapshot else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            card.title = snapshot.title
            card.text = snapshot.text
        }
        card.updatedAt = .now
        undoSnapshot = nil
        dismissToast()
        Haptics.soft()
    }

    private func show(_ newToast: BarToast, duration: Double = 5) {
        toastTask?.cancel()
        toast = newToast
        toastTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { toast = nil }
        }
    }

    private func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    // MARK: Промпт

    private static let systemPrompt = """
    Ты — ИИ-помощник в приложении-дневнике Pagefold. Пользователь ведёт записи в карточках. \
    Твой ответ вставляется НАПРЯМУЮ в текст карточки, поэтому пиши сразу готовый текст: \
    без вступлений вроде «Вот текст», без мета-комментариев и без вопросов в конце. \
    Не оборачивай ответ в кавычки и не добавляй заголовков, если их не просили. \
    Отвечай на языке пользователя. Пиши живо и по делу.
    """

    /// Собирает сообщение для ИИ: контекст карточки + задание.
    private static func composeUserMessage(card: Card, instruction: String) -> String {
        var parts: [String] = []
        if let folderName = card.folder?.name, !folderName.isBlank {
            parts.append("Проект (тетрадь): \(folderName)")
        }
        if !card.title.isBlank {
            parts.append("Заголовок записи: \(card.title)")
        }
        if !card.text.isBlank {
            // Ограничиваем контекст, чтобы не раздувать запрос
            let text = String(card.text.suffix(8000))
            parts.append("Текущий текст записи:\n\(text)")
        }
        parts.append("Задание: \(instruction)")
        return parts.joined(separator: "\n\n")
    }
}
