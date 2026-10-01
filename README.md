# Lumen Reader

A Flutter PDF reader that reads documents aloud with
[Kokoro](https://github.com/hexgrad/kokoro) neural speech — sentence by sentence,
highlighting the page as it goes. Runs on Windows and Android, fully offline.

![platform](https://img.shields.io/badge/platform-Windows%20%7C%20Android-blue) ![flutter](https://img.shields.io/badge/flutter-3.47-blue)

## What it does

- **Reads any text PDF aloud** with 54 Kokoro voices across 9 languages, on-device.
- **Highlights the sentence being spoken** directly on the rendered page, and
  scrolls to follow — but only when the sentence actually leaves the viewport, so
  reading along never turns into a jitter fight.
- **Full transport**: play/pause, previous/next sentence, back/forward 10 seconds
  (crossing sentence boundaries), scrub the whole document, 0.5×–3× speed.
- **Speed changes are instant.** Rate is applied at the player, where mpv keeps
  the pitch natural, so dragging the slider never re-renders audio or loses your
  place.
- **Double-click any paragraph** to start narrating from that sentence.
- **Resumes where you stopped**, per document, down to the sentence.
- Sleep timer, voice preview, light/dark theme, rendered-speech disk cache.

## Building

Flutter 3.47+. Nothing else — the speech engine is a Dart package with native
libraries, so there is no Python, pip or system TTS involved.

```bash
flutter pub get
```

### Windows

Fetch the voice bundle once (too large for git), then build:

```bash
pwsh tool/fetch_models.ps1
```

```bash
flutter run -d windows
```

Windows needs Developer Mode enabled for Flutter's plugin symlinks
(`start ms-settings:developers`).

### Android

```bash
flutter build apk --release --split-per-abi
```

Requires the Android SDK with `cmdline-tools` installed and licences accepted
(`flutter doctor --android-licenses`). The voice bundle is **not** packed into
the APK; the app downloads it on first launch (see below).

## How the voice gets there

The engine needs a directory holding `model.onnx`, `voices.bin`, `tokens.txt`,
`espeak-ng-data/` and the lexicons — about 383 MB unpacked.

| | |
|---|---|
| **Windows** | `windows/CMakeLists.txt` copies `models/` into the app bundle, so a built copy speaks immediately. Override with `cmake -DLUMEN_MODELS_DIR=<path>`. |
| **Android** | No bundle ships in the APK. On first launch the app offers a one-time 333 MB download, unpacks it into app storage, and works offline from then on. |

At startup Lumen probes `<app>/models`, `<app>/data/models`, `./models` and its
own app-support folder, then falls back to whatever is set in **Settings**. The
probe re-runs on every launch and whenever a saved folder has gone missing.

## Keyboard

| Key | Action |
|---|---|
| `Space` | Play / pause |
| `←` / `→` | Previous / next sentence |
| `Shift` + `←` / `→` | Back / forward 10 seconds |
| `+` / `-` | Speed up / down by 0.25× |
| `Esc` | Back to the library |

## How it works

```
PDF ──pdfium──> page text + per-character boxes
                      │
                      ├── ScriptBuilder: normalise, split into sentences,
                      │   group character boxes into per-line highlight rects
                      ▼
              NarrationScript ──> Narrator ──> TtsService
                      │               │              │
                 highlight        media_kit     engine isolate
                 on the page     (rate control)  (sherpa_onnx + Kokoro)
                                        ▲              │
                                        └── cached WAV ┘
```

**`lib/services/narration_script.dart`** is where the reading quality lives.
pdfium returns text with hard line breaks inside paragraphs, hyphenated wraps,
ligature glyphs and page furniture. The builder normalises all of that while
keeping a map from every output character back to its original index, so the
highlight boxes stay correct after the text has been rewritten. It then splits on
sentence boundaries with rules for abbreviations, initials, decimals and list
markers. Covered by `test/narration_script_test.dart`.

**`lib/services/tts_service.dart`** owns the Kokoro model. Synthesis is a
blocking native call of a second or two, so the model lives in a dedicated
isolate — its handle is a raw pointer that cannot cross isolates — and requests
are serialised through a priority queue, so whatever you are about to hear jumps
ahead of speculative prefetch.

**`lib/models/voice_table.dart`** maps voice names to speaker ids. The order is
*almost* alphabetical, except `em_santa` sits at the end, shifting 24 voices by
one. Every entry was confirmed by matching raw style-embedding vectors, not
assumed — getting this wrong silently returns the wrong speaker.

**`lib/playback/narrator.dart`** renders one sentence at a time with three more
queued speculatively, plays them back-to-back, and tracks clip durations so a
10-second rewind can walk backwards across sentence boundaries. Clips are cached
on disk by `sha1(text) + voice`, which is why speed is deliberately *not* baked
into synthesis. Each clip carries 350 ms of trailing silence: Kokoro trims its
own, so without it sentences run together and the last word can be clipped.

## Testing

```bash
flutter test
```

## Known limitations

- Scanned PDFs have no extractable text; there is no OCR step, and the reader
  says so rather than failing silently.
- Multi-column layouts follow pdfium's reading order, which is usually but not
  always correct.
- Unpacking the voice on Android is CPU-bound for a few minutes on first launch
  (bzip2 in pure Dart measures ~7 MB/s on a desktop, slower on a phone).
- Only the American English lexicon is loaded. sherpa lets the first entry win
  for duplicated words, so loading the British one alongside it would shadow
  every US pronunciation; accent comes from the voice embedding regardless.
- iOS, macOS and Linux are not wired up, though every dependency supports them.
