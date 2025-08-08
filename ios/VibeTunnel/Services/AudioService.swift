import Foundation
import Observation
import TachikomaAudio

@MainActor
@Observable
final class AudioService {
    private let audioRecorder = AudioRecorder()

    var isRecording: Bool {
        audioRecorder.isRecording
    }

    func startRecording() async throws {
        try await audioRecorder.startRecording()
    }

    func stopRecording() async throws -> URL? {
        let audioData = try await audioRecorder.stopRecording()

        // Save to temporary file for compatibility with existing code
        let fileName = "recording_\(UUID().uuidString).wav"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        try audioData.write(to: url)
        return url
    }

    func cancelRecording() async {
        await audioRecorder.cancelRecording()
    }

    var isAvailable: Bool {
        audioRecorder.isAvailable
    }

    var recordingDuration: TimeInterval {
        audioRecorder.recordingDuration
    }
}
