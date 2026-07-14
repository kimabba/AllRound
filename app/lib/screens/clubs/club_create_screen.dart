import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

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
  final _monthlyFee = TextEditingController();
  Uint8List? _logoBytes;
  String _logoExtension = 'jpg';
  String _logoContentType = 'image/jpeg';
  final List<_PendingIntroImage> _introImages = [];
  final Set<String> _meetingDays = {};
  String? _genderPreference;
  int _step = 0;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _region.dispose();
    _address.dispose();
    _contact.dispose();
    _website.dispose();
    _description.dispose();
    _monthlyFee.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_validateBasicStep()) {
      setState(() => _step = 0);
      return;
    }
    if (!(_formKey.currentState?.validate() ?? true)) return;
    setState(() => _submitting = true);
    try {
      final warnings = <String>[];
      String? logoUrl;
      if (_logoBytes != null) {
        try {
          logoUrl = await ref.read(apiProvider).uploadClubLogo(
                bytes: _logoBytes!,
                extension: _logoExtension,
                contentType: _logoContentType,
              );
        } catch (_) {
          warnings.add('클럽 로고 업로드에 실패해 로고 없이 제출했습니다.');
        }
      }
      final introImageUrls = <String>[];
      for (final image in _introImages) {
        try {
          introImageUrls.add(
            await ref.read(apiProvider).uploadClubIntroImage(
                  bytes: image.bytes,
                  extension: image.extension,
                  contentType: image.contentType,
                ),
          );
        } catch (_) {
          if (!warnings.contains('소개 사진 업로드에 실패해 사진 없이 제출했습니다.')) {
            warnings.add('소개 사진 업로드에 실패해 사진 없이 제출했습니다.');
          }
        }
      }
      final fee = int.tryParse(_monthlyFee.text.trim());
      await ref.read(apiProvider).createClub(
            sport: _sport,
            name: _name.text.trim(),
            region: _region.text.trim(),
            address: _address.text.trim(),
            logoUrl: logoUrl,
            contact: _contact.text.trim(),
            website: _website.text.trim(),
            description: _description.text.trim(),
            introImageUrls: introImageUrls,
            meetingDays: _meetingDays.toList(),
            monthlyFee: fee,
            genderPreference: _genderPreference,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              warnings.isEmpty
                  ? '클럽 생성 요청이 제출되었습니다. 관리자 승인 후 활성화됩니다.'
                  : '클럽 생성 요청은 제출되었습니다. ${warnings.join(' ')}',
            ),
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

  bool _validateBasicStep() {
    if (_name.text.trim().isEmpty) {
      _formKey.currentState?.validate();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('클럽명을 입력해주세요.')),
      );
      return false;
    }
    return true;
  }

  void _goNext() {
    if (_step == 0 && !_validateBasicStep()) return;
    FocusScope.of(context).unfocus();
    setState(() => _step = (_step + 1).clamp(0, 2).toInt());
  }

  void _goPrevious() {
    FocusScope.of(context).unfocus();
    setState(() => _step = (_step - 1).clamp(0, 2).toInt());
  }

  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 768,
      maxHeight: 768,
      imageQuality: 86,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final extension = _extensionFromName(picked.name);
    if (!mounted) return;
    setState(() {
      _logoBytes = bytes;
      _logoExtension = extension;
      _logoContentType = _contentTypeForExtension(extension);
    });
  }

  Future<void> _showLogoSheet() async {
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: AppRadius.pill,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _SheetActionRow(
                  icon: Icons.photo_library_rounded,
                  label: '앨범에서 로고 선택',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickLogo();
                  },
                ),
                if (_logoBytes != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _SheetActionRow(
                    icon: Icons.delete_outline_rounded,
                    label: '로고 삭제',
                    accentColor: cs.error,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      setState(() => _logoBytes = null);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickIntroImages() async {
    final remaining = 5 - _introImages.length;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('소개 사진은 최대 5장까지 추가할 수 있습니다.')),
      );
      return;
    }

    final picked = await ImagePicker().pickMultiImage(
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 86,
    );
    if (picked.isEmpty) return;

    final nextImages = <_PendingIntroImage>[];
    for (final image in picked.take(remaining)) {
      final extension = _extensionFromName(image.name);
      nextImages.add(
        _PendingIntroImage(
          bytes: await image.readAsBytes(),
          extension: extension,
          contentType: _contentTypeForExtension(extension),
        ),
      );
    }

    if (!mounted) return;
    setState(() => _introImages.addAll(nextImages));
    if (picked.length > remaining) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('소개 사진은 최대 5장까지만 추가했습니다.')),
      );
    }
  }

  Future<void> _showRegionPicker() async {
    final selected = await showModalBottomSheet<_RegionOption>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder: (_) => _RegionPickerSheet(selectedRegion: _region.text.trim()),
    );
    if (selected == null) return;
    setState(() {
      if (_region.text.trim() != selected.label) {
        _address.clear();
      }
      _region.text = selected.label;
    });
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
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxl,
            vertical: AppSpacing.lg,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ClubCreateStepHeader(step: _step),
                    const SizedBox(height: AppSpacing.lg),
                    if (_step == 0)
                      _BasicClubStep(
                        sport: _sport,
                        sportsToShow: sportsToShow,
                        logoBytes: _logoBytes,
                        name: _name,
                        region: _region,
                        address: _address,
                        onLogoTap: _showLogoSheet,
                        onSportChanged: (sport) =>
                            setState(() => _sport = sport),
                        onRegionTap: _showRegionPicker,
                      )
                    else if (_step == 1)
                      _OperationClubStep(
                        contact: _contact,
                        website: _website,
                        monthlyFee: _monthlyFee,
                        meetingDays: _meetingDays,
                        genderPreference: _genderPreference,
                        onMeetingDayChanged: (day, selected) => setState(() {
                          if (selected) {
                            _meetingDays.add(day);
                          } else {
                            _meetingDays.remove(day);
                          }
                        }),
                        onGenderChanged: (value) =>
                            setState(() => _genderPreference = value),
                      )
                    else
                      _IntroClubStep(
                        description: _description,
                        introImages: _introImages,
                        onAddIntroImages: _pickIntroImages,
                        onRemoveIntroImage: (index) => setState(() {
                          _introImages.removeAt(index);
                        }),
                      ),
                    if (_step == 2) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer.withValues(alpha: 0.5),
                          borderRadius: AppRadius.card,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: cs.onSecondaryContainer,
                              size: 18,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                '클럽 생성 요청은 관리자 검토 후 승인됩니다.\n승인 전까지는 다른 사용자에게 노출되지 않습니다.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: cs.onSecondaryContainer,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    _ClubCreateStepActions(
                      step: _step,
                      submitting: _submitting,
                      onPrevious: _goPrevious,
                      onNext: _goNext,
                      onSubmit: _submit,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _extensionFromName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return 'jpg';
  final ext = name.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'png' => 'png',
    'webp' => 'webp',
    'jpeg' => 'jpg',
    'jpg' => 'jpg',
    _ => 'jpg',
  };
}

