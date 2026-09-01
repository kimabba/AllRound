import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../state/providers.dart';
import '../../testing/e2e_keys.dart';
import '../../theme/color_schemes.dart';
import '../../theme/motion.dart';
import '../../theme/tokens.dart';
import '../../utils/age.dart';
import '../../utils/auth_error_message.dart';
import '../../utils/auth_redirect.dart';
import '../../utils/legal_urls.dart';
import '../in_app_browser_screen.dart';

const _loginFriendsPhotoAsset = 'assets/images/auth/login-friends-v1.jpg';
const _loginTournamentsPhotoAsset =
    'assets/images/auth/login-futsal-tournaments-v1.jpg';
const _loginClubsPhotoAsset = 'assets/images/auth/login-clubs-v1.jpg';
const _loginBallboyPhotoAsset =
    'assets/images/auth/login-futsal-ballboy-v1.jpg';
const _loginSlidePhotoAssets = <String>[
  _loginFriendsPhotoAsset,
  _loginTournamentsPhotoAsset,
  _loginClubsPhotoAsset,
  _loginBallboyPhotoAsset,
];
const _loginSlideSportLabels = <String>[
  'TENNIS',
  'FUTSAL',
  'TENNIS',
  'FUTSAL',
];

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  DateTime? _signupBirthDate;
  bool _signUp = false;
  bool _busy = false;
  bool _marketingConsent = false;
  bool _termsConsent = false;
  int _introPage = 0;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    final callbackError = authCallbackErrorMessage(Uri.base);
    if (callbackError == null) return;
    _error = callbackError;
    // Google 신규 사용자가 이메일 버튼을 누르면 로그인 탭을 한 번 더
    // 거치지 않고 바로 생년월일이 포함된 안전한 가입 흐름을 연다.
    _signUp = callbackError == '신규 가입은 이메일로 진행해 주세요.';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  // onChanged: 바텀시트의 setSheetState. 부모 setState 만으로는 시트가
  // 리빌드되지 않아 에러/로딩이 시트에 반영되지 않으므로 함께 갱신한다.
  Future<void> _emailAuth({VoidCallback? onChanged}) async {
    // 이미 처리 중이면 중복 제출(빠른 다중 탭·엔터)을 무시한다. 버튼은 rebuild
    // 후에야 비활성화돼 그 전 탭이 새어들 수 있어, 동기 가드로 확실히 막는다.
    if (_busy) return;
    void set(VoidCallback fn) {
      setState(fn);
      onChanged?.call();
    }

    final email = _email.text.trim();
    final password = _password.text;
    final passwordConfirm = _passwordConfirm.text;
    if (email.isEmpty) {
      set(() => _error = '이메일을 입력해 주세요.');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      set(() => _error = '이메일 형식으로 입력해 주세요.');
      return;
    }
    if (password.isEmpty) {
      set(() => _error = '비밀번호를 입력해 주세요.');
      return;
    }
    if (_signUp && password.length < 6) {
      set(() => _error = '비밀번호는 6자 이상으로 입력해 주세요.');
      return;
    }
    if (_signUp && password != passwordConfirm) {
      set(() => _error = '비밀번호가 서로 일치하지 않습니다.');
      return;
    }
    if (_signUp && _signupBirthDate == null) {
      set(() => _error = '계정 생성 전에 생년월일을 확인해 주세요.');
      return;
    }
    if (_signUp && !_termsConsent) {
      set(() => _error = '이용약관과 개인정보 처리방침에 동의해 주세요.');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    set(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final supa = ref.read(supabaseProvider);
      if (_signUp) {
        await supa.auth.signUp(
          email: email,
          password: password,
          data: {
            'birth_date': _formatBirthDateForAuth(_signupBirthDate!),
            'terms_agreed_at': DateTime.now().toUtc().toIso8601String(),
            'marketing_consent': _marketingConsent,
            if (_marketingConsent)
              'marketing_consent_at': DateTime.now().toUtc().toIso8601String(),
          },
        );
      } else {
        await supa.auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (e) {
      set(() => _error = _authErrorMessage(e));
    } catch (_) {
      set(() => _error = '오류가 발생했습니다. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) set(() => _busy = false);
    }
  }

  /// 비밀번호 재설정 메일 발송. 성공해도 이메일 로그인 시트를 유지하고
  /// 시트 안에서 안내한다. 사용자는 입력한 이메일을 확인하거나 메일을
  /// 다시 보낼 수 있어야 한다.
  /// 메일 링크는 구글 로그인과 동일한 딥링크 스킴으로 복귀해 passwordRecovery
  /// 이벤트를 발생시키고, 라우터가 새 비번 설정 화면으로 보낸다.
  Future<void> _forgotPassword({VoidCallback? onChanged}) async {
    void set(VoidCallback fn) {
      setState(fn);
      onChanged?.call();
    }

    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      set(() => _error = '가입한 이메일을 입력한 뒤 눌러 주세요.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('비밀번호 재설정'),
        content: Text('$email\n위 주소로 재설정 링크를 보낼까요?'),
        actionsOverflowButtonSpacing: AppSpacing.sm,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('메일 보내기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    set(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await ref.read(supabaseProvider).auth.resetPasswordForEmail(
            email,
            redirectTo: authRedirectTo(isWeb: kIsWeb, baseUri: Uri.base),
          );
      if (!mounted) return;
      set(() {
        _busy = false;
        _info = '재설정 메일을 보냈어요. 메일함을 확인해 주세요.';
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      set(() {
        _busy = false;
        _error = _authErrorMessage(e);
      });
    } catch (_) {
      if (!mounted) return;
      set(() {
        _busy = false;
        _error = '오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
      });
    }
  }

  /// Supabase AuthException 을 사용자용 한국어로 매핑한다.
  /// 매핑 규칙은 테스트 가능하도록 `utils/auth_error_message.dart` 로 분리했다.
  String _authErrorMessage(AuthException e) =>
      authErrorMessage(e, signUp: _signUp);

  // 입력을 수정하면 이전 에러를 즉시 지운다. 기존엔 제출할 때만 지워져,
  // 비번을 바꿔도 옛 에러가 남아 "계속 거절되는 것처럼" 보였다.
  void _clearAuthError(StateSetter setSheetState) {
    if (_error == null && _info == null) return;
    setState(() {
      _error = null;
      _info = null;
    });
    setSheetState(() {});
  }

  void _setMode({required bool signUp}) {
    if (_busy) return;
    setState(() {
      _signUp = signUp;
      _error = null;
      _info = null;
      _password.clear();
      _passwordConfirm.clear();
      _signupBirthDate = null;
      _termsConsent = false;
    });
  }

  String _formatBirthDateForAuth(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String _formatBirthDateForDisplay(DateTime date) =>
      '${date.year}년 ${date.month.toString().padLeft(2, '0')}월 '
      '${date.day.toString().padLeft(2, '0')}일';

  DateTime _safeAnniversary(DateTime now, int yearsAgo) {
    final targetYear = now.year - yearsAgo;
    final lastDay = DateTime(targetYear, now.month + 1, 0).day;
    final targetDay = now.day > lastDay ? lastDay : now.day;
    return DateTime(targetYear, now.month, targetDay);
  }

  Future<void> _pickSignupBirthDate({required VoidCallback onChanged}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final now = DateTime.now();
    final latestEligible = _safeAnniversary(now, kMinSignupAge);
    final initial = _signupBirthDate ?? _safeAnniversary(now, 20);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: latestEligible,
      helpText: '가입 생년월일 선택',
    );
    if (!mounted || picked == null) return;
    setState(() => _signupBirthDate = picked);
    onChanged();
  }

  Future<void> _googleSignIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // 마케팅 수신 동의는 회원가입 시트에서만 받는다. 예전엔 여기서 로그인
      // 성공을 듣고 updateUser 로 동의값을 썼는데, Google 재로그인 때마다
      // 예전 동의가 체크박스 기본값(false)으로
      // 덮어써졌다. 서버에 보정 로직이 없어 동의 이력이 조용히 사라졌다.
      await ref.read(supabaseProvider).auth.signInWithOAuth(
        OAuthProvider.google,
        // 모바일은 딥링크, 웹은 현재 origin 으로 명시적으로 복귀한다. null 이면
        // Supabase Site URL(localhost:3000 등)로 빠지므로 생략하면 안 된다.
        redirectTo: authRedirectTo(isWeb: kIsWeb, baseUri: Uri.base),
        // 로그아웃 후 재로그인 시 직전 구글 계정으로 자동 재인증되지 않도록
        // 계정 선택 화면을 항상 노출한다 (JY-113).
        queryParams: const {'prompt': 'select_account'},
      );
    } catch (_) {
      setState(() => _error = '오류가 발생했습니다. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showEmailAuthSheet() async {
    setState(() => _error = null);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            // 메일 발송·로그인 같은 비동기 작업이 끝났을 때 사용자가 이미 시트를
            // 내렸을 수 있다. 그때 화면(State)은 살아 있어 !mounted 가드를 통과하지만
            // 시트는 dispose 된 뒤라 setSheetState 가 예외를 던진다. 시트 자신의
            // context 로 한 번 더 확인한다.
            void refreshSheet() {
              if (context.mounted) setSheetState(() {});
            }

            final cs = Theme.of(context).colorScheme;
            final tt = Theme.of(context).textTheme;
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
                ),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        _signUp ? '회원가입' : '이메일로 로그인',
                        style: tt.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _SheetAuthField(
                        fieldKey: AllRoundE2EKeys.emailField,
                        controller: _email,
                        icon: Icons.email_outlined,
                        label: '이메일',
                        hintText: 'test@example.com',
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => _clearAuthError(setSheetState),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _SheetAuthField(
                        fieldKey: AllRoundE2EKeys.passwordField,
                        controller: _password,
                        icon: Icons.lock_outline_rounded,
                        label: '비밀번호',
                        hintText: _signUp ? '6자 이상 입력' : null,
                        obscureText: true,
                        textInputAction: _signUp
                            ? TextInputAction.next
                            : TextInputAction.done,
                        onSubmitted: (_) => _busy
                            ? null
                            : _emailAuth(
                                onChanged: refreshSheet,
                              ),
                        onChanged: (_) => _clearAuthError(setSheetState),
                      ),
                      if (_signUp) ...[
                        const SizedBox(height: AppSpacing.md),
                        _SheetAuthField(
                          fieldKey: AllRoundE2EKeys.passwordConfirmField,
                          controller: _passwordConfirm,
                          icon: Icons.verified_user_outlined,
                          label: '비밀번호 확인',
                          hintText: '비밀번호를 한 번 더 입력',
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _busy
                              ? null
                              : _emailAuth(
                                  onChanged: refreshSheet,
                                ),
                          onChanged: (_) => _clearAuthError(setSheetState),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          '6자 이상 · 다른 사이트에서 쓰지 않은 비밀번호를 권장해요. '
                          '유출된 흔한 비밀번호는 보안을 위해 사용할 수 없어요.',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _SignupBirthDateField(
                          key: AllRoundE2EKeys.signupBirthDate,
                          value: _signupBirthDate == null
                              ? null
                              : _formatBirthDateForDisplay(_signupBirthDate!),
                          onPressed: _busy
                              ? null
                              : () => _pickSignupBirthDate(
                                    onChanged: refreshSheet,
                                  ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _ConsentRow(
                          checkboxKey: AllRoundE2EKeys.signupTermsConsent,
                          value: _termsConsent,
                          label: '이용약관·개인정보 처리방침 동의 (필수)',
                          onChanged: (value) {
                            setState(() => _termsConsent = value ?? false);
                            refreshSheet();
                          },
                        ),
                        Wrap(
                          children: const [
                            _LegalLinkButton(
                              label: '이용약관',
                              url: kTermsOfServiceUrl,
                            ),
                            _LegalLinkButton(
                              label: '개인정보 처리방침',
                              url: kPrivacyPolicyUrl,
                            ),
                          ],
                        ),
                        // 선택 동의라 계정을 만드는 이 자리에서만 묻는다.
                        // 로그인하는 기존 회원에게는 물을 이유가 없다.
                        _ConsentRow(
                          value: _marketingConsent,
                          label: '마케팅 정보 수신 동의 (선택)',
                          onChanged: (value) {
                            setState(() => _marketingConsent = value ?? false);
                            refreshSheet();
                          },
                        ),
                      ],
                      // 비밀번호 재설정은 kr.allround.app:// 딥링크로 앱을 여는
                      // 흐름이라 모바일 전용. 웹(admin)에선 링크가 앱을 못 열고
                      // 튕기므로 버튼을 숨긴다(admin 은 구글 로그인 권장). !kIsWeb.
                      if (!_signUp && !kIsWeb)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _busy
                                ? null
                                : () => _forgotPassword(
                                      onChanged: refreshSheet,
                                    ),
                            child: const Text('비밀번호를 잊으셨나요?'),
                          ),
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          _error!,
                          style: tt.bodySmall?.copyWith(
                            color: cs.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      if (_info != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.mark_email_read_outlined,
                              color: cs.primary,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                _info!,
                                style: tt.bodySmall?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      if (_signUp && !_termsConsent) ...[
                        Text(
                          '필수 동의에 체크하면 가입을 시작할 수 있어요.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      FilledButton(
                        key: AllRoundE2EKeys.authSubmitButton,
                        onPressed: _busy || (_signUp && !_termsConsent)
                            ? null
                            : () => _emailAuth(
                                  onChanged: refreshSheet,
                                ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(AppSizes.control),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_signUp ? '회원가입 시작하기' : '로그인'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextButton(
                        key: AllRoundE2EKeys.authModeToggle,
                        onPressed: _busy
                            ? null
                            : () {
                                _setMode(signUp: !_signUp);
                                setSheetState(() {});
                              },
                        child: Text(
                          _signUp ? '이미 계정이 있어요' : '계정이 없어요. 회원가입하기',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 웹은 initState 의 Uri.base 로 OAuth 콜백 에러를 잡지만, 모바일은 세션
    // 변화 없이 딥링크만 돌아와 조용히 실패한다(에러가 onAuthStateChange
    // 스트림으로만 통지됨, supabase_flutter의 notifyException). 신규 가입
    // 차단 같은 케이스를 모바일에서도 동일하게 노출한다.
    ref.listen<AsyncValue<AuthState>>(authStateProvider, (previous, next) {
      final error = next.error;
      if (error is! AuthException) return;
      final message = authErrorMessage(error, signUp: false);
      setState(() {
        _error = message;
        _signUp = message == '신규 가입은 이메일로 진행해 주세요.';
      });
    });

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // 로컬 관리자 모드(make admin): 마케팅·온보딩 카피를 숨기고
    // 이메일·구글 로그인만 노출. 실제 권한은 서버 RLS.
    final adminMode = AppConfig.adminMode;
    // App Store 첫 출시는 자체 이메일 인증만 제공한다. iOS에서 Google 같은
    // 제3자 로그인을 노출하면 App Review Guideline 4.8에 따라 동등한
    // Sign in with Apple 옵션이 필요하다. Android/Web의 기존 Google 로그인은
    // 유지하되 iOS에서는 서버의 가입 전 연령 게이트가 있는 이메일 흐름만 쓴다.
    final showGoogleLogin =
        kIsWeb || defaultTargetPlatform != TargetPlatform.iOS;
    final photoAsset = adminMode ? null : _loginSlidePhotoAssets[_introPage];
    final sportLabel = adminMode ? null : _loginSlideSportLabels[_introPage];
    final photoSlide = photoAsset != null;

    return Scaffold(
      key: AllRoundE2EKeys.loginScreen,
      backgroundColor: cs.primaryContainer,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (photoAsset != null)
            AnimatedSwitcher(
              duration: AppDuration.medium1,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: SizedBox.expand(
                key: ValueKey(photoAsset),
                child: Image.asset(
                  photoAsset,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
            )
          else
            ColoredBox(color: cs.primaryContainer),
          if (photoSlide)
            DecoratedBox(
              // 사진의 운동감은 살리되 로고·카피·CTA 위치에서는 흰색 작은
              // 글씨도 AA 대비를 유지하도록 위치별 스크림 농도를 조절한다.
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    cs.scrim.withValues(alpha: 0.6),
                    cs.scrim.withValues(alpha: 0.6),
                    cs.scrim.withValues(alpha: 0.14),
                    cs.scrim.withValues(alpha: 0.18),
                    cs.scrim.withValues(alpha: 0.68),
                    cs.scrim.withValues(alpha: 0.88),
                  ],
                  stops: const [0, 0.08, 0.28, 0.48, 0.74, 1],
                ),
              ),
            ),
          SafeArea(
            child: Center(
              // 데스크톱에서도 로그인 콘텐츠는 모바일 폭을 유지하되, 슬라이드의
              // 배경색은 Scaffold 전체를 채워 작은 카드처럼 보이지 않게 한다.
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.xl,
                        AppSpacing.xl,
                        0,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '올라운드',
                                  maxLines: 1,
                                  style: tt.titleLarge?.copyWith(
                                    color: photoSlide
                                        ? AppPalette.photoForeground
                                        : cs.onPrimaryContainer,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.8,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          if (sportLabel != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.xs,
                              ),
                              decoration: BoxDecoration(
                                color: AppPalette.photoForeground.withValues(
                                  alpha: 0.14,
                                ),
                                borderRadius: AppRadius.pill,
                              ),
                              child: Text(
                                sportLabel,
                                maxLines: 1,
                                textScaler: TextScaler.noScaling,
                                style: tt.labelSmall?.copyWith(
                                  color: AppPalette.photoForeground,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Expanded(
                      child: _IntroCarousel(
                        adminMode: adminMode,
                        onPageChanged: (page) {
                          if (_introPage == page) return;
                          setState(() => _introPage = page);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.xl,
                        AppSpacing.xl,
                        AppSpacing.xl,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_error != null) ...[
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: BoxDecoration(
                                color: cs.errorContainer,
                                border: Border.all(color: cs.error),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Text(
                                _error!,
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onErrorContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                          if (showGoogleLogin) ...[
                            _SocialButton(
                              key: AllRoundE2EKeys.googleContinueButton,
                              onPressed: _busy ? null : _googleSignIn,
                              icon: Icons.account_circle_outlined,
                              label: 'Google로 계속하기',
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                          FilledButton(
                            key: AllRoundE2EKeys.emailFlowButton,
                            onPressed: _busy ? null : _showEmailAuthSheet,
                            style: FilledButton.styleFrom(
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(AppRadius.xxl),
                                ),
                              ),
                            ),
                            child: const Text('이메일로 계속하기'),
                          ),
                          if (!adminMode) ...[
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              '계속하면 이용약관과 개인정보 처리방침에 동의한 것으로 간주됩니다.',
                              textAlign: TextAlign.center,
                              style: tt.bodySmall?.copyWith(
                                color: photoSlide
                                    ? AppPalette.photoForeground
                                    : cs.onPrimaryContainer.withValues(
                                        alpha: 0.8,
                                      ),
                                height: 1.45,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AllRoundMascot extends StatelessWidget {
  const _AllRoundMascot({this.onPhoto = false});

  final bool onPhoto;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foreground = onPhoto ? AppPalette.photoForeground : cs.primary;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: AppSizes.touchTarget * 2,
          height: AppSizes.touchTarget * 2,
          decoration: BoxDecoration(
            color: foreground.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: foreground, width: 2),
          ),
          child: Icon(
            Icons.sentiment_satisfied_alt_rounded,
            color: foreground,
            size: AppSizes.touchTarget,
          ),
        ),
        Positioned(
          right: -AppSpacing.sm,
          bottom: -AppSpacing.sm,
          child: Container(
            width: AppSizes.touchTarget,
            height: AppSizes.touchTarget,
            decoration: BoxDecoration(
              color: foreground,
              shape: BoxShape.circle,
              border: Border.all(
                color: cs.primaryContainer,
                width: AppSpacing.xs,
              ),
            ),
            child: Icon(
              Icons.sports_tennis_rounded,
              color: onPhoto ? AppPalette.accent : cs.onPrimary,
              size: 22,
            ),
          ),
        ),
        Positioned(
          left: -AppSpacing.lg,
          top: AppSpacing.sm,
          child: Icon(
            Icons.auto_awesome_rounded,
            color: cs.primary.withValues(alpha: 0.58),
            size: 22,
          ),
        ),
      ],
    );
  }
}

/// 로그인 전에 "여기서 뭘 할 수 있는지"를 넘겨 보는 카드.
/// 첫 장은 인사, 나머지는 하단 탭의 동선(대회·클럽·볼보이)과 1:1 로 맞춘다.
class _IntroCarousel extends StatefulWidget {
  const _IntroCarousel({
    required this.adminMode,
    required this.onPageChanged,
  });

  final bool adminMode;
  final ValueChanged<int> onPageChanged;

  @override
  State<_IntroCarousel> createState() => _IntroCarouselState();
}

class _IntroCarouselState extends State<_IntroCarousel> {
  static const _adminCards = <_IntroCardData>[
    _IntroCardData(
      icon: Icons.admin_panel_settings_rounded,
      title: '관리자 로그인',
      body: '관리자 계정으로 안전하게 로그인하세요.',
    ),
  ];

  static const _cards = <_IntroCardData>[
    _IntroCardData(
      backgroundAsset: _loginFriendsPhotoAsset,
      title: '운동 친구를 만나러 가볼까요?',
      body: '대회도 모임도, 올라운드에서\n즐겁고 간편하게 찾아보세요.',
    ),
    _IntroCardData(
      icon: Icons.emoji_events_rounded,
      backgroundAsset: _loginTournamentsPhotoAsset,
      title: '열리는 대회를 한눈에',
      body: '지역별로 모아 보고, 신청 마감일까지\n한 번에 확인하세요.',
    ),
    _IntroCardData(
      icon: Icons.groups_rounded,
      backgroundAsset: _loginClubsPhotoAsset,
      title: '가까운 클럽과 모임 찾기',
      body: '동네 클럽을 둘러보고\n같이 칠 사람을 구해 보세요.',
    ),
    _IntroCardData(
      icon: Icons.chat_bubble_rounded,
      backgroundAsset: _loginBallboyPhotoAsset,
      title: '궁금한 건 볼보이에게',
      body: '대회 규정이나 일정을 물어보면\n채팅으로 바로 찾아 줍니다.',
    ),
  ];

  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _startAutoPlay();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startAutoPlay() {
    if (widget.adminMode) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_controller.hasClients) return;
      // 모션 최소화를 켠 사용자에게 화면이 저절로 움직이면 안 된다.
      if (MediaQuery.disableAnimationsOf(context)) {
        _timer?.cancel();
        return;
      }
      _controller.animateToPage(
        (_page + 1) % _cards.length,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// 이 카드가 화면 중앙에서 몇 장만큼 떨어져 있는지. 0 이면 정중앙,
  /// 0.5 면 절반쯤 넘어간 상태다. 넘기는 중에는 소수로 계속 바뀐다.
  double _offsetOf(int index) {
    if (!_controller.hasClients || !_controller.position.haveDimensions) {
      return (_page - index).toDouble();
    }
    return (_controller.page ?? _page.toDouble()) - index;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cards = widget.adminMode ? _adminCards : _cards;
    final photoSlide = cards[_page].backgroundAsset != null;
    return Column(
      children: [
        Expanded(
          // 사용자가 한 번 손으로 넘기면 자동 넘김을 멈춘다. 저절로 움직이는
          // 화면을 멈출 방법이 있어야 한다(WCAG 2.2.2). depth 0 만 보는 것은
          // 카드 안쪽 스크롤(큰 글자)이 올려보내는 알림과 구분하기 위함이다.
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification &&
                  notification.depth == 0 &&
                  notification.dragDetails != null) {
                _timer?.cancel();
              }
              return false;
            },
            child: PageView.builder(
              controller: _controller,
              itemCount: cards.length,
              onPageChanged: (value) {
                setState(() => _page = value);
                widget.onPageChanged(value);
              },
              // 화면 전체가 넘어가면서 안쪽 콘텐츠에도 작은 시차를 준다.
              itemBuilder: (context, index) => AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => _IntroCard(
                  data: cards[index],
                  offset: _offsetOf(index),
                ),
              ),
            ),
          ),
        ),
        if (cards.length > 1) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < cards.length; index++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: index == _page ? 18 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: index == _page
                        ? (photoSlide ? AppPalette.photoForeground : cs.primary)
                        : (photoSlide
                            ? AppPalette.photoForeground.withValues(alpha: 0.4)
                            : cs.outlineVariant),
                    borderRadius: AppRadius.pill,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _IntroCardData {
  const _IntroCardData({
    this.icon,
    this.backgroundAsset,
    required this.title,
    required this.body,
  });

  /// null 이면 마스코트를 쓴다(첫 인사 카드).
  final IconData? icon;
  final String? backgroundAsset;
  final String title;
  final String body;
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.data, this.offset = 0});

  final _IntroCardData data;

  /// 화면 중앙에서 떨어진 정도. 0 이 정중앙, ±1 이 한 장 옆.
  final double offset;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final onPhoto = data.backgroundAsset != null;
    final foreground =
        onPhoto ? AppPalette.photoForeground : cs.onPrimaryContainer;
    final t = offset.clamp(-1.0, 1.0);
    // 아이콘이 글자보다 더 크게 밀리면서 겹이 생긴다(패럴랙스).
    // 중앙에 서 있는 동안은 계산값이 모두 0 이라 아무 비용도 들지 않는다.
    final centeredContent = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Transform.translate(
          offset: Offset(t * 44, 0),
          child: data.icon == null
              ? _AllRoundMascot(onPhoto: onPhoto)
              // 마스코트와 같은 크기·모양이어야 장을 넘겨도 무게가 흔들리지 않는다.
              : Container(
                  width: AppSizes.touchTarget * 2,
                  height: AppSizes.touchTarget * 2,
                  decoration: BoxDecoration(
                    color: foreground.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: foreground, width: 2),
                  ),
                  child: Icon(
                    data.icon,
                    color: foreground,
                    size: AppSizes.touchTarget,
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        Transform.translate(
          offset: Offset(t * 18, 0),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    data.title,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: tt.displaySmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      letterSpacing: -1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                data.body,
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(
                  // 0.72 는 라이트에서 4.34:1 로 WCAG AA(4.5:1) 미달이었다.
                  // 0.80 이면 라이트 5.29 / 다크 5.62 로 여유가 생긴다.
                  color: onPhoto
                      ? AppPalette.photoForeground
                      : cs.onPrimaryContainer.withValues(alpha: 0.8),
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final editorialContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Transform.translate(
          offset: Offset(t * 18, 0),
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: AppRadius.pill,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Transform.translate(
          offset: Offset(t * 18, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    data.title,
                    maxLines: 1,
                    textAlign: TextAlign.left,
                    style: tt.displaySmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      letterSpacing: -1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                data.body,
                textAlign: TextAlign.left,
                style: tt.bodyMedium?.copyWith(
                  color: AppPalette.photoForeground,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final content = onPhoto ? editorialContent : centeredContent;

    final away = t.abs();
    return ClipRect(
      child: CustomPaint(
        painter: onPhoto
            ? null
            : _IntroBackdropPainter(
                accent: cs.primary,
                line: cs.onPrimaryContainer,
              ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final verticalPadding = AppSpacing.xxl * 2;
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxl,
                vertical: AppSpacing.xxl,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - verticalPadding)
                      .clamp(0.0, double.infinity),
                ),
                child: Align(
                  alignment: onPhoto ? Alignment.bottomLeft : Alignment.center,
                  child: away == 0
                      ? content
                      // 완전히 중앙일 때는 Opacity 레이어를 만들지 않는다.
                      : Opacity(
                          opacity: (1 - away * 1.1).clamp(0.0, 1.0),
                          child: content,
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 큰 원형 필드와 사선 코트 면을 화면 배경까지 확장한다. 이미지 파일 없이
/// 그리므로 화면 비율과 해상도가 달라도 같은 밀도로 보인다.
class _IntroBackdropPainter extends CustomPainter {
  const _IntroBackdropPainter({required this.accent, required this.line});

  final Color accent;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final band = Path()
      ..moveTo(0, size.height * 0.12)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.2)
      ..lineTo(0, size.height * 0.34)
      ..close();
    canvas.drawPath(
      band,
      Paint()
        ..style = PaintingStyle.fill
        ..color = accent.withValues(alpha: 0.06),
    );

    final focusCenter = Offset(size.width * 0.5, size.height * 0.46);
    final focusRadius = (size.width * 0.43).clamp(
      0.0,
      size.height * 0.32,
    );
    canvas.drawCircle(
      focusCenter,
      focusRadius,
      Paint()
        ..style = PaintingStyle.fill
        ..color = accent.withValues(alpha: 0.1),
    );

    final fieldLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = line.withValues(alpha: 0.16);
    for (var ring = 1; ring <= 3; ring++) {
      canvas.drawCircle(
        focusCenter,
        focusRadius * (0.58 + (ring * 0.18)),
        fieldLine,
      );
    }

    canvas.drawLine(
      Offset(0, focusCenter.dy),
      Offset(size.width, focusCenter.dy),
      fieldLine,
    );
    canvas.drawCircle(
      Offset(size.width, size.height),
      size.width * 0.28,
      fieldLine,
    );
  }

  @override
  bool shouldRepaint(_IntroBackdropPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.line != line;
}

class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.value,
    required this.label,
    required this.onChanged,
    this.checkboxKey,
  });

  final bool value;
  final String label;
  final ValueChanged<bool?> onChanged;
  final Key? checkboxKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Checkbox(
              key: checkboxKey,
              value: value,
              onChanged: onChanged,
              side: BorderSide(color: cs.outline, width: 1.4),
              semanticLabel: label,
            ),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalLinkButton extends StatelessWidget {
  const _LegalLinkButton({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () {
        final uri = Uri.parse(url);
        if (kIsWeb) {
          launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => InAppBrowserScreen(uri: uri)),
        );
      },
      icon: const Icon(Icons.open_in_new_rounded, size: 16),
      label: Text(label),
    );
  }
}

class _SignupBirthDateField extends StatelessWidget {
  const _SignupBirthDateField({
    super.key,
    required this.value,
    required this.onPressed,
  });

  final String? value;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(AppSizes.control),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        alignment: Alignment.centerLeft,
        side: BorderSide(color: cs.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.cake_outlined, color: cs.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value ?? '생년월일 선택',
                  style: tt.bodyLarge?.copyWith(
                    color: value == null ? cs.onSurfaceVariant : cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '만 $kMinSignupAge세 이상인지 계정 생성 전에 확인합니다.',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _SheetAuthField extends StatelessWidget {
  const _SheetAuthField({
    this.fieldKey,
    required this.controller,
    required this.icon,
    required this.label,
    this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.onSubmitted,
    this.onChanged,
  });

  final Key? fieldKey;
  final TextEditingController controller;
  final IconData icon;
  final String label;
  final String? hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(AppSizes.control),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
