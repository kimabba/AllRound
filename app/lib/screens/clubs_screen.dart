import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/tournament.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../utils/grade_labels.dart';
import '../widgets/app_card.dart';
import '../widgets/app_empty_state.dart';

class ClubsScreen extends ConsumerStatefulWidget {
  const ClubsScreen({super.key});

  @override
  ConsumerState<ClubsScreen> createState() => _ClubsScreenState();
}

class _ClubsScreenState extends ConsumerState<ClubsScreen> {
  String _q = '';
  List<Club>? _clubs;
  bool _loading = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await ref.read(apiProvider).searchClubs(sport: ref.read(activeSportProvider), q: _q);
    if (mounted) {
      setState(() {
        _clubs = list;
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activeSportProvider, (_, __) => _load());
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('동호회·클럽')),
      body: Column(
        children: [
          Container(
            color: cs.surfaceContainerLowest,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: '클럽명·설명 검색',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: cs.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: AppRadius.card,
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  ),
                  onChanged: (v) => _q = v,
                  onSubmitted: (_) => _load(),
                ),
              ],
            ),
          ),
          if (_loading) LinearProgressIndicator(color: cs.primary),
          Expanded(
            child: _clubs == null
                ? const SizedBox.shrink()
                : _clubs!.isEmpty
                    ? const AppEmptyState(
                        icon: Icons.groups_rounded,
                        title: '등록된 클럽이 없습니다',
                        description: '다른 검색어나 필터로 시도해 보세요.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.lg,
                        ),
                        itemCount: _clubs!.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _ClubCard(club: _clubs![i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _ClubCard extends StatelessWidget {
  final Club club;
  const _ClubCard({required this.club});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isTennis = club.sport == 'tennis';
    final accentColor = isTennis ? cs.primary : cs.tertiary;

    final meta = [
      sportLabelFromString(club.sport),
      if (club.region != null) club.region,
      if (club.address != null) club.address,
    ].whereType<String>().join(' · ');

    return AppCard(
      onTap: () => _showDetail(context),
      variant: AppCardVariant.elevated,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              isTennis ? Icons.sports_tennis_rounded : Icons.sports_soccer_rounded,
              color: accentColor,
              size: 24,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(club.name, style: tt.titleMedium),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (club.website != null)
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded),
              iconSize: 20,
              color: cs.onSurfaceVariant,
              onPressed: () => launchUrl(
                Uri.parse(club.website!),
                mode: LaunchMode.externalApplication,
              ),
            ),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(club.name, style: tt.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            if (club.contact != null)
              Text(
                '연락처: ${club.contact!}',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            if (club.description != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(club.description!, style: tt.bodyMedium),
            ],
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}
