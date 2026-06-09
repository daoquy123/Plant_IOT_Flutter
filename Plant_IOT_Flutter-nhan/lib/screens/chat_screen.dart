import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../providers/chat_provider.dart';
import '../providers/garden_provider.dart';
import '../providers/notifications_provider.dart';
import '../widgets/chat_sidebar.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scroll = ScrollController();
  final _drawerKey = GlobalKey<ScaffoldState>();
  int _lastMessageCount = 0;
  bool _healthCheckBusy = false;
  ChatProvider? _chat;

  static const _sidebarBreakpoint = 720.0;

  @override
  void initState() {
    super.initState();
    _chat = context.read<ChatProvider>();
    _lastMessageCount = _chat!.messages.length;
    _chat!.addListener(_onChatUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadHistory();
    });
  }

  @override
  void dispose() {
    _chat?.removeListener(_onChatUpdate);
    _scroll.dispose();
    super.dispose();
  }

  void _onChatUpdate() {
    if (!mounted) return;
    final count = _chat?.messages.length ?? 0;
    if (count == _lastMessageCount) return;
    _lastMessageCount = count;
    _scrollToEnd();
  }

  Future<void> _startHealthCheckCapture() async {
    if (_healthCheckBusy) return;
    final garden = context.read<GardenProvider>();
    final chat = context.read<ChatProvider>();
    final notifications = context.read<NotificationsProvider>();

    setState(() => _healthCheckBusy = true);
    try {
      final reply = await chat.runServerHealthCheck(garden: garden);
      if (!mounted) return;
      if (reply == null || reply.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              chat.lastError ??
                  'Không phân tích được ảnh. Kiểm tra ESP32-CAM, AI server và pm2.',
            ),
          ),
        );
        return;
      }

      garden.setAiAnalysisFromServer(reply.trim());
      await notifications.add(
        title: 'Phân tích AI',
        body: reply.trim(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _healthCheckBusy = false);
    }
  }

  void _scrollToEnd() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _closeDrawerIfNeeded() {
    if (_drawerKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final scheme = Theme.of(context).colorScheme;
    final isBusy = chat.sending || _healthCheckBusy;
    final wide = MediaQuery.sizeOf(context).width >= _sidebarBreakpoint;

    final chatBody = _ChatMainPanel(
      scrollController: _scroll,
      isBusy: isBusy,
      healthCheckBusy: _healthCheckBusy,
      onHealthCheck: _startHealthCheckCapture,
    );

    return Scaffold(
      key: _drawerKey,
      drawer: wide
          ? null
          : Drawer(
              width: 300,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
              child: ChatSidebar(
                compact: true,
                onConversationSelected: _closeDrawerIfNeeded,
              ),
            ),
      appBar: AppBar(
        leading: wide
            ? null
            : IconButton(
                icon: const Icon(Icons.menu_rounded),
                tooltip: 'Cuộc trò chuyện',
                onPressed: () => _drawerKey.currentState?.openDrawer(),
              ),
        automaticallyImplyLeading: !wide,
        titleSpacing: wide ? 20 : 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('AI'),
            const SizedBox(width: 8),
            _ModelDropdown(
              value: chat.selectedModel,
              enabled: !isBusy,
              onChanged: (model) {
                context.read<ChatProvider>().setSelectedModel(model);
              },
            ),
          ],
        ),
      ),
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ChatSidebar(),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: scheme.outline.withValues(alpha: 0.35),
                ),
                Expanded(child: chatBody),
              ],
            )
          : chatBody,
    );
  }
}

