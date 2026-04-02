//
//  SpeechRecognizer.swift
//  dime
//

import AVFoundation
import Foundation
import Speech

class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var error: String?

    private var audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var timeoutTimer: Timer?

    private let maxDuration: TimeInterval = 30

    func requestPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                        DispatchQueue.main.async {
                            completion(allowed)
                        }
                    }
                default:
                    completion(false)
                }
            }
        }
    }

    func startRecording() {
        guard !isRecording else { return }

        // Reset state
        transcript = ""
        error = nil

        let recognizer = SFSpeechRecognizer(locale: Locale.current)
        guard let recognizer = recognizer, recognizer.isAvailable else {
            error = "Speech recognition not available"
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Audio session setup failed"
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            error = "Could not create recognition request"
            return
        }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
            [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) {
            [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                DispatchQueue.main.async {
                    self.transcript = result.bestTranscription.formattedString
                }

                if result.isFinal {
                    DispatchQueue.main.async {
                        self.stopRecording()
                    }
                }
            }

            if let error = error {
                DispatchQueue.main.async {
                    // Don't overwrite transcript if we already have one
                    if self.transcript.isEmpty {
                        self.error = error.localizedDescription
                    }
                    self.stopRecording()
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isRecording = true
            }

            // Auto-stop after max duration
            timeoutTimer = Timer.scheduledTimer(withTimeInterval: maxDuration, repeats: false) {
                [weak self] _ in
                DispatchQueue.main.async {
                    self?.stopRecording()
                }
            }
        } catch {
            self.error = "Audio engine failed to start"
            cleanupResources()
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        timeoutTimer?.invalidate()
        timeoutTimer = nil

        recognitionRequest?.endAudio()
        cleanupResources()

        isRecording = false
    }

    private func cleanupResources() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
