// Throwaway harness: proves sherpa_onnx can drive the same Kokoro model the
// Python sidecar uses, before the real engine is ported over to it.
//
// Run from a terminal so stdout is visible:
//   flutter run -d windows --release
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

const bundle =
    r'C:\PROGRA~1\KMSpico\temp\claude\C--Users-pc-Documents-GitHub-pdf-to-voice'
    r'\a9768ed7-e07d-4730-973b-b17f1de4d2dc\scratchpad\kk\kokoro-multi-lang-v1_0';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final out = StringBuffer();
  void say(String line) {
    out.writeln(line);
    stdout.writeln('PROBE $line');
  }

  try {
    sherpa.initBindings();
    say('bindings loaded');

    final started = DateTime.now();
    final tts = sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          kokoro: sherpa.OfflineTtsKokoroModelConfig(
            model: '$bundle\\model.onnx',
            voices: '$bundle\\voices.bin',
            tokens: '$bundle\\tokens.txt',
            dataDir: '$bundle\\espeak-ng-data',
            dictDir: '$bundle\\dict',
            lexicon: '$bundle\\lexicon-us-en.txt,$bundle\\lexicon-zh.txt',
          ),
          numThreads: 2,
          debug: false,
        ),
      ),
    );
    say('model loaded in ${DateTime.now().difference(started).inMilliseconds}ms');
    say('voices (numSpeakers): ${tts.numSpeakers}');
    say('sampleRate: ${tts.sampleRate}');

    // sid 0 is af_alloy in the Kokoro voice pack order.
    for (final sid in [0, 3]) {
      final t = DateTime.now();
      final audio = tts.generate(
        text: 'The narration engine now runs natively, with no Python at all.',
        sid: sid,
        speed: 1.0,
      );
      final seconds = audio.samples.length / audio.sampleRate;
      say(
        'sid $sid -> ${seconds.toStringAsFixed(2)}s of audio in '
        '${DateTime.now().difference(t).inMilliseconds}ms '
        '(${audio.samples.length} samples @ ${audio.sampleRate}Hz)',
      );
      _writeWav(File('probe_sid$sid.wav'), audio.samples, audio.sampleRate);
    }

    tts.free();
    say('OK');
  } catch (e, s) {
    say('FAILED: $e');
    say('$s');
  }

  File('probe_result.txt').writeAsStringSync(out.toString());
  exit(0);
}

void _writeWav(File file, Float32List samples, int sampleRate) {
  final pcm = Int16List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    pcm[i] = (samples[i].clamp(-1.0, 1.0) * 32767).round();
  }
  final data = pcm.buffer.asUint8List();
  final header = BytesBuilder()
    ..add('RIFF'.codeUnits)
    ..add(_le32(36 + data.length))
    ..add('WAVEfmt '.codeUnits)
    ..add(_le32(16))
    ..add(_le16(1))
    ..add(_le16(1))
    ..add(_le32(sampleRate))
    ..add(_le32(sampleRate * 2))
    ..add(_le16(2))
    ..add(_le16(16))
    ..add('data'.codeUnits)
    ..add(_le32(data.length));
  file.writeAsBytesSync(header.toBytes() + data);
}

Uint8List _le32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);
Uint8List _le16(int v) => Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);
