import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../app.dart';
import '../playback/narrator.dart';
import '../services/narration_script.dart';
import '../services/settings_store.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';
import 'widgets/player_dock.dart';
import 'widgets/primitives.dart';
import 'widgets/sentence_highlight.dart';
import 'widgets/settings_dialog.dart';
import 'widgets/voice_picker.dart';

/// The reading surface: the document, the narration highlight and the transport.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.path});

  final String path;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _controller = PdfViewerController();
  final _focus = FocusNode(debugLabel: 'reader-shortcuts');

  late final TtsService _tts;
  late final SettingsStore _settings;
  late final Narrator _narrator;

  ScriptBuilder? _scriptBuilder;
  ScriptProgress? _prepareProgress;
  NarrationScript _script = NarrationScript.empty;
  bool _preparing = false;
  bool _prepared = false;

  String _title = '';
  int _page = 1;
  int _pageCount = 0;
  Timer? _saveDebounce;
  bool _wired = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) return;
    _wired = true;

    final scope = AppScope.of(context);
    _tts = scope.tts;
    _settings = scope.settings;
    _narrator = Narrator(_tts);

    _title = scope.library.byPath(widget.path)?.title ?? 'Document';

    _narrator.cursor.addListener(_onCursorChanged);
    _tts.addListener(_onEngineChanged);
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _scriptBuilder?.cancel();
    _tts.removeListener(_onEngineChanged);
    _narrator.cursor.removeListener(_onCursorChanged);
    _persistProgress();
    _narrator.dispose();
    _focus.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------- narration

  Future<void> _prepare(PdfDocument document) async {
    if (_prepared || _preparing) return;
    setState(() {
      _preparing = true;
      _pageCount = document.pages.length;
    });

    final library = AppScope.of(context).library;
    final builder = ScriptBuilder();
    _scriptBuilder = builder;

    final script = await builder.build(
      document,
      onProgress: (progress) {
        if (mounted) setState(() => _prepareProgress = progress);
      },
    );
    if (!mounted) return;

    final entry = library.byPath(widget.path);
    final resume = (entry?.sentenceIndex ?? 0).clamp(0, script.isEmpty ? 0 : script.length - 1);

    setState(() {
      _script = script;
      _preparing = false;
      _prepared = true;
    });

    await _narrator.attach(
      script,
      voiceId: _resolveVoice(),
      speed: _settings.speed,
      startIndex: resume,
    );

    unawaited(
      library.saveProgress(
        widget.path,
        pageCount: _pageCount,
        sentenceCount: script.length,
      ),
    );
  }

  /// Picks the saved voice, falling back to a warm default when the engine
  /// finishes starting after the document is already open.
  String _resolveVoice() {
    if (!_tts.isReady) return '';
    final saved = _settings.voiceId;
    final ids = _tts.voices.map((v) => v.id).toSet();
    if (saved != null && ids.contains(saved)) return saved;
    for (final preferred in const ['af_heart', 'af_bella', 'bf_emma']) {
      if (ids.contains(preferred)) return preferred;
    }
    return _tts.voices.isEmpty ? '' : _tts.voices.first.id;
  }

  void _onEngineChanged() {
    // The engine may come up after the document is open; adopt a voice then.
    if (_tts.isReady && _narrator.voiceId.isEmpty && _script.isNotEmpty) {
      _narrator.setVoice(_resolveVoice());
    }
  }

  void _onCursorChanged() {
    if (!mounted) return;
    setState(() {});
    if (_settings.autoScroll) _followNarration();
    _scheduleSave();
  }

  /// Scrolls only when the sentence has actually left the viewport, so reading
  /// along does not turn into a constant recentring jitter.
  void _followNarration() {
    final sentence = _narrator.current;
    if (sentence == null || !_controller.isReady) return;

    try {
      final target = _controller.calcRectForRectInsidePage(
        pageNumber: sentence.pageNumber,
        rect: sentence.bounds,
      );
      final visible = _controller.visibleRect;
      final margin = visible.height * 0.12;
      final comfortable = Rect.fromLTRB(
        visible.left,
        visible.top + margin,
        visible.right,
        visible.bottom - margin,
      );
      if (comfortable.contains(target.topLeft) && comfortable.contains(target.bottomRight)) {
        return;
      }
      _controller.ensureVisible(
        target,
        margin: 72,
        duration: const Duration(milliseconds: 320),
      );
    } catch (_) {
      // The viewer is mid-layout; the next sentence will catch up.
    }
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 2), _persistProgress);
  }

  void _persistProgress() {
    if (!_wired || !mounted) return;
    AppScope.of(context).library.saveProgress(
      widget.path,
      lastPage: _page,
      pageCount: _pageCount,
      sentenceIndex: _narrator.index,
      sentenceCount: _script.length,
    );
  }

  // ------------------------------------------------------------- interactions

  Future<void> _pickVoice() async {
    final chosen = await showVoicePicker(context, tts: _tts, selectedId: _narrator.voiceId);
    if (chosen == null || !mounted) return;
    await _settings.setVoiceId(chosen);
    await _narrator.setVoice(chosen);
  }

  void _openSettings() =>
      showSettingsDialog(context, settings: _settings, tts: _tts);

  void _readFromCurrentPage() {
    if (_script.isEmpty) return;
    _narrator.jumpTo(_script.firstIndexOnPage(_page), autoplay: true);
  }

  /// Double-clicking a paragraph starts narration from that sentence.
  bool _readFromPoint(Offset pagePoint, PdfPage page) {
    if (_script.isEmpty) return false;

    Sentence? best;
    var bestDistance = double.infinity;

    for (final sentence in _script.onPage(page.pageNumber)) {
      for (final box in sentence.lineRects) {
        if (box.containsXy(pagePoint.dx, pagePoint.dy, margin: 2)) {
          _narrator.jumpTo(sentence.index, autoplay: true);
          return true;
        }
        final dx = pagePoint.dx.clamp(box.left, box.right) - pagePoint.dx;
        final dy = pagePoint.dy.clamp(box.bottom, box.top) - pagePoint.dy;
        final distance = dx * dx + dy * dy;
        if (distance < bestDistance) {
          bestDistance = distance;
          best = sentence;
        }
      }
    }

    // Within roughly a line height of some text: treat it as a hit.
    if (best != null && bestDistance < 400) {
      _narrator.jumpTo(best.index, autoplay: true);
      return true;
    }
    return false;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;

    final shift = HardwareKeyboard.instance.isShiftPressed;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.space) {
      _narrator.toggle();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      shift ? _narrator.nudge(-Narrator.skipStep) : _narrator.previous();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      shift ? _narrator.nudge(Narrator.skipStep) : _narrator.next();
    } else if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) {
      _changeSpeed(-0.25);
    } else if (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.numpadAdd) {
      _changeSpeed(0.25);
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _changeSpeed(double delta) {
    final next = (_narrator.speed + delta).clamp(0.5, 3.0);
    _narrator.setSpeed(next);
    _settings.setSpeed(next);
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;

    return Scaffold(
      backgroundColor: p.pageBackdrop,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          children: [
            Positioned.fill(child: _buildViewer(p)),
            Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),
            Positioned(left: 0, right: 0, bottom: 0, child: _buildBottom()),
            if (_preparing)
              Positioned.fill(
                child: ColoredBox(
                  color: p.pageBackdrop.withValues(alpha: 0.82),
                  child: Center(child: _PreparingCard(progress: _prepareProgress)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewer(LumenPalette p) {
    final highlighter = SentenceHighlighter(
      current: _settings.highlightSentence ? _narrator.current : null,
      upcoming: _narrator.upcoming,
      fill: p.highlight,
      edge: p.highlightEdge,
      showUpcoming: _settings.highlightSentence && _narrator.isActive,
    );

    return PdfViewer.file(
      widget.path,
      controller: _controller,
      params: PdfViewerParams(
        backgroundColor: p.pageBackdrop,
        margin: 18,
        // Arrow keys drive narration instead of scrolling the page.
        enableKeyboardNavigation: false,
        onPageChanged: (pageNumber) {
          if (pageNumber != null && mounted) {
            setState(() => _page = pageNumber);
            _scheduleSave();
          }
        },
        onViewerReady: (document, controller) {
          _prepare(document);
        },
        pagePaintCallbacks: [highlighter.paint],
        pageOverlaysBuilder: (context, pageRect, page) => [
          PdfOverlayInteractionRegion(
            onDoubleTap: (details) {
              final local = details.localPosition;
              if (pageRect.width <= 0 || pageRect.height <= 0) return false;
              return _readFromPoint(
                Offset(
                  local.dx / pageRect.width * page.width,
                  page.height - (local.dy / pageRect.height * page.height),
                ),
                page,
              );
            },
            child: const SizedBox.expand(),
          ),
        ],
        loadingBannerBuilder: (context, downloaded, total) => Center(
          child: CircularProgressIndicator(color: p.accent, strokeWidth: 2.5),
        ),
        errorBannerBuilder: (context, error, stack, ref) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SoftPanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded, color: p.warning, size: 30),
                  const SizedBox(height: 12),
                  Text('This PDF could not be opened', style: context.texts.titleLarge),
                  const SizedBox(height: 8),
                  SelectableText(
                    '$error',
                    textAlign: TextAlign.center,
                    style: context.texts.bodySmall?.copyWith(color: p.inkFaint),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final p = context.lumen;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
      child: SoftPanel(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            IconAction(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back to library  (Esc)',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.titleMedium,
                  ),
                  Text(
                    _pageCount == 0 ? 'Opening...' : 'Page $_page of $_pageCount',
                    style: context.texts.bodySmall?.copyWith(color: p.inkFaint),
                  ),
                ],
              ),
            ),
            Pill(
              tooltip: 'Start narrating from the page you are looking at',
              onTap: _script.isEmpty ? null : _readFromCurrentPage,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.play_circle_outline_rounded, size: 15),
                  SizedBox(width: 6),
                  Text('Read this page'),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ListenableBuilder(
              listenable: _settings,
              builder: (context, _) => Row(
                children: [
                  IconAction(
                    icon: Icons.my_location_rounded,
                    tooltip: _settings.autoScroll ? 'Following narration' : 'Follow narration',
                    active: _settings.autoScroll,
                    onPressed: () => _settings.setAutoScroll(!_settings.autoScroll),
                  ),
                  IconAction(
                    icon: Icons.border_color_rounded,
                    tooltip: _settings.highlightSentence
                        ? 'Highlight on'
                        : 'Highlight off',
                    active: _settings.highlightSentence,
                    onPressed: () =>
                        _settings.setHighlightSentence(!_settings.highlightSentence),
                  ),
                  IconAction(
                    icon: _settings.themeMode == ThemeMode.light
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    tooltip: 'Toggle theme',
                    onPressed: () => _settings.setThemeMode(
                      _settings.themeMode == ThemeMode.light
                          ? ThemeMode.dark
                          : ThemeMode.light,
                    ),
                  ),
                ],
              ),
            ),
            IconAction(
              icon: Icons.zoom_out_rounded,
              tooltip: 'Zoom out',
              onPressed: () => _controller.zoomDown(),
            ),
            IconAction(
              icon: Icons.zoom_in_rounded,
              tooltip: 'Zoom in',
              onPressed: () => _controller.zoomUp(),
            ),
            IconAction(
              icon: Icons.keyboard_rounded,
              tooltip: 'Space play/pause  -  Left/Right sentence  -  '
                  'Shift+Left/Right 10s  -  +/- speed',
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottom() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _EngineNotice(tts: _tts, script: _script, prepared: _prepared, onFix: _openSettings),
          PlayerDock(
            narrator: _narrator,
            tts: _tts,
            onPickVoice: _pickVoice,
            onOpenSettings: _openSettings,
          ),
        ],
      ),
    );
  }
}

/// Explains, in one line, why narration cannot start - and offers the fix.
class _EngineNotice extends StatelessWidget {
  const _EngineNotice({
    required this.tts,
    required this.script,
    required this.prepared,
    required this.onFix,
  });

  final TtsService tts;
  final NarrationScript script;
  final bool prepared;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;

    return ListenableBuilder(
      listenable: tts,
      builder: (context, _) {
        String? message;
        var actionable = true;

        if (prepared && script.isEmpty) {
          message = 'No selectable text on these pages - this PDF is probably scanned images.';
          actionable = false;
        } else if (tts.status == EngineStatus.failed) {
          message = tts.error;
        } else if (tts.status == EngineStatus.idle) {
          message = 'Point Lumen at your Kokoro model to enable narration.';
        } else if (tts.status == EngineStatus.starting) {
          message = 'Warming up the speech engine...';
          actionable = false;
        }

        if (message == null) return const SizedBox.shrink();
        final warn = tts.status == EngineStatus.failed || (prepared && script.isEmpty);

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SoftPanel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: warn ? p.warning.withValues(alpha: 0.12) : p.surface,
            child: Row(
              children: [
                Icon(
                  warn ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                  size: 17,
                  color: warn ? p.warning : p.inkFaint,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall?.copyWith(color: p.inkSoft),
                  ),
                ),
                if (actionable)
                  TextButton(
                    onPressed: onFix,
                    child: Text('Fix', style: TextStyle(color: p.accent)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PreparingCard extends StatelessWidget {
  const _PreparingCard({required this.progress});

  final ScriptProgress? progress;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;
    final value = progress?.fraction ?? 0;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: SoftPanel(
        padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_stories_rounded, color: p.accent, size: 20),
                const SizedBox(width: 10),
                Text('Preparing narration', style: context.texts.titleLarge),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              progress == null
                  ? 'Reading the document...'
                  : 'Page ${progress!.pagesDone} of ${progress!.pagesTotal}  -  '
                        '${progress!.sentencesFound} sentences',
              style: context.texts.bodySmall?.copyWith(color: p.inkFaint),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value == 0 ? null : value,
                minHeight: 6,
                backgroundColor: p.stroke,
                valueColor: AlwaysStoppedAnimation(p.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
