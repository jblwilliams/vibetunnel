import Foundation
import Observation
import Tachikoma
import TachikomaAudio

@MainActor
@Observable
final class TranscriptionService {
    private let provider: AIProvider
    private let apiKey: String

    /// Provide context for better technical term recognition
    private let contextualPrompt: String =
        """
        Technical terminal session context.
        Common commands: ls, cd, git, npm, docker, kubectl.
        Programming languages: Swift, JavaScript, Python, Go.
        Technical terms and code syntax expected.
        """

    enum AIProvider: String, CaseIterable {
        case openAI = "openai"
        case groq = "groq"
        case deepgram = "deepgram"
        case elevenlabs = "elevenlabs"

        var transcriptionModel: TranscriptionModel {
            switch self {
            case .openAI:
                .openai(.whisper1)
            case .groq:
                .groq(.whisperLargeV3)
            case .deepgram:
                .deepgram(.nova2)
            case .elevenlabs:
                .elevenlabs(.scribeV1)
            }
        }

        var displayName: String {
            switch self {
            case .openAI:
                "OpenAI Whisper"
            case .groq:
                "Groq"
            case .deepgram:
                "Deepgram"
            case .elevenlabs:
                "ElevenLabs"
            }
        }
    }

    init(provider: AIProvider, apiKey: String) {
        self.provider = provider
        self.apiKey = apiKey
    }

    func transcribe(audioFileURL: URL, language: String? = nil) async throws -> String {
        // Create configuration with API key
        let configuration = TachikomaConfiguration(loadFromEnvironment: false)
        configuration.setAPIKey(apiKey, for: provider.rawValue)

        // Use TachikomaAudio's transcription API with proper configuration
        return try await TachikomaAudio.transcribe(
            contentsOf: audioFileURL,
            using: provider.transcriptionModel,
            language: language,
            configuration: configuration
        )
    }

    func transcribeWithContext(
        audioFileURL: URL,
        currentPath: String? = nil,
        lastCommand: String? = nil
    )
        async throws -> String
    {
        // Create configuration with API key
        let configuration = TachikomaConfiguration(loadFromEnvironment: false)
        configuration.setAPIKey(apiKey, for: provider.rawValue)

        // Use TachikomaAudio's transcription API with contextual prompt
        let audioData = try AudioData(contentsOf: audioFileURL)
        let result = try await TachikomaAudio.transcribe(
            audioData,
            using: provider.transcriptionModel,
            language: "en",
            prompt: contextualPrompt,
            configuration: configuration
        )
        return result.text
    }

    enum TranscriptionError: LocalizedError {
        case invalidAudioData
        case providerError(String)

        var errorDescription: String? {
            switch self {
            case .invalidAudioData:
                "Could not read audio file"
            case .providerError(let message):
                "Transcription failed: \(message)"
            }
        }
    }
}
