import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tts_service.dart';

/// User preferences plus the engine paths, persisted between launches.
class SettingsStore extends ChangeNotifier {
  SettingsStore._(this._prefs);

  static const _kTheme = 'theme_mode';
  static const _kVoice = 'voice_id';
  static const _kSpeed = 'speed';
  static const _kAutoScroll = 'auto_scroll';
  static const _kHighlight = 'highlight';
  static const _kPython = 'python_path';
  static const _kModel = 'model_path';
  static const _kVoicesFile = 'voices_path';

  final SharedPreferences _prefs;

  static Future<SettingsStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final store = SettingsStore._(prefs);
    await store._seedEnginePaths();
    return store;
  }

  // ------------------------------------------------------------- reading prefs

  ThemeMode get themeMode =>
      ThemeMode.values[(_prefs.getInt(_kTheme) ?? ThemeMode.dark.index).clamp(0, 2)];

  String? get voiceId => _prefs.getString(_kVoice);

  double get speed => (_prefs.getDouble(_kSpeed) ?? 1.0).clamp(0.5, 3.0);

  bool get autoScroll => _prefs.getBool(_kAutoScroll) ?? true;

  bool get highlightSentence => _prefs.getBool(_kHighlight) ?? true;

  EngineConfig get engineConfig => EngineConfig(
    pythonPath: _prefs.getString(_kPython) ?? _defaultPython(),
    modelPath: _prefs.getString(_kModel) ?? '',
    voicesPath: _prefs.getString(_kVoicesFile) ?? '',
  );

  // ------------------------------------------------------------- writing prefs

  Future<void> setThemeMode(ThemeMode mode) => _set(() => _prefs.setInt(_kTheme, mode.index));

  Future<void> setVoiceId(String id) => _set(() => _prefs.setString(_kVoice, id));

  Future<void> setSpeed(double value) =>
      _set(() => _prefs.setDouble(_kSpeed, value.clamp(0.5, 3.0)));

  Future<void> setAutoScroll(bool value) => _set(() => _prefs.setBool(_kAutoScroll, value));

  Future<void> setHighlightSentence(bool value) => _set(() => _prefs.setBool(_kHighlight, value));

  Future<void> setEngineConfig(EngineConfig config) => _set(() async {
    await _prefs.setString(_kPython, config.pythonPath);
    await _prefs.setString(_kModel, config.modelPath);
    await _prefs.setString(_kVoicesFile, config.voicesPath);
  });

  Future<void> _set(Future<void> Function() write) async {
    await write();
    notifyListeners();
  }

  // -------------------------------------------------------------- autodetection

  static String _defaultPython() => Platform.isWindows ? 'python' : 'python3';

  /// On first launch, look in the usual places for the Kokoro weights so most
  /// people never see the setup sheet at all.
  Future<void> _seedEnginePaths() async {
    if (_prefs.getString(_kPython) == null) {
      await _prefs.setString(_kPython, _defaultPython());
    }

    final needsModel = (_prefs.getString(_kModel) ?? '').isEmpty;
    final needsVoices = (_prefs.getString(_kVoicesFile) ?? '').isEmpty;
    if (!needsModel && !needsVoices) return;

    for (final dir in _candidateModelDirs()) {
      final model = _firstExisting(dir, const ['kokoro-v1.0.onnx', 'kokoro-v1.0.fp16.onnx', 'kokoro.onnx']);
      final voices = _firstExisting(dir, const ['voices-v1.0.bin', 'voices.bin', 'voices.json']);
      if (model != null && voices != null) {
        if (needsModel) await _prefs.setString(_kModel, model);
        if (needsVoices) await _prefs.setString(_kVoicesFile, voices);
        return;
      }
    }
  }

  static List<String> _candidateModelDirs() {
    final sep = Platform.pathSeparator;
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
    final exeDir = File(Platform.resolvedExecutable).parent.path;

    return [
      '$exeDir${sep}models',
      '${Directory.current.path}${sep}models',
      if (home.isNotEmpty) ...[
        '$home${sep}Documents${sep}GitHub${sep}A.S.H${sep}models',
        '$home$sep.kokoro',
        '$home${sep}models',
        '$home${sep}Downloads',
      ],
    ];
  }

  static String? _firstExisting(String dir, List<String> names) {
    for (final name in names) {
      final path = '$dir${Platform.pathSeparator}$name';
      if (File(path).existsSync()) return path;
    }
    return null;
  }
}
