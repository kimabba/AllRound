import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/chat_entry_context.dart';
import '../screens/chat_screen.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';

Future<void> openChatSheet(
  BuildContext context,
  ChatEntryContext entryContext,
) async {
  final hostContext = context;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (sheetContext) => _KeyboardAwareChatSheet(
      entryContext: entryContext,
      onExpand: (expandedContext) async {
        await Navigator.of(sheetContext).maybePop();
        if (hostContext.mounted) {
          hostContext.push('/chat', extra: expandedContext);
        }
      },
    ),
  );
}

class _KeyboardAwareChatSheet extends StatefulWidget {
  const _KeyboardAwareChatSheet({
    required this.entryContext,
    required this.onExpand,
  });

  final ChatEntryContext entryContext;
  final ValueChanged<ChatEntryContext?> onExpand;

  @override
  State<_KeyboardAwareChatSheet> createState() =>
      _KeyboardAwareChatSheetState();
}

class _KeyboardAwareChatSheetState extends State<_KeyboardAwareChatSheet> {
  static const _initialSize = 0.62;
  static const _minSize = 0.46;
  static const _maxSize = 0.94;

  final _sheetController = DraggableScrollableController();
  bool _keyboardVisible = false;
  double? _sizeBeforeKeyboard;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (keyboardVisible && !_keyboardVisible) {
      _sizeBeforeKeyboard =
          _sheetController.isAttached ? _sheetController.size : _initialSize;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_keyboardVisible || !_sheetController.isAttached) {
          return;
        }
        unawaited(
          _sheetController.animateTo(
            _maxSize,
            duration: AppDuration.medium1,
            curve: Curves.easeOutCubic,
          ),
        );
      });
    } else if (!keyboardVisible && _keyboardVisible) {
      final restoreSize = (_sizeBeforeKeyboard ?? _initialSize)
          .clamp(_minSize, _maxSize)
          .toDouble();
      _sizeBeforeKeyboard = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _keyboardVisible || !_sheetController.isAttached) {
          return;
        }
        unawaited(
          _sheetController.animateTo(
            restoreSize,
            duration: AppDuration.medium1,
            curve: Curves.easeOutCubic,
          ),
        );
      });
    }
    _keyboardVisible = keyboardVisible;
  }

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: _initialSize,
      minChildSize: _minSize,
      maxChildSize: _maxSize,
      expand: false,
      snap: true,
      snapSizes: const [_initialSize, _maxSize],
      builder: (sheetBodyContext, scrollController) {
        return ClipRRect(
          borderRadius: AppRadius.sheet,
          child: ChatScreen(
            embedded: true,
            scrollController: scrollController,
            entryContext: widget.entryContext,
            onExpand: widget.onExpand,
          ),
        );
      },
    );
  }
}

ChatEntryContext chatEntryContextForPath(String location) {
  final segments = Uri(path: location).pathSegments;

  if (segments.length >= 2 && segments.first == 'tournaments') {
    final id = segments[1];
    if (id != 'submit') {
      return ChatEntryContext(
        screenLabel: '현재 대회',
        entityType: 'tournament',
        entityId: id,
      );
    }
  }

  if (segments.length >= 2 && segments.first == 'clubs') {
    return ChatEntryContext(
      screenLabel: '현재 클럽',
      entityType: 'club',
      entityId: segments[1],
    );
  }

  if (location.startsWith('/tournaments')) {
    return const ChatEntryContext(
      screenLabel: '대회',
    );
  }

  if (location.startsWith('/clubs')) {
    return const ChatEntryContext(
      screenLabel: '클럽',
    );
  }

  if (location.startsWith('/rules')) {
    return const ChatEntryContext(
      screenLabel: '룰북',
    );
  }

  if (location.startsWith('/rankings')) {
    return const ChatEntryContext(
      screenLabel: '랭킹',
    );
  }

  if (location.startsWith('/profile') ||
      location.startsWith('/favorites') ||
      location.startsWith('/notifications') ||
      location.startsWith('/blocked-users') ||
      location.startsWith('/more')) {
    return const ChatEntryContext(
      screenLabel: 'MY',
    );
  }

  return const ChatEntryContext(
    screenLabel: '오늘',
  );
}
