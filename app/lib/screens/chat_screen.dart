import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chat_entry_context.dart';
import '../models/moderation.dart';
import '../state/chat_state.dart';
import '../state/chat_stream_controller.dart';
import '../state/providers.dart';
import '../testing/e2e_keys.dart';
import '../theme/tokens.dart';
import '../widgets/moderation/ugc_moderation_widgets.dart';
import '../widgets/chat_ai_disclosure.dart';
import '../widgets/chat_club_card.dart';
import '../widgets/chat_tournament_card.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    this.embedded = false,
    this.scrollController,
    this.entryContext,
    this.onExpand,
    this.compactSheet = false,
    this.onSheetDragStart,
    this.onSheetDragUpdate,
    this.onSheetDragEnd,
  });

  final bool embedded;
  final ScrollController? scrollController;
  final ChatEntryContext? entryContext;
  final ValueChanged<ChatEntryContext?>? onExpand;
  final bool compactSheet;
  final GestureDragStartCallback? onSheetDragStart;
  final GestureDragUpdateCallback? onSheetDragUpdate;
  final GestureDragEndCallback? onSheetDragEnd;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _ctrl = TextEditingController();
  late final ScrollController _ownedScroll;
  late bool _attachEntryContext;

  ScrollController get _scroll => widget.scrollController ?? _ownedScroll;

  Map<String, String>? get _selectedEntryEntity {
    final entryContext = widget.entryContext;
    if (!_attachEntryContext || entryContext == null) return null;
    if (!entryContext.canAttachEntity) return null;
    return {'type': entryContext.entityType!, 'id': entryContext.entityId!};
  }

  @override
  void initState() {
    super.initState();
    _ownedScroll = ScrollController();
    _attachEntryContext = widget.entryContext?.attachEntityByDefault ?? false;
    final entryDraft = widget.entryContext?.initialMessage ?? '';
    _ctrl.text =
        entryDraft.isNotEmpty ? entryDraft : ref.read(chatProvider).draft;
    _ctrl.addListener(_syncDraft);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_syncDraft);
    _ctrl.dispose();
    _ownedScroll.dispose();
    super.dispose();
  }

  void _stopStreaming() {
    ref.read(chatStreamControllerProvider).stop();
  }

  void _syncDraft() {
    ref.read(chatProvider).setDraft(_ctrl.text);
  }

  void _resetConversation() {
    _ctrl.clear();
    ref.read(chatStreamControllerProvider).resetConversation();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    final chat = ref.read(chatProvider);
    if (text.isEmpty || chat.busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _ctrl.clear();

    final api = ref.read(apiProvider);
    final stream = api.chat(
      message: text,
      conversationId: chat.conversationId,
      activeSport: ref.read(activeSportProvider),
      selectedEntity: _selectedEntryEntity,
    );
    _scrollToBottom();

    await ref
        .read(chatStreamControllerProvider)
        .start(userMessage: text, stream: stream);
  }

  Future<void> _sendWithEntity(
    String message,
    String entityType,
    String entityId,
  ) async {
    final chat = ref.read(chatProvider);
    if (chat.busy) return;

    final api = ref.read(apiProvider);
    final stream = api.chat(
      message: message,
      conversationId: chat.conversationId,
      activeSport: ref.read(activeSportProvider),
      selectedEntity: {'type': entityType, 'id': entityId},
    );
    _scrollToBottom();

    await ref
        .read(chatStreamControllerProvider)
        .start(userMessage: message, stream: stream);
  }

  /// 대회검색 정제 칩("내 등급만 보기"/"전체 대회 보기") 탭 → refine 페이로드로 재요청(JY-101).
  Future<void> _sendWithRefine(
    String label,
    Map<String, dynamic> refine,
  ) async {
    final chat = ref.read(chatProvider);
    if (chat.busy) return;

    final api = ref.read(apiProvider);
    final stream = api.chat(
      message: label,
      conversationId: chat.conversationId,
      activeSport: ref.read(activeSportProvider),
      tournamentRefine: refine,
    );
    _scrollToBottom();

    await ref
        .read(chatStreamControllerProvider)
        .start(userMessage: label, stream: stream);
  }

  Future<void> _reportAssistantMessage(ChatMessage message) async {
    final conversationId = ref.read(chatProvider).conversationId;
    if (conversationId == null || message.content.trim().isEmpty) return;

    try {
      final messageId = await ref.read(apiProvider).findAssistantMessageId(
            conversationId: conversationId,
            content: message.content,
          );
      if (!mounted) return;
      if (messageId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('아직 저장 중인 답변입니다. 잠시 후 다시 시도해주세요.')),
        );
        return;
      }
      await showUgcReportSheet(
        context: context,
        ref: ref,
        targetType: UgcTargetType.aiMessage,
        targetId: messageId,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('AI 답변을 신고하지 못했습니다.')));
      }
    }
  }

  Future<void> sendText(String text) async {
    _ctrl.text = text;
    await _send();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chat = ref.watch(chatProvider);
    final messages = chat.messages;
    final busy = chat.busy;
    final compactForKeyboard =
        widget.embedded && MediaQuery.viewInsetsOf(context).bottom > 0;

    if (messages.isNotEmpty) _scrollToBottom();

    final chatBody = Column(
      children: [
        if (widget.embedded && !compactForKeyboard)
          _EmbeddedChatHeader(
            compact: widget.compactSheet,
            hasMessages: messages.isNotEmpty,
            busy: busy,
            onReset: _resetConversation,
            onDragStart: widget.onSheetDragStart,
            onDragUpdate: widget.onSheetDragUpdate,
            onDragEnd: widget.onSheetDragEnd,
            onExpand: () {
              ref.read(chatProvider).setDraft(_ctrl.text);
              final expandedContext = widget.entryContext?.copyWith(
                attachEntityByDefault: _attachEntryContext,
                initialMessage: _ctrl.text,
              );
              widget.onExpand?.call(expandedContext);
            },
          ),
        if (!compactForKeyboard &&
            !widget.compactSheet &&
            (widget.entryContext?.canAttachEntity ?? false))
          _EntityContextToggle(
            key: AllRoundE2EKeys.chatContextToggle,
            stateKey: _attachEntryContext
                ? AllRoundE2EKeys.chatContextAttached
                : AllRoundE2EKeys.chatContextDetached,
            label: widget.entryContext!.screenLabel,
            selected: _attachEntryContext,
            onChanged: (selected) {
              setState(() => _attachEntryContext = selected);
            },
          ),
        Expanded(
          child: messages.isEmpty
              ? _EmptyHint(
                  compact: widget.compactSheet,
                  scrollController: widget.embedded ? _scroll : null,
                )
              : ListView.builder(
                  controller: _scroll,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final message = messages[i];
                    return _MessageBubble(
                      msg: message,
                      announce: !busy &&
                          i == messages.length - 1 &&
                          message.role == 'assistant',
                      onCardAction: _sendWithEntity,
                      onRefine: _sendWithRefine,
                      onReport: !busy &&
                              message.role == 'assistant' &&
                              message.content.trim().isNotEmpty
                          ? () => _reportAssistantMessage(message)
                          : null,
                    );
                  },
                ),
        ),
        if (busy)
          LinearProgressIndicator(
            color: cs.primary,
            backgroundColor: cs.surfaceContainerLow,
          ),
        _InputBar(
          controller: _ctrl,
          busy: busy,
          onSend: _send,
          onStop: _stopStreaming,
          showDisclosure: !compactForKeyboard && !widget.compactSheet,
          floating: widget.embedded,
          compactForKeyboard: compactForKeyboard,
          compactForSheet: widget.compactSheet,
        ),
      ],
    );

    if (widget.embedded) {
      // Material 대신 Scaffold: 신고 실패 등 SnackBar가 시트 안에도 표시되게 한다.
      // (root Scaffold의 SnackBar는 모달 시트 뒤에 가려져 사용자가 못 봄)
      return Scaffold(
        key: AllRoundE2EKeys.embeddedChatSheet,
        backgroundColor: cs.surfaceContainerLow,
        body: chatBody,
      );
    }

    return Scaffold(
      key: AllRoundE2EKeys.fullChatScreen,
      appBar: AppBar(
        title: const Text('볼보이'),
        actions: [
          if (messages.isNotEmpty)
            IconButton(
              onPressed: busy ? null : _resetConversation,
              icon: const Icon(Icons.add_comment_outlined),
              tooltip: '새 대화',
            ),
        ],
      ),
      body: chatBody,
    );
  }
}

