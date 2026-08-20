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
    barrierColor: Colors.black.withValues(alpha: 0.22),
    sheetAnimationStyle: const AnimationStyle(
      duration: AppDuration.medium3,
      reverseDuration: AppDuration.medium2,
    ),
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
  static const _maxSize = 0.94;

  final _sheetController = DraggableScrollableController();
  bool _keyboardVisible = false;
  double? _sizeBeforeKeyboard;
  double _headerDragDistance = 0;

  double _peekSize(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    return (AppSizes.chatSheetPeekMinHeight / screenHeight)
        .clamp(0.25, 0.42)
        .toDouble();
  }

  void _handleHeaderDragStart(DragStartDetails details) {
    _headerDragDistance = 0;
  }

  void _handleHeaderDragUpdate(DragUpdateDetails details) {
    if (!_sheetController.isAttached) return;
    final delta = details.primaryDelta ?? 0;
    _headerDragDistance += delta;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final peekSize = _peekSize(context);
    final nextSize = (_sheetController.size - delta / screenHeight)
        .clamp(peekSize, _maxSize)
        .toDouble();
    _sheetController.jumpTo(nextSize);
  }

  void _handleHeaderDragEnd(DragEndDetails details) {
    if (!_sheetController.isAttached) return;
    final peekSize = _peekSize(context);
    final currentSize = _sheetController.size;
    final velocity = details.primaryVelocity ?? 0;

    if (_headerDragDistance > AppSizes.touchTarget &&
        currentSize <= peekSize + 0.01) {
      Navigator.of(context).maybePop();
      return;
    }

    final midpoint = (peekSize + _maxSize) / 2;
    final targetSize =
        velocity < -300 || currentSize >= midpoint ? _maxSize : peekSize;
    unawaited(
      _sheetController.animateTo(
        targetSize,
        duration: AppDuration.medium1,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (keyboardVisible && !_keyboardVisible) {
      _sizeBeforeKeyboard = _sheetController.isAttached
          ? _sheetController.size
          : _peekSize(context);
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
      final peekSize = _peekSize(context);
      final restoreSize = (_sizeBeforeKeyboard ?? peekSize)
          .clamp(peekSize, _maxSize)
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
    final peekSize = _peekSize(context);
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: peekSize,
      minChildSize: peekSize,
      maxChildSize: _maxSize,
      expand: false,
      snap: true,
      snapSizes: [peekSize, _maxSize],
      shouldCloseOnMinExtent: false,
      builder: (sheetBodyContext, scrollController) {
        final cs = Theme.of(sheetBodyContext).colorScheme;
        final floatingRadius = BorderRadius.circular(AppRadius.xxl * 2);
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: AppDuration.medium2,
          curve: AppCurves.emphasizedDecelerate,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, AppSpacing.md * (1 - value)),
              child: child,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.sm,
              0,
              AppSpacing.sm,
              _keyboardVisible ? 0 : AppSpacing.sm,
            ),
            child: DecoratedBox(
              key: const Key('ballboy-floating-sheet-surface'),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border.all(color: cs.outlineVariant),
                borderRadius: floatingRadius,
                boxShadow: AppShadows.overlay,
              ),
              child: ClipRRect(
                borderRadius: floatingRadius,
                child: AnimatedBuilder(
                  animation: _sheetController,
                  builder: (context, _) {
                    final currentSize = _sheetController.isAttached
                        ? _sheetController.size
                        : peekSize;
                    return ChatScreen(
                      embedded: true,
                      compactSheet: currentSize <= peekSize + 0.04,
                      scrollController: scrollController,
                      entryContext: widget.entryContext,
                      onExpand: widget.onExpand,
                      onSheetDragStart: _handleHeaderDragStart,
                      onSheetDragUpdate: _handleHeaderDragUpdate,
                      onSheetDragEnd: _handleHeaderDragEnd,
                    );
                  },
                ),
              ),
            ),
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
