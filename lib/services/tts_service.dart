import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/voice.dart';

enum EngineStatus { idle, starting, ready, failed }

/// A rendered sentence sitting on disk, ready for the player to open.
class Clip {
  const Clip(this.file, this.duration);
  final File file;
  final Duration duration;
}

/// Where the engine lives. All three are user-editable because Kokoro's weights
/// are a 325 MB download that people keep in their own model folder.
class EngineConfig {
  const EngineConfig({
    required this.pythonPath,
    required this.modelPath,
    required this.voicesPath,
  });

  final String pythonPath;
  final String modelPath;
  final String voicesPath;

  bool get modelExists => modelPath.isNotEmpty && File(modelPath).existsSync();
  bool get voicesExists => voicesPath.isNotEmpty && File(voicesPath).existsSync();
  bool get isComplete => pythonPath.isNotEmpty && modelExists && voicesExists;

  EngineConfig copyWith({String? pythonPath, String? modelPath, String? voicesPath}) =>
      EngineConfig(
        pythonPath: pythonPath ?? this.pythonPath,
        modelPath: modelPath ?? this.modelPath,
        voicesPath: voicesPath ?? this.voicesPath,
      );
}

/// Owns the Kokoro sidecar process and turns sentences into cached WAV files.
///
/// Synthesis is serialised through a priority queue: whatever the user is about
/// to hear jumps ahead of the speculative prefetch for later sentences.
class TtsService extends ChangeNotifier {
  TtsService();

  static const _readyMarker = 'LUMEN_READY ';
  static const _startTimeout = Duration(seconds: 180);

  EngineStatus _status = EngineStatus.idle;
  String? _error;
  List<Voice> _voices = const [];
  int _sampleRate = 24000;

  Process? _process;
  Uri? _base;
  final _client = http.Client();
  final _log = <String>[];

  Directory? _cacheDir;
  final _inflight = <String, Completer<Clip>>{};
  final _queue = <_Job>[];
  final _durations = <String, Duration>{};
  bool _working = false;
  bool _disposed = false;

  EngineStatus get status => _status;
  String? get error => _error;
  List<Voice> get voices => _voices;
  int get sampleRate => _sampleRate;
  bool get isReady => _status == EngineStatus.ready;

  /// Recent engine output, surfaced in the settings sheet when things go wrong.
  List<String> get log => List.unmodifiable(_log);

  /// Number of sentences waiting to be rendered.
  int get pendingJobs => _queue.length + (_working ? 1 : 0);

  // ------------------------------------------------------------------ startup

  Future<void> start(EngineConfig config) async {
    if (_status == EngineStatus.starting) return;
    await _stopProcess();

    _setStatus(EngineStatus.starting, error: null);

    if (!config.modelExists) {
      return _fail('Kokoro model not found at "${config.modelPath}".');
    }
    if (!config.voicesExists) {
      return _fail('Voice pack not found at "${config.voicesPath}".');
    }

    try {
      _cacheDir ??= await _ensureCacheDir();
      final script = await _materializeScript();

      final process = await Process.start(config.pythonPath, [
        script.path,
        '--model',
        config.modelPath,
        '--voices',
        config.voicesPath,
        '--port',
        '0',
      ], runInShell: Platform.isWindows);
      _process = process;

      final ready = Completer<Map<String, dynamic>>();

      process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        _note(line);
        if (line.startsWith(_readyMarker) && !ready.isCompleted) {
          try {
            ready.complete(jsonDecode(line.substring(_readyMarker.length)) as Map<String, dynamic>);
          } catch (e) {
            ready.completeError('Malformed handshake from the speech engine: $e');
          }
        } else if (line.startsWith('{') && line.contains('"error"') && !ready.isCompleted) {
          try {
            ready.completeError((jsonDecode(line) as Map)['error'] as Object);
          } catch (_) {
            ready.completeError(line);
          }
        }
      }, onError: (Object e) => _note('stdout error: $e'));

      process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(_note);

      unawaited(
        process.exitCode.then((code) {
          _note('engine exited with code $code');
          if (!ready.isCompleted) {
            ready.completeError(
              code == 0
                  ? 'The speech engine stopped before it was ready.'
                  : 'The speech engine could not start (exit code $code). '
                        'Check that "${config.pythonPath}" has kokoro-onnx installed.',
            );
          } else if (_status == EngineStatus.ready) {
            _setStatus(EngineStatus.failed, error: 'The speech engine stopped unexpectedly.');
          }
        }),
      );

