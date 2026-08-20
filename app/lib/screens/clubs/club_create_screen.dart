import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/place_search_result.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/club_create_draft.dart';
import '../../utils/club_card_colors.dart';
import '../../utils/club_image_upload.dart';
import '../../utils/club_labels.dart';
import '../../utils/grade_labels.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/moderation/ugc_moderation_widgets.dart';

class ClubCreateScreen extends ConsumerStatefulWidget {
  const ClubCreateScreen({super.key, this.initialSport});

  /// 클럽 목록에서 사용자가 마지막으로 고른 종목.
  /// 작성 중인 임시저장이 없다면 새 클럽의 기본 종목으로 사용한다.
  final String? initialSport;

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
  String _feeType = 'monthly';
  double? _addressLatitude;
  double? _addressLongitude;
  Uint8List? _logoBytes;
  String _logoExtension = 'jpg';
  String _logoContentType = 'image/jpeg';
  final List<_PendingIntroImage> _introImages = [];
  final Set<String> _meetingDays = {};
  String _genderPreference = 'mixed';
  String _cardColor = defaultClubCardColor;
  int _step = 0;
  bool _submitting = false;
  String? _submittingLabel;
  Timer? _draftSaveTimer;
  ClubCreateDraftStore? _draftStore;
  String? _draftUserId;
  bool _draftReady = false;
  bool _submitted = false;

  List<TextEditingController> get _draftTextControllers => [
        _name,
        _region,
        _address,
        _contact,
        _website,
        _description,
        _monthlyFee,
      ];

  @override
  void initState() {
    super.initState();
    _sport = resolveClubCreateSport(
      selectedSport: widget.initialSport ?? ref.read(activeSportProvider),
    );
    for (final controller in _draftTextControllers) {
      controller.addListener(_scheduleDraftSave);
    }
    unawaited(_restoreDraft());
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    if (_draftReady && !_submitted) unawaited(_saveDraftNow());
    for (final controller in _draftTextControllers) {
      controller.removeListener(_scheduleDraftSave);
    }
    _name.dispose();
    _region.dispose();
    _address.dispose();
    _contact.dispose();
    _website.dispose();
    _description.dispose();
    _monthlyFee.dispose();
    super.dispose();
  }

  Future<void> _restoreDraft() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;

      final userId = ref.read(supabaseProvider).auth.currentUser?.id;
      final store = ClubCreateDraftStore(preferences);
      final draft = userId == null ? null : store.load(userId);
      _draftStore = store;
      _draftUserId = userId;

      setState(() {
        _sport = resolveClubCreateSport(
          selectedSport: _sport,
          draft: draft,
        );
        if (draft != null && draft.hasUserContent) {
          _name.text = draft.name;
          _region.text = draft.region;
          _address.text = draft.address;
          _addressLatitude = draft.latitude;
          _addressLongitude = draft.longitude;
          _contact.text = draft.contact;
          _website.text = draft.website;
          _description.text = draft.description;
          _monthlyFee.text = draft.monthlyFee;
          _feeType = draft.feeType;
          _meetingDays
            ..clear()
            ..addAll(draft.meetingDays);
          _genderPreference = draft.genderPreference ?? 'mixed';
          _cardColor = draft.cardColor;
          _step = draft.step;
        }
        _draftReady = true;
      });

