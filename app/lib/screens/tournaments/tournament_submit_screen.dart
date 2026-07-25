import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../state/providers.dart';
import '../../testing/e2e_keys.dart';
import '../../theme/tokens.dart';
import '../../utils/club_image_upload.dart';
import '../../utils/grade_labels.dart';
import '../../widgets/app_buttons.dart';

class TournamentSubmitScreen extends ConsumerStatefulWidget {
  const TournamentSubmitScreen({super.key});

  @override
  ConsumerState<TournamentSubmitScreen> createState() =>
      _TournamentSubmitScreenState();
}

class _TournamentSubmitScreenState
    extends ConsumerState<TournamentSubmitScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _organizer = TextEditingController();
  final _region = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();
  final _sourceUrl = TextEditingController();
  PreparedClubImage? _posterImage;
  Sport _sport = Sport.tennis;
  String _tennisOrg = 'gj'; // 테니스 주최 협회
  DateTime? _startDate;
  final Set<String> _grades = {}; // eligible_grades ({org}_{div} 코드)
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _organizer.dispose();
    _region.dispose();
    _location.dispose();
    _description.dispose();
    _sourceUrl.dispose();
    super.dispose();
  }

  Future<void> _pickPoster() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      maxHeight: 2400,
      imageQuality: 88,
    );
    if (picked == null) return;
    try {
      final image = await prepareClubImage(picked);
      if (image.bytes.lengthInBytes > 10 * 1024 * 1024) {
        throw const ClubImagePreparationException(
          '포스터 사진은 10MB 이하여야 합니다.',
        );
      }
      if (!mounted) return;
      setState(() {
        _posterImage = image;
        _error = null;
      });
    } on ClubImagePreparationException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: _startDate ?? now,
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_startDate == null) {
      setState(() => _error = '시작일을 선택하세요');
      return;
    }
    if (_grades.isEmpty) {
      setState(() => _error = '출전 가능 등급을 1개 이상 선택하세요');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final posterUrl = _posterImage == null
          ? null
          : await ref.read(apiProvider).uploadTournamentPoster(
                bytes: _posterImage!.bytes,
                extension: _posterImage!.extension,
                contentType: _posterImage!.contentType,
              );
      final gradeList = _grades.toList();
      await ref.read(apiProvider).submitTournament({
        'sport': sportToString(_sport),
        'title': _title.text.trim(),
        if (_organizer.text.trim().isNotEmpty)
          'organizer': _organizer.text.trim(),
        if (_description.text.trim().isNotEmpty)
          'description': _description.text.trim(),
        'start_date': _startDate!.toIso8601String().substring(0, 10),
        if (_region.text.trim().isNotEmpty) 'region': _region.text.trim(),
        if (_location.text.trim().isNotEmpty) 'location': _location.text.trim(),
        'eligible_grades': gradeList,
        if (_sport == Sport.tennis)
          'division_label_local': formatEligibleGrades(gradeList),
        if (_sourceUrl.text.trim().isNotEmpty)
          'source_url': _sourceUrl.text.trim(),
        if (posterUrl != null) 'poster_url': posterUrl,
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('제보 완료. 관리자 승인 후 노출됩니다.')));
        context.pop();
      }
    } catch (_) {
      setState(
        () => _error = '제보를 저장하지 못했습니다. 연결 상태를 확인한 뒤 다시 시도해 주세요.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // 테니스 협회 선택 목록 (제보에서 자주 쓰이는 협회만)
  static const _tennisOrgOptions = <(String, String)>[
    ('gj', '광주협회 (GJTA)'),
    ('jn', '전남협회 (JNTA)'),
    ('kta', 'KTA'),
    ('kata', 'KATA'),
    ('ktfs', 'KTFS'),
    ('kstf', 'KSTF (시니어)'),
    ('local', '지역/클럽 자체'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      key: AllRoundE2EKeys.tournamentSubmitScreen,
      appBar: AppBar(title: const Text('대회 정보 제보')),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: AppPrimaryButton(
          label: '제보하기',
          loading: _busy,
          onPressed: _submit,
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.xxxl,
          ),
          children: [
            Text('알고 있는 대회를 알려주세요', style: tt.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '공식 공고를 확인한 뒤 등록합니다. 필수 정보만 입력해도 괜찮아요.',
              style: tt.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: cs.outlineVariant),
                  bottom: BorderSide(color: cs.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '제보된 대회는 관리자 승인 후 모든 사용자에게 노출됩니다.',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            const _SectionTitle('기본 정보'),
            const SizedBox(height: AppSpacing.md),

            // 종목 선택
            _Label('종목 *'),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<Sport>(
              segments: [
                ButtonSegment(
                  value: Sport.tennis,
                  icon: const Icon(Icons.sports_tennis_rounded),
                  label: Text(sportLabel(Sport.tennis)),
                ),
                ButtonSegment(
                  value: Sport.futsal,
                  icon: const Icon(Icons.sports_soccer_rounded),
                  label: Text(sportLabel(Sport.futsal)),
                ),
              ],
              selected: {_sport},
              onSelectionChanged: (v) {
                if (v.isEmpty) return;
                setState(() {
                  _sport = v.first;
                  _grades.clear();
                  _tennisOrg = 'gj';
                });
              },
            ),
            const SizedBox(height: AppSpacing.lg),

            TextFormField(
              controller: _title,
              decoration: _inputDeco('대회명 *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '필수 항목입니다' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _organizer, decoration: _inputDeco('주최')),
            const SizedBox(height: AppSpacing.xxl),

            const _SectionTitle('장소 및 일정'),
            const SizedBox(height: AppSpacing.md),

            // 날짜 선택
            _Label('시작일 *'),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _pickDate,
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                minimumSize: const Size.fromHeight(AppSizes.control),
              ),
              icon: const Icon(Icons.calendar_today_rounded, size: 18),
              label: Text(
                _startDate == null
                    ? '날짜를 선택하세요'
                    : DateFormat(
                        'yyyy년 M월 d일 (E)',
                        'ko',
                      ).format(_startDate!),
                style: tt.bodyMedium?.copyWith(
                  color: _startDate == null ? cs.onSurfaceVariant : null,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            TextFormField(
              controller: _region,
              decoration: _inputDeco('지역 (시·도)'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _location,
              decoration: _inputDeco('상세 장소'),
            ),
            const SizedBox(height: AppSpacing.xxl),

            const _SectionTitle('참가 조건'),
            const SizedBox(height: AppSpacing.md),

            // 테니스: 협회 선택 → 부서 선택 / 풋살: 등급 선택
            if (_sport == Sport.tennis) ...[
              _Label('주최 협회 *'),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                // controlled dropdown: 협회 변경 시 setState 로 즉시 반영돼야 하므로
                // value 유지 (initialValue 는 최초값만 적용돼 회귀 발생).
                // ignore: deprecated_member_use
                value: _tennisOrg,
                decoration: _inputDeco('협회 선택'),
                items: _tennisOrgOptions
                    .map(
                      (e) => DropdownMenuItem(value: e.$1, child: Text(e.$2)),
                    )
                    .toList(),
                onChanged: (v) => setState(() {
                  _tennisOrg = v!;
                  _grades.clear();
                }),
              ),
              const SizedBox(height: AppSpacing.lg),
              _Label('출전 부서 * (복수 선택 가능)'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final d in divisionsForOrg(_tennisOrg))
                    FilterChip(
                      label: Text(d.label),
                      selected: _grades.contains(d.code),
                      onSelected: (s) => setState(() {
                        s ? _grades.add(d.code) : _grades.remove(d.code);
                      }),
                      selectedColor: cs.primaryContainer,
                      checkmarkColor: cs.onPrimaryContainer,
                    ),
                ],
              ),
            ] else ...[
              _Label('출전 가능 등급 *'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final g in gradesFor(_sport))
                    FilterChip(
                      label: Text(gradeLabel(g)),
                      selected: _grades.contains(g),
                      onSelected: (s) => setState(() {
                        s ? _grades.add(g) : _grades.remove(g);
                      }),
                      selectedColor: cs.primaryContainer,
                      checkmarkColor: cs.onPrimaryContainer,
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),

            const _SectionTitle('추가 정보'),
            const SizedBox(height: AppSpacing.md),

            TextFormField(
              controller: _description,
              decoration: _inputDeco('대회 설명'),
              maxLines: 4,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _sourceUrl,
              decoration: _inputDeco('원본 공고 URL'),
              keyboardType: TextInputType.url,
              validator: _optionalHttpUrlValidator,
            ),
            const SizedBox(height: AppSpacing.md),
            if (_posterImage == null)
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickPoster,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('포스터 사진 선택 (선택)'),
              )
            else
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: AppRadius.card,
                    child: Image.memory(
                      _posterImage!.bytes,
                      width: double.infinity,
                      height: 240,
                      fit: BoxFit.contain,
                    ),
                  ),
                  Positioned(
                    top: AppSpacing.xs,
                    right: AppSpacing.xs,
                    child: IconButton.filled(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _posterImage = null),
                      tooltip: '포스터 제거',
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ],
              ),

            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: cs.error),
                    bottom: BorderSide(color: cs.error),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: cs.error,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _error!,
                        style: tt.bodySmall?.copyWith(color: cs.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xxxl),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String label) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: AppRadius.card),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
      );

  String? _optionalHttpUrlValidator(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return '올바른 URL을 입력해주세요';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'http:// 또는 https:// 링크만 사용할 수 있어요';
    }
    return null;
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium);
  }
}
