import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/garden_provider.dart';
import '../widgets/app_card.dart';
import '../widgets/section_label.dart';

class ControlScreen extends StatelessWidget {
  const ControlScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final garden = context.watch<GardenProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Điều khiển')),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('Cảm biến'),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.32,
                  ),
                  itemCount: garden.sensorTiles.length,
                  itemBuilder: (context, i) {
                    final s = garden.sensorTiles[i];
                    return AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            s.name,
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: scheme.onSurface.withValues(alpha: 0.5),
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                s.valueLabel,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.5,
                                    ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                s.unit,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: scheme.onSurface
                                          .withValues(alpha: 0.45),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 26),
                const SectionLabel('Thiết bị'),
                const SizedBox(height: 4),
                _ControlRow(
                  label: 'Màn che',
                  on: garden.shadeOn,
                  busy: garden.iotBusy,
                  subtitle: null,
                  onPressed: () => context.read<GardenProvider>().toggleShade(),
                ),
                const SizedBox(height: 12),
                _ControlRow(
                  label: 'Máy bơm',
                  on: garden.pumpOn,
                  busy: garden.iotBusy,
                  subtitle: 'Hôm nay tưới: ${garden.waterTodayCount} lần',
                  onPressed: () => context.read<GardenProvider>().togglePump(),
                ),
              ],
            ),
          ),
          if (garden.iotBusy)
            Positioned.fill(
              child: ColoredBox(
                color: scheme.surface.withValues(alpha: 0.82),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

class _ControlRow extends StatelessWidget {
  const _ControlRow({
    required this.label,
    required this.on,
    required this.busy,
    required this.subtitle,
    required this.onPressed,
  });

  final String label;
  final bool on;
  final bool busy;
  final String? subtitle;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.52),
                          height: 1.35,
                        ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 104,
            child: on
                ? FilledButton(
                    onPressed: busy ? null : onPressed,
                    child: const Text('Tắt'),
                  )
                : OutlinedButton(
                    onPressed: busy ? null : onPressed,
                    child: const Text('Bật'),
                  ),
          ),
        ],
      ),
    );
  }
}
