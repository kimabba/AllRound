import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';

const Color _primaryBlue = Color(0xFF1E3A8A);
const Color _primaryBlueSoft = Color(0xFF1E40AF);
const Color _futsalGreen = Color(0xFF84CC16);
const Color _kakaoYellow = Color(0xFFFEE500);

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
  bool _marketingConsent = false;
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
                      controller: _email,
                      icon: Icons.email_outlined,
                      label: '이메일',
                      hintText: 'test@example.com',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _SheetAuthField(
                      controller: _password,
                      icon: Icons.lock_outline_rounded,
                      label: '비밀번호',
                      hintText: _signUp ? '6자 이상 입력' : null,
                      obscureText: true,
                      textInputAction:
                          _signUp ? TextInputAction.next : TextInputAction.done,
                      onSubmitted: (_) => _busy ? null : _emailAuth(),
                    ),
                    if (_signUp) ...[
                      const SizedBox(height: AppSpacing.md),
                      _SheetAuthField(
                        controller: _passwordConfirm,
                        icon: Icons.verified_user_outlined,
                        label: '비밀번호 확인',
                        hintText: '비밀번호를 한 번 더 입력',
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _busy ? null : _emailAuth(),
                      ),
                    ],
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
                      onPressed: _busy ? null : _emailAuth,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_signUp ? '회원가입 시작하기' : '로그인'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
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
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    // 로컬 관리자 모드(make admin): 컨슈머 카카오·마케팅·온보딩 카피를 숨기고
    // 이메일·구글 로그인만 노출. 실제 권한은 서버 RLS.
    final adminMode = AppConfig.adminMode;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomRight,
            colors: [_primaryBlue, _primaryBlueSoft, _futsalGreen],
            stops: [0, 0.52, 1],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                    maxWidth: 520,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: constraints.maxHeight * 0.20),
                      const _IntroSportBalls(),
                      SizedBox(height: constraints.maxHeight * 0.23),
                      const _IntroDots(),
                      const SizedBox(height: AppSpacing.xxl),
                      Text(
                        adminMode ? '관리자 로그인' : '주말마다\n같이 뛸 사람을 찾고 있나요?',
                        textAlign: TextAlign.left,
                        style: tt.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          height: 1.18,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        adminMode
                            ? '관리자 계정(이메일·구글)으로 로그인하세요.'
                            : '축구/풋살부터 테니스까지, 내 근처\n모임부터 대회까지 한눈에 확인하세요.',
                        style: tt.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.86),
                          height: 1.7,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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
                      if (!adminMode) ...[
                        _KakaoStartButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          '카카오 로그인은 준비 중입니다. 이메일 로그인을 이용해 주세요.'),
                                    ),
                                  );
                                },
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (AppConfig.googleWebClientId.isNotEmpty ||
                          AppConfig.googleIosClientId.isNotEmpty) ...[
                        _SocialButton(
                          onPressed: _busy ? null : _googleSignIn,
                          icon: Icons.account_circle_outlined,
                          label: '구글로 계속하기',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      TextButton(
                        onPressed: _busy ? null : _showEmailAuthSheet,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(44),
                        ),
                        child: const Text(
                          '이메일로 계속하기',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (!adminMode) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          '시작하면 이용약관과 개인정보 처리방침에\n동의한 것으로 간주됩니다.',
                          textAlign: TextAlign.center,
                          style: tt.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.64),
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _MarketingConsentRow(
                          value: _marketingConsent,
                          onChanged: (value) =>
                              setState(() => _marketingConsent = value ?? false),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _IntroSportBalls extends StatelessWidget {
  const _IntroSportBalls();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Text('⚽', style: TextStyle(fontSize: 108, height: 1)),
        SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 108,
          height: 108,
          child: CustomPaint(painter: _TennisBallPainter()),
        ),
      ],
    );
  }
}

class _TennisBallPainter extends CustomPainter {
  const _TennisBallPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.shortestSide / 2;
    final ballPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.35, -0.42),
        radius: 1,
        colors: [
          Color(0xFFECFF2E),
          Color(0xFFBFEA13),
          Color(0xFF8BC700),
        ],
      ).createShader(rect);
    canvas.drawCircle(center, radius * 0.88, ballPaint);

    final seamPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.14
      ..strokeCap = StrokeCap.round;
    final leftSeam = Path()
      ..moveTo(size.width * 0.24, size.height * 0.10)
      ..cubicTo(
        size.width * 0.54,
        size.height * 0.28,
        size.width * 0.54,
        size.height * 0.72,
        size.width * 0.24,
        size.height * 0.90,
      );
    final rightSeam = Path()
      ..moveTo(size.width * 0.76, size.height * 0.10)
      ..cubicTo(
        size.width * 0.46,
        size.height * 0.28,
        size.width * 0.46,
        size.height * 0.72,
        size.width * 0.76,
        size.height * 0.90,
      );
    canvas.drawPath(leftSeam, seamPaint);
    canvas.drawPath(rightSeam, seamPaint);

    final glossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width * 0.34, size.height * 0.28),
        radius * 0.18, glossPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _IntroDots extends StatelessWidget {
  const _IntroDots();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _IntroDot(active: true),
        SizedBox(width: AppSpacing.sm),
        _IntroDot(active: false),
        SizedBox(width: AppSpacing.sm),
        _IntroDot(active: false),
        SizedBox(width: AppSpacing.sm),
        _IntroDot(active: false),
        SizedBox(width: AppSpacing.sm),
        _IntroDot(active: false),
      ],
    );
  }
}

class _IntroDot extends StatelessWidget {
  const _IntroDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: active ? 28 : 10,
      height: 10,
      decoration: BoxDecoration(
        color: active ? Colors.white : Colors.white.withValues(alpha: 0.30),
        borderRadius: AppRadius.pill,
      ),
    );
  }
}

class _KakaoStartButton extends StatelessWidget {
  const _KakaoStartButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(64),
        backgroundColor: _kakaoYellow,
        foregroundColor: Colors.black,
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.35),
        disabledForegroundColor: Colors.black.withValues(alpha: 0.38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: 0.22),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_rounded, size: 22),
          SizedBox(width: AppSpacing.md),
          Text(
            '카카오로 시작하기',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ],
      ),
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
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged,
              side: const BorderSide(color: Colors.white, width: 1.6),
              checkColor: Colors.black,
              activeColor: _kakaoYellow,
            ),
            Text(
              '마케팅 정보 수신 동의 (선택)',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetAuthField extends StatelessWidget {
  const _SheetAuthField({
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
