import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../models/voice.dart';
import '../models/voice_table.dart';

enum EngineStatus { idle, starting, ready, failed }

/// A rendered sentence sitting on disk, ready for the player to open.
class Clip {
  const Clip(this.file, this.duration);
  final File file;
  final Duration duration;
}

/// Where the Kokoro bundle lives: one directory holding `model.onnx`,
/// `voices.bin`, `tokens.txt`, `espeak-ng-data/` and the lexicons.
class EngineConfig {
  const EngineConfig({required this.modelDir});

  final String modelDir;

  String get modelPath => _join('model.onnx');
  String get voicesPath => _join('voices.bin');
  String get tokensPath => _join('tokens.txt');
  String get dataDir => _join('espeak-ng-data');
  String get dictDir => _join('dict');

  /// sherpa takes a comma-separated list, and the first entry wins for any word
  /// that appears twice. Loading both English lexicons means every British
  /// pronunciation is shadowed by the American one, so only `us-en` is passed —
  /// which is what the upstream Kokoro configuration does. Accent comes from the
  /// voice embedding, not this dictionary. Absent files are dropped: the Chinese
  /// lexicon only ships in the multilingual bundle.
  String get lexicons => [
    _join('lexicon-us-en.txt'),
    _join('lexicon-zh.txt'),
  ].where((p) => File(p).existsSync()).join(',');

  String _join(String name) => '$modelDir${Platform.pathSeparator}$name';

  bool get isComplete => missing == null;

  /// The first missing required file, or null when the bundle is usable.
  String? get missing {
    if (modelDir.isEmpty) return 'No model folder chosen';
    for (final entry in {
      'model.onnx': modelPath,
      'voices.bin': voicesPath,
      'tokens.txt': tokensPath,
    }.entries) {
      if (!File(entry.value).existsSync()) return 'Missing ${entry.key}';
    }
    if (!Directory(dataDir).existsSync()) return 'Missing espeak-ng-data/';
    return null;
  }

  EngineConfig copyWith({String? modelDir}) =>
      EngineConfig(modelDir: modelDir ?? this.modelDir);
}

/// Turns sentences into cached WAV files using Kokoro, in-process.
///
/// Synthesis is a blocking native call of a second or two, so the model lives in
/// a dedicated isolate and requests are serialised through a priority queue:
/// whatever the user is about to hear jumps ahead of speculative prefetch.
class TtsService extends ChangeNotifier {
  TtsService();

  /// Trailing silence added to every clip. Kokoro stops on the final phoneme,
  /// so without this, sentences run together and the last word can be clipped.
  static const tailSilence = Duration(milliseconds: 350);

  /// Bumped when rendered audio changes shape, so stale clips are re-rendered.
  static const _cacheVersion = 'v3';

  EngineStatus _status = EngineStatus.idle;
  String? _error;
  List<Voice> _voices = const [];
  int _sampleRate = 24000;

  Isolate? _isolate;
  SendPort? _engine;
  ReceivePort? _fromEngine;
  final _log = <String>[];

  Directory? _cacheDir;
  final _inflight = <String, Completer<Clip>>{};
  final _queue = <_Job>[];
  final _durations = <String, Duration>{};
  final _pending = <int, Completer<_SynthResult>>{};
  var _working = false;
  var _disposed = false;
  var _nextTicket = 0;

  EngineStatus get status => _status;
  String? get error => _error;
  List<Voice> get voices => _voices;
  int get sampleRate => _sampleRate;
  bool get isReady => _status == EngineStatus.ready;
  List<String> get log => List.unmodifiable(_log);
  int get pendingJobs => _queue.length + (_working ? 1 : 0);

  // ------------------------------------------------------------------ startup

