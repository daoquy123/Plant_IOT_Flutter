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
  late final TextEditingController _serverUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _cam;
  late final TextEditingController _ai;
  late final SettingsProvider _settings;
  late final VoidCallback _hydrateListener;
  bool _hydrated = false;
  @override
  void initState() {
    super.initState();
    _serverUrl = TextEditingController();
    _apiKey = TextEditingController();
    _cam = TextEditingController();
    _ai = TextEditingController();
    _settings = context.read<SettingsProvider>();
    void hydrate() {
      if (_hydrated || !_settings.isLoaded) return;
      _hydrated = true;
      _serverUrl.text = _settings.serverUrl;
      _apiKey.text = _settings.apiKey;
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
    _serverUrl.dispose();
    _apiKey.dispose();
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
                ..setServerUrl(_serverUrl.text)
                ..setApiKey(_apiKey.text)
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
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(
                    'Tưới tự động',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  subtitle: Text(
                    'Server tưới lúc 6:00 sáng và 17:00 chiều (giờ VN) khi bật',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.52),
                          height: 1.4,
                        ),
                  ),
                  value: settings.autoWater,
                  onChanged: (value) async {
                    await settings.setAutoWater(value);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          value
                              ? 'Đã bật tưới tự động trên server'
                              : 'Đã tắt tưới tự động',
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(
                    'Cảnh báo thông số',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  subtitle: Text(
                    'Email khi thông số vượt hoặc dưới ngưỡng (tối đa 1 lần/giờ)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.52),
                          height: 1.4,
                        ),
                  ),
                  value: settings.sensorAlert,
                  onChanged: (value) async {
                    await settings.setSensorAlert(value);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          value
                              ? 'Đã bật cảnh báo thông số qua email'
                              : 'Đã tắt cảnh báo thông số',
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(
                    'Thông báo khi có sâu',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  subtitle: Text(
                    'ResNet kiểm tra ảnh camera mỗi giờ — email nếu phát hiện sâu (không có ảnh thì bỏ qua)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.52),
                          height: 1.4,
                        ),
                  ),
                  value: settings.pestAlert,
                  onChanged: (value) async {
                    await settings.setPestAlert(value);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          value
                              ? 'Đã bật thông báo sâu bệnh'
                              : 'Đã tắt thông báo sâu bệnh',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionLabel('Kết nối'),
          const SizedBox(height: 4),
          _LabeledField(
            label: 'Server URL',
            controller: _serverUrl,
            onChanged: settings.setServerUrl,
          ),
          const SizedBox(height: 14),
          _LabeledField(
            label: 'API Key',
            controller: _apiKey,
            onChanged: settings.setApiKey,
          ),
          const SizedBox(height: 14),
          _LabeledField(
            label: 'URL Camera',
            controller: _cam,
            onChanged: settings.setCameraUrl,
          ),
          const SizedBox(height: 14),
          _LabeledField(
            label: 'URL AI Server',
            controller: _ai,
            onChanged: settings.setAiServerUrl,
          ),
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    this.onChanged,
    this.hintText,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String? hintText;

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
          onChanged: onChanged,
          decoration: InputDecoration(hintText: hintText),
        ),
      ],
    );
  }
}
