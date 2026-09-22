import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'services/library_store.dart';
import 'services/settings_store.dart';
import 'services/tts_service.dart';

bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  MediaKit.ensureInitialized();
  pdfrxFlutterInitialize();

  if (_isDesktop) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1280, 860),
        minimumSize: Size(880, 620),
        center: true,
        title: 'Lumen Reader',
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  final settings = await SettingsStore.load();
  final library = await LibraryStore.load();
  final tts = TtsService();

  // Bring the engine up in the background: the library is usable immediately and
  // Kokoro is usually warm by the time a document is open.
  final config = settings.engineConfig;
  if (config.isComplete) {
    tts.start(config);
  }

  if (_isDesktop) {
    await windowManager.setPreventClose(true);
    windowManager.addListener(_ShutdownHandler(tts));
  }

  runApp(LumenApp(settings: settings, library: library, tts: tts));
}

/// Stops the Kokoro sidecar before the window goes away, so the model is not
/// left resident in a stranded Python process.
class _ShutdownHandler extends WindowListener {
  _ShutdownHandler(this.tts);

  final TtsService tts;
  bool _closing = false;

  @override
  void onWindowClose() async {
    if (_closing) return;
    _closing = true;
    tts.dispose();
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }
}