  Future<void> start(EngineConfig config) async {
    if (_status == EngineStatus.starting) return;
    await _stopEngine();
    _setStatus(EngineStatus.starting, error: null);

    final missing = config.missing;
    if (missing != null) {
      return _fail('$missing in "${config.modelDir}".');
    }

    try {
      _cacheDir ??= await _ensureCacheDir();

      final fromEngine = ReceivePort();
      _fromEngine = fromEngine;
      final ready = Completer<_EngineReady>();

      fromEngine.listen((Object? message) {
        switch (message) {
          case _EngineReady():
            if (!ready.isCompleted) ready.complete(message);
          case _EngineFailed():
            if (!ready.isCompleted) ready.completeError(message.reason);
          case _SynthResult():
            _pending.remove(message.ticket)?.complete(message);
          case _EngineLog():
            _note(message.line);
        }
      });

      _isolate = await Isolate.spawn(
        _engineMain,
        _EngineBoot(fromEngine.sendPort, _bootConfig(config)),
        errorsAreFatal: true,
        debugName: 'kokoro-engine',
      );

      final handshake = await ready.future.timeout(
        const Duration(seconds: 180),
        onTimeout: () => throw 'The speech engine did not start within 180s.',
      );

      _engine = handshake.commands;
      _sampleRate = handshake.sampleRate;
      _voices = _voicesFor(handshake.numSpeakers);
      _note('Kokoro ready: ${_voices.length} voices at $_sampleRate Hz');
      _setStatus(EngineStatus.ready, error: null);
    } on Object catch (e) {
      await _stopEngine();
      await _fail(e is String ? e : e.toString());
    }
  }

  /// The bundle ships a fixed voice order; trust it only as far as the engine
  /// agrees on the count.
  static List<Voice> _voicesFor(int numSpeakers) {
    final names = numSpeakers >= kokoroVoicesBySid.length
        ? kokoroVoicesBySid
        : kokoroVoicesBySid.take(numSpeakers).toList();
    return names.map(Voice.fromId).toList(growable: false);
  }

  Future<void> _fail(String message) async =>
      _setStatus(EngineStatus.failed, error: message);

  void _setStatus(EngineStatus status, {String? error}) {
    _status = status;
    _error = error;
    if (!_disposed) notifyListeners();
  }

  void _note(String line) {
    if (line.trim().isEmpty) return;
    _log.add(line);
    if (_log.length > 200) _log.removeRange(0, _log.length - 200);
    if (kDebugMode) debugPrint('[kokoro] $line');
  }

