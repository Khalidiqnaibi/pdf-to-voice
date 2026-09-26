import 'package:flutter/material.dart';

import '../../models/voice.dart';
import '../../playback/narrator.dart';
import '../../services/tts_service.dart';
import '../../theme/app_theme.dart';
import 'primitives.dart';
import 'speed_chip.dart';

/// The transport bar docked at the bottom of the reader.
///
/// Reads three things at a glance: what is being said right now, how far through
/// the document you are, and how long is left.
class PlayerDock extends StatelessWidget {
  const PlayerDock({
    super.key,
    required this.narrator,
    required this.tts,
    required this.onPickVoice,
    required this.onOpenSettings,
  });

  final Narrator narrator;
  final TtsService tts;
  final VoidCallback onPickVoice;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: narrator,
      builder: (context, _) {
        final p = context.lumen;
        final hasScript = narrator.hasScript;
        final sentence = narrator.current;
        final remaining = hasScript ? narrator.remaining : Duration.zero;

        return SoftPanel(
          radius: LumenRadius.brXl,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SentenceStrip(narrator: narrator),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 132,
                    child: Text(
                      hasScript
                          ? 'p. ${sentence?.pageNumber ?? 1}  -  ${narrator.index + 1} / ${narrator.script.length}'
                          : 'No narration yet',
                      style: context.texts.bodySmall?.copyWith(
                        color: p.inkFaint,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ValueListenableBuilder<Duration>(
                      valueListenable: narrator.position,
                      builder: (context, _, _) => DocumentRail(
                        progress: narrator.documentProgress,
                        enabled: hasScript,
                        onSeek: (fraction) {
                          final target = (fraction * narrator.script.length).floor();
                          narrator.jumpTo(target, autoplay: narrator.isActive);
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 132,
                    child: Text(
                      hasScript ? formatRemaining(remaining) : '',
                      textAlign: TextAlign.right,
                      style: context.texts.bodySmall?.copyWith(color: p.inkFaint),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        SpeedChip(
                          speed: narrator.speed,
                          enabled: hasScript,
                          onChanged: narrator.setSpeed,
                        ),
                        const SizedBox(width: 8),
                        _SleepChip(narrator: narrator),
                      ],
                    ),
                  ),
                  _Transport(narrator: narrator, hasScript: hasScript),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _VoiceChip(
                          tts: tts,
                          voiceId: narrator.voiceId,
                          onTap: onPickVoice,
                        ),
                        const SizedBox(width: 6),
                        IconAction(
                          icon: Icons.tune_rounded,
                          tooltip: 'Settings',
                          onPressed: onOpenSettings,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.narrator, required this.hasScript});

  final Narrator narrator;
  final bool hasScript;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconAction(
          icon: Icons.skip_previous_rounded,
          tooltip: 'Previous sentence  (Left)',
          iconSize: 22,
          onPressed: hasScript ? narrator.previous : null,
        ),
        IconAction(
          icon: Icons.replay_10_rounded,
          tooltip: 'Back 10 seconds  (Shift+Left)',
          iconSize: 22,
          size: 44,
          onPressed: hasScript ? () => narrator.nudge(-Narrator.skipStep) : null,
        ),
        const SizedBox(width: 6),
        ValueListenableBuilder<Duration>(
          valueListenable: narrator.position,
          builder: (context, position, _) {
            final total = narrator.clipDuration.inMilliseconds;
            return PlayControl(
              playing: narrator.isActive,
              busy: narrator.isRendering,
              progress: total == 0 ? 0 : position.inMilliseconds / total,
              onPressed: hasScript ? narrator.toggle : null,
            );
          },
        ),
        const SizedBox(width: 6),
        IconAction(
          icon: Icons.forward_10_rounded,
          tooltip: 'Forward 10 seconds  (Shift+Right)',
          iconSize: 22,
          size: 44,
          onPressed: hasScript ? () => narrator.nudge(Narrator.skipStep) : null,
        ),
        IconAction(
          icon: Icons.skip_next_rounded,
          tooltip: 'Next sentence  (Right)',
          iconSize: 22,
          onPressed: hasScript ? narrator.next : null,
        ),
      ],
    );
  }
}

/// Shows the sentence being spoken, so you can follow without watching the page.
class _SentenceStrip extends StatelessWidget {
  const _SentenceStrip({required this.narrator});

  final Narrator narrator;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;
    final sentence = narrator.current;

