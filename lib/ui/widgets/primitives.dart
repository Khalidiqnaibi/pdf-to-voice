import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The app's one surface treatment: a soft card with a hairline border and a
/// diffuse shadow. Every floating panel uses it so the app reads as one object.
class SoftPanel extends StatelessWidget {
  const SoftPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = LumenRadius.brLg,
    this.elevated = true,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius radius;
  final bool elevated;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? p.surface,
        borderRadius: radius,
        border: Border.all(color: p.stroke),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.45 : 0.10),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                  spreadRadius: -6,
                ),
              ]
            : null,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Square icon button with a hover wash, used across the toolbars.
class IconAction extends StatelessWidget {
  const IconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.size = 40,
    this.iconSize = 19,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;
    final enabled = onPressed != null;

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: active ? p.accent.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: LumenRadius.brMd,
          child: InkWell(
            borderRadius: LumenRadius.brMd,
            onTap: onPressed,
            hoverColor: p.ink.withValues(alpha: 0.06),
            child: Icon(
              icon,
              size: iconSize,
              color: !enabled
                  ? p.inkFaint.withValues(alpha: 0.5)
                  : active
                  ? p.accent
                  : p.inkSoft,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact labelled control, e.g. the speed and voice chips in the dock.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.child,
    this.onTap,
    this.tooltip,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.accented = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;
  final EdgeInsetsGeometry padding;
  final bool accented;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;

    final body = Material(
      color: accented ? p.accent.withValues(alpha: 0.14) : p.surfaceHigh,
      borderRadius: LumenRadius.brMd,
      child: InkWell(
        borderRadius: LumenRadius.brMd,
        onTap: onTap,
        hoverColor: p.ink.withValues(alpha: 0.05),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: LumenRadius.brMd,
            border: Border.all(color: accented ? p.accent.withValues(alpha: 0.4) : p.stroke),
          ),
          child: DefaultTextStyle.merge(
            style: context.texts.labelLarge!.copyWith(
              color: accented ? p.accent : p.inkSoft,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            child: child,
          ),
        ),
      ),
    );

    return tooltip == null ? body : Tooltip(message: tooltip!, child: body);
  }
}

/// The big play/pause control, wrapped in a ring that doubles as the progress
/// indicator for the sentence being spoken.
class PlayControl extends StatelessWidget {
  const PlayControl({
    super.key,
    required this.playing,
    required this.busy,
    required this.progress,
    required this.onPressed,
    this.size = 60,
  });

  final bool playing;
  final bool busy;

  /// 0..1 through the current sentence.
  final double progress;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;

    return Tooltip(
      message: playing ? 'Pause  (Space)' : 'Play  (Space)',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CustomPaint(
                painter: _RingPainter(
                  progress: busy ? null : progress,
                  track: p.stroke,
                  fill: p.accent,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(5),
              child: Material(
                color: p.accent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onPressed,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: LumenMotion.quick,
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: Icon(
                        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        key: ValueKey(playing),
                        size: size * 0.42,
                        color: p.accentInk,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.track, required this.fill});

  /// Null renders the indeterminate "rendering" arc.
  final double? progress;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = math.min(size.width, size.height) / 2 - 1.5;

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = track;
    canvas.drawCircle(center, radius, base);

    final sweep = progress == null ? math.pi * 0.6 : (progress!.clamp(0.0, 1.0)) * math.pi * 2;
    if (sweep <= 0) return;

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = fill;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.fill != fill || old.track != track;
}

/// Scrub bar for the whole document. Dragging maps directly onto the narration
/// script, so releasing lands on a sentence boundary.
class DocumentRail extends StatefulWidget {
  const DocumentRail({
    super.key,
    required this.progress,
    required this.onSeek,
    this.enabled = true,
    this.height = 22,
  });

  final double progress;
  final ValueChanged<double> onSeek;
  final bool enabled;
  final double height;

  @override
  State<DocumentRail> createState() => _DocumentRailState();
}

class _DocumentRailState extends State<DocumentRail> {
  double? _dragValue;
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;
    final value = (_dragValue ?? widget.progress).clamp(0.0, 1.0);
    final thick = _hovering || _dragValue != null;

    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: widget.enabled ? (d) => _update(d.localPosition.dx) : null,
        onHorizontalDragUpdate: widget.enabled ? (d) => _update(d.localPosition.dx) : null,
        onHorizontalDragEnd: widget.enabled ? (_) => _commit() : null,
        onTapDown: widget.enabled ? (d) => _update(d.localPosition.dx) : null,
        onTapUp: widget.enabled ? (_) => _commit() : null,
        child: SizedBox(
          height: widget.height,
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return AnimatedContainer(
                  duration: LumenMotion.quick,
                  height: thick ? 8 : 5,
                  decoration: BoxDecoration(
                    color: p.stroke,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Stack(
                    children: [
                      FractionallySizedBox(
                        widthFactor: value == 0 ? 0.0001 : value,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [p.accent.withValues(alpha: 0.75), p.accent],
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                      if (thick)
                        Positioned(
                          left: (value * width - 5).clamp(0.0, math.max(0.0, width - 10)),
                          top: -1,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: p.accent,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: p.accent.withValues(alpha: 0.5),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _update(double dx) {
    final width = context.size?.width ?? 1;
    setState(() => _dragValue = (dx / width).clamp(0.0, 1.0));
  }

  void _commit() {
    final value = _dragValue;
    setState(() => _dragValue = null);
    if (value != null) widget.onSeek(value);
  }
}

/// Section label used in sheets and the library.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: context.texts.labelSmall?.copyWith(color: p.inkFaint, letterSpacing: 1.1),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

String formatDuration(Duration d) {
  final total = d.inSeconds.abs();
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final sign = d.isNegative ? '-' : '';
  if (hours > 0) {
    return '$sign$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$sign$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// "18 min left", "1 hr 4 min left" - friendlier than a raw clock in the dock.
String formatRemaining(Duration d) {
  if (d.inSeconds < 45) return 'almost done';
  if (d.inMinutes < 60) return '${d.inMinutes} min left';
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  return minutes == 0 ? '$hours hr left' : '$hours hr $minutes min left';
}