  Future<Directory> _ensureCacheDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}${Platform.pathSeparator}speech-cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static _EngineBootConfig _bootConfig(EngineConfig config) => _EngineBootConfig(
    model: config.modelPath,
    voices: config.voicesPath,
    tokens: config.tokensPath,
    dataDir: config.dataDir,
    dictDir: Directory(config.dictDir).existsSync() ? config.dictDir : '',
    lexicons: config.lexicons,
  );

  // ---------------------------------------------------------------- synthesis

  String _key(String text, String voice) =>
      '$voice/$_cacheVersion-${sha1.convert(utf8.encode(text))}';

  File _fileFor(String key) => File(
    '${_cacheDir!.path}${Platform.pathSeparator}${key.replaceAll('/', '_')}.wav',
  );

  /// Duration of an already-rendered clip, or null if it has not been made yet.
  /// The transport uses this to scrub backwards across sentence boundaries.
  Duration? knownDuration(String text, String voice) => _durations[_key(text, voice)];

  bool isRendered(String text, String voice) {
    if (_cacheDir == null) return false;
    final key = _key(text, voice);
    return _durations.containsKey(key) || _fileFor(key).existsSync();
  }

  /// Renders [text] (or returns the cached file). Lower [priority] runs sooner.
  Future<Clip> clip(String text, String voice, {int priority = 10}) {
    if (!isReady) return Future.error('The speech engine is not running.');
    if (sidForVoice(voice) == null) return Future.error('Unknown voice "$voice".');

    final key = _key(text, voice);
    final file = _fileFor(key);

    if (file.existsSync() && file.lengthSync() > 44) {
      final duration = _durations[key] ??= _wavDuration(file);
      return Future.value(Clip(file, duration));
    }

    final existing = _inflight[key];
    if (existing != null) {
      // Someone already asked for this; make sure it is not stuck behind
      // lower-value prefetch work.
      for (final job in _queue) {
        if (job.key == key && priority < job.priority) job.priority = priority;
      }
      return existing.future;
    }

    final completer = Completer<Clip>();
    _inflight[key] = completer;
    _queue.add(_Job(key: key, text: text, voice: voice, priority: priority, file: file));
    _pump();
    return completer.future;
  }

  /// Fire-and-forget render used to stay ahead of playback. Failures are
  /// ignored here; whoever actually needs the clip will surface the error.
  void prefetch(String text, String voice, {int priority = 50}) {
    if (!isReady || isRendered(text, voice)) return;
    clip(text, voice, priority: priority).then((_) {}, onError: (Object _) {});
  }

  /// Drops queued prefetch work, e.g. after the user changes voice.
  void cancelPending() {
    for (final job in _queue) {
      _inflight.remove(job.key)?.completeError('cancelled');
    }
    _queue.clear();
    if (!_disposed) notifyListeners();
  }

  Future<void> _pump() async {
    if (_working || _queue.isEmpty || _disposed) return;
    _working = true;
    notifyListeners();

    while (_queue.isNotEmpty && !_disposed) {
      _queue.sort((a, b) => a.priority.compareTo(b.priority));
      final job = _queue.removeAt(0);
      final completer = _inflight.remove(job.key);
      if (completer == null) continue;

      try {
        completer.complete(await _render(job));
      } on Object catch (e) {
        completer.completeError(e is String ? e : e.toString());
      }
      if (!_disposed) notifyListeners();
    }

    _working = false;
    if (!_disposed) notifyListeners();
  }

  Future<Clip> _render(_Job job) async {
    final engine = _engine;
    if (engine == null) throw 'The speech engine is not running.';

    final ticket = _nextTicket++;
    final completer = Completer<_SynthResult>();
    _pending[ticket] = completer;

    engine.send(
      _SynthRequest(
        ticket: ticket,
        text: job.text,
        sid: sidForVoice(job.voice)!,
        outputPath: job.file.path,
        tailSilenceMs: tailSilence.inMilliseconds,
      ),
    );

    final result = await completer.future.timeout(
      const Duration(seconds: 180),
      onTimeout: () {
        _pending.remove(ticket);
        throw 'Rendering timed out.';
      },
    );

    if (result.error != null) throw result.error!;

    final duration = Duration(milliseconds: result.durationMs);
    _durations[job.key] = duration;
    return Clip(job.file, duration);
  }

  /// Reads the duration out of the WAV header so cached clips keep working
  /// across restarts without a side-car index file.
  static Duration _wavDuration(File file) {
    try {
      final bytes = file.readAsBytesSync();
      if (bytes.length < 44) return Duration.zero;
      final data = bytes.buffer.asByteData();
      var offset = 12; // skip "RIFF" + size + "WAVE"
      var byteRate = 0;
      while (offset + 8 <= bytes.length) {
        final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
        final size = data.getUint32(offset + 4, Endian.little);
        if (id == 'fmt ') {
          byteRate = data.getUint32(offset + 16, Endian.little);
        } else if (id == 'data') {
          if (byteRate <= 0) break;
          final usable = size == 0 || offset + 8 + size > bytes.length
              ? bytes.length - offset - 8
              : size;
          return Duration(microseconds: (usable / byteRate * 1e6).round());
        }
        offset += 8 + size + (size.isOdd ? 1 : 0);
      }
    } catch (_) {}
    return Duration.zero;
  }

  // ------------------------------------------------------------------ cleanup

  Future<int> cacheSizeBytes() async {
    final dir = _cacheDir;
    if (dir == null || !dir.existsSync()) return 0;
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  Future<void> clearCache() async {
    final dir = _cacheDir;
    _durations.clear();
    if (dir == null || !dir.existsSync()) return;
    await for (final entity in dir.list()) {
      if (entity is File) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _stopEngine() async {
    _engine?.send(const _Shutdown());
    _engine = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError('engine stopped');
    }
    _pending.clear();
    _fromEngine?.close();
    _fromEngine = null;
    // Give the isolate a moment to free the native model, then make sure.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  @override
  void dispose() {
    _disposed = true;
    cancelPending();
    unawaited(_stopEngine());
    super.dispose();
  }
}

class _Job {
  _Job({
    required this.key,
    required this.text,
    required this.voice,
    required this.priority,
    required this.file,
  });

  final String key;
  final String text;
  final String voice;
  final File file;
  int priority;
}

// ---------------------------------------------------------------- isolate side

class _EngineBootConfig {
  const _EngineBootConfig({
    required this.model,
    required this.voices,
    required this.tokens,
    required this.dataDir,
    required this.dictDir,
    required this.lexicons,
  });

  final String model;
  final String voices;
  final String tokens;
  final String dataDir;
  final String dictDir;
  final String lexicons;
}

class _EngineBoot {
  const _EngineBoot(this.reply, this.config);
  final SendPort reply;
  final _EngineBootConfig config;
}

class _EngineReady {
  const _EngineReady(this.commands, this.numSpeakers, this.sampleRate);
  final SendPort commands;
  final int numSpeakers;
  final int sampleRate;
}

class _EngineFailed {
  const _EngineFailed(this.reason);
  final String reason;
}

class _EngineLog {
  const _EngineLog(this.line);
  final String line;
}

class _SynthRequest {
  const _SynthRequest({
    required this.ticket,
    required this.text,
    required this.sid,
    required this.outputPath,
    required this.tailSilenceMs,
  });

  final int ticket;
  final String text;
  final int sid;
  final String outputPath;
  final int tailSilenceMs;
}

class _SynthResult {
  const _SynthResult({required this.ticket, this.durationMs = 0, this.error});
  final int ticket;
  final int durationMs;
  final String? error;
}

class _Shutdown {
  const _Shutdown();
}

/// Entry point for the engine isolate. The native model is created here and
/// never leaves: its handle is a raw pointer that cannot cross isolates.
void _engineMain(_EngineBoot boot) {
  sherpa.OfflineTts? tts;

  try {
    sherpa.initBindings();
    final config = boot.config;
    tts = sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          kokoro: sherpa.OfflineTtsKokoroModelConfig(
            model: config.model,
            voices: config.voices,
            tokens: config.tokens,
            dataDir: config.dataDir,
            dictDir: config.dictDir,
            lexicon: config.lexicons,
          ),
          numThreads: 2,
          debug: false,
        ),
      ),
    );
  } on Object catch (e) {
    boot.reply.send(_EngineFailed('Could not load the Kokoro model: $e'));
    return;
  }

  final engine = tts;
  final commands = ReceivePort();
  boot.reply.send(_EngineReady(commands.sendPort, engine.numSpeakers, engine.sampleRate));

  commands.listen((Object? message) {
    switch (message) {
      case _SynthRequest():
        try {
          // Always render at speed 1.0: playback rate is applied at the player,
          // so one cached clip stays valid at every speed.
          final audio = engine.generate(text: message.text, sid: message.sid, speed: 1.0);
          final ms = _writeWav(
            File(message.outputPath),
            audio.samples,
            audio.sampleRate,
            message.tailSilenceMs,
          );
          boot.reply.send(_SynthResult(ticket: message.ticket, durationMs: ms));
        } on Object catch (e) {
          boot.reply.send(_SynthResult(ticket: message.ticket, error: '$e'));
        }
      case _Shutdown():
        engine.free();
        commands.close();
    }
  });
}