      if (draft != null && draft.hasUserContent && mounted) {
        final message = draft.hadSelectedImages
            ? '임시저장 내용을 불러왔습니다. 사진은 다시 선택해주세요.'
            : '임시저장 내용을 불러왔습니다.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (_) {
      // 로컬 저장소가 손상돼도 클럽 작성 화면 자체는 계속 사용할 수 있어야 한다.
      if (mounted) setState(() => _draftReady = true);
    }
  }

  ClubCreateDraft _currentDraft() => ClubCreateDraft(
        sport: _sport,
        name: _name.text,
        region: _region.text,
        address: _address.text,
        contact: _contact.text,
        website: _website.text,
        description: _description.text,
        monthlyFee: _monthlyFee.text,
        feeType: _feeType,
        meetingDays: _meetingDays.toList(growable: false),
        genderPreference: _genderPreference,
        cardColor: _cardColor,
        step: _step,
        hadSelectedImages: _logoBytes != null || _introImages.isNotEmpty,
        latitude: _addressLatitude,
        longitude: _addressLongitude,
      );

  void _scheduleDraftSave() {
    if (!_draftReady || _submitted) return;
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(_saveDraftNow());
    });
  }

  Future<void> _saveDraftNow() async {
    final store = _draftStore;
    final userId = _draftUserId;
    if (store == null || userId == null || _submitted) return;

    final draft = _currentDraft();
    try {
      if (draft.hasUserContent) {
        await store.save(userId, draft);
      } else {
        await store.clear(userId);
      }
    } catch (_) {
      // 임시저장 실패가 작성 흐름을 막거나 처리되지 않은 비동기 오류가 되지 않게 한다.
    }
  }

  Future<void> _clearSavedDraft() async {
    _draftSaveTimer?.cancel();
    final store = _draftStore;
    final userId = _draftUserId;
    if (store != null && userId != null) await store.clear(userId);
  }

  Future<void> _showPlaceSearch() async {
    FocusScope.of(context).unfocus();
    final selected = await showModalBottomSheet<PlaceSearchResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _PlaceSearchSheet(
        search: ref.read(apiProvider).searchPlaces,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _address.text = selected.displayText;
      _addressLatitude = selected.latitude;
      _addressLongitude = selected.longitude;
    });
    _scheduleDraftSave();
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('작성 내용 초기화'),
        content: const Text('입력한 내용과 선택한 사진을 모두 지울까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('초기화'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _draftSaveTimer?.cancel();
    setState(() {
      _draftReady = false;
      for (final controller in _draftTextControllers) {
        controller.clear();
      }
      _sport = ref.read(activeSportProvider) ?? 'tennis';
      _addressLatitude = null;
      _addressLongitude = null;
      _logoBytes = null;
      _introImages.clear();
      _meetingDays.clear();
      _feeType = 'monthly';
      _genderPreference = 'mixed';
      _step = 0;
    });
    try {
      await _clearSavedDraft();
    } catch (_) {
      // 초기화는 메모리 상태를 기준으로 완료하고 로컬 저장소 오류는 다음 저장 때 복구한다.
    } finally {
      if (mounted) setState(() => _draftReady = true);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('작성 내용을 초기화했습니다.')),
    );
  }

  void _setSubmittingLabel(String label) {
    if (mounted) setState(() => _submittingLabel = label);
  }

  Future<void> _submit() async {
    // 약관 확인 같은 첫 await 전에 잠가야 빠른 연속 탭이 두 요청을 만들지 않는다.
    if (_submitting || _submitted) return;
    if (!_validateBasicStep()) {
      setState(() => _step = 0);
      return;
    }
    if (!_validateOperationStep()) {
      setState(() => _step = 1);
      return;
    }
    if (!_validateIntroStep()) {
      setState(() => _step = 2);
      return;
    }
    if (!(_formKey.currentState?.validate() ?? true)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _submitting = true;
      _submittingLabel = '권한 확인 중';
    });
    try {
      final allowed = await ensureUgcPermission(
        context,
        ref,
        UgcActionKind.community,
      );
      if (!allowed || !mounted) return;
      _setSubmittingLabel('제출 준비 중');

      String? logoUrl;
      final introImageUrls = <String>[];
      final imageCount = (_logoBytes == null ? 0 : 1) + _introImages.length;
      var uploadedImageCount = 0;
      try {
        if (_logoBytes != null) {
          _setSubmittingLabel(
            '사진 업로드 ${uploadedImageCount + 1}/$imageCount',
          );
          logoUrl = await ref.read(apiProvider).uploadClubLogo(
                bytes: _logoBytes!,
                extension: _logoExtension,
                contentType: _logoContentType,
              );
          uploadedImageCount += 1;
        }
        for (final image in _introImages) {
          _setSubmittingLabel(
            '사진 업로드 ${uploadedImageCount + 1}/$imageCount',
          );
          introImageUrls.add(
            await ref.read(apiProvider).uploadClubIntroImage(
                  bytes: image.bytes,
                  extension: image.extension,
                  contentType: image.contentType,
                ),
          );
          uploadedImageCount += 1;
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('사진 업로드에 실패했습니다. 연결 상태를 확인한 뒤 다시 시도해주세요.'),
            ),
          );
        }
        return;
      }
      _setSubmittingLabel('클럽 생성 요청 중');
      final fee = int.tryParse(_monthlyFee.text.trim());
      double? latitude;
      double? longitude;
      final address = _address.text.trim();
      if (_addressLatitude != null && _addressLongitude != null) {
        latitude = _addressLatitude;
        longitude = _addressLongitude;
      } else if (address.isNotEmpty) {
        try {
          final locations = await Geocoding().locationFromAddress(address);
          if (locations.isNotEmpty) {
            latitude = locations.first.latitude;
            longitude = locations.first.longitude;
          }
        } catch (_) {
          // 주소 좌표 변환 실패가 클럽 생성 자체를 막지 않도록 한다.
        }
      }
      await ref.read(apiProvider).createClub(
            sport: _sport,
            name: _name.text.trim(),
            region: _region.text.trim(),
            address: address,
            logoUrl: logoUrl,
            contact: _contact.text.trim(),
            website: normalizeClubWebsiteInput(_website.text),
            description: _description.text.trim(),
            introImageUrls: introImageUrls,
            meetingDays: _meetingDays.toList(),
            monthlyFee: fee,
            feeType: _feeType,
            genderPreference: _genderPreference,
            cardColor: _cardColor,
            latitude: latitude,
            longitude: longitude,
          );
      _draftSaveTimer?.cancel();
      _submitted = true;
      try {
        await _clearSavedDraft();
      } catch (_) {
        // 클럽 생성 성공 이후 로컬 임시저장 삭제 실패는 제출 결과에 영향을 주지 않는다.
      }
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ugcActionErrorMessage(e, fallback: '클럽 생성 요청을 제출하지 못했습니다.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted && !_submitted) {
        setState(() {
          _submitting = false;
          _submittingLabel = null;
        });
      }
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

  bool _validateOperationStep() {
    final error = clubWebsiteInputError(_website.text) ??
        clubMonthlyFeeInputError(_monthlyFee.text);
    if (error == null) return true;
    _formKey.currentState?.validate();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error)),
    );
    return false;
  }

  bool _validateIntroStep() {
    final error = clubDescriptionInputError(_description.text);
    if (error == null) return true;
    _formKey.currentState?.validate();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error)),
    );
    return false;
  }

  void _goNext() {
    if (_step == 0 && !_validateBasicStep()) return;
    if (_step == 1 && !_validateOperationStep()) return;
    FocusScope.of(context).unfocus();
    setState(() => _step = (_step + 1).clamp(0, 2).toInt());
    _scheduleDraftSave();
  }

  void _goPrevious() {
    FocusScope.of(context).unfocus();
    setState(() => _step = (_step - 1).clamp(0, 2).toInt());
    _scheduleDraftSave();
  }

  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 768,
      maxHeight: 768,
      imageQuality: 86,
    );
    if (picked == null) return;

    final PreparedClubImage image;
    try {
      // 로고는 club-logos(5MB) 로 올라간다 — prepareClubImage 의 기본값과 같다.
      image = await prepareClubImage(picked, maxBytes: clubImageMaxBytes);
    } on ClubImagePreparationException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _logoBytes = image.bytes;
      _logoExtension = image.extension;
      _logoContentType = image.contentType;
    });
    _scheduleDraftSave();
  }

  Future<void> _showLogoSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
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
                      _scheduleDraftSave();
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

    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await ImagePicker().pickMultiImage(
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 86,
    );
    if (picked.isEmpty) return;

    final nextImages = <_PendingIntroImage>[];
    try {
      for (final file in picked.take(remaining)) {
        // 소개 사진 버킷(club-intro-images)은 10MB 까지 받는다.
        final image = await prepareClubImage(
          file,
          maxBytes: clubPhotoMaxBytes,
        );
        nextImages.add(
          _PendingIntroImage(
            bytes: image.bytes,
            extension: image.extension,
            contentType: image.contentType,
          ),
        );
      }
    } on ClubImagePreparationException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() => _introImages.addAll(nextImages));
    _scheduleDraftSave();
    if (picked.length > remaining) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('소개 사진은 최대 5장까지만 추가했습니다.')),
      );
    }
  }

  Future<void> _showRegionPicker() async {
    FocusManager.instance.primaryFocus?.unfocus();
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
        _addressLatitude = null;
        _addressLongitude = null;
      }
      _region.text = selected.label;
    });
    _scheduleDraftSave();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 사용자가 등록한 종목만 선택지로 노출 (미등록 시에만 양쪽 fallback)
    final registered = (ref.watch(userSportsProvider).value ?? [])
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
      appBar: AppBar(
        leading: const AppBackButton(fallbackLocation: '/clubs'),
        title: const Text('클럽 만들기'),
        actions: [
          IconButton(
            onPressed: !_draftReady || _submitting ? null : _confirmReset,
            icon: const Icon(Icons.restart_alt_rounded),
            tooltip: '작성 내용 초기화',
          ),
        ],
      ),
      body: !_draftReady
          ? const Center(child: CircularProgressIndicator())
          : Form(
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
                          const SizedBox(height: AppSpacing.sm),
                          const _ClubDraftNotice(),
                          const SizedBox(height: AppSpacing.lg),
                          if (_step == 0)
                            _BasicClubStep(
                              sport: _sport,
                              sportsToShow: sportsToShow,
                              logoBytes: _logoBytes,
                              name: _name,
                              region: _region,
                              address: _address,
                              cardColor: _cardColor,
                              onLogoTap: _showLogoSheet,
                              onSportChanged: (sport) {
                                setState(() => _sport = sport);
                                _scheduleDraftSave();
                              },
                              onRegionTap: _showRegionPicker,
                              onAddressTap: _showPlaceSearch,
                              onCardColorChanged: (value) {
                                setState(() => _cardColor = value);
                                _scheduleDraftSave();
                              },
                            )
                          else if (_step == 1)
                            _OperationClubStep(
                              contact: _contact,
                              website: _website,
                              monthlyFee: _monthlyFee,
                              feeType: _feeType,
                              meetingDays: _meetingDays,
                              genderPreference: _genderPreference,
                              onMeetingDayChanged: (day, selected) =>
                                  setState(() {
                                if (selected) {
                                  _meetingDays.add(day);
                                } else {
                                  _meetingDays.remove(day);
                                }
                                _scheduleDraftSave();
                              }),
                              onGenderChanged: (value) {
                                setState(() => _genderPreference = value);
                                _scheduleDraftSave();
                              },
                              onFeeTypeChanged: (value) {
                                setState(() => _feeType = value);
                                _scheduleDraftSave();
                              },
                            )
                          else
                            _IntroClubStep(
                              description: _description,
                              introImages: _introImages,
                              onAddIntroImages: _pickIntroImages,
                              onRemoveIntroImage: (index) => setState(() {
                                _introImages.removeAt(index);
                                _scheduleDraftSave();
                              }),
                            ),
                          if (_step == 2) ...[
                            const SizedBox(height: AppSpacing.lg),
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: BoxDecoration(
                                color: cs.secondaryContainer
                                    .withValues(alpha: 0.5),
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
                            submittingLabel: _submittingLabel,
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

class _ClubDraftNotice extends StatelessWidget {
  const _ClubDraftNotice();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.cloud_done_outlined, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            '작성 내용은 이 기기에 자동 저장됩니다. 사진은 제외됩니다.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }
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
    required this.cardColor,
    required this.onLogoTap,
    required this.onSportChanged,
    required this.onRegionTap,
    required this.onAddressTap,
    required this.onCardColorChanged,
  });

  final String sport;
  final List<String> sportsToShow;
  final Uint8List? logoBytes;
  final TextEditingController name;
  final TextEditingController region;
  final TextEditingController address;
  final String cardColor;
  final VoidCallback onLogoTap;
  final ValueChanged<String> onSportChanged;
  final VoidCallback onRegionTap;
  final VoidCallback onAddressTap;
  final ValueChanged<String> onCardColorChanged;

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
          decoration: InputDecoration(
            labelText: '클럽명 *',
            hintText: clubNameHintForSport(sport),
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
          readOnly: true,
          onTap: onAddressTap,
          decoration: const InputDecoration(
            labelText: '활동 장소',
            hintText: '장소명 또는 주소로 검색',
            prefixIcon: Icon(Icons.place_outlined),
            suffixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('클럽 카드 색상', style: tt.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '나의 클럽 카드 배경에 사용돼요.',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final value in clubCardColorChoices)
              Semantics(
                label: '클럽 카드 색상 $value',
                selected: cardColor == value,
                button: true,
                child: InkWell(
                  onTap: () => onCardColorChanged(value),
                  customBorder: const CircleBorder(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: AppSizes.touchTarget,
                    height: AppSizes.touchTarget,
                    decoration: BoxDecoration(
                      color: clubCardColor(value),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: cardColor == value
                            ? cs.onSurface
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: cardColor == value
                        ? const Icon(Icons.check_rounded, color: Colors.white)
                        : null,
                  ),
                ),
              ),
          ],
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
    required this.feeType,
    required this.meetingDays,
    required this.genderPreference,
    required this.onMeetingDayChanged,
    required this.onGenderChanged,
    required this.onFeeTypeChanged,
  });

  final TextEditingController contact;
  final TextEditingController website;
  final TextEditingController monthlyFee;
  final String feeType;
  final Set<String> meetingDays;
  final String genderPreference;
  final void Function(String day, bool selected) onMeetingDayChanged;
  final ValueChanged<String> onGenderChanged;
  final ValueChanged<String> onFeeTypeChanged;

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
          validator: clubWebsiteInputError,
          decoration: const InputDecoration(
            labelText: '웹사이트 / SNS',
            hintText: '예: instagram.com/계정명',
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
        const SizedBox(height: AppSpacing.lg),
        Text('회비 방식', style: tt.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'monthly', label: Text('월회비')),
            ButtonSegment(value: 'per_event', label: Text('1회 참가비')),
          ],
          selected: {feeType},
          onSelectionChanged: (selected) => onFeeTypeChanged(selected.first),
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: monthlyFee,
          validator: clubMonthlyFeeInputError,
          decoration: InputDecoration(
            labelText: feeType == 'per_event' ? '1회 참가비 (원)' : '월회비 (원)',
            hintText: '예: 30000',
          ),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('성별 선호', style: tt.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<String>(
          segments: const [
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
          validator: clubDescriptionInputError,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: const InputDecoration(
            labelText: '클럽 소개',
            hintText: '활동 내용과 가입 조건을 30자 이상 적어주세요',
            alignLabelWithHint: true,
          ),
          maxLength: 2000,
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
    required this.submittingLabel,
    required this.onPrevious,
    required this.onNext,
    required this.onSubmit,
  });

  final int step;
  final bool submitting;
  final String? submittingLabel;
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
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(child: Text(submittingLabel ?? '처리 중')),
                    ],
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
            borderRadius: BorderRadius.circular(AppRadius.sm),
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
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.md),
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
                borderRadius: BorderRadius.circular(AppRadius.sm),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
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
                  borderRadius: BorderRadius.circular(AppRadius.sm),
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

typedef _PlaceSearchCallback = Future<List<PlaceSearchResult>> Function(
  String query,
);

class _PlaceSearchSheet extends StatefulWidget {
  const _PlaceSearchSheet({required this.search});

  final _PlaceSearchCallback search;

  @override
  State<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<_PlaceSearchSheet> {
  final _query = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _searchDebounce;
  int _searchRequest = 0;
  List<PlaceSearchResult> _results = const [];
  bool _loading = false;
  bool _searched = false;
  String? _error;
  PlaceSearchResult? _selectedPlace;
  LatLng? _pinCenter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _query.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (query.length < 2) {
      _searchRequest++;
      setState(() {
        _loading = false;
        _searched = false;
        _results = const [];
        _error = null;
      });
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _runSearch(keepKeyboardOpen: true),
    );
  }

  Future<void> _runSearch({bool keepKeyboardOpen = false}) async {
    final query = _query.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (query.length < 2) {
      setState(() => _error = '장소명이나 주소를 2자 이상 입력해주세요.');
      return;
    }
    if (!keepKeyboardOpen) FocusScope.of(context).unfocus();
    final request = ++_searchRequest;
    setState(() {
      _loading = true;
      _searched = true;
      _error = null;
    });
    try {
      final results = await widget.search(query);
      if (!mounted || request != _searchRequest) return;
      setState(() => _results = results);
    } catch (_) {
      if (!mounted || request != _searchRequest) return;
      setState(() {
        _results = const [];
        _error = '장소를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.';
      });
    } finally {
      if (mounted && request == _searchRequest) {
        setState(() => _loading = false);
      }
    }
  }

  void _showOnMap(PlaceSearchResult place) {
    FocusScope.of(context).unfocus();
    setState(() {
      _selectedPlace = place;
      _pinCenter = LatLng(place.latitude, place.longitude);
    });
  }

  void _backToResults() {
    setState(() {
      _selectedPlace = null;
      _pinCenter = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _confirmLocation() {
    final place = _selectedPlace;
    final pin = _pinCenter;
    if (place == null || pin == null) return;
    Navigator.pop(
      context,
      place.withCoordinates(
        latitude: pin.latitude,
        longitude: pin.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final selectedPlace = _selectedPlace;
    return FractionallySizedBox(
      heightFactor: 0.86,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (selectedPlace == null) ...[
              Text(
                '활동 장소 검색',
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '장소명이나 주소를 입력하면 바로 검색해드려요.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _query,
                focusNode: _focusNode,
                textInputAction: TextInputAction.search,
                onChanged: _onQueryChanged,
                onSubmitted: (_) => _runSearch(),
                decoration: InputDecoration(
                  hintText: '예: 잠실 풋살장, 올림픽로 25',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _query.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _query.clear();
                                _onQueryChanged('');
                                _focusNode.requestFocus();
                              },
                              tooltip: '검색어 지우기',
                              icon: const Icon(Icons.close_rounded),
                            ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: tt.bodySmall?.copyWith(color: cs.error),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: _results.isEmpty
                    ? Center(
                        child: Text(
                          _searched
                              ? '검색 결과가 없습니다.'
                              : '두 글자 이상 입력하면 검색 결과가 나타납니다.',
                          style: tt.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.separated(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final place = _results[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xs,
                            ),
                            onTap: () => _showOnMap(place),
                            leading: Icon(
                              Icons.place_outlined,
                              color: cs.primary,
                            ),
                            title: Text(
                              place.name,
                              style: tt.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(place.preferredAddress),
                            trailing: const Icon(Icons.chevron_right_rounded),
                          );
                        },
                      ),
              ),
            ] else ...[
              Row(
                children: [
                  IconButton(
                    onPressed: _backToResults,
                    tooltip: '검색 결과로 돌아가기',
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      '정확한 위치 지정',
                      style: tt.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedPlace.name,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selectedPlace.preferredAddress,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      FlutterMap(
                        options: MapOptions(
                          initialCenter: _pinCenter!,
                          initialZoom: 17,
                          minZoom: 6,
                          maxZoom: 19,
                          onPositionChanged: (camera, hasGesture) {
                            if (hasGesture) _pinCenter = camera.center;
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'kr.jyoung.allround',
                          ),
                          SimpleAttributionWidget(
                            source: const Text('OpenStreetMap contributors'),
                            onTap: () => launchUrl(
                              Uri.parse(
                                  'https://www.openstreetmap.org/copyright'),
                              mode: LaunchMode.externalApplication,
                            ),
                            backgroundColor: cs.surface.withValues(alpha: 0.85),
                          ),
                        ],
                      ),
                      IgnorePointer(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 36),
                          child: Icon(
                            Icons.location_pin,
                            size: 52,
                            color: cs.primary,
                            shadows: const [
                              Shadow(
                                blurRadius: 8,
                                color: Colors.black38,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        top: AppSpacing.sm,
                        left: AppSpacing.sm,
                        right: AppSpacing.sm,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: cs.surface.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              boxShadow: const [
                                BoxShadow(
                                  blurRadius: 10,
                                  color: Colors.black12,
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm,
                              ),
                              child: Text(
                                '지도를 움직여 정확한 입구나 운동장 위치에 핀을 맞춰주세요.',
                                style: tt.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: _confirmLocation,
                icon: const Icon(Icons.check_rounded),
                label: const Text('이 위치로 선택'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
