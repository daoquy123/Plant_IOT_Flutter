import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
                    final confirm = await showConfirm(
                      context,
                      garden.shadeOn
                          ? "Bạn có muốn ĐÓNG màn che?"
                          : "Bạn có muốn MỞ màn che?",
                    );

                    if (!confirm) return;

                    if (garden.shadeOn) {
                      await context
                          .read<GardenProvider>()
                          .closeShade();
                    } else {
                      await context
                          .read<GardenProvider>()
                          .openShade();
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
                      'Trạng thái: ${garden.pumpDisplayOn ? 'Đang tắt' : 'Đang bật'}',
                  onLabel: 'Bật',
                  offLabel: 'Tắt',
                  onPressed: () async {
                    final confirm = await showConfirm(
                      context,
                      garden.pumpDisplayOn
                          ? "Bạn có muốn Bật máy bơm?"
                          : "Bạn có muốn Tắt máy bơm?",
                    );

                    if (!confirm) return;

                    context
                        .read<GardenProvider>()
                        .togglePump();
                  },
                ),
              ],
            ),
          ),

          /// ⏳ LOADING OVERLAY
          if (garden.iotBusy)
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