/// Writes 16-bit mono PCM and returns the clip length in milliseconds.
int _writeWav(File file, Float32List samples, int sampleRate, int tailSilenceMs) {
  final tail = (sampleRate * tailSilenceMs / 1000).round();
  final total = samples.length + tail;
  final pcm = Int16List(total); // trailing samples stay zero: the silence tail

  for (var i = 0; i < samples.length; i++) {
    final v = samples[i];
    pcm[i] = ((v < -1.0 ? -1.0 : (v > 1.0 ? 1.0 : v)) * 32767).round();
  }
  final data = pcm.buffer.asUint8List();

  final header = BytesBuilder()
    ..add(ascii.encode('RIFF'))
    ..add(_le32(36 + data.length))
    ..add(ascii.encode('WAVE'))
    ..add(ascii.encode('fmt '))
    ..add(_le32(16))
    ..add(_le16(1)) // PCM
    ..add(_le16(1)) // mono
    ..add(_le32(sampleRate))
    ..add(_le32(sampleRate * 2))
    ..add(_le16(2))
    ..add(_le16(16))
    ..add(ascii.encode('data'))
    ..add(_le32(data.length));

  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(header.toBytes() + data, flush: true);
  return (total * 1000 / sampleRate).round();
}

Uint8List _le32(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);
Uint8List _le16(int v) =>
    Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);
