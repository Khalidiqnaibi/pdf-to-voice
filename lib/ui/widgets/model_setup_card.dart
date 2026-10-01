import 'package:flutter/material.dart';

import '../../services/model_store.dart';
import '../../theme/app_theme.dart';
import 'primitives.dart';

/// Offers the one-time voice download, and reports on it while it runs.
///
/// Desktop builds ship the bundle, so this never appears there. On mobile it is
/// the first thing the library shows until the model is in place.
class ModelSetupCard extends StatelessWidget {
  const ModelSetupCard({super.key, required this.models});

  final ModelStore models;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: models,
      builder: (context, _) {
        if (models.isReady || models.phase == ModelPhase.checking) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: SoftPanel(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: switch (models.phase) {
              ModelPhase.downloading || ModelPhase.extracting => _Busy(models: models),
              ModelPhase.failed => _Failed(models: models),
              _ => _Offer(models: models),
            },
          ),
        );
      },
    );
  }
}

class _Offer extends StatelessWidget {
  const _Offer({required this.models});

  final ModelStore models;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.graphic_eq_rounded, size: 19, color: p.accent),
            const SizedBox(width: 10),
            Text('Download the voice', style: context.texts.titleLarge),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Lumen reads aloud with Kokoro, a neural voice that runs entirely on '
          'this device. It needs a one-time 333 MB download, and takes a few '
          'minutes to unpack. After that it works offline.',
          style: context.texts.bodyMedium?.copyWith(color: p.inkSoft, height: 1.55),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: p.accent,
                foregroundColor: p.accentInk,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                shape: const RoundedRectangleBorder(borderRadius: LumenRadius.brMd),
              ),
              onPressed: models.install,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download voice'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'You can still open and read PDFs without it.',
                style: context.texts.bodySmall?.copyWith(color: p.inkFaint),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.models});

  final ModelStore models;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;
    final downloading = models.phase == ModelPhase.downloading;

    final mb = (ModelStore.downloadBytes / (1 << 20) * models.progress).round();
    final totalMb = (ModelStore.downloadBytes / (1 << 20)).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: p.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                downloading ? 'Downloading the voice' : 'Unpacking the voice',
                style: context.texts.titleMedium,
              ),
            ),
            TextButton(
              onPressed: models.cancel,
              child: Text('Cancel', style: TextStyle(color: p.inkFaint)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            // Unpacking is CPU-bound with no cheap progress signal, so the bar
            // runs indeterminate rather than lying about how far along it is.
            value: downloading ? models.progress : null,
            minHeight: 6,
            backgroundColor: p.stroke,
            valueColor: AlwaysStoppedAnimation(p.accent),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          downloading
              ? '$mb MB of $totalMb MB'
              : 'This takes a few minutes and cannot be hurried - '
                    '${_mmss(models.elapsed)} so far.',
          style: context.texts.bodySmall?.copyWith(color: p.inkFaint),
        ),
      ],
    );
  }

  static String _mmss(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _Failed extends StatelessWidget {
  const _Failed({required this.models});

  final ModelStore models;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.warning_amber_rounded, size: 19, color: p.warning),
            const SizedBox(width: 10),
            Text('Download failed', style: context.texts.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
        SelectableText(
          models.error ?? 'Unknown error.',
          style: context.texts.bodySmall?.copyWith(color: p.inkSoft, height: 1.5),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: p.accent,
            foregroundColor: p.accentInk,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: const RoundedRectangleBorder(borderRadius: LumenRadius.brMd),
          ),
          onPressed: models.install,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}
