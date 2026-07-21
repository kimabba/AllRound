import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config.dart';
import '../../state/providers.dart';
import '../../testing/e2e_keys.dart';
import '../../theme/tokens.dart';
import '../../utils/age.dart';

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
  String? _error;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void dispose() {
    _authSubscription?.cancel();
    _email.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  // onChanged: 바텀시트의 setSheetState. 부모 setState 만으로는 시트가
  // 리빌드되지 않아 에러/로딩이 시트에 반영되지 않으므로 함께 갱신한다.
  Future<void> _emailAuth({VoidCallback? onChanged}) async {
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

    set(() {
      _busy = true;
      _error = null;
    });
    try {
      final supa = ref.read(supabaseProvider);
      if (_signUp) {
        await supa.auth.signUp(
          email: email,
          password: password,
          data: {
            'birth_date': _formatBirthDateForAuth(_signupBirthDate!),
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

  /// 비밀번호 재설정 메일 발송. 성공 시 시트를 닫고 스낵바로 안내한다.
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
    });
    try {
      await ref.read(supabaseProvider).auth.resetPasswordForEmail(
            email,
            redirectTo: kIsWeb ? null : 'kr.allround.app://login-callback/',
          );
      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('재설정 메일을 보냈어요. 메일함을 확인해 주세요.')),
      );
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

  /// Supabase AuthException 영어 원문을 사용자용 한국어로 매핑한다.
  String _authErrorMessage(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login') || m.contains('invalid credentials')) {
      return '이메일 또는 비밀번호가 올바르지 않습니다.';
    }
    if (m.contains('already registered') || m.contains('already exists')) {
      return '이미 가입된 이메일입니다. 로그인해 주세요.';
    }
    if (m.contains('email not confirmed')) {
      return '이메일 인증이 필요합니다. 메일함을 확인해 주세요.';
    }
    if (m.contains('rate limit') || m.contains('too many')) {
      return '요청이 많습니다. 잠시 후 다시 시도해 주세요.';
    }
    if (m.contains('weak password') || m.contains('password should')) {
      return '비밀번호가 너무 약합니다. 더 복잡하게 설정해 주세요.';
    }
    if (m.contains('birth_date_required')) {
      return '계정 생성 전에 생년월일을 확인해 주세요.';
    }
    if (m.contains('invalid_birth_date')) {
      return '올바른 생년월일을 입력해 주세요.';
    }
    if (m.contains('minor_not_allowed')) {
      return '만 $kMinSignupAge세 이상만 가입할 수 있습니다.';
    }
    if (m.contains('google_signup_disabled')) {
      return '신규 가입은 이메일로 진행해 주세요.';
    }
    if (m.contains('signups not allowed') || m.contains('disabled')) {
      return '현재 회원가입이 제한되어 있습니다.';
    }
    return _signUp
        ? '회원가입에 실패했습니다. 잠시 후 다시 시도해 주세요.'
        : '로그인에 실패했습니다. 잠시 후 다시 시도해 주세요.';
  }

  void _setMode({required bool signUp}) {
    if (_busy) return;
    setState(() {
      _signUp = signUp;
      _error = null;
      _password.clear();
      _passwordConfirm.clear();
      _signupBirthDate = null;
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

  Future<void> _openEmailFlow({
    required bool signUp,
    String presetEmail = '',
  }) async {
    if (_busy) return;
    _setMode(signUp: signUp);
    _email.text = presetEmail;
    await _showEmailAuthSheet();
  }

  Future<void> _googleSignIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final supa = ref.read(supabaseProvider);
      final consent = _marketingConsent;
      _authSubscription?.cancel();
      _authSubscription = supa.auth.onAuthStateChange.listen((data) async {
        if (data.event == AuthChangeEvent.signedIn) {
          _authSubscription?.cancel();
          _authSubscription = null;
          await supa.auth.updateUser(
            UserAttributes(data: {
              'marketing_consent': consent,
              if (consent)
                'marketing_consent_at':
                    DateTime.now().toUtc().toIso8601String(),
            }),
          );
        }
      });
      await supa.auth.signInWithOAuth(
        OAuthProvider.google,
        // 모바일은 딥링크 스킴으로 복귀. 웹(admin/웹빌드)에서는 모바일 스킴을 쓰면
        // 브라우저로 못 돌아오므로 redirectTo 를 비워 현재 origin 으로 복귀시킨다 (JY-132).
        redirectTo: kIsWeb ? null : 'kr.allround.app://login-callback/',
        // 로그아웃 후 재로그인 시 직전 구글 계정으로 자동 재인증되지 않도록
        // 계정 선택 화면을 항상 노출한다 (JY-113).
        queryParams: const {'prompt': 'select_account'},
      );
    } catch (_) {
      _authSubscription?.cancel();
      _authSubscription = null;
      setState(() => _error = '오류가 발생했습니다. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openGoogleExistingLogin() async {
    final existingAccount = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Google 로그인 안내'),
        content: const Text(
          'Google은 기존 AllRound 계정 로그인만 지원합니다. '
          '처음 가입한다면 이메일로 생년월일을 먼저 확인해 주세요.',
        ),
        actions: [
          TextButton(
            key: AllRoundE2EKeys.googleEmailSignupAction,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('이메일로 신규 가입'),
          ),
          FilledButton(
            key: AllRoundE2EKeys.googleExistingLoginConfirm,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('기존 계정 로그인'),
          ),
        ],
      ),
    );
    if (!mounted || existingAccount == null) return;
    if (existingAccount) {
      await _googleSignIn();
    } else {
      await _openEmailFlow(signUp: true);
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
                                onChanged: () => setSheetState(() {}),
                              ),
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
                                  onChanged: () => setSheetState(() {}),
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
                                    onChanged: () => setSheetState(() {}),
                                  ),
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
                                      onChanged: () => setSheetState(() {}),
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
                      const SizedBox(height: AppSpacing.lg),
                      FilledButton(
                        key: AllRoundE2EKeys.authSubmitButton,
                        onPressed: _busy
                            ? null
                            : () => _emailAuth(
                                  onChanged: () => setSheetState(() {}),
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // 로컬 관리자 모드(make admin): 마케팅·온보딩 카피를 숨기고
    // 이메일·구글 로그인만 노출. 실제 권한은 서버 RLS.
    final adminMode = AppConfig.adminMode;
    final showTestShortcuts = kDebugMode;
    // App Store 첫 출시는 자체 이메일 인증만 제공한다. iOS에서 Google 같은
    // 제3자 로그인을 노출하면 App Review Guideline 4.8에 따라 동등한
    // Sign in with Apple 옵션이 필요하다. Android/Web의 기존 Google 로그인은
    // 유지하되 iOS에서는 서버의 가입 전 연령 게이트가 있는 이메일 흐름만 쓴다.
    final showGoogleLogin =
        kIsWeb || defaultTargetPlatform != TargetPlatform.iOS;

    return Scaffold(
      key: AllRoundE2EKeys.loginScreen,
      backgroundColor: cs.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.xl,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - (AppSpacing.xl * 2),
                    maxWidth: 480,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _IntroSportBalls(),
                      const SizedBox(height: AppSpacing.huge + AppSpacing.xxl),
                      Text(
                        adminMode ? '관리자 로그인' : '운동할 곳을\n빠르게 찾아보세요.',
                        style: tt.headlineLarge?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w900,
                          height: 1.08,
                          letterSpacing: -1.2,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        adminMode
                            ? '관리자 계정으로 안전하게 로그인하세요.'
                            : '풋살과 테니스 대회, 클럽, 룰북을 한곳에서 확인할 수 있어요.',
                        style: tt.bodyLarge?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.6,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: cs.errorContainer,
                            border: Border.all(color: cs.error),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            _error!,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onErrorContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      if (showGoogleLogin) ...[
                        _SocialButton(
                          key: AllRoundE2EKeys.googleExistingLoginButton,
                          onPressed: _busy ? null : _openGoogleExistingLogin,
                          icon: Icons.account_circle_outlined,
                          label: 'Google 기존 회원 로그인',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      FilledButton(
                        key: AllRoundE2EKeys.emailFlowButton,
                        onPressed: _busy ? null : _showEmailAuthSheet,
                        child: const Text('이메일로 계속하기'),
                      ),
                      if (showTestShortcuts) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _TestLoginShortcutCard(
                          adminEmail: AppConfig.testAdminEmail,
                          userEmail: AppConfig.testUserEmail,
                          busy: _busy,
                          onAdminLogin: () => _openEmailFlow(
                            signUp: false,
                            presetEmail: AppConfig.testAdminEmail,
                          ),
                          onUserLogin: () => _openEmailFlow(
                            signUp: false,
                            presetEmail: AppConfig.testUserEmail,
                          ),
                          onUserSignUp: () => _openEmailFlow(
                            signUp: true,
                            presetEmail: AppConfig.testUserEmail,
                          ),
                        ),
                      ],
                      if (!adminMode) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          '계속하면 이용약관과 개인정보 처리방침에 동의한 것으로 간주됩니다.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _MarketingConsentRow(
                          value: _marketingConsent,
                          onChanged: (value) => setState(
                            () => _marketingConsent = value ?? false,
                          ),
                        ),
                      ],
                    ],
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

class _TestLoginShortcutCard extends StatelessWidget {
  const _TestLoginShortcutCard({
    required this.adminEmail,
    required this.userEmail,
    required this.busy,
    required this.onAdminLogin,
    required this.onUserLogin,
    required this.onUserSignUp,
  });

  final String adminEmail;
  final String userEmail;
  final bool busy;
  final VoidCallback onAdminLogin;
  final VoidCallback onUserLogin;
  final VoidCallback onUserSignUp;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasPresetUserEmail = userEmail.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '로컬 테스트 바로가기',
            style: tt.titleMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '운영진 계정과 일반 계정 진입을 빠르게 열어줍니다. 실제 권한은 서버 기준입니다.',
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _TestLoginItem(
            icon: Icons.admin_panel_settings_outlined,
            title: '운영진 계정',
            subtitle: adminEmail,
            buttonLabel: '운영진 로그인',
            busy: busy,
            onPressed: onAdminLogin,
          ),
          const SizedBox(height: AppSpacing.md),
          _TestLoginItem(
            icon: Icons.person_outline_rounded,
            title: '일반 계정',
            subtitle: hasPresetUserEmail ? userEmail : '회원가입 또는 일반 로그인 테스트',
            buttonLabel: hasPresetUserEmail ? '일반 로그인' : '일반 로그인 열기',
            busy: busy,
            onPressed: onUserLogin,
            secondaryLabel: '새 일반 계정 회원가입',
            onSecondaryPressed: onUserSignUp,
          ),
        ],
      ),
    );
  }
}

class _TestLoginItem extends StatelessWidget {
  const _TestLoginItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.busy,
    required this.onPressed,
    this.secondaryLabel,
    this.onSecondaryPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final bool busy;
  final VoidCallback onPressed;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cs.primary, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: tt.titleSmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: busy ? null : onPressed,
            child: Text(
              buttonLabel,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          if (secondaryLabel != null && onSecondaryPressed != null) ...[
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: busy ? null : onSecondaryPressed,
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(AppSizes.touchTarget),
              ),
              child: Text(
                secondaryLabel!,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _IntroSportBalls extends StatelessWidget {
  const _IntroSportBalls();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Text(
          '올라운드',
          style: tt.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
          ),
        ),
        const Spacer(),
        Text(
          '로그인',
          style: tt.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _MarketingConsentRow extends StatelessWidget {
  const _MarketingConsentRow({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged,
              side: BorderSide(color: cs.outline, width: 1.4),
            ),
            Expanded(
              child: Text(
                '마케팅 정보 수신 동의 (선택)',
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

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      onSubmitted: onSubmitted,
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