class _ModelDropdown extends StatelessWidget {
  const _ModelDropdown({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = ChatProvider.modelOptions[value] ?? value;

    return PopupMenuButton<String>(
      enabled: enabled,
      tooltip: 'Chọn model AI',
      offset: const Offset(0, 8),
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (context) {
        return ChatProvider.modelOptions.entries.map((entry) {
          final selected = entry.key == value;
          return PopupMenuItem<String>(
            value: entry.key,
            height: 40,
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: selected
                      ? Icon(Icons.check_rounded, size: 16, color: scheme.primary)
                      : null,
                ),
                const SizedBox(width: 6),
                Text(
                  entry.value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                ),
              ],
            ),
          );
        }).toList();
      },
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.55),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(10),
          ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: scheme.onSurface.withValues(alpha: 0.65),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMainPanel extends StatelessWidget {
  const _ChatMainPanel({
    required this.scrollController,
    required this.isBusy,
    required this.healthCheckBusy,
    required this.onHealthCheck,
  });

  final ScrollController scrollController;
  final bool isBusy;
  final bool healthCheckBusy;
  final Future<void> Function() onHealthCheck;

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.surface,
                  scheme.surfaceContainerLow,
                ],
              ),
            ),
            child: chat.loadingHistory
                ? const Center(child: CircularProgressIndicator())
                : chat.messages.isEmpty
                    ? const _ChatEmptyState()
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                        itemCount: chat.messages.length,
                        itemBuilder: (context, i) {
                          return _Bubble(message: chat.messages[i]);
                        },
                      ),
          ),
        ),
        if (chat.lastError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                chat.lastError!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
        if (healthCheckBusy)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Đang lấy ảnh mới từ camera để phân tích sức khỏe cây...',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.62),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: ChatProvider.suggestions.map((s) {
              return _SuggestionChip(
                label: s,
                enabled: !isBusy,
                onTap: () async {
                  if (s == 'Kiểm tra sức khỏe cây') {
                    await onHealthCheck();
                    return;
                  }
                  final garden = context.read<GardenProvider>();
                  final reply =
                      await context.read<ChatProvider>().runSmartSuggestion(
                            intent: s,
                            garden: garden,
                          );
                  if (!context.mounted) return;
                  if (reply != null && reply.trim().isNotEmpty) {
                    await context.read<NotificationsProvider>().add(
                          title: 'Phân tích AI',
                          body: reply.trim(),
                        );
                  }
                },
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.image_outlined, size: 22),
            label: chat.sending
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Đang gửi ảnh'),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ],
                  )
                : const Text('Gửi ảnh'),
            onPressed: isBusy
                ? null
                : () async {
                    final reply =
                        await context.read<ChatProvider>().pickImageAndPredict();
                    if (!context.mounted) return;
                    if (reply != null && reply.trim().isNotEmpty) {
                      context
                          .read<GardenProvider>()
                          .setAiAnalysisFromServer(reply.trim());
                      await context.read<NotificationsProvider>().add(
                            title: 'Phân tích AI',
                            body: reply.trim(),
                          );
                    }
                  },
          ),
        ),
      ],
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          decoration: BoxDecoration(
            color: enabled
                ? scheme.primaryContainer.withValues(alpha: 0.5)
                : scheme.surfaceContainerLow.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: enabled
                  ? scheme.primary.withValues(alpha: 0.38)
                  : scheme.outline.withValues(alpha: 0.35),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: enabled
                      ? scheme.onPrimaryContainer
                      : scheme.onSurface.withValues(alpha: 0.4),
                ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _ChatEmptyState extends StatelessWidget {
  const _ChatEmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          'Chọn gợi ý nhanh hoặc gửi ảnh lá để phân tích.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.72),
                height: 1.45,
              ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.senderType == SenderType.user;
    final time =
        '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}';

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(isUser ? 20 : 5),
      bottomRight: Radius.circular(isUser ? 5 : 20),
    );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.84,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isUser
                ? scheme.primaryContainer.withValues(alpha: 0.65)
                : scheme.surfaceContainerLow,
            borderRadius: radius,
            border: Border.all(
              color: scheme.outline.withValues(alpha: isUser ? 0.22 : 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isUser ? 'Bạn' : 'Hệ thống',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface.withValues(alpha: 0.42),
                    ),
              ),
              if (isUser && _hasLocalImage(message.localImagePath)) ...[
                const SizedBox(height: 8),
                _UserMessageImage(path: message.localImagePath!),
                const SizedBox(height: 8),
              ],
              if (message.text.isNotEmpty &&
                  !(isUser &&
                      _hasLocalImage(message.localImagePath) &&
                      _isAttachmentCaption(message.text))) ...[
                Text(
                  message.text,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                time,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.38),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _hasLocalImage(String? path) {
  if (path == null || path.trim().isEmpty) return false;
  return File(path).existsSync();
}

bool _isAttachmentCaption(String text) {
  final t = text.trim();
  return t.startsWith('[Ảnh') || t.startsWith('[Kiểm tra sức khỏe cây');
}

class _UserMessageImage extends StatelessWidget {
  const _UserMessageImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Image.file(
        File(path),
        width: double.infinity,
        height: 200,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
}
