import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'services/library_store.dart';
import 'services/settings_store.dart';
import 'services/tts_service.dart';
import 'theme/app_theme.dart';
import 'ui/library_screen.dart';

/// Hands the long-lived services down the tree without pulling in a state
/// management package.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.settings,
    required this.library,
    required this.tts,
    required super.child,
  });

  final SettingsStore settings;
  final LibraryStore library;
  final TtsService tts;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing from the widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      settings != oldWidget.settings || library != oldWidget.library || tts != oldWidget.tts;
}

class LumenApp extends StatelessWidget {
  const LumenApp({
    super.key,
    required this.settings,
    required this.library,
    required this.tts,
  });

  final SettingsStore settings;
  final LibraryStore library;
  final TtsService tts;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      settings: settings,
      library: library,
      tts: tts,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return MaterialApp(
            title: 'Lumen Reader',
            debugShowCheckedModeBanner: false,
            themeMode: settings.themeMode,
            theme: AppTheme.build(Brightness.light),
            darkTheme: AppTheme.build(Brightness.dark),
            home: const LibraryScreen(),
            scrollBehavior: const _DesktopScrollBehavior(),
          );
        },
      ),
    );
  }
}

/// Lets trackpads and mice drag scrollable surfaces on desktop.
class _DesktopScrollBehavior extends MaterialScrollBehavior {
  const _DesktopScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}
