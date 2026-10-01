import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'settings_store.dart';
import 'tts_service.dart';

enum ModelPhase { checking, absent, downloading, extracting, ready, failed }

/// Obtains the Kokoro bundle: already present, or downloaded on first run.
///
/// Desktop builds ship the bundle beside the executable, so this usually
/// resolves instantly. On mobile there is nothing to ship it with, so the
/// archive is fetched once and unpacked into app storage.
class ModelStore extends ChangeNotifier {
  ModelStore(this._settings);

  /// Full-precision Kokoro v1.0, multilingual. Roughly 333 MB compressed and
  /// 383 MB on disk once unpacked.
  static const archiveUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
      'kokoro-multi-lang-v1_0.tar.bz2';

  static const downloadBytes = 349906910;

  final SettingsStore _settings;

  ModelPhase _phase = ModelPhase.checking;
  double _progress = 0;
  String? _error;
  String? _modelDir;
  DateTime? _startedAt;
  HttpClient? _client;
  var _cancelled = false;

  ModelPhase get phase => _phase;
  String? get error => _error;
  String? get modelDir => _modelDir;
  bool get isReady => _phase == ModelPhase.ready;
  bool get isBusy => _phase == ModelPhase.downloading || _phase == ModelPhase.extracting;

  /// 0..1 while downloading; meaningless while extracting, which has no
  /// cheaply observable progress.
  double get progress => _progress;

  /// How long the current download/extract has been running.
  Duration get elapsed =>
      _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!);

  /// Looks for a usable bundle without downloading anything.
  Future<void> locate() async {
    _set(ModelPhase.checking);

    final stored = _settings.engineConfig;
    if (stored.isComplete) {
      _modelDir = stored.modelDir;
      _set(ModelPhase.ready);
      return;
    }

    for (final dir in [...SettingsStore.candidateModelDirs(), await _installDir()]) {
      if (EngineConfig(modelDir: dir).isComplete) {
        _modelDir = dir;
        await _settings.adoptModelDir(dir);
        _set(ModelPhase.ready);
        return;
      }
    }

    _set(ModelPhase.absent);
  }

  Future<String> _installDir() async {
    final support = await getApplicationSupportDirectory();
    return '${support.path}${Platform.pathSeparator}kokoro';
  }

  /// Downloads and unpacks the bundle. Safe to call again after a failure.
  Future<void> install() async {
    if (isBusy) return;
    _cancelled = false;
    _error = null;
    _startedAt = DateTime.now();

    final temp = await getTemporaryDirectory();
    final archive = File('${temp.path}${Platform.pathSeparator}kokoro-bundle.tar.bz2');
    final target = await _installDir();

    try {
      _set(ModelPhase.downloading);
      await _download(archive);
      if (_cancelled) return _set(ModelPhase.absent);

      _set(ModelPhase.extracting);
      final dir = await _extract(archive.path, target);
      if (_cancelled) return _set(ModelPhase.absent);

      final config = EngineConfig(modelDir: dir);
      final missing = config.missing;
      if (missing != null) throw '$missing after unpacking.';

      _modelDir = dir;
      await _settings.adoptModelDir(dir);
      _set(ModelPhase.ready);
    } on Object catch (e) {
      _error = e is String ? e : e.toString();
      _set(ModelPhase.failed);
    } finally {
      _client = null;
      if (archive.existsSync()) {
        try {
          archive.deleteSync();
        } catch (_) {}
      }
    }
  }

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  Future<void> _download(File target) async {
    // Resume is not worth the complexity here: a partial file is discarded.
    if (target.existsSync()) target.deleteSync();

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    _client = client;

    final request = await client.getUrl(Uri.parse(archiveUrl));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw 'Download failed with HTTP ${response.statusCode}.';
    }

    final total = response.contentLength > 0 ? response.contentLength : downloadBytes;
    final sink = target.openWrite();
    var received = 0;
    var lastNotify = 0;

    try {
      await for (final chunk in response) {
        if (_cancelled) break;
        sink.add(chunk);
        received += chunk.length;
        // Notifying on every chunk would rebuild the UI thousands of times.
        if (received - lastNotify > 1 << 20) {
          lastNotify = received;
          _progress = (received / total).clamp(0.0, 1.0);
          notifyListeners();
        }
      }
    } finally {
      await sink.close();
      client.close();
    }

    if (_cancelled) return;
    if (received < downloadBytes ~/ 2) {
      throw 'Download ended early (${received ~/ (1 << 20)} MB).';
    }
    _progress = 1;
    notifyListeners();
  }

  /// Unpacks on a worker isolate: bzip2 in Dart is CPU-bound for minutes and
  /// would otherwise freeze the interface.
  Future<String> _extract(String archivePath, String target) async {
    final dir = Directory(target);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);

    await Isolate.run(() => extractFileToDisk(archivePath, target));

    // The archive holds a single top-level folder; flatten it so the model
    // directory is predictable.
    final entries = dir.listSync();
    if (entries.length == 1 && entries.single is Directory) {
      return (entries.single as Directory).path;
    }
    return target;
  }

  void _set(ModelPhase phase) {
    _phase = phase;
    if (phase != ModelPhase.downloading) _progress = phase == ModelPhase.ready ? 1 : 0;
    if (phase == ModelPhase.ready || phase == ModelPhase.failed) _startedAt = null;
    notifyListeners();
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}
