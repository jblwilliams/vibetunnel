import Observation
import SwiftUI

@MainActor
@Observable
final class VoiceInputViewModel {
    private(set) var isRecording = false
    private(set) var isTranscribing = false
    private(set) var error: Error?

    private let audioService: AudioService
    private let transcriptionService: TranscriptionService

    init(audioService: AudioService, transcriptionService: TranscriptionService) {
        self.audioService = audioService
        self.transcriptionService = transcriptionService
    }

    func toggleRecording() async -> String? {
        if isRecording {
            return await stopAndTranscribe()
        } else {
            await startRecording()
            return nil
        }
    }

    private func startRecording() async {
        error = nil
        do {
            try await audioService.startRecording()
            isRecording = true
        } catch {
            self.error = error
        }
    }

    private func stopAndTranscribe() async -> String? {
        isRecording = false

        let audioURL: URL
        do {
            guard let url = try await audioService.stopRecording() else {
                error = TranscriptionError.noAudioRecorded
                return nil
            }
            audioURL = url
        } catch {
            self.error = error
            return nil
        }

        isTranscribing = true
        defer { isTranscribing = false }

        do {
            let transcribedText = try await transcriptionService.transcribe(audioFileURL: audioURL)

            // Clean up temporary file
            try? FileManager.default.removeItem(at: audioURL)

            return transcribedText
        } catch {
            self.error = error
            return nil
        }
    }

    enum TranscriptionError: LocalizedError {
        case noAudioRecorded

        var errorDescription: String? {
            switch self {
            case .noAudioRecorded:
                "No audio was recorded"
            }
        }
    }
}

// MARK: - Voice Commands

extension VoiceInputViewModel {
    enum VoiceCommand {
        case clear
        case cancel
        case run
        case tab
        case none

        init(from text: String) {
            switch text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
            case "clear", "clear screen":
                self = .clear
            case "cancel", "stop":
                self = .cancel
            case "run", "execute":
                self = .run
            case "tab", "complete":
                self = .tab
            default:
                self = .none
            }
        }

        var terminalCommand: String? {
            switch self {
            case .clear: "\u{000C}" // Ctrl+L
            case .cancel: "\u{0003}" // Ctrl+C
            case .run: "\n"
            case .tab: "\t"
            case .none: nil
            }
        }
    }

    func processVoiceCommand(_ text: String) -> (command: VoiceCommand, processedText: String?) {
        let command = VoiceCommand(from: text)
        if command != .none {
            return (command, nil)
        }
        return (.none, text)
    }
}
