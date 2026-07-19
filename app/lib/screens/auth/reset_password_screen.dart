import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/session_security.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';

/// 비밀번호 재설정 메일 딥링크(passwordRecovery 이벤트)로 진입하는 화면.
/// 세션은 이미 복원된 상태이므로 새 비밀번호만 받아 updateUser 로 설정한다.
/// 성공 시 userUpdated 이벤트가 발생해 라우터가 홈으로 되돌린다.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _password.text;
    if (password.length < 6) {
      setState(() => _error = '비밀번호는 6자 이상으로 입력해 주세요.');
      return;
    }
    if (password != _passwordConfirm.text) {
      setState(() => _error = '비밀번호가 서로 일치하지 않습니다.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final supa = ref.read(supabaseProvider);
      await supa.auth.updateUser(UserAttributes(password: password));
      // 성공: recovery 모드를 먼저 끄고(complete) 홈으로 이동. 플래그가 먼저
      // 꺼지므로 redirect 재평가 시 되돌림 race 가 없다.
      if (!mounted) return;
      ref.read(recoveryModeProvider.notifier).complete();
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비밀번호가 변경됐어요.')),
      );
      context.go('/');
    } on AuthException catch (e) {
      if (!mounted) return;
      final m = e.message.toLowerCase();
      setState(() {
        _busy = false;
        _error = m.contains('should be different')
            ? '이전과 다른 비밀번호로 설정해 주세요.'
            : '재설정에 실패했습니다. 링크가 만료됐다면 다시 요청해 주세요.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '새 비밀번호 설정',
                    style: tt.headlineSmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '사용할 새 비밀번호를 입력해 주세요.',
                    style: tt.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _Field(
                    controller: _password,
                    label: '새 비밀번호',
                    hintText: '6자 이상 입력',
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _Field(
                    controller: _passwordConfirm,
                    label: '새 비밀번호 확인',
                    hintText: '비밀번호를 한 번 더 입력',
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _busy ? null : _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _error!,
                      style: tt.bodySmall?.copyWith(
                        color: cs.error,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
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
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('비밀번호 변경'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // 링크 만료 등으로 재설정을 못 하거나 그만두려는 경우의 탈출구.
                  // 로그아웃하면 signedOut 이벤트로 recovery 모드가 풀려 로그인 화면으로.
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            try {
                              await signOutSecurely(
                                ref.read(supabaseProvider),
                              );
                            } catch (_) {
                              if (mounted) {
                                setState(
                                    () => _error = '로그아웃에 실패했습니다. 다시 시도해 주세요.');
                              }
                            }
                          },
                    child: const Text('취소하고 로그인으로'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hintText,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? hintText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: true,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: const Icon(Icons.lock_outline_rounded),
      ),
    );
  }
}
