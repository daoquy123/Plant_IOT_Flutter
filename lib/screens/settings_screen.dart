import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../widgets/app_card.dart';
import '../widgets/section_label.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _esp;
  late final TextEditingController _cam;
  late final TextEditingController _ai;
  late final SettingsProvider _settings;
  late final VoidCallback _hydrateListener;
  bool _hydrated = false;

  @override
  void initState() {
    super.initState();
    _esp = TextEditingController();
    _cam = TextEditingController();
    _ai = TextEditingController();
    _settings = context.read<SettingsProvider>();
    void hydrate() {
      if (_hydrated || !_settings.isLoaded) return;
      _hydrated = true;
      _esp.text = _settings.esp32Ip;
      _cam.text = _settings.cameraUrl;
      _ai.text = _settings.aiServerUrl;
      if (mounted) setState(() {});
    }

    _hydrateListener = hydrate;
    hydrate();
    _settings.addListener(_hydrateListener);
  }

  @override
  void dispose() {
    _settings.removeListener(_hydrateListener);
    _esp.dispose();
    _cam.dispose();
    _ai.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cấu hình'),
        actions: [
          TextButton(
            onPressed: () async {
              settings
                ..setEsp32Ip(_esp.text)
                ..setCameraUrl(_cam.text)
                ..setAiServerUrl(_ai.text);
              await settings.saveAll();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã lưu')),
                );
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        children: [
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scheme.primary.withValues(alpha: 0.18),
                        scheme.primary.withValues(alpha: 0.06),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: scheme.outline.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    'QĐ',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: scheme.primary,
                        ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quý Đào',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tài khoản cục bộ',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.52),
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionLabel('Tự động hóa'),
          AppCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              title: Text(
                'Tưới tự động',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              subtitle: Text(
                'Bật khi backend / ESP hỗ trợ lệnh tương ứng',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.52),
                      height: 1.4,
                    ),
              ),
              value: settings.autoWater,
              onChanged: settings.setAutoWater,
            ),
          ),
          const SizedBox(height: 22),
          const SectionLabel('Kết nối'),
          const SizedBox(height: 4),
          _LabeledField(label: 'URL Server Node.js', controller: _esp),
          const SizedBox(height: 14),
          _LabeledField(label: 'URL Camera', controller: _cam),
          const SizedBox(height: 14),
          _LabeledField(label: 'URL AI Server', controller: _ai),
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.52),
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: const InputDecoration(),
        ),
      ],
    );
  }
}
