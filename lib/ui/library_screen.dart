import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../app.dart';
import '../models/library_entry.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import 'reader_screen.dart';
import 'widgets/model_setup_card.dart';
import 'widgets/primitives.dart';
import 'widgets/settings_dialog.dart';

/// Home: the shelf of documents you have opened, and the way in to new ones.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _opening = false;

  Future<void> _pickAndOpen() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        dialogTitle: 'Choose a PDF to read aloud',
      );
      final path = picked?.path;
      if (path != null && mounted) await _open(path);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _open(String path) async {
    final scope = AppScope.of(context);
    if (!File(path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That file is no longer where it used to be.')),
      );
      await scope.library.remove(path);
      return;
    }

    await scope.library.touch(path);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ReaderScreen(path: path)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;
    final scope = AppScope.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.7, -1.1),
            radius: 1.5,
            colors: [p.accent.withValues(alpha: 0.07), p.canvas],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _Header(onOpen: _pickAndOpen, opening: _opening),
              ModelSetupCard(models: scope.models),
              Expanded(
                child: ListenableBuilder(
                  listenable: scope.library,
                  builder: (context, _) {
                    final entries = scope.library.entries;
                    if (entries.isEmpty) {
                      return _EmptyLibrary(onOpen: _pickAndOpen);
                    }
                    return _Shelf(
                      entries: entries,
                      onOpen: _open,
                      onRemove: scope.library.remove,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onOpen, required this.opening});

  final VoidCallback onOpen;
  final bool opening;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;
    final scope = AppScope.of(context);
    final compact = context.isCompact;

    final mark = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 36 : 42,
          height: compact ? 36 : 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: LumenRadius.brMd,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [p.accent, p.accent.withValues(alpha: 0.65)],
            ),
          ),
          child: Icon(Icons.graphic_eq_rounded, color: p.accentInk, size: compact ? 19 : 22),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Lumen',
              style: compact ? context.texts.headlineSmall : context.texts.headlineMedium,
            ),
            if (!compact)
              Text(
                'PDFs, read aloud by Kokoro',
                style: context.texts.bodySmall?.copyWith(color: p.inkFaint),
              ),
          ],
        ),
      ],
    );

    final openButton = FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.accentInk,
        padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 20, vertical: 16),
        shape: const RoundedRectangleBorder(borderRadius: LumenRadius.brMd),
        textStyle: context.texts.labelLarge,
      ),
      onPressed: opening ? null : onOpen,
      icon: opening
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.add_rounded, size: 19),
      label: const Text('Open PDF'),
    );

    final settingsButton = IconAction(
      icon: Icons.tune_rounded,
      tooltip: 'Settings',
      size: context.tapTarget,
      onPressed: () => showSettingsDialog(
        context,
        settings: scope.settings,
        tts: scope.tts,
      ),
    );

    if (compact) {
      // Two rows: identity and status on top, the call to action beneath it at
      // full width, where a thumb can reach it.
      return Padding(
        padding: EdgeInsets.fromLTRB(context.gutter, 16, context.gutter, 14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: mark),
                const _EngineBadge(compact: true),
                settingsButton,
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: openButton),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(context.gutter, 30, context.gutter, 20),
      child: Row(
        children: [
          mark,
          const Spacer(),
          const _EngineBadge(),
          const SizedBox(width: 8),
          settingsButton,
          const SizedBox(width: 12),
          openButton,
        ],
      ),
    );
  }
}

