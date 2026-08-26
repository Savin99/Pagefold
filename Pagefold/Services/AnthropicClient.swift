import Foundation

/// Ошибки ИИ-клиента с понятными пользователю сообщениями.
enum AIError: LocalizedError {
    case badResponse
    case unauthorized
    case rateLimited
    case overloaded
    case api(status: Int, message: String)
    case refusal

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "Не удалось связаться с сервером ИИ. Проверь интернет."
        case .unauthorized:
            return "Ключ не подошёл. Проверь его в настройках."
        case .rateLimited:
            return "Слишком много запросов подряд. Попробуй через минуту."
        case .overloaded:
            return "Модель сейчас перегружена. Попробуй ещё раз."
        case .api(let status, let message):
            return "Ошибка API (\(status)): \(message)"
        case .refusal:
            return "Запрос отклонён политиками безопасности модели."
        }
    }

    /// Разбор кода ответа в понятную ошибку.
    static func from(status: Int, message: @autoclosure () -> String) -> AIError {
        switch status {
        case 401, 403: return .unauthorized
        case 429: return .rateLimited
        case 500, 502, 503, 529: return .overloaded
        default: return .api(status: status, message: message())
        }
    }
}

/// Минимальный клиент Claude API (Anthropic Messages API) со стримингом SSE.
/// Swift не имеет официального SDK, поэтому ходим по HTTP напрямую.
struct AnthropicClient {
    let apiKey: String
    var model = "claude-opus-5"

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let modelsEndpoint = URL(string: "https://api.anthropic.com/v1/models?limit=1")!

    /// Стримит текст ответа модели кусками по мере генерации.
    func streamText(system: String, userMessage: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(system: system, userMessage: userMessage)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw AIError.badResponse
                    }
                    guard http.statusCode == 200 else {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                        }
                        throw AIError.from(status: http.statusCode, message: Self.extractErrorMessage(from: body))
                    }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard
                            let data = payload.data(using: .utf8),
                            let event = try? JSONDecoder().decode(StreamEvent.self, from: data)
                        else { continue }

                        switch event.type {
                        case "content_block_delta":
                            if event.delta?.type == "text_delta", let text = event.delta?.text {
                                continuation.yield(text)
                            }
                        case "message_delta":
                            if event.delta?.stopReason == "refusal" {
                                throw AIError.refusal
                            }
                        case "error":
                            throw AIError.api(status: 200, message: event.error?.message ?? "неизвестная ошибка стрима")
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Проверка ключа без расхода токенов: спрашиваем список моделей.
    func validate() async throws {
        var request = URLRequest(url: Self.modelsEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.badResponse }
        guard http.statusCode == 200 else {
            throw AIError.from(
                status: http.statusCode,
                message: Self.extractErrorMessage(from: String(data: data, encoding: .utf8) ?? "")
            )
        }
    }

    private func makeRequest(system: String, userMessage: String) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // Серверный fallback: при отказе по политикам запрос дорабатывает резервная модель
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")

        let body = RequestBody(
            model: model,
            maxTokens: 16000,
            stream: true,
            fallbacks: "default",
            system: system,
            messages: [.init(role: "user", content: userMessage)]
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// Достаёт человекочитаемое сообщение из тела ошибки API.
    private static func extractErrorMessage(from body: String) -> String {
        guard
            let data = body.data(using: .utf8),
            let parsed = try? JSONDecoder().decode(ErrorResponse.self, from: data)
        else {
            return body.isEmpty ? "пустой ответ" : body
        }
        return parsed.error.message
    }
}

// MARK: - Модели запроса и SSE-событий

private struct RequestBody: Encodable {
    let model: String
    let maxTokens: Int
    let stream: Bool
    let fallbacks: String
    let system: String
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case stream, fallbacks, system, messages
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct StreamEvent: Decodable {
    let type: String
    let delta: Delta?
    let error: APIErrorPayload?

    struct Delta: Decodable {
        let type: String?
        let text: String?
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case type, text
            case stopReason = "stop_reason"
        }
    }
}

private struct APIErrorPayload: Decodable {
    let message: String?
}

private struct ErrorResponse: Decodable {
    let error: ErrorDetail

    struct ErrorDetail: Decodable {
        let message: String
    }
}
