import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/providers.dart';
import '../theme/tokens.dart';

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
                  '\n\n[오류] ${evt.data['message'] ?? '알 수 없는 오류'}';
            });
        }
      }
    } catch (e) {
      setState(() {
        _messages[assistantIdx].content += '\n\n[연결 실패] $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
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

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome_rounded,
                  size: 16, color: cs.primary),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Text('AI 챗봇'),
          ],
        ),
      ),
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
                    itemBuilder: (_, i) =>
                        _MessageBubble(msg: _messages[i]),
                  ),
          ),
          if (_busy)
            LinearProgressIndicator(
              color: cs.primary,
              backgroundColor: cs.surfaceContainerLow,
            ),
          _InputBar(
            controller: _ctrl,
            busy: _busy,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final Future<void> Function(String) onSend;
  const _EmptyHint({required this.onSend});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    const suggestions = [
      ('이번 주말 내 등급 대회', '이번 주말 내 등급에 맞는 대회 알려줘'),
      ('테니스 서브 규칙', '테니스 서브 기본 규칙 알려줘'),
      ('광주 테니스 협회 정보', '광주 테니스 협회 등급 체계와 대회 정보 알려줘'),
      ('풋살 파울 규칙', '풋살 누적 파울 규칙 알려줘'),
      ('내 등급 클럽 추천', '내 등급에 맞는 클럽 추천해줘'),
      ('대회 신청 방법', '동호인 테니스 대회 신청하는 방법 알려줘'),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.lg),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_awesome_rounded,
                size: 32, color: cs.primary),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'AI가 답해드려요',
            style: tt.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '내 등급 대회 검색, 종목 규칙, 협회 정보를 물어보세요',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 3.5,
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            children: [
              for (final (label, msg) in suggestions.take(4))
                _SuggestionChip(label, onTap: () => onSend(msg)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  const _SuggestionChip(this.text, {this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: AppRadius.pill,
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Text(
          text,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
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
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: '메시지를 입력하세요',
                  filled: true,
                  fillColor: cs.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: AppRadius.pill,
                    borderSide: BorderSide.none,
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
              color: isUser ? cs.primaryContainer : cs.surfaceContainerLow,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(AppRadius.lg),
                topRight: const Radius.circular(AppRadius.lg),
                bottomLeft: Radius.circular(isUser ? AppRadius.lg : AppRadius.xs),
                bottomRight: Radius.circular(isUser ? AppRadius.xs : AppRadius.lg),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  msg.content.isEmpty ? '…' : msg.content,
                  style: tt.bodyMedium?.copyWith(
                    color: isUser ? cs.onPrimaryContainer : cs.onSurface,
                    height: 1.5,
                  ),
                ),
                if (msg.citations.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Divider(color: cs.outlineVariant.withValues(alpha: 0.5), height: 1),
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
            ? () => launchUrl(Uri.parse(url),
                mode: LaunchMode.externalApplication)
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
