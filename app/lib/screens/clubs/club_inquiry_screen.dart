import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/club_inquiry.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_card.dart';
import '../../widgets/moderation/ugc_moderation_widgets.dart';

class ClubInquiryConversationScreen extends ConsumerStatefulWidget {
  const ClubInquiryConversationScreen({
    super.key,
    required this.clubId,
    this.threadId,
    this.clubName,
  });

  final String clubId;
  final String? threadId;
  final String? clubName;

  @override
  ConsumerState<ClubInquiryConversationScreen> createState() =>
      _ClubInquiryConversationScreenState();
}

class _ClubInquiryConversationScreenState
    extends ConsumerState<ClubInquiryConversationScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  String? _threadId;
  String? _clubName;
  List<ClubInquiryMessage> _messages = const [];
  ClubInquiryThread? _requesterThread;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _threadId = widget.threadId;
    _clubName = widget.clubName;
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final api = ref.read(apiProvider);
      final club = await api.getClub(widget.clubId);
      _clubName ??= club.name;
      _threadId ??= (await api.myClubInquiry(widget.clubId))?.id;
      ClubInquiryThread? requesterThread;
      if (_threadId != null && club.isManager) {
        final threads = await api.managedClubInquiries(widget.clubId);
        for (final thread in threads) {
          if (thread.id == _threadId) {
            requesterThread = thread;
            break;
          }
        }
      }
      final messages = _threadId == null
          ? const <ClubInquiryMessage>[]
          : await api.clubInquiryMessages(_threadId!);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _requesterThread = requesterThread;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (_) {
      if (mounted) setState(() => _error = '문의 내용을 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty || body.length > 1000 || _sending) return;
    setState(() => _sending = true);
    try {
      final threadId = await ref.read(apiProvider).sendClubInquiry(
            clubId: _threadId == null ? widget.clubId : null,
            threadId: _threadId,
            body: body,
          );
      _threadId = threadId;
      _controller.clear();
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ugcActionErrorMessage(error, fallback: '문의를 보내지 못했습니다.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentUserId = ref.watch(currentUserProvider)?.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(_clubName == null ? '1:1 문의' : '${_clubName!} 문의'),
        actions: [
          if (_requesterThread != null)
            IconButton(
              tooltip: '문의자 프로필 보기',
              onPressed: () =>
                  _showRequesterProfile(context, _requesterThread!),
              icon: const Icon(Icons.account_circle_outlined),
            ),
          IconButton(
            tooltip: '새로고침',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _messages.isEmpty
                    ? _InquiryEmpty(
                        icon: Icons.error_outline_rounded,
                        title: _error!,
                        actionLabel: '다시 시도',
                        onAction: _load,
                      )
                    : _messages.isEmpty
                        ? const _InquiryEmpty(
                            icon: Icons.forum_outlined,
                            title: '가입 전에 궁금한 점을 물어보세요',
                            message: '클럽장·매니저가 함께 확인하고 답변합니다.',
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final message = _messages[index];
                              return _MessageBubble(
                                message: message,
                                mine: message.senderId == currentUserId,
                              );
                            },
                          ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(top: BorderSide(color: cs.outlineVariant)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_sending,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      decoration: const InputDecoration(
                        hintText: '문의 내용을 입력하세요',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton.filled(
                    tooltip: '보내기',
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ClubInquiryInboxScreen extends ConsumerStatefulWidget {
  const ClubInquiryInboxScreen({
    super.key,
    required this.clubId,
    this.clubName,
  });

  final String clubId;
  final String? clubName;

  @override
  ConsumerState<ClubInquiryInboxScreen> createState() =>
      _ClubInquiryInboxScreenState();
}

class _ClubInquiryInboxScreenState
    extends ConsumerState<ClubInquiryInboxScreen> {
  late Future<List<ClubInquiryThread>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ClubInquiryThread>> _load() {
    return ref.read(apiProvider).managedClubInquiries(widget.clubId);
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('가입 전 문의')),
      body: FutureBuilder<List<ClubInquiryThread>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _InquiryEmpty(
              icon: Icons.error_outline_rounded,
              title: '문의함을 불러오지 못했습니다.',
              actionLabel: '다시 시도',
              onAction: _refresh,
            );
          }
          final threads = snapshot.data ?? const [];
          if (threads.isEmpty) {
            return const _InquiryEmpty(
              icon: Icons.mark_chat_unread_outlined,
              title: '아직 도착한 문의가 없습니다',
              message: '새 문의가 오면 종 알림으로 알려드립니다.',
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: threads.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final thread = threads[index];
                return AppCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: cs.primaryContainer,
                      foregroundImage: _validNetworkImage(
                        thread.requesterAvatarUrl,
                      ),
                      child: Icon(Icons.person_outline_rounded,
                          color: cs.onPrimaryContainer),
                    ),
                    title: Text(thread.requesterLabel),
                    subtitle: Text([
                      if ((thread.requesterRegion ?? '').trim().isNotEmpty)
                        thread.requesterRegion!.trim(),
                      if ((thread.requesterAgeGroup ?? '').trim().isNotEmpty)
                        thread.requesterAgeGroup!.trim(),
                      _formatDate(thread.lastMessageAt),
                    ].join(' · ')),
                    trailing: IconButton(
                      tooltip: '문의자 프로필 보기',
                      onPressed: () => _showRequesterProfile(context, thread),
                      icon: const Icon(Icons.account_circle_outlined),
                    ),
                    onTap: () async {
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ClubInquiryConversationScreen(
                            clubId: widget.clubId,
                            clubName: widget.clubName,
                            threadId: thread.id,
                          ),
                        ),
                      );
                      await _refresh();
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

ImageProvider<Object>? _validNetworkImage(String? value) {
  final url = value?.trim();
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !uri.hasScheme ||
      !{'http', 'https'}.contains(uri.scheme)) {
    return null;
  }
  return NetworkImage(url);
}

Future<void> _showRequesterProfile(
  BuildContext context,
  ClubInquiryThread thread,
) {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 38,
              backgroundColor: cs.primaryContainer,
              foregroundImage: _validNetworkImage(thread.requesterAvatarUrl),
              child: Icon(Icons.person_outline_rounded,
                  size: 36, color: cs.onPrimaryContainer),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              thread.requesterLabel,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if ((thread.requesterRegion ?? '').trim().isNotEmpty)
                  Chip(
                    avatar: const Icon(Icons.location_on_outlined, size: 18),
                    label: Text(thread.requesterRegion!.trim()),
                  ),
                if ((thread.requesterAgeGroup ?? '').trim().isNotEmpty)
                  Chip(
                    avatar: const Icon(Icons.badge_outlined, size: 18),
                    label: Text(thread.requesterAgeGroup!.trim()),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '가입 전 문의를 받은 클럽장과 매니저에게만 공개되는 프로필입니다.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.mine});

  final ClubInquiryMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: mine ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.body),
            const SizedBox(height: 4),
            Text(
              _formatDate(message.createdAt),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InquiryEmpty extends StatelessWidget {
  const _InquiryEmpty({
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: cs.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(title, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}/${local.day} $hour:$minute';
}
