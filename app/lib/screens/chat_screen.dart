import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/matchup_logo.dart';

class _Msg {
  final String role;
  String content;
  List<Map<String, dynamic>> citations;

  _Msg({required this.role, required this.content})
      : citations = <Map<String, dynamic>>[];
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Msg>[];
  String? _conversationId;
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _busy) return;
    _ctrl.clear();

    setState(() {
      _messages.add(_Msg(role: 'user', content: text));
      _messages.add(_Msg(role: 'assistant', content: ''));
      _busy = true;
    });
    _scrollToBottom();

    final assistantIdx = _messages.length - 1;
    final api = ref.read(apiProvider);

    try {
      await for (final evt in api.chat(
        message: text,
        conversationId: _conversationId,
        activeSport: ref.read(activeSportProvider),
      )) {
        if (!mounted) return;
        switch (evt.event) {
          case 'meta':
            _conversationId = evt.data['conversation_id'] as String?;
          case 'delta':
            setState(() {
              _messages[assistantIdx].content +=
                  evt.data['text'] as String? ?? '';
            });
            _scrollToBottom();
          case 'citation':
            final items = (evt.data['items'] as List?) ?? const [];
            setState(() {
              _messages[assistantIdx].citations = [
                ..._messages[assistantIdx].citations,
                ...items.cast<Map<String, dynamic>>(),
              ];
            });
          case 'error':
            setState(() {
              _messages[assistantIdx].content +=
                  '\n\n[오류] ${_formatChatError(evt.data['message'])}';
            });
        }
      }
    } catch (e) {
      setState(() {
        _messages[assistantIdx].content += '\n\n[연결 실패] ${_formatChatError(e)}';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatChatError(Object? error) {
    final text = error?.toString() ?? '';
    if (text.contains('API_KEY_INVALID') ||
        text.contains('API key not valid') ||
        text.contains('GEMINI_API_KEY')) {
      return 'AI 챗봇 API 키가 설정되지 않았거나 올바르지 않습니다. supabase/functions/.env의 GEMINI_API_KEY를 실제 Gemini 키로 바꾼 뒤 백엔드를 다시 실행해 주세요.';
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

    return Scaffold(
      appBar: AppBar(title: const BrandedAppBarTitle(title: '코치봇')),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _EmptyHint(onSend: sendText)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _MessageBubble(msg: _messages[i]),
                  ),
          ),
          if (_busy)
            LinearProgressIndicator(
              color: cs.primary,
              backgroundColor: cs.surfaceContainerLow,
            ),
          _InputBar(controller: _ctrl, busy: _busy, onSend: _send),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final Future<void> Function(String) onSend;
  const _EmptyHint({required this.onSend});

  static const _suggestions = [
    ('🏆', '이번 주 대회', '이번 주 내 등급에 맞는 대회 알려줘'),
    ('📖', '규칙 질문', '테니스 서브 기본 규칙 알려줘'),
    ('📍', '구장 찾기', '광주 풋살장 알려줘'),
    ('🏅', '등급 안내', '광주 테니스 협회 등급 체계 알려줘'),
  ];

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
          const SizedBox(height: AppSpacing.xl),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary, cs.tertiary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 36,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '무엇이든 물어보세요',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '대회 · 규칙 · 구장 · 클럽 정보를\nAI 코치봇이 즉시 답변합니다',
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          for (final (emoji, label, msg) in _suggestions) ...[
            _SuggestionCard(
              emoji: emoji,
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
  final String emoji;
  final String label;
  final VoidCallback? onTap;
  const _SuggestionCard({required this.emoji, required this.label, this.onTap});

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
              Text(emoji, style: const TextStyle(fontSize: 22)),
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
  const _InputBar({
    required this.controller,
    required this.busy,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                    borderRadius: AppRadius.pill,
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppRadius.pill,
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                ),
                textInputAction: TextInputAction.send,
                maxLines: null,
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filled(
              onPressed: busy ? null : onSend,
              icon: const Icon(Icons.arrow_upward_rounded),
              style: IconButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                disabledBackgroundColor: cs.surfaceContainerHigh,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.msg});
  final _Msg msg;

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
                if (msg.citations.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Divider(
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                    height: 1,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final c in msg.citations.take(8))
                    _CitationRow(citation: c),
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