      final handshake = await ready.future.timeout(
        _startTimeout,
        onTimeout: () => throw 'The speech engine did not respond within '
            '${_startTimeout.inSeconds}s.',
      );

      _base = Uri.parse('http://127.0.0.1:${handshake['port']}');
      _sampleRate = (handshake['sample_rate'] as num?)?.toInt() ?? 24000;
      _voices = ((handshake['voices'] as List?) ?? const [])
          .cast<String>()
          .map(Voice.fromId)
          .toList(growable: false);

      _setStatus(EngineStatus.ready, error: null);
    } on Object catch (e) {
      await _stopProcess();
      await _fail(_describe(e));
    }
  }

  Future<void> _fail(String message) async {
    _setStatus(EngineStatus.failed, error: message);
  }

  static String _describe(Object e) {
    if (e is String) return e;
    if (e is ProcessException) {
      return 'Could not launch "${e.executable}". ${e.message}';
    }
    return e.toString();
  }

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

  /// Copies the bundled sidecar next to the app data so it can be launched by a
  /// plain `python path/to/tts_server.py`, in both debug and release builds.
  Future<File> _materializeScript() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}${Platform.pathSeparator}engine');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final source = await rootBundle.loadString('assets/python/tts_server.py');
    final file = File('${dir.path}${Platform.pathSeparator}tts_server.py');
    if (!file.existsSync() || await file.readAsString() != source) {
      await file.writeAsString(source);
    }
    return file;
  }

  Future<Directory> _ensureCacheDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}${Platform.pathSeparator}speech-cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  // ---------------------------------------------------------------- synthesis

  String _key(String text, String voice) =>
      '$voice/${sha1.convert(utf8.encode(text)).toString()}';

  File _fileFor(String key) =>
      File('${_cacheDir!.path}${Platform.pathSeparator}${key.replaceAll('/', '_')}.wav');

  /// Duration of an already-rendered clip, or null if it has not been made yet.
  /// The transport uses this to scrub backwards across sentence boundaries.
  Duration? knownDuration(String text, String voice) => _durations[_key(text, voice)];

  bool isRendered(String text, String voice) {
    final key = _key(text, voice);
    if (_durations.containsKey(key)) return true;
    return _cacheDir != null && _fileFor(key).existsSync();
  }

  /// Renders [text] (or returns the cached file). Lower [priority] runs sooner.
  Future<Clip> clip(String text, String voice, {int priority = 10}) {
    if (!isReady) return Future.error('The speech engine is not running.');

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

  /// Fire-and-forget render used to stay ahead of playback.
  void prefetch(String text, String voice, {int priority = 50}) {
    if (!isReady || isRendered(text, voice)) return;
    clip(text, voice, priority: priority).catchError((Object _) => Clip(_fileFor(''), Duration.zero));
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
        final clip = await _render(job);
        completer.complete(clip);
      } on Object catch (e) {
        completer.completeError(_describe(e));
      }
      if (!_disposed) notifyListeners();
    }

    _working = false;
    if (!_disposed) notifyListeners();
  }

  Future<Clip> _render(_Job job) async {
    final base = _base;
    if (base == null) throw 'The speech engine is not running.';

    final response = await _client
        .post(
          base.replace(path: '/speak'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'text': job.text, 'voice': job.voice, 'speed': 1.0}),
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      throw _errorFrom(response.body, response.statusCode);
    }

    await job.file.writeAsBytes(response.bodyBytes, flush: true);

    final header = response.headers['x-audio-duration'];
    final seconds = header == null ? null : double.tryParse(header);
    final duration = seconds != null
        ? Duration(microseconds: (seconds * 1e6).round())
        : _wavDuration(job.file);

    _durations[job.key] = duration;
    return Clip(job.file, duration);
  }

  static String _errorFrom(String body, int code) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] != null) return decoded['error'].toString();
    } catch (_) {}
    return 'Speech engine returned HTTP $code.';
  }

  /// Reads the duration straight out of the WAV header so cached clips keep
  /// working across restarts without a side-car index file.
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

  Future<void> _stopProcess() async {
    final process = _process;
    final base = _base;
    _process = null;
    _base = null;
    if (process == null) return;

    if (base != null) {
      try {
        await _client
            .post(base.replace(path: '/shutdown'))
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    try {
      process.kill();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    cancelPending();
    unawaited(_stopProcess());
    _client.close();
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
