"""
Kokoro TTS sidecar for Lumen Reader.

A tiny localhost HTTP server that wraps kokoro-onnx. The Flutter app spawns this
process, waits for the READY line on stdout, then POSTs sentences to /speak and
gets back 24 kHz mono WAV bytes.

Protocol
--------
stdout: ``LUMEN_READY {"port": 51234, "voices": [...], "sample_rate": 24000}``
        Any other stdout/stderr output is forwarded to the app's log pane.

GET  /health   -> {"ok": true, "voices": [...]}
GET  /voices   -> {"voices": [...]}
POST /speak    -> audio/wav   body: {"text": str, "voice": str, "speed": float}
POST /shutdown -> {"ok": true}
"""

from __future__ import annotations

import argparse
import io
import json
import os
import struct
import sys
import threading
import traceback
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SAMPLE_RATE = 24000

# Kokoro trims silence from both ends, so a clip stops dead on its final
# phoneme. That makes back-to-back sentences run together, and leaves no
# slack for the player's end-of-file timing, which clips the last word.
# A short tail fixes both.
TAIL_SILENCE_SEC = 0.35

# Kokoro's voice names are prefixed with a language letter and a gender letter,
# e.g. "af_heart" = American English, female. espeak needs the language code.
_LANG_BY_PREFIX = {
    "a": "en-us",
    "b": "en-gb",
    "e": "es",
    "f": "fr-fr",
    "h": "hi",
    "i": "it",
    "j": "ja",
    "p": "pt-br",
    "z": "cmn",
}

# A single sentence should always fit, but Kokoro hard-caps at 510 phoneme
# tokens. Anything longer is split on clause boundaries and concatenated.
_MAX_CHARS = 400


def _log(*args):
    # Never let logging raise. Once the app exits, the reader on our stderr pipe
    # is gone and a write raises BrokenPipeError -- which, from the shutdown
    # watchdog, would kill the very thread whose job is to terminate us.
    try:
        print(*args, file=sys.stderr, flush=True)
    except Exception:
        pass


class Engine:
    """Serialises access to the ONNX session and renders WAV bytes."""

    def __init__(self, model_path: str, voices_path: str):
        from kokoro_onnx import Kokoro  # imported late so errors are reportable

        self._lock = threading.Lock()
        self._kokoro = Kokoro(model_path, voices_path)
        self.voices = sorted(self._kokoro.get_voices())

    def lang_for(self, voice: str) -> str:
        return _LANG_BY_PREFIX.get(voice[:1], "en-us")

    def synth(self, text: str, voice: str, speed: float) -> bytes:
        import numpy as np

        pieces = [p for p in _split(text, _MAX_CHARS) if p.strip()]
        if not pieces:
            pieces = [" "]

        lang = self.lang_for(voice)
        chunks = []
        with self._lock:
            for piece in pieces:
                samples, _ = self._kokoro.create(piece, voice=voice, speed=speed, lang=lang)
                chunks.append(np.asarray(samples, dtype=np.float32))
                # A short breath between forced splits keeps them from colliding.
                if len(pieces) > 1:
                    chunks.append(np.zeros(int(SAMPLE_RATE * 0.06), dtype=np.float32))

        audio = np.concatenate(chunks) if len(chunks) > 1 else chunks[0]
        tail = np.zeros(int(SAMPLE_RATE * TAIL_SILENCE_SEC), dtype=np.float32)
        return _to_wav(np.concatenate([audio, tail]))


def _split(text: str, limit: int) -> list[str]:
    """Split overlong text on the softest available boundary."""
    text = text.strip()
    if len(text) <= limit:
        return [text]

    for seps in ("; ", ", ", " — ", " "):
        cut = text.rfind(seps, 0, limit)
        if cut > limit // 3:
            head = text[: cut + len(seps)].strip()
            return [head] + _split(text[cut + len(seps) :], limit)

    return [text[:limit]] + _split(text[limit:], limit)


