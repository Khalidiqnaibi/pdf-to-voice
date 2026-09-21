import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/settings_store.dart';
import '../../services/tts_service.dart';
import '../../theme/app_theme.dart';
import 'primitives.dart';

Future<void> showSettingsDialog(
  BuildContext context, {
  required SettingsStore settings,
  required TtsService tts,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) => _SettingsDialog(settings: settings, tts: tts),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.settings, required this.tts});

  final SettingsStore settings;
  final TtsService tts;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final _python = TextEditingController(text: widget.settings.engineConfig.pythonPath);
  late final _model = TextEditingController(text: widget.settings.engineConfig.modelPath);
  late final _voices = TextEditingController(text: widget.settings.engineConfig.voicesPath);

  int _cacheBytes = 0;
  bool _showLog = false;

  @override
  void initState() {
    super.initState();
    _refreshCache();
  }

  @override
  void dispose() {
    _python.dispose();
    _model.dispose();
    _voices.dispose();
    super.dispose();
  }

  Future<void> _refreshCache() async {
    final bytes = await widget.tts.cacheSizeBytes();
    if (mounted) setState(() => _cacheBytes = bytes);
  }

  Future<void> _pick(TextEditingController target, List<String> extensions) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    final path = result?.files.single.path;
    if (path != null) setState(() => target.text = path);
  }

  Future<void> _applyAndRestart() async {
    final config = EngineConfig(
      pythonPath: _python.text.trim(),
      modelPath: _model.text.trim(),
      voicesPath: _voices.text.trim(),
    );
    await widget.settings.setEngineConfig(config);
    await widget.tts.start(config);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: SoftPanel(
          padding: EdgeInsets.zero,
          radius: LumenRadius.brXl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 14, 8),
                child: Row(
                  children: [
                    Expanded(child: Text('Settings', style: context.texts.headlineSmall)),
                    IconAction(
                      icon: Icons.close_rounded,
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                  children: [
                    const SectionLabel('Appearance'),
                    ListenableBuilder(
                      listenable: widget.settings,
                      builder: (context, _) => Column(
                        children: [
                          _ThemeSelector(settings: widget.settings),
                          const SizedBox(height: 4),
                          _SwitchRow(
                            title: 'Highlight the sentence being read',
                            subtitle: 'Draws a marker straight onto the page.',
                            value: widget.settings.highlightSentence,
                            onChanged: widget.settings.setHighlightSentence,
                          ),
                          _SwitchRow(
                            title: 'Follow along automatically',
                            subtitle: 'Scrolls the page to keep narration in view.',
                            value: widget.settings.autoScroll,
                            onChanged: widget.settings.setAutoScroll,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const SectionLabel('Speech engine'),
                    ListenableBuilder(
                      listenable: widget.tts,
                      builder: (context, _) => _EngineStatusCard(tts: widget.tts),
                    ),
                    const SizedBox(height: 16),
                    _PathField(
                      label: 'Python interpreter',
                      hint: 'python',
                      helper: 'Must have kokoro-onnx installed (pip install kokoro-onnx).',
                      controller: _python,
                    ),
                    _PathField(
                      label: 'Kokoro model',
                      hint: r'C:\models\kokoro-v1.0.onnx',
                      controller: _model,
                      onBrowse: () => _pick(_model, ['onnx']),
                    ),
                    _PathField(
                      label: 'Voice pack',
                      hint: r'C:\models\voices-v1.0.bin',
                      controller: _voices,
                      onBrowse: () => _pick(_voices, ['bin', 'json']),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: p.accent,
                          foregroundColor: p.accentInk,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          shape: const RoundedRectangleBorder(borderRadius: LumenRadius.brMd),
                        ),
                        onPressed: _applyAndRestart,
                        icon: const Icon(Icons.restart_alt_rounded, size: 18),
                        label: const Text('Apply and restart engine'),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const SectionLabel('Rendered speech cache'),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _cacheBytes == 0
                                ? 'Nothing cached yet.'
                                : '${(_cacheBytes / (1024 * 1024)).toStringAsFixed(1)} MB of rendered audio.',
                            style: context.texts.bodyMedium?.copyWith(color: p.inkSoft),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            await widget.tts.clearCache();
                            await _refreshCache();
                          },
                          child: Text('Clear cache', style: TextStyle(color: p.warning)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ListenableBuilder(
                      listenable: widget.tts,
                      builder: (context, _) {
                        if (widget.tts.log.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextButton.icon(
                              onPressed: () => setState(() => _showLog = !_showLog),
                              icon: Icon(
                                _showLog ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                                size: 18,
                                color: p.inkFaint,
                              ),
                              label: Text(
                                'Engine log',
                                style: TextStyle(color: p.inkFaint),
                              ),
                            ),
                            if (_showLog)
                              Container(
                                height: 160,
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: p.canvas,
                                  borderRadius: LumenRadius.brMd,
                                  border: Border.all(color: p.stroke),
                                ),
                                child: SingleChildScrollView(
                                  reverse: true,
                                  child: SelectableText(
                                    widget.tts.log.join('\n'),
                                    style: context.texts.bodySmall?.copyWith(
                                      color: p.inkFaint,
                                      fontFamily: 'monospace',
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _EngineStatusCard extends StatelessWidget {
  const _EngineStatusCard({required this.tts});

  final TtsService tts;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;

    final (color, icon, title, detail) = switch (tts.status) {
      EngineStatus.ready => (
        p.positive,
        Icons.check_circle_rounded,
        'Kokoro is running',
        '${tts.voices.length} voices at ${tts.sampleRate ~/ 1000} kHz.',
      ),
      EngineStatus.starting => (
        p.accent,
        Icons.hourglass_top_rounded,
        'Starting the engine',
        'Loading the model into memory...',
      ),
      EngineStatus.failed => (
        p.warning,
        Icons.error_rounded,
        'Engine unavailable',
        tts.error ?? 'Unknown error.',
      ),
      EngineStatus.idle => (
        p.inkFaint,
        Icons.circle_outlined,
        'Engine not started',
        'Point Lumen at your Kokoro model below.',
      ),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: LumenRadius.brMd,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.texts.titleMedium?.copyWith(color: color)),
                const SizedBox(height: 2),
                SelectableText(
                  detail,
                  style: context.texts.bodySmall?.copyWith(color: p.inkSoft, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PathField extends StatelessWidget {
  const _PathField({
    required this.label,
    required this.hint,
    required this.controller,
    this.helper,
    this.onBrowse,
  });

  final String label;
  final String hint;
  final String? helper;
  final TextEditingController controller;
  final VoidCallback? onBrowse;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.texts.titleMedium),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  style: context.texts.bodySmall?.copyWith(color: p.inkSoft),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: context.texts.bodySmall?.copyWith(color: p.inkFaint),
                    filled: true,
                    fillColor: p.surfaceHigh,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
              if (onBrowse != null) ...[
                const SizedBox(width: 8),
                IconAction(
                  icon: Icons.folder_open_rounded,
                  tooltip: 'Browse',
                  onPressed: onBrowse,
                  size: 44,
                ),
              ],
            ],
          ),
          if (helper != null) ...[
            const SizedBox(height: 6),
            Text(helper!, style: context.texts.bodySmall?.copyWith(color: p.inkFaint)),
          ],
        ],
      ),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({required this.settings});

  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text('Theme', style: context.texts.titleMedium)),
          for (final mode in ThemeMode.values)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Pill(
                accented: settings.themeMode == mode,
                onTap: () => settings.setThemeMode(mode),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text(switch (mode) {
                  ThemeMode.system => 'Auto',
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                }),
              ),
            ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.lumen;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.texts.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: context.texts.bodySmall?.copyWith(color: p.inkFaint)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: p.accentInk,
            activeTrackColor: p.accent,
          ),
        ],
      ),
    );
  }
}