String _contentTypeForExtension(String extension) {
  return switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}

class _ClubCreateStepHeader extends StatelessWidget {
  const _ClubCreateStepHeader({required this.step});

  final int step;

  static const _titles = ['기본 정보', '운영 정보', '소개 작성'];
  static const _messages = [
    '클럽을 찾고 구분하는 데 필요한 정보입니다.',
    '연락처, 회비, 정기 모임 조건을 정리합니다.',
    '가입 전 확인할 소개글과 사진을 추가합니다.',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final progress = (step + 1) / 3;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${step + 1}/3',
                style: tt.labelLarge?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  borderRadius: AppRadius.pill,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _titles[step],
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _messages[step],
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _BasicClubStep extends StatelessWidget {
  const _BasicClubStep({
    required this.sport,
    required this.sportsToShow,
    required this.logoBytes,
    required this.name,
    required this.region,
    required this.address,
    required this.onLogoTap,
    required this.onSportChanged,
    required this.onRegionTap,
  });

  final String sport;
  final List<String> sportsToShow;
  final Uint8List? logoBytes;
  final TextEditingController name;
  final TextEditingController region;
  final TextEditingController address;
  final VoidCallback onLogoTap;
  final ValueChanged<String> onSportChanged;
  final VoidCallback onRegionTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LogoPickerCard(
          sport: sport,
          logoBytes: logoBytes,
          onTap: onLogoTap,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('종목', style: tt.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        if (sportsToShow.length == 1)
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
              style: tt.titleMedium,
            ),
          )
        else
          SegmentedButton<String>(
            segments: sportsToShow
                .map(
                  (value) => ButtonSegment(
                    value: value,
                    label: Text(sportLabelFromString(value)),
                  ),
                )
                .toList(),
            selected: {sport},
            onSelectionChanged: (selected) => onSportChanged(selected.first),
          ),
        const SizedBox(height: AppSpacing.lg),
        TextFormField(
          controller: name,
          decoration: const InputDecoration(
            labelText: '클럽명 *',
            hintText: '예: 광주 테니스 클럽',
          ),
          validator: (value) =>
              (value == null || value.trim().isEmpty) ? '클럽명은 필수입니다' : null,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: region,
          readOnly: true,
          onTap: onRegionTap,
          decoration: const InputDecoration(
            labelText: '지역',
            hintText: '활동 지역 선택',
            prefixIcon: Icon(Icons.map_outlined),
            suffixIcon: Icon(Icons.keyboard_arrow_down_rounded),
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: address,
          decoration: const InputDecoration(
            labelText: '활동 장소',
            hintText: '예: 서울 송파구 올림픽로 25 잠실 풋살파크',
            prefixIcon: Icon(Icons.place_outlined),
          ),
          textInputAction: TextInputAction.next,
        ),
      ],
    );
  }
}

