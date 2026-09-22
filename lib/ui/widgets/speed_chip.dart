import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'primitives.dart';

/// The speed control: a chip showing the current rate that opens an anchored
/// popover with presets and a fine slider.
///
/// Rate is applied at the player rather than re-rendered, so dragging the slider
/// changes the voice speed immediately without losing your place.
class SpeedChip extends StatefulWidget {
  const SpeedChip({
    super.key,
    required this.speed,
    required this.onChanged,
    this.enabled = true,
  });

  final double speed;
  final ValueChanged<double> onChanged;
  final bool enabled;

  static const presets = <double>[0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  State<SpeedChip> createState() => _SpeedChipState();
}

class _SpeedChipState extends State<SpeedChip> {
  final _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;

    return MenuAnchor(
      controller: _controller,
      alignmentOffset: const Offset(0, 10),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(p.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.4)),
        side: WidgetStatePropertyAll(BorderSide(color: p.stroke)),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: LumenRadius.brLg),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      menuChildren: [
        _SpeedPanel(
          speed: widget.speed,
          onChanged: widget.onChanged,
        ),
      ],
      builder: (context, controller, _) {
        return Pill(
          tooltip: 'Playback speed  (- / +)',
          accented: widget.speed != 1.0,
          onTap: widget.enabled
              ? () => controller.isOpen ? controller.close() : controller.open()
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.speed_rounded, size: 15),
              const SizedBox(width: 6),
              Text(formatSpeed(widget.speed)),
            ],
          ),
        );
      },
    );
  }
}

String formatSpeed(double value) {
  final text = value.toStringAsFixed(2);
  final trimmed = text.endsWith('0') ? text.substring(0, text.length - 1) : text;
  return '${trimmed}x';
}

class _SpeedPanel extends StatefulWidget {
  const _SpeedPanel({required this.speed, required this.onChanged});

  final double speed;
  final ValueChanged<double> onChanged;

  @override
  State<_SpeedPanel> createState() => _SpeedPanelState();
}

class _SpeedPanelState extends State<_SpeedPanel> {
  late double _value = widget.speed;

  @override
  void didUpdateWidget(_SpeedPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speed != widget.speed) _value = widget.speed;
  }

  void _set(double value) {
    final rounded = (value * 20).round() / 20; // 0.05 steps
    setState(() => _value = rounded);
    widget.onChanged(rounded);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;

    return SizedBox(
      width: 320,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const SectionLabel('Playback speed'),
                const Spacer(),
                Text(
                  formatSpeed(_value),
                  style: context.texts.titleMedium?.copyWith(color: p.accent),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: _value.clamp(0.5, 3.0),
                min: 0.5,
                max: 3.0,
                onChanged: _set,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in SpeedChip.presets)
                  _PresetChip(
                    label: formatSpeed(preset),
                    selected: (_value - preset).abs() < 0.001,
                    onTap: () => _set(preset),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Pitch stays natural at every speed.',
              style: context.texts.bodySmall?.copyWith(color: p.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;

    return Material(
      color: selected ? p.accent : p.surfaceHigh,
      borderRadius: LumenRadius.brSm,
      child: InkWell(
        borderRadius: LumenRadius.brSm,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: LumenRadius.brSm,
            border: Border.all(color: selected ? p.accent : p.stroke),
          ),
          child: Text(
            label,
            style: context.texts.labelLarge?.copyWith(
              color: selected ? p.accentInk : p.inkSoft,
            ),
          ),
        ),
      ),
    );
  }
}
