import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private var settings = SettingsStore()
    private let recorder = AudioRecorder()
    private let transcriber = ParakeetTranscriber()
    private let hotkeyController = HotkeyController()
    private let recordingHUD = RecordingHUDWindowController()
    private var hotkeyError: String?
    private var targetAppForPaste: NSRunningApplication?
    private var audioMuteToken: MediaController.MuteToken?
    private var statusItem: NSStatusItem?
    private var preferencesWindowController: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.autoPaste = settings.autoPaste
        appState.muteAudioWhileListening = settings.muteAudioWhileListening
        recorder.onLevel = { [weak self] level in
            Task { @MainActor in
                self?.recordingHUD.updateAudioLevel(level)
            }
        }
        setupMenu()
        setupHotkey()
        requestPermissionsAndWarmUp()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyController.stop()
        _ = recorder.stop()
        stopMutingAudioIfNeeded()
    }

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "◉"
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let status = NSMenuItem(title: "Status: \(appState.status)", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Start Listening", action: #selector(startListeningFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Stop Listening", action: #selector(stopListeningFromMenu), keyEquivalent: ""))

        let autoPaste = NSMenuItem(title: "Paste Automatically", action: #selector(toggleAutoPaste), keyEquivalent: "")
        autoPaste.state = appState.autoPaste ? .on : .off
        menu.addItem(autoPaste)

        let muteAudio = NSMenuItem(title: "Mute Audio While Listening", action: #selector(toggleMuteAudio), keyEquivalent: "")
        muteAudio.state = appState.muteAudioWhileListening ? .on : .off
        menu.addItem(muteAudio)

        let copyLast = NSMenuItem(title: "Copy Last Transcript", action: #selector(copyLastTranscript), keyEquivalent: "")
        copyLast.isEnabled = !appState.lastTranscript.isEmpty
        menu.addItem(copyLast)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    private func setupHotkey() {
        hotkeyController.onPressed = { [weak self] in
            Task { @MainActor in self?.startRecording() }
        }
        hotkeyController.onReleased = { [weak self] in
            Task { @MainActor in self?.stopRecordingAndTranscribe() }
        }
        let status = hotkeyController.start()
        guard status == noErr else {
            hotkeyError = "Option-/ hotkey failed to register (OSStatus \(status)). Another app may already own it."
            appState.status = "Hotkey failed"
            appState.lastError = hotkeyError
            rebuildMenu()
            return
        }
    }

    private func requestPermissionsAndWarmUp() {
        let trusted = PermissionManager.requestAccessibilityAccess()
        if !trusted {
            appState.status = "Grant Accessibility, then relaunch"
            appState.lastError = "Option-/ needs Accessibility permission for global hotkey and paste."
            rebuildMenu()
        }

        Task {
            let hasMicrophone = await PermissionManager.requestMicrophoneAccess()
            await MainActor.run {
                if !hasMicrophone {
                    appState.status = "Microphone denied"
                    appState.lastError = "Microphone permission is required."
                    rebuildMenu()
                } else if trusted {
                    appState.status = "Loading Parakeet"
                    rebuildMenu()
                }
            }

            guard hasMicrophone else { return }

            do {
                try await transcriber.warmUp()
                await MainActor.run {
                    appState.status = hotkeyError == nil ? "Hold Option-/" : "Hotkey failed"
                    appState.lastError = hotkeyError
                    rebuildMenu()
                }
            } catch {
                await MainActor.run {
                    appState.status = "Model load failed"
                    appState.lastError = error.localizedDescription
                    rebuildMenu()
                }
            }
        }
    }

    private func startRecording() {
        guard !appState.isRecording, !appState.isTranscribing else { return }
        targetAppForPaste = NSWorkspace.shared.frontmostApplication
        NSLog("ParakeetPTT target app for paste: \(targetAppForPaste?.localizedName ?? "unknown")")
        audioMuteToken = nil
        if appState.muteAudioWhileListening {
            let muteToken = MediaController.muteSystemAudioForRecording()
            audioMuteToken = muteToken.isMuting ? muteToken : nil
        }

        Task {
            guard await PermissionManager.requestMicrophoneAccess() else {
                await MainActor.run {
                    stopMutingAudioIfNeeded()
                    appState.status = "Microphone denied"
                    appState.lastError = "Microphone permission is required."
                    rebuildMenu()
                }
                return
            }

            do {
                try recorder.start()
                await MainActor.run {
                    appState.isRecording = true
                    appState.status = "Listening"
                    appState.lastError = nil
                    statusItem?.button?.title = "●"
                    recordingHUD.show(mode: .recording)
                    rebuildMenu()
                }
            } catch {
                await MainActor.run {
                    stopMutingAudioIfNeeded()
                    appState.status = "Recording failed"
                    appState.lastError = error.localizedDescription
                    recordingHUD.hide()
                    rebuildMenu()
                }
            }
        }
    }

    private func stopRecordingAndTranscribe() {
        guard appState.isRecording else {
            stopMutingAudioIfNeeded()
            return
        }

        let samples = recorder.stop()
        stopMutingAudioIfNeeded()
        appState.isRecording = false
        statusItem?.button?.title = "◉"
        let duration = Double(samples.count) / 16_000.0
        let rms = audioRMS(samples)
        NSLog(
            "ParakeetPTT captured %.2fs audio, %d samples, rms %.5f",
            duration,
            samples.count,
            rms
        )

        guard samples.count >= 4_800 else {
            appState.status = "Hold Option-/"
            appState.lastError = String(format: "Recording too short: %.2fs", duration)
            recordingHUD.hide()
            rebuildMenu()
            return
        }

        appState.isTranscribing = true
        appState.status = "Transcribing"
        recordingHUD.update(mode: .transcribing)
        rebuildMenu()

        Task {
            do {
                let text = try await transcriber.transcribe(samples: samples)
                await MainActor.run {
                    NSLog(
                        "ParakeetPTT transcript result: %d chars, preview: %@",
                        text.count,
                        text.prefix(120) as NSString
                    )
                    appState.isTranscribing = false
                    appState.lastTranscript = text
                    appState.status = text.isEmpty ? "No speech detected" : "Transcript ready"
                    appState.lastError = text.isEmpty
                        ? String(format: "Captured %.2fs audio, but Parakeet returned empty text. Try speaking louder or holding longer.", duration)
                        : nil
                    if appState.autoPaste, !text.isEmpty {
                        let pasteAllowed = TextInjector.paste(text, into: targetAppForPaste)
                        if !pasteAllowed {
                            appState.status = "Transcript copied"
                            appState.lastError = "Auto-paste needs Accessibility permission. The transcript is on your clipboard."
                        }
                    }
                    recordingHUD.hide()
                    rebuildMenu()
                }
            } catch {
                await MainActor.run {
                    appState.isTranscribing = false
                    appState.status = "Transcription failed"
                    appState.lastError = error.localizedDescription
                    recordingHUD.hide()
                    rebuildMenu()
                }
            }
        }
    }

    @objc private func startListeningFromMenu() {
        startRecording()
    }

    @objc private func stopListeningFromMenu() {
        stopRecordingAndTranscribe()
    }

    @objc private func toggleAutoPaste() {
        appState.autoPaste.toggle()
        settings.autoPaste = appState.autoPaste
        rebuildMenu()
    }

    @objc private func toggleMuteAudio() {
        appState.muteAudioWhileListening.toggle()
        settings.muteAudioWhileListening = appState.muteAudioWhileListening
        rebuildMenu()
    }

    @objc private func copyLastTranscript() {
        guard !appState.lastTranscript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.lastTranscript, forType: .string)
        appState.status = "Transcript copied"
        rebuildMenu()
    }

    @objc private func showPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(
                appState: appState,
                onAutoPasteChanged: { [weak self] value in
                    self?.settings.autoPaste = value
                    self?.rebuildMenu()
                },
                onMuteAudioChanged: { [weak self] value in
                    self?.settings.muteAudioWhileListening = value
                    self?.rebuildMenu()
                },
                onOpenPrivacy: { PermissionManager.openPrivacySettings() }
            )
        }
        preferencesWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openAccessibilitySettings() {
        PermissionManager.openPrivacySettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func audioRMS(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Double(0)) { partial, sample in
            let value = Double(sample)
            return partial + value * value
        }
        return sqrt(sum / Double(samples.count))
    }

    private func stopMutingAudioIfNeeded() {
        guard let audioMuteToken else { return }
        self.audioMuteToken = nil
        MediaController.unmuteSystemAudioAfterRecording(audioMuteToken)
    }
}