class _OperationClubStep extends StatelessWidget {
  const _OperationClubStep({
    required this.contact,
    required this.website,
    required this.monthlyFee,
    required this.meetingDays,
    required this.genderPreference,
    required this.onMeetingDayChanged,
    required this.onGenderChanged,
  });

  final TextEditingController contact;
  final TextEditingController website;
  final TextEditingController monthlyFee;
  final Set<String> meetingDays;
  final String? genderPreference;
  final void Function(String day, bool selected) onMeetingDayChanged;
  final ValueChanged<String?> onGenderChanged;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: contact,
          decoration: const InputDecoration(
            labelText: '연락처',
            hintText: '전화번호 또는 카카오 링크 등',
          ),
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: website,
          decoration: const InputDecoration(
            labelText: '웹사이트 / SNS',
            hintText: 'https://',
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('정기 모임 요일', style: tt.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          children: ['월', '화', '수', '목', '금', '토', '일']
              .map(
                (day) => FilterChip(
                  label: Text(day),
                  selected: meetingDays.contains(day),
                  onSelected: (selected) => onMeetingDayChanged(day, selected),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: monthlyFee,
          decoration: const InputDecoration(
            labelText: '월 회비 (원)',
            hintText: '예: 30000',
          ),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('성별 선호', style: tt.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<String?>(
          segments: const [
            ButtonSegment(value: null, label: Text('무관')),
            ButtonSegment(value: 'mixed', label: Text('혼성')),
            ButtonSegment(value: 'male', label: Text('남성')),
            ButtonSegment(value: 'female', label: Text('여성')),
          ],
          selected: {genderPreference},
          onSelectionChanged: (selected) => onGenderChanged(selected.first),
        ),
      ],
    );
  }
}

class _IntroClubStep extends StatelessWidget {
  const _IntroClubStep({
    required this.description,
    required this.introImages,
    required this.onAddIntroImages,
    required this.onRemoveIntroImage,
  });

  final TextEditingController description;
  final List<_PendingIntroImage> introImages;
  final VoidCallback onAddIntroImages;
  final ValueChanged<int> onRemoveIntroImage;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextFormField(
          controller: description,
          decoration: const InputDecoration(
            labelText: '클럽 소개',
            hintText: '클럽 소개, 활동 내용, 가입 조건 등',
            alignLabelWithHint: true,
          ),
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          minLines: 5,
          maxLines: 5,
        ),
        const SizedBox(height: AppSpacing.md),
        _IntroPhotoPicker(
          images: introImages,
          onAdd: onAddIntroImages,
          onRemove: onRemoveIntroImage,
        ),
      ],
    );
  }
}