class _EmbeddedChatHeader extends StatelessWidget {
  const _EmbeddedChatHeader({
    required this.compact,
    required this.hasMessages,
    required this.busy,
    required this.onReset,
    required this.onExpand,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
  });

  final bool compact;
  final bool hasMessages;
  final bool busy;
  final VoidCallback onReset;
  final VoidCallback onExpand;
  final GestureDragStartCallback? onDragStart;
  final GestureDragUpdateCallback? onDragUpdate;
  final GestureDragEndCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      children: [
        SizedBox(height: compact ? 2 : AppSpacing.xs),
        Container(
          width: AppSpacing.xxxl,
          height: AppRadius.xs,
          decoration: BoxDecoration(
            color: cs.outline,
            borderRadius: AppRadius.pill,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            0,
          ),
          child: GestureDetector(
            key: const Key('ballboy-floating-header'),
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: onDragStart,
            onVerticalDragUpdate: onDragUpdate,
            onVerticalDragEnd: onDragEnd,
            child: Container(
              height: compact ? AppSizes.touchTarget : AppSizes.appBar,
              padding: const EdgeInsets.only(left: AppSpacing.md),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(AppRadius.xxl),
              ),
              child: Row(
                children: [
                  Container(
                    width: AppSpacing.xxxl,
                    height: AppSpacing.xxxl,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: AppRadius.pill,
                    ),
                    child: Text(
                      'BB',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '볼보이',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (!compact)
                          Text(
                            '대회·클럽 AI 도우미',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (hasMessages)
                    _ChatHeaderAction(
                      onPressed: busy ? null : onReset,
                      icon: Icons.add_comment_outlined,
                      tooltip: '새 대화',
                    ),
                  _ChatHeaderAction(
                    key: AllRoundE2EKeys.chatExpandButton,
                    onPressed: onExpand,
                    icon: Icons.open_in_full_rounded,
                    tooltip: '전체 화면으로 열기',
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatHeaderAction extends StatelessWidget {
  const _ChatHeaderAction({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.tooltip,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: AppSizes.touchTarget,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        tooltip: tooltip,
        style: IconButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.pill),
        ),
      ),
    );
  }
}

class _EntityContextToggle extends StatelessWidget {
  const _EntityContextToggle({
    super.key,
    required this.stateKey,
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final Key stateKey;
  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      toggled: selected,
      label: '$label 연결',
      value: selected ? '연결됨' : '연결 안 됨',
      hint: '공개된 정보만 질문에 함께 사용합니다.',
      onTap: () => onChanged(!selected),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            0,
          ),
          child: Material(
            color: selected ? cs.primaryContainer : cs.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: BorderSide(color: cs.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onChanged(!selected),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      selected ? Icons.link_rounded : Icons.link_off_rounded,
                      size: 18,
                      color: selected ? cs.primary : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$label 연결',
                            style: tt.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '공개된 정보만 질문에 함께 사용합니다.',
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Checkbox(
                      key: stateKey,
                      value: selected,
                      onChanged: (value) => onChanged(value ?? false),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final ScrollController? scrollController;
  final bool compact;
  const _EmptyHint({required this.compact, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return SingleChildScrollView(
      controller: scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        compact ? AppSpacing.sm : AppSpacing.xxl,
        AppSpacing.xl,
        compact ? AppSpacing.sm : AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '궁금한 건 그냥 물어보세요',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final bool showDisclosure;
  final bool floating;
  final bool compactForKeyboard;
  final bool compactForSheet;
  const _InputBar({
    required this.controller,
    required this.busy,
    required this.onSend,
    required this.onStop,
    required this.showDisclosure,
    required this.floating,
    required this.compactForKeyboard,
    required this.compactForSheet,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final compactComposer = compactForKeyboard || compactForSheet;
    return SafeArea(
      top: false,
      child: Padding(
        padding: floating && !compactForKeyboard
            ? const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                0,
                AppSpacing.sm,
                AppSpacing.sm,
              )
            : EdgeInsets.zero,
        child: Container(
          key: floating ? const Key('ballboy-floating-composer') : null,
          padding: compactComposer
              ? const EdgeInsets.all(AppSpacing.sm)
              : const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  10,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
          decoration: BoxDecoration(
            color: cs.surface,
            border: floating && !compactForKeyboard
                ? Border.all(color: cs.outlineVariant)
                : Border(top: BorderSide(color: cs.outlineVariant)),
            borderRadius: floating && !compactForKeyboard
                ? BorderRadius.circular(AppRadius.xxl * 1.5)
                : BorderRadius.zero,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: AppSizes.control,
                        maxHeight: compactComposer
                            ? AppSizes.control
                            : AppSizes.chatComposerMax,
                      ),
                      child: TextField(
                        key: AllRoundE2EKeys.chatInput,
                        controller: controller,
                        decoration: InputDecoration(
                          hintText: '볼보이에게 물어보세요',
                          isDense: compactComposer,
                          fillColor: cs.surfaceContainerLowest,
                          border: OutlineInputBorder(
                            borderRadius: AppRadius.pill,
                            borderSide: BorderSide(color: cs.outlineVariant),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: AppRadius.pill,
                            borderSide: BorderSide(color: cs.outlineVariant),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: AppRadius.pill,
                            borderSide: BorderSide(
                              color: cs.primary,
                              width: 1.5,
                            ),
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical:
                                compactComposer ? AppSpacing.sm : AppSpacing.md,
                          ),
                        ),
                        textInputAction: TextInputAction.send,
                        minLines: 1,
                        maxLines: compactComposer ? 1 : 4,
                        onSubmitted: (_) => onSend(),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      final canSend = value.text.trim().isNotEmpty;
                      return _ChatComposerAction(
                        onPressed: busy ? onStop : (canSend ? onSend : null),
                        icon: busy
                            ? Icons.stop_rounded
                            : Icons.arrow_upward_rounded,
                        tooltip: busy ? '응답 중지' : '메시지 보내기',
                        backgroundColor: busy ? cs.error : cs.primary,
                        foregroundColor: busy ? cs.onError : cs.onPrimary,
                        disabledBackgroundColor: cs.surfaceContainerHighest,
                        disabledForegroundColor: cs.onSurfaceVariant,
                        round: floating,
                      );
                    },
                  ),
                ],
              ),
              if (showDisclosure) ...[
                const SizedBox(height: AppSpacing.sm),
                const ChatAiDisclosure(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatComposerAction extends StatelessWidget {
  const _ChatComposerAction({
    required this.onPressed,
    required this.icon,
    required this.tooltip,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.disabledBackgroundColor,
    required this.disabledForegroundColor,
    required this.round,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String tooltip;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color disabledBackgroundColor;
  final Color disabledForegroundColor;
  final bool round;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: AppSizes.touchTarget,
      child: IconButton.filled(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: disabledBackgroundColor,
          disabledForegroundColor: disabledForegroundColor,
          shape: RoundedRectangleBorder(
            borderRadius:
                round ? AppRadius.pill : BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.msg,
    required this.announce,
    required this.onCardAction,
    required this.onRefine,
    required this.onReport,
  });
  final ChatMessage msg;
  final bool announce;
  final void Function(String message, String entityType, String entityId)
      onCardAction;
  final void Function(String label, Map<String, dynamic> refine) onRefine;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isUser = msg.role == 'user';
    final visibleContent = isUser
        ? (msg.content.isEmpty ? '…' : msg.content)
        : _cleanAssistantContent(msg.content);

    final messageContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          key: !isUser && announce
              ? AllRoundE2EKeys.latestAssistantMessage
              : null,
          label: '${isUser ? '사용자 메시지' : 'AI 답변'}, $visibleContent',
          child: ExcludeSemantics(
            child: isUser
                ? SelectableText(
                    visibleContent,
                    style: tt.bodyMedium?.copyWith(
                      color: cs.onPrimary,
                      height: 1.5,
                    ),
                  )
                : MarkdownBody(
                    data: visibleContent,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: tt.bodyMedium?.copyWith(
                        color: cs.onSurface,
                        height: 1.5,
                      ),
                      h3: tt.titleSmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                      listBullet: tt.bodyMedium?.copyWith(color: cs.onSurface),
                      strong: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
          ),
        ),
        // 카드(대회·클럽)가 있으면 출처 리스트는 카드와 중복이라 숨긴다.
        // 카드 없는 응답(규칙·구장 등)에서만 출처를 표시.
        if (msg.citations.isNotEmpty &&
            !msg.uiBlocks.any(
              (b) => b.tournamentItems.isNotEmpty || b.clubItems.isNotEmpty,
            )) ...[
          const SizedBox(height: AppSpacing.sm),
          Divider(color: cs.outlineVariant.withValues(alpha: 0.5), height: 1),
          const SizedBox(height: AppSpacing.sm),
          for (final c in msg.citations.take(8)) _CitationRow(citation: c),
        ],
        if (msg.uiBlocks.isNotEmpty)
          for (final block in msg.uiBlocks) ...[
            for (final item in block.tournamentItems)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: ChatTournamentCard(
                  item: item,
                  onAction: (message, entityId) =>
                      onCardAction(message, 'tournament', entityId),
                ),
              ),
            for (final item in block.clubItems)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: ChatClubCard(
                  item: item,
                  onAction: (message, entityId) =>
                      onCardAction(message, 'club', entityId),
                ),
              ),
            if (block.refineChip != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    avatar: const Icon(Icons.filter_alt_outlined, size: 18),
                    label: Text(block.refineChip!.label),
                    onPressed: () => onRefine(
                      block.refineChip!.label,
                      block.refineChip!.refine,
                    ),
                  ),
                ),
              ),
          ],
        if (onReport != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onReport,
              icon: const Icon(Icons.flag_outlined, size: 16),
              label: const Text('AI 답변 신고'),
            ),
          ),
        ],
      ],
    );

    final messageWidget = isUser
        ? ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.78,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: messageContent,
            ),
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _BallboyMessageMark(),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: messageContent),
            ],
          );

    return Semantics(
      container: true,
      liveRegion: announce,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: messageWidget,
        ),
      ),
    );
  }
}

class _BallboyMessageMark extends StatelessWidget {
  const _BallboyMessageMark();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      width: AppSpacing.xxxl,
      height: AppSpacing.xxxl,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        'BB',
        style: tt.labelSmall?.copyWith(
          color: cs.onPrimaryContainer,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

/// 어시스턴트 응답에서 raw 출처 ID 패턴 제거
String _cleanAssistantContent(String content) {
  if (content.isEmpty) return '…';
  // "(출처: id xxx-xxx, ...)" or "(출처: xxx-xxx)" 패턴 제거
  return content
      .replaceAll(RegExp(r'\(출처:?\s*(?:id\s*)?[a-f0-9\-,\s]+\)'), '')
      // "(id: xxx-xxx, ...)" — 규정/대회 컨텍스트의 raw DB id 인라인 노출 제거
      .replaceAll(RegExp(r'\s*\(id:\s*[a-f0-9\-,\s]+\)'), '')
      .replaceAll(
        RegExp(r'출처:\s*(?:id\s+)?[a-f0-9\-]+(?:,\s*(?:id\s+)?[a-f0-9\-]+)*'),
        '',
      )
      .trim();
}

class _CitationRow extends StatelessWidget {
  final Map<String, dynamic> citation;
  const _CitationRow({required this.citation});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final title = citation['title']?.toString() ??
        citation['url']?.toString() ??
        citation['source']?.toString() ??
        '';
    final url = citation['url'] as String?;
    final isWeb = citation['type'] == 'web';
    void openCitation() {
      if (url == null) return;
      unawaited(
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      );
    }

    return Semantics(
      link: url != null,
      label: url != null ? '출처 링크, $title' : '출처, $title',
      onTap: url != null ? openCitation : null,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: url != null ? openCitation : null,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSizes.touchTarget),
            child: Row(
              children: [
                Icon(
                  isWeb ? Icons.link_rounded : Icons.storage_rounded,
                  size: 12,
                  color: cs.primary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    title,
                    style: tt.labelSmall?.copyWith(
                      color: url != null ? cs.primary : cs.onSurfaceVariant,
                      decoration: url != null ? TextDecoration.underline : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
