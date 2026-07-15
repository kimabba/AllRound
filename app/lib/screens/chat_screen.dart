import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chat_ui.dart';
import '../services/api.dart';
import '../state/chat_state.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/chat_club_card.dart';
import '../widgets/chat_tournament_card.dart';
import '../widgets/allround_logo.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  static const _firstByteTimeout = Duration(seconds: 15);

  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<ChatStreamEvent>? _streamSub;

  @override
  void dispose() {
    _streamSub?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _stopStreaming() {
    _streamSub?.cancel();
    _streamSub = null;
    ref.read(chatProvider).finishStreaming();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    final chat = ref.read(chatProvider);
    if (text.isEmpty || chat.busy) return;
    _ctrl.clear();

    chat.addUserMessage(text);
    _scrollToBottom();

    final assistantIdx = chat.lastAssistantIndex;
    final api = ref.read(apiProvider);

    await _consumeChatStream(
      api.chat(
        message: text,
        conversationId: chat.conversationId,
        activeSport: ref.read(activeSportProvider),
      ),
      assistantIdx,
    );
  }

  Future<void> _sendWithEntity(
      String message, String entityType, String entityId) async {
    final chat = ref.read(chatProvider);
    if (chat.busy) return;

    chat.addUserMessage(message);
    _scrollToBottom();

    final assistantIdx = chat.lastAssistantIndex;
    final api = ref.read(apiProvider);

    await _consumeChatStream(
      api.chat(
        message: message,
        conversationId: chat.conversationId,
        activeSport: ref.read(activeSportProvider),
        selectedEntity: {'type': entityType, 'id': entityId},
      ),
      assistantIdx,
    );
  }

  /// 대회검색 정제 칩("내 등급만 보기"/"전체 대회 보기") 탭 → refine 페이로드로 재요청(JY-101).
  Future<void> _sendWithRefine(
      String label, Map<String, dynamic> refine) async {
    final chat = ref.read(chatProvider);
    if (chat.busy) return;

    chat.addUserMessage(label);
    _scrollToBottom();

    final assistantIdx = chat.lastAssistantIndex;
    final api = ref.read(apiProvider);

    await _consumeChatStream(
      api.chat(
        message: label,
        conversationId: chat.conversationId,
        activeSport: ref.read(activeSportProvider),
        tournamentRefine: refine,
      ),
      assistantIdx,
    );
  }

  Future<void> _consumeChatStream(
      Stream<ChatStreamEvent> stream, int assistantIdx) async {
    final chat = ref.read(chatProvider);
    final completer = Completer<void>();

    _streamSub = stream.timeout(_firstByteTimeout, onTimeout: (sink) {
      sink.addError(TimeoutException('응답 대기 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.'));
      sink.close();
    }).listen(
      (evt) {
        if (!mounted) {
          _streamSub?.cancel();
          if (!completer.isCompleted) completer.complete();
          return;
        }
        switch (evt.event) {
          case 'meta':
            chat.setConversationId(evt.data['conversation_id'] as String?);
          case 'delta':
            chat.appendContent(assistantIdx, evt.data['text'] as String? ?? '');
            _scrollToBottom();
          case 'citation':
            final items = (evt.data['items'] as List?) ?? const [];
            chat.setCitations(assistantIdx, items.cast<Map<String, dynamic>>());
          case 'ui':
            final blocks = ChatUiBlock.listFromEvent(evt.data);
            if (blocks.isNotEmpty) {
              chat.addUiBlocks(assistantIdx, blocks);
              _scrollToBottom();
            }
          case 'error':
            chat.appendContent(assistantIdx,
                '\n\n[오류] ${_formatChatError(evt.data['message'])}');
        }
      },
      onError: (Object e) {
        chat.appendContent(assistantIdx, '\n\n[연결 실패] ${_formatChatError(e)}');
      },
      onDone: () {
        chat.finishStreaming();
        _streamSub = null;
        if (!completer.isCompleted) completer.complete();
      },
    );

    return completer.future;
  }

  String _formatChatError(Object? error) {
    final text = error?.toString() ?? '';
    if (text.contains('API_KEY_INVALID') ||
        text.contains('API key not valid') ||
        text.contains('GEMINI_API_KEY')) {
      // 내부 경로·환경변수명(GEMINI_API_KEY 등)은 사용자에게 노출하지 않는다.
      return 'AI 코치를 일시적으로 이용할 수 없어요. 잠시 후 다시 시도해 주세요.';
    }
    if (text.contains('401') || text.contains('JWT')) {
      return '로그인 세션을 확인할 수 없습니다. 다시 로그인한 뒤 시도해 주세요.';
    }
    if (text.contains('rate limit') || text.contains('429')) {
      return '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.';
    }
    return '챗봇 응답을 가져오지 못했습니다. 잠시 후 다시 시도해 주세요.';
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

    return Scaffold(
      appBar: AppBar(
        title: const BrandedAppBarTitle(title: '라운드 코치'),
        actions: [
          if (messages.isNotEmpty)
            IconButton(
              onPressed: busy ? null : () => ref.read(chatProvider).reset(),
              icon: const Icon(Icons.add_comment_outlined),
              tooltip: '새 대화',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? _EmptyHint(
                    onSend: sendText,
                    sport: ref.watch(activeSportProvider),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    itemCount: messages.length,
                    itemBuilder: (_, i) => _MessageBubble(
                      msg: messages[i],
                      onCardAction: _sendWithEntity,
                      onRefine: _sendWithRefine,
                    ),
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
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final Future<void> Function(String) onSend;
  // 활성 종목(풋살/테니스)에 맞춰 예시 질문을 바꾼다.
  final String? sport;
  const _EmptyHint({required this.onSend, this.sport});

  List<(IconData, String, String)> get _suggestions {
    final isFutsal = sport == 'futsal';
    final label = isFutsal ? '풋살' : '테니스';
    final ruleIcon =
        isFutsal ? Icons.sports_soccer_outlined : Icons.sports_tennis_outlined;
    final ruleMsg = isFutsal ? '풋살 경기 규칙 알려줘' : '테니스 복식 규칙 알려줘';
    return [
      (Icons.emoji_events_outlined, '이번 달 대회', '이번 달 대회 일정 알려줘'),
      (Icons.article_outlined, '대회 신청', '대회 신청 방법 알려줘'),
      (Icons.groups_outlined, '클럽 찾기', '$label 클럽 추천해줘'),
      (ruleIcon, '$label 규칙', ruleMsg),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.xxl),
          Text(
            '무엇이든 물어보세요',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '대회 · 규칙 · 구장 · 클럽 정보를\n코치처럼 쉽게 알려드릴게요',
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          for (final (icon, label, msg) in _suggestions) ...[
            _SuggestionCard(
              icon: icon,
              label: label,
              onTap: () => onSend(msg),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _SuggestionCard({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onStop;
  const _InputBar({
    required this.controller,
    required this.busy,
    required this.onSend,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const inputBorderRadius = AppRadius.card;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
          boxShadow: AppShadows.cardFor(Theme.of(context).brightness),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: '메시지를 입력하세요',
                  filled: true,
                  fillColor: cs.surface,
                  border: OutlineInputBorder(
                    borderRadius: inputBorderRadius,
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: inputBorderRadius,
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: inputBorderRadius,
                    borderSide: BorderSide(color: cs.primary, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                ),
                textInputAction: TextInputAction.send,
                maxLines: 4,
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            busy
                ? IconButton.filled(
                    onPressed: onStop,
                    icon: const Icon(Icons.stop_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: cs.error,
                      foregroundColor: cs.onError,
                    ),
                  )
                : IconButton.filled(
                    onPressed: onSend,
                    icon: const Icon(Icons.arrow_upward_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.msg,
    required this.onCardAction,
    required this.onRefine,
  });
  final ChatMessage msg;
  final void Function(String message, String entityType, String entityId)
      onCardAction;
  final void Function(String label, Map<String, dynamic> refine) onRefine;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isUser = msg.role == 'user';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: isUser ? cs.primary : cs.surfaceContainerLow,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isUser ? 18 : AppRadius.xs),
                bottomRight: Radius.circular(isUser ? AppRadius.xs : 18),
              ),
              boxShadow: isUser
                  ? null
                  : AppShadows.cardFor(Theme.of(context).brightness),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                isUser
                    ? SelectableText(
                        msg.content.isEmpty ? '…' : msg.content,
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onPrimary,
                          height: 1.5,
                        ),
                      )
                    : MarkdownBody(
                        data: _cleanAssistantContent(msg.content),
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
                          listBullet:
                              tt.bodyMedium?.copyWith(color: cs.onSurface),
                          strong: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                // 카드(대회·클럽)가 있으면 출처 리스트는 카드와 중복이라 숨긴다.
                // 카드 없는 응답(규칙·구장 등)에서만 출처를 표시.
                if (msg.citations.isNotEmpty &&
                    !msg.uiBlocks.any((b) =>
                        b.tournamentItems.isNotEmpty ||
                        b.clubItems.isNotEmpty)) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Divider(
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                    height: 1,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final c in msg.citations.take(8))
                    _CitationRow(citation: c),
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
                            avatar: const Icon(
                              Icons.filter_alt_outlined,
                              size: 18,
                            ),
                            label: Text(block.refineChip!.label),
                            onPressed: () => onRefine(
                              block.refineChip!.label,
                              block.refineChip!.refine,
                            ),
                          ),
                        ),
                      ),
                  ],
              ],
            ),
          ),
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
      .replaceAll(
          RegExp(r'출처:\s*(?:id\s+)?[a-f0-9\-]+(?:,\s*(?:id\s+)?[a-f0-9\-]+)*'),
          '')
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: GestureDetector(
        onTap: url != null
            ? () => launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                )
            : null,
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
    );
  }
}