class _ClubCreateStepActions extends StatelessWidget {
  const _ClubCreateStepActions({
    required this.step,
    required this.submitting,
    required this.onPrevious,
    required this.onNext,
    required this.onSubmit,
  });

  final int step;
  final bool submitting;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final isLastStep = step == 2;
    return Row(
      children: [
        if (step > 0) ...[
          Expanded(
            child: OutlinedButton(
              onPressed: submitting ? null : onPrevious,
              child: const Text('이전'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: submitting ? null : (isLastStep ? onSubmit : onNext),
            child: submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(isLastStep ? '생성 요청 제출' : '다음'),
          ),
        ),
      ],
    );
  }
}

class _PendingIntroImage {
  const _PendingIntroImage({
    required this.bytes,
    required this.extension,
    required this.contentType,
  });

  final Uint8List bytes;
  final String extension;
  final String contentType;
}

class _IntroPhotoPicker extends StatelessWidget {
  const _IntroPhotoPicker({
    required this.images,
    required this.onAdd,
    required this.onRemove,
  });

  final List<_PendingIntroImage> images;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '소개 사진',
                      style:
                          tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '클럽 분위기를 보여주는 사진을 최대 5장 추가하세요.',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: images.length >= 5 ? null : onAdd,
                icon: const Icon(Icons.add_photo_alternate_rounded),
                tooltip: '소개 사진 추가',
              ),
            ],
          ),
          if (images.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) => _IntroPhotoThumb(
                  image: images[index],
                  onRemove: () => onRemove(index),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _IntroPhotoThumb extends StatelessWidget {
  const _IntroPhotoThumb({
    required this.image,
    required this.onRemove,
  });

  final _PendingIntroImage image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Container(
          width: 96,
          height: 96,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Image.memory(image.bytes, fit: BoxFit.cover),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: Material(
            color: cs.scrim.withValues(alpha: 0.62),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onRemove,
              customBorder: const CircleBorder(),
              child: const SizedBox(
                width: 28,
                height: 28,
                child: Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LogoPickerCard extends StatelessWidget {
  const _LogoPickerCard({
    required this.sport,
    required this.logoBytes,
    required this.onTap,
  });

  final String sport;
  final Uint8List? logoBytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final accent = sport == 'tennis' ? cs.tertiary : cs.secondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 72,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: logoBytes == null
                  ? Icon(Icons.add_photo_alternate_rounded,
                      color: accent, size: 30)
                  : Image.memory(logoBytes!, fit: BoxFit.cover),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    logoBytes == null ? '클럽 로고 추가' : '클럽 로고 선택됨',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '정사각형 이미지가 가장 깔끔하게 보여요.',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _SheetActionRow extends StatelessWidget {
  const _SheetActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accentColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = accentColor ?? cs.onSurface;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      tileColor: cs.surfaceContainerLow,
      onTap: onTap,
    );
  }
}

class _RegionOption {
  const _RegionOption(this.label);

  final String label;
}

class _RegionPickerSheet extends StatelessWidget {
  const _RegionPickerSheet({required this.selectedRegion});

  final String selectedRegion;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.42,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: AppRadius.pill,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '활동 지역 선택',
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '클럽이 주로 활동하는 시·도를 선택하세요.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final option in _regionOptions) ...[
              ListTile(
                onTap: () => Navigator.pop(context, option),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xs,
                ),
                title: Text(
                  option.label,
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                trailing: selectedRegion == option.label
                    ? Icon(Icons.check_rounded, color: cs.primary)
                    : const Icon(Icons.chevron_right_rounded),
                tileColor: cs.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        );
      },
    );
  }
}

final _regionOptions = [
  for (final code in regionCodes) _RegionOption(regionLabel(code)),
];
