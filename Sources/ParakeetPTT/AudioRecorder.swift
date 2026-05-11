import AVFoundation
import FluidAudio
import Foundation
import os

final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let converter = AudioConverter()
    private let queue = DispatchQueue(label: "ParakeetPTT.AudioRecorder")
    private var samples: [Float] = []
    private var recording = false

    var onLevel: (@Sendable (Double) -> Void)?

    var isRecording: Bool {
        queue.sync { recording }
    }

    func start() throws {
        queue.sync {
            guard !recording else { return }
            samples.removeAll(keepingCapacity: true)
            recording = true
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            do {
                let converted = try self.converter.resampleBuffer(buffer)
                let level = Self.rms(converted)
                self.onLevel?(level)
                self.queue.async {
                    guard self.recording else { return }
                    self.samples.append(contentsOf: converted)
                }
            } catch {
                os_log("Audio conversion failed: %{public}@", String(describing: error))
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            queue.sync {
                recording = false
                samples.removeAll(keepingCapacity: true)
            }
            throw error
        }
    }

    func stop() -> [Float] {
        guard engine.isRunning || isRecording else {
            return []
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        return queue.sync {
            recording = false
            let captured = samples
            samples.removeAll(keepingCapacity: true)
            return captured
        }
    }

    private static func rms(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Double(0)) { partial, sample in
            let value = Double(sample)
            return partial + value * value
        }
        return sqrt(sum / Double(samples.count))
    }
}
