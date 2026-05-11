# Parakeet PTT

Parakeet PTT is a small macOS menu bar app for local push-to-talk speech transcription.

It records while you hold `Option-/`, transcribes locally with FluidAudio's CoreML build of NVIDIA Parakeet TDT v2, copies the transcript to the clipboard, and tries to insert it into the active app.

There is no Whisper, OpenAI API, cloud transcription, translation, summarization, or background meeting mode.

## Requirements

- Apple Silicon Mac
- macOS 14 or newer
- Xcode Command Line Tools
- Microphone permission
- Accessibility permission for automatic text insertion

Install Command Line Tools if needed:

```bash
xcode-select --install
```

## Install From Source

Clone the repo:

```bash
git clone https://github.com/henry-pg/ParakeetPTT.git
cd ParakeetPTT
```

Check the Swift toolchain:

```bash
Scripts/doctor.sh
```

Build and install the app into `~/Applications`:

```bash
Scripts/install-app.sh
```

Launch it:

```bash
open ~/Applications/Parakeet\ PTT.app
```

On first launch, FluidAudio downloads the Parakeet CoreML model into its local cache. The model is not committed to this repository.

## Permissions

Grant these macOS permissions:

- **Microphone**: required to record audio.
- **Accessibility**: required for global text insertion and paste simulation.

Open Accessibility settings:

```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
```

Add and enable this exact app:

```text
~/Applications/Parakeet PTT.app
```

If auto-insert does not work after rebuilding, remove the old Parakeet PTT entry from Accessibility, run `Scripts/install-app.sh`, re-add the `~/Applications` app, and relaunch.

## Usage

1. Click into a text field.
2. Hold `Option-/`.
3. Speak.
4. Release `Option-/`.

The app shows a floating waveform HUD while recording. The waveform is based on real microphone levels and freezes while transcription runs.

After transcription:

- The transcript is copied to the clipboard.
- The app attempts automatic insertion.
- If automatic insertion fails, press `Cmd-V` manually.

The menu bar item also includes **Copy Last Transcript**.

## Build Scripts

```bash
Scripts/doctor.sh
```

Checks that Swift, SwiftPM, Foundation imports, and the package manifest work.

```bash
Scripts/build-app.sh
```

Builds a release binary and packages it as:

```text
.build/Parakeet PTT.app
```

```bash
Scripts/install-app.sh
```

Builds the app and installs it to:

```text
~/Applications/Parakeet PTT.app
```

## Architecture

- `AudioRecorder`: captures microphone audio with `AVAudioEngine`.
- `ParakeetTranscriber`: loads and runs FluidAudio Parakeet v2 locally.
- `HotkeyController`: registers the global `Option-/` push-to-talk hotkey.
- `RecordingHUDWindowController`: displays the floating waveform HUD.
- `TextInjector`: copies the transcript and attempts automatic insertion.

## Notes

- This app is English-only because it intentionally uses Parakeet v2.
- The first transcription may take longer while the model loads.
- Terminal apps can be harder to insert into than standard text fields; the transcript still remains on the clipboard.
- The repository intentionally ignores `.build/`, downloaded models, and local app bundles.

## License

No license has been added yet. Add a license before publishing if you want others to reuse or modify the code.
