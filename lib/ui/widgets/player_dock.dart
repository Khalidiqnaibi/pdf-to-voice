import 'package:flutter/material.dart';

import '../../models/voice.dart';
import '../../playback/narrator.dart';
import '../../services/tts_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import 'primitives.dart';
import 'speed_chip.dart';

/// The transport bar docked at the bottom of the reader.
///
/// Reads three things at a glance: what is being said right now, how far through
/// the document you are, and how long is left.
///
/// On desktop the controls spread across one row. The transport cluster alone is
/// about 240 logical pixels, so on a phone it cannot share a row with the speed
/// and voice chips: there the dock stacks into transport, then chips.
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
    final compact = context.isCompact;

    return ListenableBuilder(
      listenable: narrator,
      builder: (context, _) {
        return SoftPanel(
          radius: LumenRadius.brXl,
          padding: EdgeInsets.fromLTRB(compact ? 12 : 18, 12, compact ? 12 : 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SentenceStrip(narrator: narrator),
              const SizedBox(height: 10),
              _Timeline(narrator: narrator),
              SizedBox(height: compact ? 6 : 10),
              if (compact) ...[
                _Transport(narrator: narrator, hasScript: narrator.hasScript),
                const SizedBox(height: 4),
                _ChipRow(
                  narrator: narrator,
                  tts: tts,
                  onPickVoice: onPickVoice,
                  onOpenSettings: onOpenSettings,
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          SpeedChip(
                            speed: narrator.speed,
                            enabled: narrator.hasScript,
                            onChanged: narrator.setSpeed,
                          ),
                          const SizedBox(width: 8),
                          _SleepChip(narrator: narrator),
                        ],
                      ),
                    ),
                    _Transport(narrator: narrator, hasScript: narrator.hasScript),
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

/// Page/sentence position, the scrub rail and time remaining.
///
/// Desktop puts the labels either side of the rail. A phone has no room for
/// that, so they sit above it.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.narrator});

  final Narrator narrator;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;
    final hasScript = narrator.hasScript;
    final sentence = narrator.current;
    final remaining = hasScript ? narrator.remaining : Duration.zero;

    final position = hasScript
        ? 'p. ${sentence?.pageNumber ?? 1}  ·  ${narrator.index + 1} / ${narrator.script.length}'
        : 'No narration yet';
    final left = hasScript ? formatRemaining(remaining) : '';

    final label = context.texts.bodySmall?.copyWith(
      color: p.inkFaint,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final rail = ValueListenableBuilder<Duration>(
      valueListenable: narrator.position,
      builder: (context, _, _) => DocumentRail(
        progress: narrator.documentProgress,
        enabled: hasScript,
        onSeek: (fraction) => narrator.jumpTo(
          (fraction * narrator.script.length).floor(),
          autoplay: narrator.isActive,
        ),
      ),
    );

    if (context.isCompact) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(position, style: label)),
              Text(left, style: label),
            ],
          ),
          rail,
        ],
      );
    }

    return Row(
      children: [
        SizedBox(width: 136, child: Text(position, style: label)),
        Expanded(child: rail),
        SizedBox(
          width: 136,
          child: Text(left, textAlign: TextAlign.right, style: label),
        ),
      ],
    );
  }
}

/// Speed, sleep timer, voice and settings — the compact second row.
class _ChipRow extends StatelessWidget {
  const _ChipRow({
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
    return Row(
      children: [
        SpeedChip(
          speed: narrator.speed,
          enabled: narrator.hasScript,
          onChanged: narrator.setSpeed,
        ),
        const SizedBox(width: 6),
        _SleepChip(narrator: narrator),
        const SizedBox(width: 6),
        // Expanded rather than Spacer + Flexible: a Spacer claims every spare
        // pixel first, which squeezed the voice name out of the chip entirely.
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: _VoiceChip(
              tts: tts,
              voiceId: narrator.voiceId,
              onTap: onPickVoice,
              compact: true,
            ),
          ),
        ),
        IconAction(
          icon: Icons.tune_rounded,
          tooltip: 'Settings',
          onPressed: onOpenSettings,
        ),
      ],
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.narrator, required this.hasScript});

  final Narrator narrator;
  final bool hasScript;

  @override
  Widget build(BuildContext context) {
    final target = context.tapTarget;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconAction(
          icon: Icons.skip_previous_rounded,
          tooltip: 'Previous sentence',
          iconSize: 22,
          size: target,
          onPressed: hasScript ? narrator.previous : null,
        ),
        IconAction(
          icon: Icons.replay_10_rounded,
          tooltip: 'Back 10 seconds',
          iconSize: 23,
          size: target + 4,
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
              size: context.isCompact ? 58 : 60,
            );
          },
        ),
        const SizedBox(width: 6),
        IconAction(
          icon: Icons.forward_10_rounded,
          tooltip: 'Forward 10 seconds',
          iconSize: 23,
          size: target + 4,
          onPressed: hasScript ? () => narrator.nudge(Narrator.skipStep) : null,
        ),
        IconAction(
          icon: Icons.skip_next_rounded,
          tooltip: 'Next sentence',
          iconSize: 22,
          size: target,
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
    final compact = context.isCompact;

    final String text;
    final Color color;
    if (narrator.phase == NarratorPhase.error) {
      text = narrator.error ?? 'Something went wrong.';
      color = p.warning;
    } else if (narrator.phase == NarratorPhase.finished) {
      text = 'End of document.';
      color = p.inkFaint;
    } else if (sentence == null) {
      text = compact
          ? 'Open a PDF and press play.'
          : 'Open a PDF and press play to start listening.';
      color = p.inkFaint;
    } else {
      text = sentence.text;
      color = narrator.isActive ? p.ink : p.inkSoft;
    }

    return Container(
      constraints: BoxConstraints(minHeight: compact ? 48 : 54),
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: 8),
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
            height: narrator.isActive ? 24 : 14,
            decoration: BoxDecoration(
              color: narrator.isActive ? p.accent : p.stroke,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: compact ? 10 : 12),
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
                style: (compact ? context.texts.bodySmall : context.texts.bodyMedium)
                    ?.copyWith(color: color, height: 1.35),
              ),
            ),
          ),
          if (narrator.isRendering) ...[
            SizedBox(width: compact ? 8 : 12),
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
        if (!context.isCompact) ...[
          const SizedBox(width: 8),
          Text(
            'rendering',
            style: context.texts.labelSmall?.copyWith(
              color: p.inkFaint,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ],
    );
  }
}

class _VoiceChip extends StatelessWidget {
  const _VoiceChip({
    required this.tts,
    required this.voiceId,
    required this.onTap,
    this.compact = false,
  });

  final TtsService tts;
  final String voiceId;
  final VoidCallback onTap;
  final bool compact;

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
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: 10),
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
              Flexible(
                child: Text(
                  voice?.displayName ?? 'No voice',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
