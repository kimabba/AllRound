import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/club_chat.dart';
import '../../models/club_event.dart';
import '../../models/moderation.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/moderation/ugc_moderation_widgets.dart';

class ClubMemberChatScreen extends ConsumerStatefulWidget {
  const ClubMemberChatScreen({
    super.key,
    required this.clubId,
    required this.title,
    this.threadId,
    this.otherMember,
    this.members = const [],
  });

  final String clubId;
  final String title;
  final String? threadId;
  final ClubMember? otherMember;
  final List<ClubMember> members;

  @override
  ConsumerState<ClubMemberChatScreen> createState() =>
      _ClubMemberChatScreenState();
}

class _ClubMemberChatScreenState extends ConsumerState<ClubMemberChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  String? _threadId;
  List<ClubChatMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _threadId = widget.threadId;
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !_loading && !_sending) _load(showLoading: false);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (mounted && showLoading) setState(() => _loading = true);
    try {
      final api = ref.read(apiProvider);
      final threadId = _threadId ??
          await api.openClubChat(
            clubId: widget.clubId,
            otherUserId: widget.otherMember?.userId,
          );
      final messages = await api.clubChatMessages(threadId);
      if (!mounted) return;
      setState(() {
        _threadId = threadId;
        _messages = messages;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (_) {
      if (mounted) {
        setState(() => _error = '대화를 불러오지 못했습니다. 멤버 상태를 확인해주세요.');
      }
    } finally {
      if (mounted && showLoading) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final threadId = _threadId;
    final body = _controller.text.trim();
    if (threadId == null || body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(apiProvider).sendClubChatMessage(
            threadId: threadId,
            body: body,
          );
      _controller.clear();
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('메시지를 보내지 못했습니다. 다시 시도해주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showMessageActions(ClubChatMessage message) async {
    final senderId = message.senderId;
    if (senderId == null || senderId == ref.read(currentUserProvider)?.id) {
      return;
    }
    final report = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('사용자 신고'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.block_rounded),
              title: const Text('사용자 차단'),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (!mounted || report == null) return;
    if (report) {
      await showUgcReportSheet(
        context: context,
        ref: ref,
        targetType: UgcTargetType.user,
        targetId: senderId,
      );
    } else {
      final blocked = await confirmBlockUser(
        context: context,
        ref: ref,
        userId: senderId,
        displayName: _memberName(senderId),
      );
      if (blocked) await _load();
    }
  }

  String _memberName(String? userId) {
    if (userId == null) return '탈퇴한 사용자';
    for (final member in widget.members) {
      if (member.userId == userId) {
        final name = member.displayName?.trim();
        return name == null || name.isEmpty ? '멤버' : name;
      }
    }
    final directName = widget.otherMember?.displayName?.trim();
    if (widget.otherMember?.userId == userId &&
        directName != null &&
        directName.isNotEmpty) {
      return directName;
    }
    return '멤버';
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserProvider)?.id;
    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(fallbackLocation: '/clubs/${widget.clubId}'),
        title: Text(widget.title),
        actions: [
          if (widget.otherMember != null)
            IconButton(
              tooltip: '프로필 보기',
              onPressed: () => _showMemberProfile(widget.otherMember!),
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
                    ? _ChatEmpty(
                        message: _error!,
                        actionLabel: '다시 시도',
                        onAction: _load,
                      )
                    : _messages.isEmpty
                        ? const _ChatEmpty(
                            message: '첫 메시지를 보내 대화를 시작해보세요.',
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final message = _messages[index];
                              return _ChatBubble(
                                message: message,
                                mine: message.senderId == currentUserId,
                                senderName: _memberName(message.senderId),
                                onLongPress: () => _showMessageActions(message),
                              );
                            },
                          ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      decoration: const InputDecoration(
                        hintText: '메시지 입력',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filled(
                    tooltip: '메시지 보내기',
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

  Future<void> _showMemberProfile(ClubMember member) {
    final values = <(String, List<String>)>[
      ('관심 종목·레벨', member.sports),
      ('가입한 클럽', member.teams),
      ('참가 대회', member.tournaments),
      ('테니스 협회·레벨', member.tennisOrganizations),
    ];
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(
              _memberName(member.userId),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final entry in values)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.$1,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      entry.$2.isEmpty ? '등록된 정보가 없습니다.' : entry.$2.join('\n'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.mine,
    required this.senderName,
    required this.onLongPress,
  });

  final ClubChatMessage message;
  final bool mine;
  final String senderName;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: mine ? null : onLongPress,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: mine ? cs.primaryContainer : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine) ...[
                Text(senderName, style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: AppSpacing.xs),
              ],
              Text(message.body),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatEmpty extends StatelessWidget {
  const _ChatEmpty({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.forum_outlined, size: 40),
            const SizedBox(height: AppSpacing.sm),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
