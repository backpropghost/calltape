# CallTape

**Silent, automatic call recording for macOS. Both sides, no announcement, no extra hardware.**

CallTape runs quietly in your menu bar and records your calls the moment they start:
the other party through a Core Audio process tap, your own voice through the
microphone, mixed into a single AAC file with a JSON sidecar (number, direction,
duration, contact). It works for cellular and FaceTime calls answered on the Mac
through Continuity, and for WhatsApp desktop calls.

> Recording calls is your responsibility to use lawfully. Consent rules vary by
> region, so make sure you are allowed to record where you are. See the in-app
> disclaimer for details.

## Features

- **Automatic.** Detects an active call and records hands-free, then stops when it ends.
- **Both sides, one file.** The remote party plus your mic, level-balanced, mono AAC.
- **No announcement.** Captures at the audio layer, so nothing is injected into the call.
- **Bluetooth-safe.** Your mic is captured with AVAudioEngine, so AirPods and Buds work.
- **Rich metadata.** Every recording gets a plain-text `.json` you fully own.
- **Menu-bar app.** Status, one-tap Record, recent recordings, and full Settings.
- **Private by design.** Everything stays on your Mac. No accounts, no servers.

## How it works

| Stage | Mechanism |
|-------|-----------|
| Detect | Core Audio process activity on `com.apple.avconferenced` and WhatsApp |
| Capture (remote) | `AudioHardwareCreateProcessTap` on the call process |
| Capture (you) | `AVAudioEngine` on the default input device |
| Encode | `AVAudioFile` to mono AAC (64 kbps default) |
| Enrich | Matched against Apple's call log, WhatsApp's databases, and Contacts |

WhatsApp direction, voice-vs-video, and phone numbers are recovered from WhatsApp's
own `CallHistory.sqlite` and `LID.sqlite`.

## Build

Requires macOS 15 or later and the Swift toolchain (Xcode).

```sh
./scripts/make-signing-cert.sh   # once: a stable identity so permissions persist
./scripts/build.sh --install     # builds CallTape.app and installs to /Applications
```

On first launch, grant **Microphone** and **Contacts** when prompted, and enable
**Full Disk Access** for CallTape so it can read the call log for metadata.

## Layout

```
Sources/CallTape/
  App.swift          entry point, menu bar, windows, Dock and login wiring
  Engine.swift       call detection, process tap, mic capture, mixing
  Enrichment.swift   call-log matching, WhatsApp and LID lookup, Contacts, sidecars
  Recordings.swift   folder-backed list of recordings
  MainView.swift     three-column library shell and sidebar
  CallsView.swift    call list, detail, playback, and actions
  MenuView.swift     menu-bar popover
  SettingsView.swift settings pane
  AboutPane.swift    about and disclaimer
  Onboarding.swift   first-run setup
  Components.swift   shared card and row components
  Theme.swift        palette, spacing, and Liquid Glass helpers
  Settings.swift     user preferences (UserDefaults)
  Permissions.swift  microphone, Contacts, and Full Disk Access helpers
  Player.swift       audio playback
  Log.swift          unified and rotating file logging
  Legal.swift        the disclaimer text
```

## License

MIT. See [LICENSE](LICENSE).
