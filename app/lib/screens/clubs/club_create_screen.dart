import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/venue.dart';
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
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      String? logoUrl;
      if (_logoBytes != null) {
        logoUrl = await ref.read(apiProvider).uploadClubLogo(
              bytes: _logoBytes!,
              extension: _logoExtension,
              contentType: _logoContentType,
            );
      }
      final introImageUrls = <String>[];
      for (final image in _introImages) {
        introImageUrls.add(
          await ref.read(apiProvider).uploadClubIntroImage(
                bytes: image.bytes,
                extension: image.extension,
                contentType: image.contentType,
              ),
        );
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

  Future<void> _showAddressPicker() async {
    final selected = await showModalBottomSheet<_ClubAddressOption>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder: (_) => _AddressPickerSheet(
        sport: _sport,
        region: _region.text.trim().isEmpty ? null : _region.text.trim(),
      ),
    );
    if (selected == null) return;
    if (selected.custom) {
      await _showCustomAddressDialog();
      return;
    }
    setState(() {
      _region.text = selected.region;
      _address.text = selected.address;
    });
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

  Future<void> _showCustomAddressDialog() async {
    final region = TextEditingController(text: _region.text);
    final address = TextEditingController(text: _address.text);
    final result = await showDialog<_ClubAddressOption>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('주소 직접 입력'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: region,
              decoration: const InputDecoration(
                labelText: '지역',
                hintText: '예: 서울',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: address,
              decoration: const InputDecoration(
                labelText: '활동 장소 주소',
                hintText: '예: 송파구 올림픽로 ...',
              ),
              minLines: 1,
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              _ClubAddressOption(
                region: region.text.trim(),
                address: address.text.trim(),
                label: '직접 입력',
              ),
            ),
            child: const Text('적용'),
          ),
        ],
      ),
    );
    region.dispose();
    address.dispose();
    if (result == null) return;
    setState(() {
      _region.text = result.region;
      _address.text = result.address;
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
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _LogoPickerCard(
              sport: _sport,
              logoBytes: _logoBytes,
              onTap: _showLogoSheet,
            ),
            const SizedBox(height: AppSpacing.lg),

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
              readOnly: true,
              onTap: _showRegionPicker,
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
              controller: _address,
              readOnly: true,
              onTap: _showAddressPicker,
              decoration: const InputDecoration(
                labelText: '주소',
                hintText: '주요 활동 장소 선택',
                prefixIcon: Icon(Icons.place_outlined),
                suffixIcon: Icon(Icons.search_rounded),
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

            // 정기 모임 요일
            Text('정기 모임 요일', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              children: ['월', '화', '수', '목', '금', '토', '일']
                  .map((d) => FilterChip(
                        label: Text(d),
                        selected: _meetingDays.contains(d),
                        onSelected: (v) => setState(() {
                          if (v) {
                            _meetingDays.add(d);
                          } else {
                            _meetingDays.remove(d);
                          }
                        }),
                      ))
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.md),

            TextFormField(
              controller: _monthlyFee,
              decoration: const InputDecoration(
                labelText: '월 회비 (원)',
                hintText: '예: 30000',
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.md),

            // 성별 선호
            Text('성별 선호', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<String?>(
              segments: const [
                ButtonSegment(value: null, label: Text('무관')),
                ButtonSegment(value: 'mixed', label: Text('혼성')),
                ButtonSegment(value: 'male', label: Text('남성')),
                ButtonSegment(value: 'female', label: Text('여성')),
              ],
              selected: {_genderPreference},
              onSelectionChanged: (s) =>
                  setState(() => _genderPreference = s.first),
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
            const SizedBox(height: AppSpacing.md),
            _IntroPhotoPicker(
              images: _introImages,
              onAdd: _pickIntroImages,
              onRemove: (index) => setState(() {
                _introImages.removeAt(index);
              }),
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

class _ClubAddressOption {
  const _ClubAddressOption({
    required this.region,
    required this.address,
    required this.label,
    this.custom = false,
  });

  final String region;
  final String address;
  final String label;
  final bool custom;
}

class _RegionOption {
  const _RegionOption({
    required this.label,
    required this.searchRegion,
  });

  final String label;
  final String searchRegion;
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

class _AddressPickerSheet extends ConsumerStatefulWidget {
  const _AddressPickerSheet({
    required this.sport,
    required this.region,
  });

  final String sport;
  final String? region;

  @override
  ConsumerState<_AddressPickerSheet> createState() =>
      _AddressPickerSheetState();
}

class _AddressPickerSheetState extends ConsumerState<_AddressPickerSheet> {
  final _query = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  String? _error;
  List<Venue> _venues = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadVenues());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadVenues() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);
      final region = _searchRegionForLabel(widget.region);
      final query = _query.text.trim();
      var venues = await api.searchVenues(
        sport: widget.sport,
        region: region,
        query: query,
        limit: 40,
      );
      if (query.isNotEmpty && venues.isEmpty) {
        final regionalVenues = await api.searchVenues(
          sport: widget.sport,
          region: region,
          limit: 120,
        );
        venues = _rankSimilarVenues(regionalVenues, query);
      }
      if (!mounted) return;
      setState(() {
        _venues = venues;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _venues = const [];
        _loading = false;
        _error = '구장 정보를 불러오지 못했습니다. 직접 입력으로 계속 진행할 수 있습니다.';
      });
    }
  }

  void _scheduleSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) unawaited(_loadVenues());
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final selectedRegion = widget.region;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.42,
      maxChildSize: 0.92,
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
              '활동 장소 선택',
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              selectedRegion == null
                  ? '구장명 또는 주소로 검색하세요. 지역을 먼저 고르면 더 정확합니다.'
                  : '$selectedRegion 지역의 구장명 또는 주소로 검색하세요.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _query,
              onChanged: _scheduleSearch,
              decoration: const InputDecoration(
                hintText: '예: 잠실, 송파, 풋살파크',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _loadVenues(),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  _error!,
                  style: tt.bodySmall?.copyWith(color: cs.error),
                ),
              )
            else if (_venues.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  '검색 결과가 없습니다. 장소명을 직접 입력해 주세요.',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              )
            else
              for (final venue in _venues) ...[
                _AddressOptionTile(option: _optionFromVenue(venue)),
                const SizedBox(height: AppSpacing.sm),
              ],
            if (!_loading && _venues.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                '전국 구장 데이터 기준으로 표시됩니다.',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(
                context,
                const _ClubAddressOption(
                  region: '',
                  address: '',
                  label: '직접 입력',
                  custom: true,
                ),
              ),
              icon: const Icon(Icons.edit_location_alt_outlined),
              label: const Text('직접 입력하기'),
            ),
          ],
        );
      },
    );
  }

  _ClubAddressOption _optionFromVenue(Venue venue) {
    final addressParts = [
      venue.region,
      if (venue.address != null && venue.address!.trim().isNotEmpty)
        venue.address!.trim(),
    ];
    return _ClubAddressOption(
      region: _labelForVenueRegion(venue.region),
      address: addressParts.join(' '),
      label: venue.name,
    );
  }
}

