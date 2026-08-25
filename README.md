<div align="center">

# CallTape

**Silent, automatic call recording for macOS. Both sides, on-device, source-available.**

Records your cellular, FaceTime, and WhatsApp calls straight on your Mac, transcribes and summarizes them locally, and keeps everything on your device. No accounts, no servers, nothing uploaded.

![Platform](https://img.shields.io/badge/macOS-15%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![License](https://img.shields.io/badge/License-Noncommercial-green)
[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%99%A5-E5A800)](https://github.com/sponsors/backpropghost)

**[Website](https://backpropghost.github.io/calltape/)** · [Download](https://github.com/backpropghost/calltape/releases) · [Sponsor](https://github.com/sponsors/backpropghost)

</div>

## Why

Recording a call on Apple platforms is deliberately hard, and every ready-made option came with a catch:

- **Third-party call-recording apps** merge in a separate conference line, so the other person hears a join and an announcement. Not silent, and not private.
- **On iPhone, iOS 26's Call Recording** plays an audible "this call is being recorded" notice to both sides. Useful, but the opposite of quiet.
- **Cloud recorders and "AI notetaker" bots** work by uploading your conversation to someone else's server. A hard no for something this personal.

None of those were acceptable, so CallTape takes a different route: it records the call **on your Mac**, at the system audio layer. Cellular and FaceTime calls arrive through Continuity; WhatsApp is captured directly. Both sides land in one file with **no beep and nothing announced to the other person**, and nothing ever leaves your machine. It is source-available, so you can confirm all of that for yourself.

## Features

- **Automatic.** Detects an active call and records hands-free, then stops when it ends.
- **Both sides, one file.** The other party plus your microphone, level-balanced, mono AAC.
- **No announcement.** Captured at the audio layer, so nothing is injected into the call.
- **Cellular, FaceTime, and WhatsApp.** Cellular and FaceTime come through Continuity; WhatsApp desktop calls are captured directly.
- **On-device transcription.** Full-length transcripts via Apple's SpeechAnalyzer, with clickable timestamps and speaker labels ("You" vs the caller).
- **On-device summaries.** Two-line summary plus action items via Apple Intelligence (Apple Silicon).
- **Rich, private metadata.** Name, number, direction, duration, and contact photo, resolved from your Mac's call logs and Contacts. Stored as plain text you own.
- **Bluetooth-safe.** Your mic is captured with AVAudioEngine, so AirPods and other headsets work.
- **Menu-bar app.** Live status and timer, one-tap record, recent calls, and quick access. Optional Dock icon.
- **Search everything**, including what was said inside transcripts.

## How it works

| Stage | Mechanism |
|-------|-----------|
| Detect | Core Audio process activity on `com.apple.avconferenced` and WhatsApp |
| Capture (other party) | `AudioHardwareCreateProcessTap` on the call process |
| Capture (you) | `AVAudioEngine` on the default input device |
| Encode | `AVAudioFile` to mono AAC (64 kbps default) |
| Enrich | Matched against Apple's call log, WhatsApp's databases (incl. `LID.sqlite`), and Contacts |
| Transcribe | `SpeechAnalyzer` / `SpeechTranscriber`, forced on-device |
| Summarize | Foundation Models (`LanguageModelSession`), on-device |

## Requirements

- macOS 15 or later (transcription and summaries use macOS 26 APIs; on older systems the app records and labels calls, transcription falls back to the classic recognizer).
- Xcode / the Swift toolchain to build.

## Build and run

```sh
# One time: a stable signing identity so macOS permissions persist across rebuilds.
./scripts/make-signing-cert.sh

# Build the app and install it to /Applications.
./scripts/build.sh --install
open /Applications/CallTape.app
```

On first launch, grant **Microphone** and **Contacts** when asked, and enable **Full Disk Access** for CallTape so it can read the call log for names and numbers.

## Privacy

Everything stays on your Mac. There is no account, no analytics, and no server. Recordings and their metadata are plain files in a folder you choose. Transcription is forced on-device (`requiresOnDeviceRecognition`) and summaries run on the local model.

Recording calls is regulated and the rules differ by region. It is your responsibility to record only where it is legal and to obtain any consent the law requires. See [DISCLAIMER.md](DISCLAIMER.md).

## Project layout

```
Sources/CallTape/
  App.swift           entry point, menu bar, windows, menu commands
  Engine.swift        call detection, process tap, mic capture, mixing, speaker timeline
  Enrichment.swift    call-log matching, WhatsApp + LID lookup, Contacts, sidecars
  Transcription.swift on-device transcription (SpeechAnalyzer) and summaries
  Recordings.swift    folder-backed list of recordings
  MainView.swift      three-column library shell and sidebar
  CallsView.swift     call list, detail, playback, transcript UI
  MenuView.swift      menu-bar popover
  SettingsView.swift  settings pane
  Player.swift        audio playback
  Intents.swift       Siri / Shortcuts actions
  ...
```

## Support

CallTape is free for you, and it stays that way. If it ever saved you a "wait, what did they say?" moment, you can chip in.

Right now the money has a very specific, very boring job: an **Apple Developer ID** (the $99/year Apple tax). With it I can properly sign and notarize the app so you stop seeing the scary "unidentified developer" warning on install. So really you'd be buying the app a passport.

[**Sponsor on GitHub →**](https://github.com/sponsors/backpropghost)

No pressure though. Using it, starring the repo, and telling a friend all count as support too.

## License

Source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE): **free for personal, non-commercial use**, forever. You can read it, run it, tinker with it, and share it. You just can't use it (or its code) commercially or in a business without permission. Note this is a source-available license, not an OSI open-source one, precisely because of that restriction.
