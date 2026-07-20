import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/chat_entry_context.dart';
import '../screens/chat_screen.dart';
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
    builder: (sheetContext) {
      return DraggableScrollableSheet(
        initialChildSize: 0.62,
        minChildSize: 0.46,
        maxChildSize: 0.94,
        expand: false,
        snap: true,
        snapSizes: const [0.62, 0.94],
        builder: (sheetBodyContext, scrollController) {
          return ClipRRect(
            borderRadius: AppRadius.sheet,
            child: ChatScreen(
              embedded: true,
              scrollController: scrollController,
              entryContext: entryContext,
              onExpand: (expandedContext) async {
                await Navigator.of(sheetContext).maybePop();
                if (hostContext.mounted) {
                  hostContext.push('/chat', extra: expandedContext);
                }
              },
            ),
          );
        },
      );
    },
  );
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
