import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../models/voice.dart';
import '../../services/tts_service.dart';
import '../../theme/app_theme.dart';
import 'primitives.dart';

/// Voice browser with search, accent grouping and in-place preview.
///
/// Returns the chosen voice id, or null if the sheet was dismissed.
Future<String?> showVoicePicker(
  BuildContext context, {
  required TtsService tts,
  required String selectedId,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) => _VoicePickerDialog(tts: tts, selectedId: selectedId),
  );
}

class _VoicePickerDialog extends StatefulWidget {
  const _VoicePickerDialog({required this.tts, required this.selectedId});

  final TtsService tts;
  final String selectedId;

  @override
  State<_VoicePickerDialog> createState() => _VoicePickerDialogState();
}

class _VoicePickerDialogState extends State<_VoicePickerDialog> {
  final _search = TextEditingController();
  final _player = Player();

  late String _selected = widget.selectedId;
  String? _previewing;

  @override
  void dispose() {
    _search.dispose();
    _player.dispose();
    super.dispose();
  }

  List<Voice> get _filtered {
    final query = _search.text.trim().toLowerCase();
    final voices = widget.tts.voices;
    if (query.isEmpty) return voices;
    return voices
        .where(
          (v) =>
              v.displayName.toLowerCase().contains(query) ||
              v.accent.toLowerCase().contains(query) ||
              v.gender.toLowerCase().contains(query) ||
              v.id.toLowerCase().contains(query),
        )
        .toList();
  }

  Future<void> _preview(Voice voice) async {
    setState(() => _previewing = voice.id);
    try {
      final clip = await widget.tts.clip(voice.previewLine, voice.id, priority: 0);
      if (!mounted || _previewing != voice.id) return;
      await _player.open(Media(clip.file.path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not preview ${voice.displayName}: $e')),
      );
    } finally {
      if (mounted) setState(() => _previewing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;
    final grouped = _group(_filtered);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: SoftPanel(
          padding: EdgeInsets.zero,
          radius: LumenRadius.brXl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Narrator', style: context.texts.headlineSmall),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.tts.voices.length} Kokoro voices',
                            style: context.texts.bodySmall?.copyWith(color: p.inkFaint),
                          ),
                        ],
                      ),
                    ),
                    IconAction(
                      icon: Icons.close_rounded,
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  style: context.texts.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Search voices, accents...',
                    hintStyle: context.texts.bodyMedium?.copyWith(color: p.inkFaint),
                    prefixIcon: Icon(Icons.search_rounded, size: 18, color: p.inkFaint),
                    filled: true,
                    fillColor: p.surfaceHigh,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: LumenRadius.brMd,
                      borderSide: BorderSide(color: p.stroke),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: LumenRadius.brMd,
                      borderSide: BorderSide(color: p.stroke),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: LumenRadius.brMd,
                      borderSide: BorderSide(color: p.accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: grouped.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(40),
                        child: Text(
                          'No voices match "${_search.text}".',
                          style: context.texts.bodyMedium?.copyWith(color: p.inkFaint),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                        itemCount: grouped.length,
                        itemBuilder: (context, index) {
                          final row = grouped[index];
                          if (row is String) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
                              child: SectionLabel(row),
                            );
                          }
                          final voice = row as Voice;
                          return _VoiceRow(
                            voice: voice,
                            selected: voice.id == _selected,
                            previewing: _previewing == voice.id,
                            onTap: () => setState(() => _selected = voice.id),
                            onPreview: () => _preview(voice),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Previews render on demand and are cached.',
                        style: context.texts.bodySmall?.copyWith(color: p.inkFaint),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Cancel', style: TextStyle(color: p.inkSoft)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: p.accentInk,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: const RoundedRectangleBorder(borderRadius: LumenRadius.brMd),
                      ),
                      onPressed: () => Navigator.of(context).pop(_selected),
                      child: const Text('Use this voice'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Flattens the voices into [header, voice, voice, header, ...] rows.
  List<Object> _group(List<Voice> voices) {
    final byAccent = <String, List<Voice>>{};
    for (final voice in voices) {
      byAccent.putIfAbsent(voice.accentCode, () => []).add(voice);
    }

    final codes = byAccent.keys.toList()
      ..sort((a, b) {
        final ai = Voice.accentOrder.indexOf(a);
        final bi = Voice.accentOrder.indexOf(b);
        return (ai == -1 ? 99 : ai).compareTo(bi == -1 ? 99 : bi);
      });

    final rows = <Object>[];
    for (final code in codes) {
      final group = byAccent[code]!
        ..sort((a, b) {
          if (a.isFemale != b.isFemale) return a.isFemale ? -1 : 1;
          return a.displayName.compareTo(b.displayName);
        });
      rows.add(group.first.accent);
      rows.addAll(group);
    }
    return rows;
  }
}

class _VoiceRow extends StatelessWidget {
  const _VoiceRow({
    required this.voice,
    required this.selected,
    required this.previewing,
    required this.onTap,
    required this.onPreview,
  });

  final Voice voice;
  final bool selected;
  final bool previewing;
  final VoidCallback onTap;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected ? p.accent.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: LumenRadius.brMd,
        child: InkWell(
          borderRadius: LumenRadius.brMd,
          onTap: onTap,
          hoverColor: p.ink.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? p.accent : p.surfaceHigh,
                    border: Border.all(color: selected ? p.accent : p.stroke),
                  ),
                  child: Text(
                    voice.initials,
                    style: context.texts.titleMedium?.copyWith(
                      color: selected ? p.accentInk : p.inkSoft,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        voice.displayName,
                        style: context.texts.titleMedium?.copyWith(
                          color: selected ? p.accent : p.ink,
                        ),
                      ),
                      Text(
                        voice.subtitle,
                        style: context.texts.bodySmall?.copyWith(color: p.inkFaint),
                      ),
                    ],
                  ),
                ),
                if (previewing)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: p.accent),
                  )
                else
                  IconAction(
                    icon: Icons.volume_up_rounded,
                    tooltip: 'Preview',
                    onPressed: onPreview,
                    size: 34,
                    iconSize: 17,
                  ),
                if (selected) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.check_circle_rounded, size: 19, color: p.accent),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
