import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'services/library_store.dart';
import 'services/settings_store.dart';
import 'services/tts_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  MediaKit.ensureInitialized();
  pdfrxFlutterInitialize();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1280, 860),
        minimumSize: Size(880, 620),
        center: true,
        title: 'Lumen Reader',
        titleBarStyle: TitleBarStyle.normal,
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
  unawaitedStart(tts, settings);

  runApp(LumenApp(settings: settings, library: library, tts: tts));
}

void unawaitedStart(TtsService tts, SettingsStore settings) {
  final config = settings.engineConfig;
  if (config.isComplete) {
    tts.start(config);
  }
}
