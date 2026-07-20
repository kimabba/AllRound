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
        suggestions: const [
          ChatPromptSuggestion(
            label: '참가 가능 여부',
            message: '내 등급과 조건으로 참가할 수 있는지 알려줘',
          ),
          ChatPromptSuggestion(
            label: '신청 준비 정리',
            message: '신청 마감과 준비할 내용을 정리해줘',
          ),
        ],
      );
    }
  }

  if (segments.length >= 2 && segments.first == 'clubs') {
    return ChatEntryContext(
      screenLabel: '현재 클럽',
      entityType: 'club',
      entityId: segments[1],
      suggestions: const [
        ChatPromptSuggestion(
          label: '나와 맞는지 확인',
          message: '내 활동 조건과 잘 맞는 클럽인지 알려줘',
        ),
        ChatPromptSuggestion(
          label: '가입 전 확인할 것',
          message: '가입 전에 확인할 내용을 정리해줘',
        ),
      ],
    );
  }

  if (location.startsWith('/tournaments')) {
    return const ChatEntryContext(
      screenLabel: '대회',
      suggestions: [
        ChatPromptSuggestion(
          label: '내게 맞는 대회 찾기',
          message: '내 등급과 지역에 맞는 대회를 찾아줘',
        ),
        ChatPromptSuggestion(
          label: '이번 달 일정',
          message: '이번 달 참가할 수 있는 대회 일정을 알려줘',
        ),
      ],
    );
  }

  if (location.startsWith('/clubs')) {
    return const ChatEntryContext(
      screenLabel: '클럽',
      suggestions: [
        ChatPromptSuggestion(
          label: '클럽 추천',
          message: '내 지역과 종목에 맞는 클럽을 추천해줘',
        ),
        ChatPromptSuggestion(
          label: '가입 기준',
          message: '클럽 가입 전에 살펴볼 기준을 알려줘',
        ),
      ],
    );
  }

  if (location.startsWith('/rules')) {
    return const ChatEntryContext(
      screenLabel: '룰북',
      suggestions: [
        ChatPromptSuggestion(
          label: '규칙 쉽게 설명',
          message: '헷갈리는 경기 규칙을 쉽게 설명해줘',
        ),
        ChatPromptSuggestion(
          label: '상황별 판정',
          message: '경기 상황을 말하면 판정을 알려줘',
        ),
      ],
    );
  }

  if (location.startsWith('/profile') ||
      location.startsWith('/favorites') ||
      location.startsWith('/notifications') ||
      location.startsWith('/blocked-users') ||
      location.startsWith('/more')) {
    return const ChatEntryContext(
      screenLabel: 'MY',
      suggestions: [
        ChatPromptSuggestion(
          label: '이번 주 활동 정리',
          message: '내가 이번 주에 확인하면 좋은 운동 일정을 정리해줘',
        ),
        ChatPromptSuggestion(
          label: '다음 활동 추천',
          message: '내 운동 정보에 맞는 다음 활동을 추천해줘',
        ),
      ],
    );
  }

  return const ChatEntryContext(
    screenLabel: '오늘',
    suggestions: [
      ChatPromptSuggestion(
        label: '오늘 할 수 있는 것',
        message: '오늘 확인하면 좋은 대회와 클럽 활동을 알려줘',
      ),
      ChatPromptSuggestion(
        label: '내게 맞는 활동',
        message: '내 종목과 지역에 맞는 활동을 추천해줘',
      ),
    ],
  );
}
