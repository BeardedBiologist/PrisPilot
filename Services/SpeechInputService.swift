import AVFAudio
import Foundation
import Observation
import Speech

@MainActor
@Observable
final class SpeechInputService {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var seedText = ""
    private var isStoppingIntentionally = false

    var transcript = ""
    var isRecording = false
    var errorMessage: String?

    var isAvailable: Bool {
        speechRecognizer?.isAvailable == true
    }

    func toggleRecording(seedText: String) async {
        if isRecording {
            stopRecording()
        } else {
            await startRecording(seedText: seedText)
        }
    }

    func startRecording(seedText: String) async {
        errorMessage = nil
        self.seedText = seedText.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = self.seedText

        guard await requestPermissions() else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition is not available right now."
            return
        }

        stopRecognitionTask()
        isStoppingIntentionally = false

        do {
            try configureAudioSession()
            try startAudioEngine(using: speechRecognizer)
            isRecording = true
        } catch {
            stopRecording()
            errorMessage = "Could not start listening: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        isStoppingIntentionally = true
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestPermissions() async -> Bool {
        let speechStatus = await requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            errorMessage = speechAuthorizationMessage(for: speechStatus)
            return false
        }

        let hasMicrophoneAccess = await AVAudioApplication.requestRecordPermission()
        guard hasMicrophoneAccess else {
            errorMessage = "Microphone access is needed to speak to PrisPilot. You can enable it in Settings."
            return false
        }

        return true
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func speechAuthorizationMessage(for status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .denied:
            return "Speech recognition access is needed to dictate messages. You can enable it in Settings."
        case .restricted:
            return "Speech recognition is restricted on this device."
        case .notDetermined:
            return "Speech recognition access has not been decided yet."
        case .authorized:
            return ""
        @unknown default:
            return "Speech recognition is not available right now."
        }
    }

    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startAudioEngine(using speechRecognizer: SFSpeechRecognizer) throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.applyRecognizedText(result.bestTranscription.formattedString)
                    if result.isFinal {
                        self.stopRecording()
                    }
                }
                if let error {
                    if self.isStoppingIntentionally || self.isExpectedStopError(error) {
                        self.isStoppingIntentionally = false
                        return
                    }
                    self.errorMessage = self.displayMessage(for: error)
                    self.stopRecording()
                }
            }
        }
    }

    private func applyRecognizedText(_ recognizedText: String) {
        let trimmedRecognized = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if seedText.isEmpty {
            transcript = trimmedRecognized
        } else if trimmedRecognized.isEmpty {
            transcript = seedText
        } else {
            transcript = "\(seedText) \(trimmedRecognized)"
        }
    }

    private func stopRecognitionTask() {
        isStoppingIntentionally = true
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    private func isExpectedStopError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let message = nsError.localizedDescription.lowercased()
        return nsError.code == NSUserCancelledError ||
            message.contains("cancel") ||
            message.contains("closed")
    }

    private func displayMessage(for error: Error) -> String {
        let message = error.localizedDescription
        guard !message.isEmpty else {
            return "Speech recognition stopped unexpectedly."
        }
        return message
    }
}
