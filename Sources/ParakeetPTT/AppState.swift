import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var status: String = "Starting"
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var lastTranscript = ""
    @Published var lastError: String?
    @Published var autoPaste = true
}
