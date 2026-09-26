# Lumen Reader

A Flutter desktop PDF reader that reads documents aloud with
[Kokoro](https://github.com/thewh1teagle/kokoro-onnx) neural speech — sentence by
sentence, highlighting the page as it goes.

![platform](https://img.shields.io/badge/platform-Windows-blue) ![flutter](https://img.shields.io/badge/flutter-3.47-blue)

## What it does

- **Reads any text PDF aloud** with 54 Kokoro voices across 9 languages.
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

## Requirements

To **build**: Flutter 3.47+ with Windows desktop support. Nothing else.

To **run a built copy**: nothing. The speech model and a private Python runtime
are both bundled into the app — see [Self-contained builds](#self-contained-builds).

### Windows Developer Mode

Flutter needs symlink support to build plugins on Windows. Enable Developer Mode
once, then the build works:

```bash
start ms-settings:developers
```

## Running

The model and runtime are too large for git, so fetch them once. Both scripts are
idempotent — re-running them is a no-op:

```bash
pwsh tool/fetch_models.ps1
```

```bash
pwsh tool/fetch_runtime.ps1
```

Then:

```bash
flutter pub get
flutter run -d windows
```

## Self-contained builds

`windows/CMakeLists.txt` copies both the model and the Python runtime into the
application bundle:

```
build/windows/x64/runner/Release/
  lumen_reader.exe
  models/
    kokoro-v1.0.onnx     325 MB
    voices-v1.0.bin       28 MB
  runtime/               144 MB   embedded Python + kokoro-onnx
  data/flutter_assets/
```

Zip that folder and it speaks on a machine with no Python, no pip and nothing to
download — about 500 MB all in.

`tool/fetch_runtime.ps1` assembles the runtime from the official Windows
embeddable distribution: it enables site-packages (off by default in that build),
bootstraps pip, installs `kokoro-onnx`, then drops pip, setuptools and wheel,
which are only needed at install time.

At startup Lumen prefers `<app>/runtime/python.exe` for the interpreter and
`<app>/models` for the weights, then falls back through `./models`, `~/.kokoro`,
`~/models`, `~/Downloads` and finally whatever is set in **Settings**. The probe
re-runs on every launch and whenever a saved path has gone missing, so a bundled
copy is picked up even for someone whose settings name an older location. An
interpreter path you typed yourself is never overwritten.

CMake skips files that are already up to date, so the large payloads are copied
once rather than on every incremental build. To bundle from elsewhere:

```bash
cmake -DLUMEN_MODELS_DIR=<path> -DLUMEN_RUNTIME_DIR=<path>
```

Either can be absent: the build still succeeds with a warning, and the app falls
back to a system Python and a model chosen in Settings.

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
              NarrationScript ──> Narrator ──HTTP──> Kokoro sidecar (Python)
                      │               │                      │
                 highlight        media_kit <──── cached WAV ┘
                 on the page       (rate control)
```

**`lib/services/narration_script.dart`** is where the quality lives. pdfium hands
back text with hard line breaks inside paragraphs, hyphenated wraps, ligature
glyphs and page furniture. The builder normalises all of that while keeping a map
from every output character back to its original index, so the highlight boxes
stay pixel-correct after the text has been rewritten. It then splits on sentence
boundaries with rules for abbreviations, initials, decimals and list markers.
Covered by `test/narration_script_test.dart`.

**`assets/python/tts_server.py`** is a stdlib HTTP server wrapping `kokoro-onnx`.
The app extracts it to its support directory, spawns it, and waits for a
`LUMEN_READY` handshake on stdout. The sidecar watches stdin for EOF, so it exits
with the app rather than leaving a 325 MB model resident.

**`lib/playback/narrator.dart`** renders one sentence at a time with three more
queued speculatively, plays them back-to-back, and tracks clip durations so a
10-second rewind can walk backwards across sentence boundaries. Clips are cached
on disk by `sha1(text) + voice`, which is why speed is deliberately *not* baked
into synthesis.

## Testing

```bash
flutter test
```

## Known limitations

- Scanned PDFs have no extractable text; there is no OCR step, and the reader
  says so rather than failing silently.
- Multi-column layouts follow pdfium's reading order, which is usually but not
  always correct.
- Windows only so far. The code is platform-neutral apart from the sidecar launch;
  macOS and Linux need `media_kit_libs_<os>_audio` added to `pubspec.yaml`, plus
  their own bundle rules for the model and runtime.
- A self-contained build is ~500 MB, most of it the Kokoro weights. Nothing here
  streams the model or fetches it on first launch.
