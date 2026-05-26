import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';

class ClubCreateScreen extends ConsumerStatefulWidget {
  const ClubCreateScreen({super.key});

  @override
  ConsumerState<ClubCreateScreen> createState() => _ClubCreateScreenState();
}

class _ClubCreateScreenState extends ConsumerState<ClubCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  String _sport = 'tennis';
  final _name = TextEditingController();
  final _region = TextEditingController();
  final _address = TextEditingController();
  final _contact = TextEditingController();
  final _website = TextEditingController();
  final _description = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _region.dispose();
    _address.dispose();
    _contact.dispose();
    _website.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await ref.read(apiProvider).createClub(
            sport: _sport,
            name: _name.text.trim(),
            region: _region.text.trim(),
            address: _address.text.trim(),
            contact: _contact.text.trim(),
            website: _website.text.trim(),
            description: _description.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('클럽 생성 요청이 제출되었습니다. 관리자 승인 후 활성화됩니다.'),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('제출 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 사용자가 등록한 종목만 선택지로 노출 (미등록 시에만 양쪽 fallback)
    final registered = (ref.watch(userSportsProvider).valueOrNull ?? [])
        .map((s) => s.sport)
        .toSet()
        .toList()
      ..sort();
    final sportsToShow =
        registered.isEmpty ? const ['tennis', 'futsal'] : registered;
    // 현재 _sport 가 선택지에 없으면 primary(activeSport) 또는 첫 종목으로 보정
    if (!sportsToShow.contains(_sport)) {
      _sport = ref.read(activeSportProvider) ?? sportsToShow.first;
      if (!sportsToShow.contains(_sport)) _sport = sportsToShow.first;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('클럽 만들기')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // 종목 — 사용자가 등록한 종목만 노출
            Text('종목', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            if (sportsToShow.length == 1)
              // 등록 종목이 하나면 선택 없이 고정 표시
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: AppRadius.card,
                ),
                child: Text(
                  sportLabelFromString(sportsToShow.first),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              )
            else
              SegmentedButton<String>(
                segments: sportsToShow
                    .map((s) => ButtonSegment(
                          value: s,
                          label: Text(sportLabelFromString(s)),
                        ))
                    .toList(),
                selected: {_sport},
                onSelectionChanged: (s) => setState(() => _sport = s.first),
              ),
            const SizedBox(height: AppSpacing.lg),

            // 클럽명 (필수)
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '클럽명 *',
                hintText: '예: 광주 테니스 클럽',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '클럽명은 필수입니다' : null,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.md),

            TextFormField(
              controller: _region,
              decoration: const InputDecoration(
                labelText: '지역',
                hintText: '예: 광주광역시',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.md),

            TextFormField(
              controller: _address,
              decoration: const InputDecoration(
                labelText: '주소',
                hintText: '주요 활동 장소',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.md),

            TextFormField(
              controller: _contact,
              decoration: const InputDecoration(
                labelText: '연락처',
                hintText: '전화번호 또는 카카오 링크 등',
              ),
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.md),

            TextFormField(
              controller: _website,
              decoration: const InputDecoration(
                labelText: '웹사이트 / SNS',
                hintText: 'https://',
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.md),

            TextFormField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: '클럽 소개',
                hintText: '클럽 소개, 활동 내용, 가입 조건 등',
                alignLabelWithHint: true,
              ),
              maxLines: 4,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: AppSpacing.xl),

            // 안내 문구
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: cs.secondaryContainer.withValues(alpha: 0.5),
                borderRadius: AppRadius.card,
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: cs.onSecondaryContainer, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '클럽 생성 요청은 관리자 검토 후 승인됩니다.\n승인 전까지는 다른 사용자에게 노출되지 않습니다.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSecondaryContainer,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('생성 요청 제출'),
            ),
          ],
        ),
      ),
    );
  }
}
