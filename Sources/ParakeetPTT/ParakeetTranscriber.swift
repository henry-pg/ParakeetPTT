import FluidAudio
import Foundation

actor ParakeetTranscriber {
    private var manager: AsrManager?

    func warmUp() async throws {
        if manager != nil { return }

        let version = AsrModelVersion.v2
        let models = try await AsrModels.downloadAndLoad(version: version)
        let config = ASRConfig(
            tdtConfig: TdtConfig(blankId: version.blankId),
            encoderHiddenSize: version.encoderHiddenSize
        )
        let loadedManager = AsrManager(config: config)
        try await loadedManager.loadModels(models)
        manager = loadedManager
    }

    func transcribe(samples: [Float]) async throws -> String {
        try await warmUp()
        guard let manager else { return "" }

        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
