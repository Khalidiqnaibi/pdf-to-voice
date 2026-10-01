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
  static const _kModelDir = 'model_dir';

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

  EngineConfig get engineConfig =>
      EngineConfig(modelDir: _prefs.getString(_kModelDir) ?? '');

  // ------------------------------------------------------------- writing prefs

  Future<void> setThemeMode(ThemeMode mode) => _set(() => _prefs.setInt(_kTheme, mode.index));

  Future<void> setVoiceId(String id) => _set(() => _prefs.setString(_kVoice, id));

  Future<void> setSpeed(double value) =>
      _set(() => _prefs.setDouble(_kSpeed, value.clamp(0.5, 3.0)));

  Future<void> setAutoScroll(bool value) => _set(() => _prefs.setBool(_kAutoScroll, value));

  Future<void> setHighlightSentence(bool value) => _set(() => _prefs.setBool(_kHighlight, value));

  Future<void> setEngineConfig(EngineConfig config) =>
      _set(() => _prefs.setString(_kModelDir, config.modelDir));

  Future<void> _set(Future<void> Function() write) async {
    await write();
    notifyListeners();
  }

  // -------------------------------------------------------------- autodetection

  /// Finds the Kokoro bundle so the setup sheet is something people opt into
  /// rather than something they have to get past.
  ///
  /// This runs on every launch, not just the first, and re-probes whenever the
  /// stored folder has gone missing. That way a build which ships the model
  /// beside the executable is picked up automatically, even for someone whose
  /// settings still name an older location.
  Future<void> _seedEnginePaths() async {
    final stored = _prefs.getString(_kModelDir) ?? '';
    if (stored.isNotEmpty && EngineConfig(modelDir: stored).isComplete) return;

    for (final dir in candidateModelDirs()) {
      if (EngineConfig(modelDir: dir).isComplete) {
        await _prefs.setString(_kModelDir, dir);
        return;
      }
    }
  }

  /// Bundled location first: desktop builds install the model next to the
  /// executable, and on mobile it is downloaded into app support.
  static List<String> candidateModelDirs() {
    final sep = Platform.pathSeparator;
    final roots = <String>[
      if (!Platform.isAndroid && !Platform.isIOS) ...[
        File(Platform.resolvedExecutable).parent.path,
        Directory.current.path,
      ],
    ];

    return [
      for (final root in roots) ...['$root${sep}models', '$root${sep}data${sep}models'],
    ];
  }

  /// Records a bundle that was downloaded at runtime (mobile first launch).
  Future<void> adoptModelDir(String dir) =>
      _set(() => _prefs.setString(_kModelDir, dir));
}
