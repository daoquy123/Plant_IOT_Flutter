import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_conversation.dart';
import '../providers/chat_provider.dart';
import '../utils/conversation_time.dart';

Future<void> showRenameConversationDialog(
  BuildContext context,
  ChatConversation conversation,
) async {
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => _RenameConversationDialog(
      initialTitle: conversation.title,
    ),
  );
  if (result == null || !context.mounted) return;
  await context.read<ChatProvider>().renameConversation(
        conversation.id,
        result,
      );
}

class _RenameConversationDialog extends StatefulWidget {
  const _RenameConversationDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_RenameConversationDialog> createState() =>
      _RenameConversationDialogState();
}

class _RenameConversationDialogState extends State<_RenameConversationDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Đặt tên cuộc trò chuyện'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        decoration: const InputDecoration(
          hintText: 'Nhập tên...',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}

class ChatSidebar extends StatelessWidget {
  const ChatSidebar({
    super.key,
    this.compact = false,
    this.onConversationSelected,
  });

  final bool compact;
  final VoidCallback? onConversationSelected;

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final scheme = Theme.of(context).colorScheme;
    final width = compact ? 280.0 : 300.0;

    return Material(
      color: scheme.surfaceContainerLow,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 16, compact ? 12 : 16, 10),
              child: FilledButton.icon(
                onPressed: chat.sending
                    ? null
                    : () async {
                        await context.read<ChatProvider>().createNewConversation();
                        onConversationSelected?.call();
                      },
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Cuộc trò chuyện mới'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  alignment: Alignment.centerLeft,
                  shape: const RoundedRectangleBorder(),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 20),
              child: Text(
                'Lịch sử',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface.withValues(alpha: 0.45),
                    ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: chat.conversations.isEmpty
                  ? Center(
                      child: Text(
                        'Chưa có cuộc trò chuyện',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.5),
                            ),
                      ),
                    )
                  : Builder(
                      builder: (context) {
                        final sections =
                            groupConversationsByTime(chat.conversations);
                        return ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            compact ? 10 : 12,
                            0,
                            compact ? 10 : 12,
                            16,
                          ),
                          itemCount: sections.fold<int>(
                            0,
                            (sum, s) => sum + 1 + s.items.length,
                          ),
                          itemBuilder: (context, index) {
                            var cursor = 0;
                            for (final section in sections) {
                              if (index == cursor) {
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    10,
                                    8,
                                    6,
                                  ),
                                  child: Text(
                                    section.group.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          letterSpacing: 1.1,
                                          fontWeight: FontWeight.w700,
                                          color: scheme.onSurface
                                              .withValues(alpha: 0.42),
                                        ),
                                  ),
                                );
                              }
                              cursor += 1;
                              for (final conv in section.items) {
                                if (index == cursor) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: _ConversationTile(
                                      conversation: conv,
                                      selected:
                                          conv.id == chat.activeConversationId,
                                      onTap: chat.sending
                                          ? null
                                          : () async {
                                              await context
                                                  .read<ChatProvider>()
                                                  .selectConversation(conv.id);
                                              onConversationSelected?.call();
                                            },
                                      onRename: () =>
                                          showRenameConversationDialog(
                                        context,
                                        conv,
                                      ),
                                      onDelete: () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text(
                                              'Xóa cuộc trò chuyện?',
                                            ),
                                            content: Text(
                                              'Xóa "${conv.title}" và toàn bộ tin nhắn bên trong?',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text('Hủy'),
                                              ),
                                              FilledButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                child: const Text('Xóa'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (ok == true && context.mounted) {
                                          await context
                                              .read<ChatProvider>()
                                              .deleteConversation(conv.id);
                                        }
                                      },
                                    ),
                                  );
                                }
                                cursor += 1;
                              }
                            }
                            return const SizedBox.shrink();
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final ChatConversation conversation;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final modelLabel =
        ChatProvider.modelOptions[conversation.model] ?? conversation.model;
    final timeLabel = formatConversationTime(conversation.updatedAt);

    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 18,
                color: selected
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$timeLabel · $modelLabel',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.45),
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                tooltip: 'Đổi tên',
                onPressed: onRename,
                icon: Icon(
                  Icons.edit_outlined,
                  color: scheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                tooltip: 'Xóa',
                onPressed: onDelete,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: scheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
