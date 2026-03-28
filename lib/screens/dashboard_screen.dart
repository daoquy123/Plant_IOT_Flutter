import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/garden_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/app_card.dart';
import '../widgets/notification_history_sheet.dart';
import '../widgets/section_label.dart';

/// Khu vực camera — sau này gắn luồng thật; lật ngang / lật dọc xem thử.
Widget buildCameraStream(
  BuildContext context,
  String url, {
  bool flipHorizontal = false,
  bool flipVertical = false,
}) {
  final hasUrl = url.trim().isNotEmpty;
  final cameraHint = hasUrl ? 'Luồng camera đã sẵn sàng' : 'Đang chờ luồng Camera…';
  Widget core = Stack(
    fit: StackFit.expand,
    children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF080D0C),
              Color(0xFF12221A),
              Color(0xFF1A3328),
            ],
          ),
        ),
      ),
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.03),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.45),
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
        ),
      ),
      Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            cameraHint,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 15,
              height: 1.55,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    ],
  );

  final sx = flipHorizontal ? -1.0 : 1.0;
  final sy = flipVertical ? -1.0 : 1.0;
  if (sx != 1.0 || sy != 1.0) {
    core = Transform(
      alignment: Alignment.center,
      transform: Matrix4.diagonal3Values(sx, sy, 1.0),
      child: core,
    );
  }
  return core;
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _cameraFlipHorizontal = false;
  bool _cameraFlipVertical = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshEsp());
  }

  /// Trả về `true` nếu không có lỗi sau khi làm mới.
  Future<bool> _refreshEsp() async {
    final garden = context.read<GardenProvider>();
    final notifications = context.read<NotificationsProvider>();
    await garden.refreshFromEsp32();
    if (!mounted) return false;
    final err = garden.lastError;
    if (err != null && err.isNotEmpty) {
      await notifications.add(
        title: 'Giám sát',
        body: err,
      );
      return false;
    }
    return true;
  }

  void _openCameraFullscreen(String url) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, anim, secAnim) {
        return SafeArea(
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                buildCameraStream(
                  ctx,
                  url,
                  flipHorizontal: _cameraFlipHorizontal,
                  flipVertical: _cameraFlipVertical,
                ),
                Positioned(
                  top: 8,
                  right: 4,
                  child: IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    tooltip: 'Đóng',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final garden = context.watch<GardenProvider>();
    final notifications = context.watch<NotificationsProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Giám sát'),
        actions: [
          IconButton(
            tooltip: 'Thông báo',
            onPressed: () => showNotificationHistorySheet(context),
            icon: Badge(
              isLabelVisible: notifications.unreadCount > 0,
              label: Text(
                notifications.unreadCount > 9
                    ? '9+'
                    : '${notifications.unreadCount}',
                style: const TextStyle(fontSize: 10),
              ),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                buildCameraStream(
                  context,
                  settings.cameraUrl,
                  flipHorizontal: _cameraFlipHorizontal,
                  flipVertical: _cameraFlipVertical,
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 20, 8, 12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _CameraActionChip(
                              icon: Icons.refresh_rounded,
                              label: 'Làm mới',
                              onTap: () async {
                                final notifications =
                                    context.read<NotificationsProvider>();
                                final ok = await _refreshEsp();
                                if (!mounted) return;
                                if (ok) {
                                  await notifications.add(
                                    title: 'Giám sát',
                                    body: 'Đã làm mới dữ liệu cảm biến.',
                                  );
                                }
                              },
                            ),
                            const SizedBox(width: 8),
                            _CameraActionChip(
                              icon: Icons.fullscreen_rounded,
                              label: 'Phóng to',
                              onTap: () =>
                                  _openCameraFullscreen(settings.cameraUrl),
                            ),
                            const SizedBox(width: 8),
                            _CameraActionChip(
                              icon: Icons.flip_rounded,
                              label: 'Lật ngang',
                              onTap: () => setState(
                                () => _cameraFlipHorizontal =
                                    !_cameraFlipHorizontal,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _CameraActionChip(
                              icon: Icons.swap_vert_rounded,
                              label: 'Lật dọc',
                              onTap: () => setState(
                                () => _cameraFlipVertical =
                                    !_cameraFlipVertical,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(26)),
              child: ColoredBox(
                color: scheme.surface,
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SectionLabel('Trạng thái'),
                          AppCard(
                            child: Text(
                              garden.gardenStatus,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                          const SizedBox(height: 18),
                          const SectionLabel('Tình trạng cây'),
                          if (garden.aiAnalysis.trim().isNotEmpty)
                            AppCard(
                              child: Text(
                                garden.aiAnalysis,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (garden.iotBusy)
                      Positioned.fill(
                        child: ColoredBox(
                          color: scheme.surface.withValues(alpha: 0.82),
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraActionChip extends StatelessWidget {
  const _CameraActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.95), size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.85),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
