import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/matchup_logo.dart';

const Color _primaryBlue = Color(0xFF1E3A8A);
const Color _primaryBlueSoft = Color(0xFF1E40AF);
const Color _futsalGreen = Color(0xFF84CC16);
const Color _kakaoYellow = Color(0xFFFEE500);
const Color _ink = Color(0xFF0F172A);

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  Future<void> _emailAuth() async {
    final email = _email.text.trim();
    final password = _password.text;
    final passwordConfirm = _passwordConfirm.text;
    if (email.isEmpty) {
      setState(() => _error = '이메일을 입력해 주세요.');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = '이메일 형식으로 입력해 주세요.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = '비밀번호를 입력해 주세요.');
      return;
    }
    if (_signUp && password.length < 6) {
      setState(() => _error = '비밀번호는 6자 이상으로 입력해 주세요.');
      return;
    }
    if (_signUp && password != passwordConfirm) {
      setState(() => _error = '비밀번호가 서로 일치하지 않습니다.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final supa = ref.read(supabaseProvider);
      if (_signUp) {
        await supa.auth.signUp(email: email, password: password);
      } else {
        await supa.auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setMode({required bool signUp}) {
    if (_busy) return;
    setState(() {
      _signUp = signUp;
      _error = null;
      _password.clear();
      _passwordConfirm.clear();
    });
  }

  Future<void> _googleSignIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final supa = ref.read(supabaseProvider);
      await supa.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.matchup.app://login-callback/',
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_primaryBlue, _primaryBlueSoft, _futsalGreen],
            stops: [0, 0.55, 1],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.xxxl),
                    const _BrandMark(),
                    const SizedBox(height: AppSpacing.huge),
                    Text(
                      _signUp ? '환영해요!\n계정을 만들어볼까요?' : '주말마다\n같이 뛸 사람을 찾고 있나요?',
                      textAlign: TextAlign.left,
                      style: tt.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _signUp
                          ? '이메일과 비밀번호를 입력하면 내 근처 대회와 모임을 바로 확인할 수 있어요.'
                          : '풋살부터 테니스까지, 내 근처 모임과 대회를 한눈에 확인하세요.',
                      style: tt.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.86),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.huge),
                    _AuthField(
                      controller: _email,
                      icon: Icons.email_outlined,
                      label: '이메일',
                      hintText: 'test@example.com',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _AuthField(
                      controller: _password,
                      icon: Icons.lock_outline_rounded,
                      label: '비밀번호',
                      hintText: _signUp ? '6자 이상 입력' : null,
                      obscureText: true,
                      textInputAction: _signUp
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onSubmitted: (_) => _busy ? null : _emailAuth(),
                    ),
                    if (_signUp) ...[
                      const SizedBox(height: AppSpacing.md),
                      _AuthField(
                        controller: _passwordConfirm,
                        icon: Icons.verified_user_outlined,
                        label: '비밀번호 확인',
                        hintText: '비밀번호를 한 번 더 입력',
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _busy ? null : _emailAuth(),
                      ),
                    ],
                    if (_signUp) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        '테스트용 이메일 형식과 6자 이상 비밀번호를 입력해 주세요.',
                        style: tt.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE84118),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                _error!,
                                style: tt.bodySmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    FilledButton(
                      onPressed: _busy ? null : _emailAuth,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        backgroundColor: _kakaoYellow,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: Colors.white.withValues(
                          alpha: 0.35,
                        ),
                        disabledForegroundColor: Colors.black.withValues(
                          alpha: 0.38,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 8,
                        shadowColor: Colors.black.withValues(alpha: 0.24),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : Text(_signUp ? '회원가입 시작하기' : '이메일로 로그인'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _ModeSwitchButton(
                      label: _signUp ? '이미 계정이 있어요' : '계정이 없어요. 회원가입하기',
                      onPressed: () => _setMode(signUp: !_signUp),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: Colors.white.withValues(alpha: 0.42),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            child: Text(
                              '또는',
                              style: tt.labelSmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.86),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color: Colors.white.withValues(alpha: 0.42),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (AppConfig.googleWebClientId.isNotEmpty ||
                        AppConfig.googleIosClientId.isNotEmpty) ...[
                      _SocialButton(
                        onPressed: _busy ? null : _googleSignIn,
                        icon: Icons.account_circle_outlined,
                        label: '구글로 계속하기',
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    _SocialButton(
                      onPressed: null,
                      icon: Icons.chat_bubble_outline_rounded,
                      label: '카카오로 계속하기 (준비 중)',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      '시작하면 이용약관과 개인정보 처리방침에 동의한 것으로 간주됩니다.',
                      textAlign: TextAlign.center,
                      style: tt.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.huge),

                    // ── Dev 퀵로그인 (개발용) ───────────────────
                    if (const bool.fromEnvironment('dart.vm.product') ==
                        false) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: Colors.white.withValues(alpha: 0.42),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                              ),
                              child: Text(
                                'DEV',
                                style: tt.labelSmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: Colors.white.withValues(alpha: 0.42),
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed:
                            _busy ? null : () => _devLogin('ssfak@naver.com'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.pill,
                          ),
                        ),
                        child: const Text('Dev 어드민 로그인'),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _devLogin(String email) async {
    setState(() { _busy = true; _error = null; });
    try {
      // 1) dev-auth Edge Function 호출 → magic link 토큰 획득
      final baseUrl = AppConfig.apiBaseUrl;
      final res = await http.post(
        Uri.parse('$baseUrl/dev-auth'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      if (res.statusCode >= 400) {
        setState(() => _error = 'dev-auth 실패: ${res.body}');
        return;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final token = data['hashed_token'] as String;

      // 2) verifyOTP로 세션 설정
      final supa = ref.read(supabaseProvider);
      await supa.auth.verifyOTP(
        tokenHash: token,
        type: OtpType.magiclink,
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _SportBadge(
              icon: Icons.sports_soccer_rounded,
              background: Colors.white,
              foreground: _ink,
            ),
            SizedBox(width: AppSpacing.sm),
            _SportBadge(
              icon: Icons.sports_tennis_rounded,
              background: _kakaoYellow,
              foreground: Color(0xFF466300),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const MatchUpLogo(
          fontSize: 24,
          textColor: Colors.white,
          dotColor: _futsalGreen,
        ),
      ],
    );
  }
}

class _SportBadge extends StatelessWidget {
  const _SportBadge({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Icon(icon, size: 34, color: foreground),
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.icon,
    required this.label,
    this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.onSubmitted,
  });

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
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      cursorColor: _kakaoYellow,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.42),
          fontWeight: FontWeight.w600,
        ),
        labelStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.76),
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.88)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.14),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kakaoYellow, width: 2),
        ),
      ),
    );
  }
}

class _ModeSwitchButton extends StatelessWidget {
  const _ModeSwitchButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
        minimumSize: const Size.fromHeight(48),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white.withValues(alpha: 0.54),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.46)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