def _to_wav(samples) -> bytes:
    import numpy as np

    peak = float(np.max(np.abs(samples))) if samples.size else 0.0
    if peak > 1.0:  # guard against clipping on loud voices
        samples = samples / peak
    pcm = np.clip(samples * 32767.0, -32768, 32767).astype("<i2")

    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(pcm.tobytes())
    return buf.getvalue()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    engine: Engine = None  # type: ignore[assignment]

    def log_message(self, fmt, *args):  # quieter than the default access log
        pass

    def _send(self, code: int, body: bytes, ctype: str, extra: dict | None = None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, str(v))
        self.end_headers()
        self.wfile.write(body)

    def _json(self, code: int, payload: dict):
        self._send(code, json.dumps(payload).encode("utf-8"), "application/json")

    def do_GET(self):
        if self.path == "/health":
            self._json(200, {"ok": True, "voices": self.engine.voices, "sample_rate": SAMPLE_RATE})
        elif self.path == "/voices":
            self._json(200, {"voices": self.engine.voices})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        if self.path == "/shutdown":
            self._json(200, {"ok": True})
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return
        if self.path != "/speak":
            self._json(404, {"error": "not found"})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            req = json.loads(self.rfile.read(length) or b"{}")
            text = (req.get("text") or "").strip()
            voice = req.get("voice") or (self.engine.voices[0] if self.engine.voices else "af_heart")
            speed = float(req.get("speed") or 1.0)

            if not text:
                self._json(400, {"error": "text is required"})
                return
            if voice not in self.engine.voices:
                self._json(400, {"error": f"unknown voice '{voice}'"})
                return

            wav = self.engine.synth(text, voice, max(0.5, min(2.0, speed)))
            frames = (len(wav) - 44) // 2
            self._send(
                200,
                wav,
                "audio/wav",
                {"X-Audio-Duration": f"{frames / SAMPLE_RATE:.4f}"},
            )
        except Exception as exc:  # surface the reason to the app instead of hanging
            _log("synth failed:", traceback.format_exc())
            self._json(500, {"error": str(exc)})


def _watch_parent(server, parent_pid: int | None):
    """Exit when the app goes away, so a 325 MB model is never left resident.

    Two independent triggers, because either one alone has a blind spot:

    * stdin EOF -- covers a normal shutdown, where the app closes the pipe.
    * a wait on the parent's process handle -- covers a crash or a forced kill,
      which does not reliably surface as EOF on our end of the pipe.
    """

    def on_stdin():
        try:
            while sys.stdin.readline():
                pass
        except Exception:
            pass
        _log("parent closed stdin; shutting down")
        server.shutdown()

    threading.Thread(target=on_stdin, daemon=True).start()

    if parent_pid is None or os.name != "nt":
        return

    import ctypes
    from ctypes import wintypes

    SYNCHRONIZE = 0x00100000
    INFINITE = 0xFFFFFFFF
    WAIT_OBJECT_0 = 0x00000000

    # argtypes/restype are not optional here. Left untyped, ctypes passes the
    # handle and timeout as plain C ints, and the call returns WAIT_OBJECT_0
    # immediately instead of blocking -- which would shut the engine down the
    # moment it started.
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    kernel32.WaitForSingleObject.restype = wintypes.DWORD

    handle = kernel32.OpenProcess(SYNCHRONIZE, False, parent_pid)
    if not handle:
        _log(
            "could not watch parent pid %s (error %s)"
            % (parent_pid, ctypes.get_last_error())
        )
        return

    def on_exit():
        # Blocks until the parent terminates, however it terminates.
        if kernel32.WaitForSingleObject(handle, INFINITE) != WAIT_OBJECT_0:
            return
        _log("parent process %s exited; shutting down" % parent_pid)
        # os._exit rather than server.shutdown(): once the app is gone, the
        # reader on our stdin pipe is gone with it, and the stdin thread stays
        # wedged in a blocking read that never returns EOF. That stalls
        # interpreter finalisation, so a graceful shutdown here would leave the
        # model resident forever. There is nothing left worth flushing.
        os._exit(0)

    threading.Thread(target=on_exit, daemon=True).start()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--voices", required=True)
    ap.add_argument("--port", type=int, default=0)
    ap.add_argument("--parent-pid", type=int, default=None)
    args = ap.parse_args()

    for label, path in (("model", args.model), ("voices", args.voices)):
        if not os.path.isfile(path):
            print(json.dumps({"error": f"{label} file not found: {path}"}), flush=True)
            return 2

    try:
        engine = Engine(args.model, args.voices)
    except Exception as exc:
        _log(traceback.format_exc())
        print(json.dumps({"error": f"failed to load Kokoro: {exc}"}), flush=True)
        return 3

    Handler.engine = engine
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    port = server.server_address[1]

    _watch_parent(server, args.parent_pid)

    print(
        "LUMEN_READY "
        + json.dumps({"port": port, "voices": engine.voices, "sample_rate": SAMPLE_RATE}),
        flush=True,
    )

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