class _AddressOptionTile extends StatelessWidget {
  const _AddressOptionTile({required this.option});

  final _ClubAddressOption option;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ListTile(
      onTap: () => Navigator.pop(context, option),
      leading: CircleAvatar(
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        child: const Icon(Icons.place_outlined, size: 19),
      ),
      title: Text(
        option.label,
        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
      subtitle: Text('${option.region} · ${option.address}'),
      trailing: const Icon(Icons.chevron_right_rounded),
      tileColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}

const _regionOptions = [
  _RegionOption(label: '서울', searchRegion: '서울시'),
  _RegionOption(label: '경기', searchRegion: '경기도'),
  _RegionOption(label: '인천', searchRegion: '인천시'),
  _RegionOption(label: '부산', searchRegion: '부산시'),
  _RegionOption(label: '울산', searchRegion: '울산시'),
  _RegionOption(label: '경남', searchRegion: '경상남도'),
  _RegionOption(label: '대구', searchRegion: '대구시'),
  _RegionOption(label: '경북', searchRegion: '경상북도'),
  _RegionOption(label: '충북', searchRegion: '충청북도'),
  _RegionOption(label: '충남', searchRegion: '충청남도'),
  _RegionOption(label: '전북', searchRegion: '전라북도'),
  _RegionOption(label: '광주', searchRegion: '광주시'),
  _RegionOption(label: '전남', searchRegion: '전라남도'),
  _RegionOption(label: '강원', searchRegion: '강원도'),
  _RegionOption(label: '제주', searchRegion: '제주도'),
];

String? _searchRegionForLabel(String? label) {
  if (label == null || label.isEmpty) return null;
  for (final option in _regionOptions) {
    if (option.label == label) return option.searchRegion;
  }
  return label;
}

String _labelForVenueRegion(String region) {
  for (final option in _regionOptions) {
    if (option.searchRegion == region) return option.label;
  }
  return switch (region) {
    '서울시' => '서울',
    '경기도' => '경기',
    '인천시' => '인천',
    '부산시' => '부산',
    '울산시' => '울산',
    '경상남도' => '경남',
    '대구시' => '대구',
    '경상북도' => '경북',
    '충청북도' => '충북',
    '충청남도' => '충남',
    '전라북도' => '전북',
    '광주시' => '광주',
    '전라남도' => '전남',
    '강원도' => '강원',
    '제주도' => '제주',
    _ => region,
  };
}

List<Venue> _rankSimilarVenues(List<Venue> venues, String query) {
  final normalizedQuery = _normalizeVenueText(query);
  if (normalizedQuery.isEmpty) return const [];
  final queryParts = _venueSearchParts(normalizedQuery);
  final scored = <({Venue venue, int score})>[];

  for (final venue in venues) {
    final haystack = _normalizeVenueText([
      venue.name,
      venue.region,
      venue.address ?? '',
    ].join(' '));
    var score = 0;
    if (haystack.contains(normalizedQuery)) score += 20;
    for (final part in queryParts) {
      if (haystack.contains(part)) {
        score += part.length >= 3 ? 4 : 2;
      }
    }
    if (score > 0) scored.add((venue: venue, score: score));
  }

  scored.sort((a, b) {
    final scoreCompare = b.score.compareTo(a.score);
    if (scoreCompare != 0) return scoreCompare;
    return a.venue.name.compareTo(b.venue.name);
  });
  return scored.map((item) => item.venue).take(20).toList(growable: false);
}

String _normalizeVenueText(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^0-9a-z가-힣]'), '').trim();
}

Set<String> _venueSearchParts(String normalizedQuery) {
  final parts = <String>{};
  final compact = normalizedQuery
      .replaceAll('풋살장', '')
      .replaceAll('풋살파크', '')
      .replaceAll('풋살구장', '')
      .replaceAll('체육공원', '공원')
      .replaceAll('근린공원', '공원');
  if (compact.length >= 2) parts.add(compact);
  for (final token in [normalizedQuery, compact]) {
    for (var size = 2; size <= 4; size++) {
      if (token.length < size) continue;
      for (var i = 0; i <= token.length - size; i++) {
        parts.add(token.substring(i, i + size));
      }
    }
  }
  return parts.where((part) => part.length >= 2).toSet();
}
