import SwiftUI

/// Настройки: ключ Anthropic, модель и сведения о приложении.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = ""
    @State private var savedKey = ""
    @State private var revealKey = false
    @State private var check: CheckState = .idle
    @State private var showDeleteKey = false

    /// Состояние проверки ключа.
    private enum CheckState: Equatable {
        case idle
        case checking
        case ok
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                keySection
                modelSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .paperBackground()
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save)
                        .fontWeight(.semibold)
                        .disabled(apiKey.trimmed == savedKey)
                }
            }
            .onAppear {
                savedKey = KeychainStore.apiKey ?? ""
                apiKey = savedKey
            }
            .confirmationDialog("Удалить ключ?", isPresented: $showDeleteKey, titleVisibility: .visible) {
                Button("Удалить ключ", role: .destructive) { deleteKey() }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("ИИ-панель перестанет работать, пока не введёшь ключ снова.")
            }
        }
    }

    // MARK: Ключ

    private var keySection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(statusTint)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                if check == .checking {
                    ProgressView()
                }
            }

            HStack(spacing: 8) {
                if revealKey {
                    TextField("sk-ant-…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.footnote, design: .monospaced))
                } else {
                    SecureField("sk-ant-…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Button {
                    revealKey.toggle()
                } label: {
                    Image(systemName: revealKey ? "eye.slash" : "eye")
                        .foregroundStyle(Theme.inkSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(revealKey ? "Скрыть ключ" : "Показать ключ")
            }

            Button {
                Task { await validate() }
            } label: {
                Label("Проверить ключ", systemImage: "checkmark.seal")
            }
            .disabled(apiKey.isBlank || check == .checking)

            if !savedKey.isEmpty {
                Button(role: .destructive) {
                    showDeleteKey = true
                } label: {
                    Label("Удалить ключ", systemImage: "trash")
                }
            }
        } header: {
            Eyebrow(text: "Ключ Anthropic")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ключ лежит только в Keychain этого устройства и никуда больше не уходит.")
                Link("Взять ключ в console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.footnote.weight(.medium))
            }
        }
    }

    private var modelSection: some View {
        Section {
            LabeledContent("Модель", value: "Claude Opus 5")
            LabeledContent("Резерв", value: "включён")
        } header: {
            Eyebrow(text: "ИИ")
        } footer: {
            Text("Если модель откажется отвечать по политикам безопасности, запрос автоматически подхватит резервная модель.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Версия", value: appVersion)
            VStack(alignment: .leading, spacing: 8) {
                Text("Как это работает")
                    .font(Font.system(.subheadline, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Тетрадь — проект. Внутри — лента записей: листай её как роадмап, добавляй фото и проси ИИ дописать, причесать или подвести итог. Записи и фотографии хранятся на устройстве.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineSpacing(3)
            }
            .padding(.vertical, 2)
        } header: {
            Eyebrow(text: "Pagefold")
        }
    }

    // MARK: Состояние

    private var statusIcon: String {
        switch check {
        case .ok: return "checkmark.seal.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .checking: return "hourglass"
        case .idle: return savedKey.isEmpty ? "key.slash" : "key.fill"
        }
    }

    private var statusTint: Color {
        switch check {
        case .ok: return Theme.sage
        case .failed: return Theme.wax
        case .checking: return Theme.inkSecondary
        case .idle: return savedKey.isEmpty ? Theme.wax : Theme.sage
        }
    }

    private var statusText: String {
        switch check {
        case .ok: return "Ключ рабочий"
        case .failed(let message): return message
        case .checking: return "Проверяю ключ…"
        case .idle: return savedKey.isEmpty ? "Ключа пока нет — ИИ выключен" : "Ключ сохранён"
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: Действия

    private func save() {
        let trimmed = apiKey.trimmed
        KeychainStore.apiKey = trimmed
        savedKey = trimmed
        apiKey = trimmed
        Haptics.success()
        dismiss()
    }

    private func deleteKey() {
        KeychainStore.apiKey = nil
        savedKey = ""
        apiKey = ""
        check = .idle
        Haptics.warning()
    }

    private func validate() async {
        let key = apiKey.trimmed
        guard !key.isEmpty else { return }
        check = .checking
        do {
            try await AnthropicClient(apiKey: key).validate()
            check = .ok
            Haptics.success()
            // Рабочий ключ сохраняем сразу — пользователь уже подтвердил намерение
            if key != savedKey {
                KeychainStore.apiKey = key
                savedKey = key
            }
        } catch {
            check = .failed(error.localizedDescription)
            Haptics.warning()
        }
    }
}