    final String text;
    final Color color;
    if (narrator.phase == NarratorPhase.error) {
      text = narrator.error ?? 'Something went wrong.';
      color = p.warning;
    } else if (narrator.phase == NarratorPhase.finished) {
      text = 'End of document.';
      color = p.inkFaint;
    } else if (sentence == null) {
      text = 'Open a PDF and press play to start listening.';
      color = p.inkFaint;
    } else {
      text = sentence.text;
      color = narrator.isActive ? p.ink : p.inkSoft;
    }

    return Container(
      height: 54,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: p.surfaceHigh,
        borderRadius: LumenRadius.brMd,
        border: Border.all(color: p.stroke),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: LumenMotion.base,
            width: 3,
            height: narrator.isActive ? 26 : 14,
            decoration: BoxDecoration(
              color: narrator.isActive ? p.accent : p.stroke,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedSwitcher(
              duration: LumenMotion.base,
              switchInCurve: LumenMotion.curve,
              // The default layout builder stacks children centred; the strip
              // reads as a line of prose, so it has to start at the left edge.
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, ?current],
              ),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.25),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                text,
                key: ValueKey('${narrator.phase}:${narrator.index}:$text'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodyMedium?.copyWith(color: color, height: 1.35),
              ),
            ),
          ),
          if (narrator.isRendering) ...[
            const SizedBox(width: 12),
            const _RenderingBadge(),
          ],
        ],
      ),
    );
  }
}

class _RenderingBadge extends StatelessWidget {
  const _RenderingBadge();

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 13,
          height: 13,
          child: CircularProgressIndicator(strokeWidth: 1.8, color: p.accent),
        ),
        const SizedBox(width: 8),
        Text(
          'rendering',
          style: context.texts.labelSmall?.copyWith(color: p.inkFaint, letterSpacing: 0.8),
        ),
      ],
    );
  }
}

class _VoiceChip extends StatelessWidget {
  const _VoiceChip({required this.tts, required this.voiceId, required this.onTap});

  final TtsService tts;
  final String voiceId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;

    return ListenableBuilder(
      listenable: tts,
      builder: (context, _) {
        final ready = tts.isReady;
        final voice = voiceId.isEmpty ? null : Voice.fromId(voiceId);

        return Pill(
          tooltip: ready ? 'Change narrator' : 'Speech engine unavailable',
          onTap: ready ? onTap : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ready ? p.accent.withValues(alpha: 0.2) : p.stroke,
                ),
                child: Text(
                  voice?.initials ?? '?',
                  style: context.texts.labelSmall?.copyWith(
                    color: ready ? p.accent : p.inkFaint,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(voice?.displayName ?? 'No voice'),
              const SizedBox(width: 4),
              Icon(Icons.expand_more_rounded, size: 15, color: p.inkFaint),
            ],
          ),
        );
      },
    );
  }
}

class _SleepChip extends StatelessWidget {
  const _SleepChip({required this.narrator});

  final Narrator narrator;

  static const _options = <String, Duration?>{
    'Off': null,
    '5 minutes': Duration(minutes: 5),
    '15 minutes': Duration(minutes: 15),
    '30 minutes': Duration(minutes: 30),
    '45 minutes': Duration(minutes: 45),
    '1 hour': Duration(hours: 1),
  };

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;
    final sleepAt = narrator.sleepAt;
    final active = sleepAt != null;

    return MenuAnchor(
      alignmentOffset: const Offset(0, 10),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(p.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStatePropertyAll(BorderSide(color: p.stroke)),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: LumenRadius.brMd),
        ),
      ),
      menuChildren: [
        for (final entry in _options.entries)
          MenuItemButton(
            onPressed: () => narrator.setSleepTimer(entry.value),
            leadingIcon: Icon(
              entry.value == null ? Icons.block_rounded : Icons.bedtime_rounded,
              size: 16,
              color: p.inkFaint,
            ),
            child: Text(entry.key, style: context.texts.bodyMedium),
          ),
      ],
      builder: (context, controller, _) => Pill(
        tooltip: active ? 'Sleep timer running' : 'Sleep timer',
        accented: active,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bedtime_outlined, size: 15),
            if (active) ...[
              const SizedBox(width: 6),
              Text(formatRemaining(sleepAt.difference(DateTime.now()))),
            ],
          ],
        ),
      ),
    );
  }
}