/// A quiet traffic light for the Kokoro sidecar, with the failure reason on tap.
class _EngineBadge extends StatelessWidget {
  const _EngineBadge({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;
    final scope = AppScope.of(context);

    return ListenableBuilder(
      listenable: scope.tts,
      builder: (context, _) {
        final (color, label) = switch (scope.tts.status) {
          EngineStatus.ready => (p.positive, 'Voice ready'),
          EngineStatus.starting => (p.accent, 'Warming up'),
          EngineStatus.failed => (p.warning, 'Voice offline'),
          EngineStatus.idle => (p.inkFaint, 'Voice not set up'),
        };

        return Pill(
          tooltip: scope.tts.error ?? 'Kokoro speech engine',
          onTap: () => showSettingsDialog(
            context,
            settings: scope.settings,
            tts: scope.tts,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              if (!compact) ...[
                const SizedBox(width: 8),
                Text(label),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Shelf extends StatelessWidget {
  const _Shelf({required this.entries, required this.onOpen, required this.onRemove});

  final List<LibraryEntry> entries;
  final Future<void> Function(String path) onOpen;
  final Future<void> Function(String path) onRemove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Cards keep a comfortable width rather than stretching on wide
        // screens, and never drop below two columns on a phone.
        final compact = context.isCompact;
        final target = compact ? 170.0 : 260.0;
        final columns = (constraints.maxWidth / target).floor().clamp(2, 6);
        final gutter = context.gutter;

        return GridView.builder(
          padding: EdgeInsets.fromLTRB(gutter, 4, gutter, compact ? 28 : 40),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: compact ? 12 : 20,
            mainAxisSpacing: compact ? 16 : 24,
            childAspectRatio: compact ? 0.62 : 0.66,
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            return _DocumentCard(
              entry: entry,
              onOpen: () => onOpen(entry.path),
              onRemove: () => onRemove(entry.path),
            );
          },
        );
      },
    );
  }
}

class _DocumentCard extends StatefulWidget {
  const _DocumentCard({required this.entry, required this.onOpen, required this.onRemove});

  final LibraryEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  State<_DocumentCard> createState() => _DocumentCardState();
}

class _DocumentCardState extends State<_DocumentCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;
    final entry = widget.entry;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        onLongPress: () => _confirmRemove(context),
        child: AnimatedContainer(
          duration: LumenMotion.quick,
          transform: Matrix4.translationValues(0, _hovering ? -4 : 0, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: LumenRadius.brMd,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: p.surfaceHigh,
                          border: Border.all(color: p.stroke),
                          borderRadius: LumenRadius.brMd,
                        ),
                        child: _Thumbnail(path: entry.path),
                      ),
                    ),
                    AnimatedOpacity(
                      duration: LumenMotion.quick,
                      opacity: _hovering ? 1 : 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: LumenRadius.brMd,
                          color: Colors.black.withValues(alpha: 0.45),
                        ),
                        child: Center(
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                            child: Icon(
                              entry.isStarted
                                  ? Icons.play_arrow_rounded
                                  : Icons.menu_book_rounded,
                              color: p.accentInk,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Hover reveals it on desktop; touch uses the long press.
                    if (_hovering && !context.isCompact)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: const CircleBorder(),
                          child: IconAction(
                            icon: Icons.close_rounded,
                            tooltip: 'Remove from library',
                            iconSize: 15,
                            size: 28,
                            onPressed: widget.onRemove,
                          ),
                        ),
                      ),
                    if (entry.isStarted)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(bottom: LumenRadius.md),
                          child: LinearProgressIndicator(
                            value: entry.progress,
                            minHeight: 4,
                            backgroundColor: Colors.black.withValues(alpha: 0.35),
                            valueColor: AlwaysStoppedAnimation(p.accent),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                entry.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.texts.titleMedium?.copyWith(height: 1.3),
              ),
              const SizedBox(height: 2),
              Text(
                _subtitle(entry),
                style: context.texts.bodySmall?.copyWith(color: p.inkFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final p = context.lumen;
    final remove = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SoftPanel(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Text(
                    widget.entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.titleMedium,
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: p.warning),
                  title: Text(
                    'Remove from library',
                    style: context.texts.bodyLarge?.copyWith(color: p.warning),
                  ),
                  subtitle: Text(
                    'The file itself is left alone.',
                    style: context.texts.bodySmall?.copyWith(color: p.inkFaint),
                  ),
                  onTap: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (remove ?? false) widget.onRemove();
  }

  static String _subtitle(LibraryEntry entry) {
    if (entry.isFinished) return 'Finished';
    if (entry.isStarted) return '${(entry.progress * 100).round()}% - page ${entry.lastPage}';
    return _relative(entry.openedAt);
  }

  static String _relative(DateTime when) {
    final delta = DateTime.now().difference(when);
    if (delta.inMinutes < 1) return 'Just now';
    if (delta.inHours < 1) return '${delta.inMinutes} min ago';
    if (delta.inDays < 1) return '${delta.inHours} hr ago';
    if (delta.inDays < 7) return '${delta.inDays} d ago';
    return '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
  }
}

/// First page of the document, rendered by pdfium.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;

    return PdfDocumentViewBuilder.file(
      path,
      loadingBuilder: (context) => Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: p.inkFaint),
        ),
      ),
      errorBuilder: (context, error, stack) => Center(
        child: Icon(Icons.description_outlined, size: 30, color: p.inkFaint),
      ),
      builder: (context, document) {
        if (document == null) return const SizedBox.shrink();
        return PdfPageView(
          document: document,
          pageNumber: 1,
          alignment: Alignment.topCenter,
          maximumDpi: 120,
          backgroundColor: Colors.white,
        );
      },
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;

    final compact = context.isCompact;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: context.gutter),
        child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 76 : 96,
              height: compact ? 76 : 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.accent.withValues(alpha: 0.10),
                border: Border.all(color: p.accent.withValues(alpha: 0.3)),
              ),
              child: Icon(Icons.headphones_rounded, size: 40, color: p.accent),
            ),
            const SizedBox(height: 26),
            Text('Nothing on the shelf yet', style: context.texts.headlineSmall),
            const SizedBox(height: 10),
            Text(
              'Open a PDF and Lumen will read it out loud, sentence by sentence, '
              'highlighting the page as it goes.',
              textAlign: TextAlign.center,
              style: context.texts.bodyMedium?.copyWith(color: p.inkSoft, height: 1.6),
            ),
            const SizedBox(height: 26),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: p.accent,
                foregroundColor: p.accentInk,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                shape: const RoundedRectangleBorder(borderRadius: LumenRadius.brMd),
                textStyle: context.texts.labelLarge,
              ),
              onPressed: onOpen,
              icon: const Icon(Icons.folder_open_rounded, size: 19),
              label: const Text('Choose a PDF'),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
