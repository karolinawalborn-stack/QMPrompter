import AVFoundation
import Speech

@MainActor
final class PromptDictation: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    @Published private(set) var errorMessage: String?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var inputTapInstalled = false
    private var recognitionSessionID = UUID()

    func toggle() {
        isRecording ? stop() : start()
    }

    func start() {
        Task {
            await startRecording()
        }
    }

    func stop() {
        recognitionSessionID = UUID()
        isRecording = false

        if inputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            inputTapInstalled = false
        }

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startRecording() async {
        stop()
        errorMessage = nil
        transcript = ""

        guard await requestSpeechAuthorization() else {
            errorMessage = "语音识别权限未开启。"
            return
        }

        guard await requestMicrophonePermission() else {
            errorMessage = "麦克风权限未开启。"
            return
        }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "当前语音识别不可用。"
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        recognitionRequest = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 512, format: format) { [weak request] buffer, _ in
                request?.append(buffer)
            }
            inputTapInstalled = true

            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            errorMessage = "麦克风启动失败。"
            stop()
            return
        }

        isRecording = true
        let sessionID = UUID()
        recognitionSessionID = sessionID
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard self?.recognitionSessionID == sessionID else { return }

                if let result {
                    self?.transcript = result.bestTranscription.formattedString
                }

                if error != nil {
                    guard self?.isRecording == true else { return }
                    self?.errorMessage = "语音输入中断。"
                    self?.stop()
                }
            }
        }
    }

    private func requestSpeechAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
