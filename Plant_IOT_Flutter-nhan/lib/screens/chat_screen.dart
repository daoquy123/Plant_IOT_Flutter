import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../providers/chat_provider.dart';
import '../providers/garden_provider.dart';
import '../providers/notifications_provider.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scroll = ScrollController();
  int _lastMessageCount = 0;
  String _selectedModel = 'vgg16';
  bool _healthCheckBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadHistory();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _startHealthCheckCapture() async {
    if (_healthCheckBusy) return;
    final garden = context.read<GardenProvider>();
    final chat = context.read<ChatProvider>();
    final notifications = context.read<NotificationsProvider>();

    setState(() => _healthCheckBusy = true);
    try {
      final imageUrl = await garden.waitForNewCameraImageAfterRequest();
      if (!mounted) return;
      if (imageUrl == null || imageUrl.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Không nhận được ảnh mới từ camera. Kiểm tra ESP32-CAM, Nginx/socket.io và thử lại.',
            ),
          ),
        );
        return;
      }

      final reply = await chat.analyzeCurrentCameraImage(
        model: _selectedModel,
        preferredImageUrl: imageUrl.trim(),
      );
      if (!mounted) return;
      if (reply != null && reply.trim().isNotEmpty) {
        garden.setAiAnalysisFromServer(reply.trim());
        await notifications.add(
          title: 'Phân tích AI',
          body: reply.trim(),
        );
      }
    } finally {
      if (mounted) setState(() => _healthCheckBusy = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final scheme = Theme.of(context).colorScheme;

    if (chat.messages.length != _lastMessageCount) {
      _lastMessageCount = chat.messages.length;
      _scrollToEnd();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('AI')),
      body: Column(
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
                  : ListView.builder(
                      controller: _scroll,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                    value: 'vgg16',
                    label: Text('VGG16'),
                  ),
                  ButtonSegment<String>(
                    value: 'resnet',
                    label: Text('ResNet'),
                  ),
                ],
                selected: <String>{_selectedModel},
                onSelectionChanged: chat.sending
                    ? null
                    : (set) {
                        setState(() => _selectedModel = set.first);
                      },
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: ChatProvider.suggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final s = ChatProvider.suggestions[i];
                return OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  onPressed: (chat.sending || _healthCheckBusy)
                      ? null
                      : () async {
                          if (s == 'Kiểm tra sức khỏe cây') {
                            await _startHealthCheckCapture();
                            return;
                          }
                          final garden = context.read<GardenProvider>();
                          final reply = await context.read<ChatProvider>().runSmartSuggestion(
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
                  child: Text(
                    s,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: scheme.outline.withValues(alpha: 0.38),
                ),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.image_outlined),
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
                  onPressed: chat.sending
                      ? null
                      : () async {
                          final reply = await context
                              .read<ChatProvider>()
                              .pickImageAndPredict();
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
            ),
          ),
        ],
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
                ? scheme.primary.withValues(alpha: 0.14)
                : scheme.surfaceContainerHighest,
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
              const SizedBox(height: 8),
              Text(
                message.text,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
              ),
              const SizedBox(height: 8),
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
