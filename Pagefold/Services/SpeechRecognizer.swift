import Foundation
import Speech
import AVFoundation
import Observation

/// Диктовка: живое распознавание речи через Speech framework.
/// Частичные результаты попадают в `transcript` по мере произнесения.
@MainActor
@Observable
final class SpeechRecognizer {
    var transcript = ""
    var isRecording = false
    var errorMessage: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // Русская локаль в приоритете, иначе — системная
    private let recognizer: SFSpeechRecognizer? =
        SFSpeechRecognizer(locale: Locale(identifier: "ru-RU")) ?? SFSpeechRecognizer()

    func start() async {
        errorMessage = nil

        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard authStatus == .authorized else {
            errorMessage = "Нет доступа к распознаванию речи. Разреши его в Настройках."
            return
        }

        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Нет доступа к микрофону. Разреши его в Настройках."
            return
        }

        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Распознавание речи сейчас недоступно."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true

            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            engine.prepare()
            try engine.start()

            audioEngine = engine
            recognitionRequest = request
            transcript = ""
            isRecording = true

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if let error {
                        // Если запись остановили вручную, isRecording уже false —
                        // такую «ошибку отмены» пользователю не показываем.
                        if self.isRecording && self.transcript.isEmpty {
                            self.errorMessage = "Диктовка не сработала: \(error.localizedDescription)"
                        }
                        self.stop()
                    } else if result?.isFinal ?? false {
                        self.stop()
                    }
                }
            }
        } catch {
            errorMessage = "Не удалось начать запись: \(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
