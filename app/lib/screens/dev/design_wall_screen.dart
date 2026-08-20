import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';
import 'design_preview_device.dart';
import '../auth/login_screen.dart';
import '../auth/onboarding_screen.dart';
import '../auth/reset_password_screen.dart';
import '../blocked_users_screen.dart';
import '../chat_screen.dart';
import '../clubs/club_detail_screen.dart';
import '../clubs_screen.dart';
import '../favorites_screen.dart';
import '../home_screen.dart';
import '../more_screen.dart';
import '../notifications_screen.dart';
import '../profile_screen.dart';
import '../rankings/my_record_screen.dart';
import '../rankings/rankings_screen.dart';
import '../rules_screen.dart';
import '../tournaments/tournament_detail_screen.dart';
import '../tournaments/tournament_submit_screen.dart';
import '../tournaments/tournaments_screen.dart';

class DesignWallScreen extends ConsumerStatefulWidget {
  const DesignWallScreen({super.key});

  @override
  ConsumerState<DesignWallScreen> createState() => _DesignWallScreenState();
}

class _DesignWallScreenState extends ConsumerState<DesignWallScreen> {
  DesignPreviewDevice _device = DesignPreviewDevice.phone390;
  bool _dark = false;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final sport = ref.watch(sportOverrideProvider) ?? 'tennis';
    final entries = _designScreens
        .where((entry) => entry.matches(_query))
        .toList(growable: false);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLow,
      body: SafeArea(
        child: Column(
          children: [
            _DesignToolbar(
              device: _device,
              dark: _dark,
              sport: sport,
              visibleCount: entries.length,
              onQueryChanged: (value) => setState(() => _query = value),
              onDeviceChanged: (value) => setState(() => _device = value),
              onDarkChanged: (value) => setState(() => _dark = value),
              onSportChanged: (value) {
                ref.read(sportOverrideProvider.notifier).select(value);
              },
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontalPadding = constraints.maxWidth < 700
                      ? AppSpacing.md
                      : AppSpacing.xxl;
                  final displayWidth = math.min(
                    _device.size.width,
                    math.max(
                      1.0,
                      constraints.maxWidth - (horizontalPadding * 2),
                    ),
                  );
                  final scale = displayWidth / _device.size.width;
                  final displayHeight = _device.size.height * scale;
                  final cardHeight = displayHeight + 61;
                  final availableWidth =
                      constraints.maxWidth - (horizontalPadding * 2);
                  final columnCount = math.max(
                    1,
                    ((availableWidth + AppSpacing.xl) /
                            (displayWidth + AppSpacing.xl))
                        .floor(),
                  );
                  final rowCount = (entries.length / columnCount).ceil();

                  if (entries.isEmpty) {
                    return const Center(
                      child: Text('검색 조건에 맞는 화면이 없습니다.'),
                    );
                  }

                  return ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      AppSpacing.xl,
                      horizontalPadding,
                      AppSpacing.xxxl,
                    ),
                    itemCount: rowCount,
                    itemBuilder: (context, rowIndex) {
                      final firstIndex = rowIndex * columnCount;
                      final lastIndex = math.min(
                        firstIndex + columnCount,
                        entries.length,
                      );
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: rowIndex == rowCount - 1 ? 0 : AppSpacing.xl,
                        ),
                        child: SizedBox(
                          height: cardHeight,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var index = firstIndex;
                                  index < lastIndex;
                                  index++) ...[
                                if (index > firstIndex)
                                  const SizedBox(width: AppSpacing.xl),
                                SizedBox(
                                  width: displayWidth,
                                  child: _ScreenPreviewCard(
                                    key: ValueKey(
                                      '${entries[index].route}-${_device.name}-$_dark-$sport',
                                    ),
                                    entry: entries[index],
                                    device: _device,
                                    scale: scale,
                                    dark: _dark,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesignToolbar extends StatelessWidget {
  const _DesignToolbar({
    required this.device,
    required this.dark,
    required this.sport,
    required this.visibleCount,
    required this.onQueryChanged,
    required this.onDeviceChanged,
    required this.onDarkChanged,
    required this.onSportChanged,
  });

  final DesignPreviewDevice device;
  final bool dark;
  final String sport;
  final int visibleCount;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<DesignPreviewDevice> onDeviceChanged;
  final ValueChanged<bool> onDarkChanged;
  final ValueChanged<String> onSportChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const SizedBox(
              width: 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ALLROUND DESIGN',
                    style: TextStyle(
                      color: Color(0xFF3156D8),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    '전체 화면 디자인 월',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                onChanged: onQueryChanged,
                decoration: const InputDecoration(
                  hintText: '화면 또는 경로 검색',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            DropdownButton<DesignPreviewDevice>(
              value: device,
              onChanged: (value) {
                if (value != null) onDeviceChanged(value);
              },
              items: DesignPreviewDevice.values
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(value.label),
                    ),
                  )
                  .toList(growable: false),
            ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('라이트')),
                ButtonSegment(value: true, label: Text('다크')),
              ],
              selected: {dark},
              onSelectionChanged: (value) => onDarkChanged(value.first),
            ),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'tennis',
                  label: Text(sportLabelFromString('tennis')),
                ),
                ButtonSegment(
                  value: 'futsal',
                  label: Text(sportLabelFromString('futsal')),
                ),
              ],
              selected: {sport},
              onSelectionChanged: (value) => onSportChanged(value.first),
            ),
            Text(
              '$visibleCount개 화면',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            Text(
              '카드는 첫 화면 미리보기 · 전체 내용은 열어서 스크롤',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScreenPreviewCard extends StatelessWidget {
  const _ScreenPreviewCard({
    super.key,
    required this.entry,
    required this.device,
    required this.scale,
    required this.dark,
  });

  final _DesignScreen entry;
  final DesignPreviewDevice device;
  final double scale;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final deviceSize = device.size;
    final displaySize = deviceSize * scale;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Column(
          children: [
            SizedBox(
              height: 60,
              child: Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.md,
                  right: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            '${entry.group} · ${entry.route}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.push(
                        device.locationFor(entry.route, dark: dark),
                      ),
                      child: const Text('전체 화면·스크롤'),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: displaySize.width,
              height: displaySize.height,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: deviceSize.width,
                  maxWidth: deviceSize.width,
                  minHeight: deviceSize.height,
                  maxHeight: deviceSize.height,
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: deviceSize.width,
                      height: deviceSize.height,
                      child: Theme(
                        data: dark ? AppTheme.dark() : AppTheme.light(),
                        child: MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            size: deviceSize,
                            padding: device.safeArea,
                            viewPadding: device.safeArea,
                            viewInsets: EdgeInsets.zero,
                          ),
                          child: IgnorePointer(child: entry.build()),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesignScreen {
  const _DesignScreen({
    required this.group,
    required this.title,
    required this.route,
    required this.build,
  });

  final String group;
  final String title;
  final String route;
  final Widget Function() build;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return '$group $title $route'.toLowerCase().contains(normalized);
  }
}

final _designScreens = <_DesignScreen>[
  _DesignScreen(group: '핵심', title: '오늘', route: '/', build: HomeScreen.new),
  _DesignScreen(
    group: '핵심',
    title: '대회',
    route: '/tournaments',
    build: TournamentsScreen.new,
  ),
  _DesignScreen(
    group: '핵심',
    title: '클럽',
    route: '/clubs',
    build: ClubsScreen.new,
  ),
  _DesignScreen(
    group: '핵심',
    title: 'MY',
    route: '/profile',
    build: ProfileScreen.new,
  ),
  _DesignScreen(
    group: '핵심',
    title: 'AI 채팅',
    route: '/chat',
    build: ChatScreen.new,
  ),
  _DesignScreen(
    group: '핵심',
    title: '더보기',
    route: '/more',
    build: MoreScreen.new,
  ),
  _DesignScreen(
    group: '탐색',
    title: '룰북',
    route: '/rules',
    build: RulesScreen.new,
  ),
  _DesignScreen(
    group: '탐색',
    title: '랭킹',
    route: '/rankings',
    build: RankingsScreen.new,
  ),
  _DesignScreen(
    group: '탐색',
    title: '내 경기 기록',
    route: '/rankings/me',
    build: MyRecordScreen.new,
  ),
  _DesignScreen(
    group: '탐색',
    title: '알림',
    route: '/notifications',
    build: NotificationsScreen.new,
  ),
  _DesignScreen(
    group: '탐색',
    title: '관심 목록',
    route: '/favorites',
    build: FavoritesScreen.new,
  ),
  _DesignScreen(
    group: '탐색',
    title: '차단 사용자',
    route: '/blocked-users',
    build: BlockedUsersScreen.new,
  ),
  _DesignScreen(
    group: '인증',
    title: '로그인',
    route: '/login',
    build: LoginScreen.new,
  ),
  _DesignScreen(
    group: '인증',
    title: '온보딩',
    route: '/onboarding',
    build: OnboardingScreen.new,
  ),
  _DesignScreen(
    group: '인증',
    title: '비밀번호 재설정',
    route: '/reset-password',
    build: ResetPasswordScreen.new,
  ),
  _DesignScreen(
    group: '상세',
    title: '대회 상세',
    route: '/tournaments/preview-tennis-1',
    build: () => const TournamentDetailScreen(
      tournamentId: 'preview-tennis-1',
    ),
  ),
  _DesignScreen(
    group: '상세',
    title: '클럽 상세',
    route: '/clubs/preview-tennis-01',
    build: () => ClubDetailScreen(
      club: clubDesignPreviewById('preview-tennis-01')!,
    ),
  ),
  _DesignScreen(
    group: '작성',
    title: '대회 제보',
    route: '/tournaments/submit',
    build: TournamentSubmitScreen.new,
  ),
];
