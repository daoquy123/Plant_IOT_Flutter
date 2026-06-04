import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/growing_cycle.dart';
import '../providers/garden_provider.dart';
import '../widgets/app_card.dart';
import '../widgets/section_label.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  int shadeCooldown = 0;
  Timer? _timer;
  DateTime _plantStartDate = DateTime.now();

  String _formatDate(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '$day/$month/${d.year}';
  }

  Future<void> _pickPlantStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _plantStartDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Ngày bắt đầu trồng',
    );
    if (picked != null) {
      setState(() => _plantStartDate = picked);
    }
  }

  void startCooldown() {
    setState(() {
      shadeCooldown = 60;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (shadeCooldown == 0) {
        timer.cancel();
      } else {
        setState(() {
          shadeCooldown--;
        });
      }
    });
  }

  Future<bool> showConfirm(BuildContext context, String message) async {
    return await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Xác nhận"),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Hủy"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Đồng ý"),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GardenProvider>().refreshActiveGrowingCycle();
    });
  }

  @override
  Widget build(BuildContext context) {
    final garden = context.watch<GardenProvider>();
    final scheme = Theme.of(context).colorScheme;
    final cycle = garden.activeGrowingCycle;
    final cycleBusy = garden.cycleBusy;

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
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
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
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            s.name,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: scheme.onSurface
                                      .withValues(alpha: 0.5),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.baseline,
                            textBaseline:
                                TextBaseline.alphabetic,
                            children: [
                              Text(
                                s.valueLabel,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
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

                /// 🌿 MÀN CHE
                _ControlRow(
                  label: 'Màn che',
                  on: garden.shadeOn,
                  busy: garden.iotBusy || shadeCooldown > 0,
                  subtitle:
                      'Trạng thái hiện tại: ${garden.shadeOn ? 'Đang mở' : 'Đang đóng'}',
                  onLabel: shadeCooldown > 0
                      ? '${shadeCooldown}s'
                      : 'Đóng',
                  offLabel: shadeCooldown > 0
                      ? '${shadeCooldown}s'
                      : 'Mở',
                  onPressed: () async {
                    final gardenProvider = context.read<GardenProvider>();
                    final confirm = await showConfirm(
                      context,
                      garden.shadeOn
                          ? "Bạn có muốn ĐÓNG màn che?"
                          : "Bạn có muốn MỞ màn che?",
                    );

                    if (!confirm) return;

                    if (garden.shadeOn) {
                      await gardenProvider.closeShade();
                    } else {
                      await gardenProvider.openShade();
                    }

                    startCooldown(); // 🔥 khóa 60s
                  },
                ),

                const SizedBox(height: 12),

                /// 💧 MÁY BƠM
                _ControlRow(
                  label: 'Máy bơm',
                  on: garden.pumpDisplayOn,
                  busy: garden.iotBusy,
                  subtitle:
                      'Trạng thái: ${garden.pumpDisplayOn ? 'Đang bật' : 'Đang tắt'}',
                  onLabel: 'Tắt',
                  offLabel: 'Bật',
                  onPressed: () async {
                    final gardenProvider = context.read<GardenProvider>();
                    final confirm = await showConfirm(
                      context,
                      garden.pumpDisplayOn
                          ? "Bạn có muốn Bật máy bơm?"
                          : "Bạn có muốn Tắt máy bơm?",
                    );

                    if (!confirm) return;
                    gardenProvider.togglePump();
                  },
                ),

                const SizedBox(height: 26),
                const SectionLabel('Chu kỳ trồng'),
                const SizedBox(height: 4),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  child: cycle != null && cycle.isActive
                      ? _ActiveCyclePanel(
                          cycle: cycle,
                          busy: cycleBusy,
                          onEnd: () async {
                            final ok = await showConfirm(
                              context,
                              'Kết thúc chu kỳ bắt đầu từ ${cycle.startedLabel}?',
                            );
                            if (!ok || !context.mounted) return;
                            final success = await context
                                .read<GardenProvider>()
                                .endActiveGrowingCycle();
                            if (!context.mounted) return;
                            if (success) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Đã kết thúc chu kỳ trồng'),
                                ),
                              );
                            } else if (garden.lastError != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(garden.lastError!)),
                              );
                            }
                          },
                        )
                      : _StartCyclePanel(
                          startDateLabel: _formatDate(_plantStartDate),
                          busy: cycleBusy,
                          onPickDate: cycleBusy ? null : _pickPlantStartDate,
                          onStart: () async {
                            final ok = await showConfirm(
                              context,
                              'Bắt đầu theo dõi chu kỳ từ ngày ${_formatDate(_plantStartDate)}?',
                            );
                            if (!ok || !context.mounted) return;
                            final success = await context
                                .read<GardenProvider>()
                                .startGrowingCycle(_plantStartDate);
                            if (!context.mounted) return;
                            if (success) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Đã lưu ngày bắt đầu trồng'),
                                ),
                              );
                            } else if (garden.lastError != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(garden.lastError!)),
                              );
                            }
                          },
                        ),
                ),
              ],
            ),
          ),

          /// ⏳ LOADING OVERLAY
          if (garden.iotBusy || cycleBusy)
            Positioned.fill(
              child: ColoredBox(
                color: scheme.surface
                    .withValues(alpha: 0.82),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StartCyclePanel extends StatelessWidget {
  const _StartCyclePanel({
    required this.startDateLabel,
    required this.busy,
    required this.onPickDate,
    required this.onStart,
  });

  final String startDateLabel;
  final bool busy;
  final VoidCallback? onPickDate;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Theo dõi số ngày từ khi trồng (lưu trên server).',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.55),
                height: 1.4,
              ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: onPickDate,
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text('Ngày bắt đầu: $startDateLabel'),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: busy ? null : onStart,
          icon: const Icon(Icons.eco_outlined, size: 20),
          label: const Text('Bắt đầu chu kỳ'),
        ),
      ],
    );
  }
}

class _ActiveCyclePanel extends StatelessWidget {
  const _ActiveCyclePanel({
    required this.cycle,
    required this.busy,
    required this.onEnd,
  });

  final GrowingCycle cycle;
  final bool busy;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = cycle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.spa_outlined, color: scheme.primary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Đang theo dõi — ngày thứ ${c.daysElapsed}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Bắt đầu trồng: ${c.startedLabel}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.72),
              ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: busy ? null : onEnd,
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.error,
            side: BorderSide(color: scheme.error.withValues(alpha: 0.55)),
          ),
          icon: const Icon(Icons.flag_outlined, size: 18),
          label: const Text('Kết thúc chu kỳ'),
        ),
      ],
    );
  }
}

class _ControlRow extends StatelessWidget {
  const _ControlRow({
    required this.label,
    required this.on,
    required this.busy,
    required this.subtitle,
    required this.onLabel,
    required this.offLabel,
    required this.onPressed,
  });

  final String label;
  final bool on;
  final bool busy;
  final String? subtitle;
  final String onLabel;
  final String offLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      padding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color: scheme.onSurface
                              .withValues(alpha: 0.52),
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
                    child: Text(onLabel),
                  )
                : OutlinedButton(
                    onPressed: busy ? null : onPressed,
                    child: Text(offLabel),
                  ),
          ),
        ],
      ),
    );
  }
}