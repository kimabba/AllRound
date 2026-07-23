import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_base.dart';
import '../../state/providers.dart';
import '../../testing/e2e_keys.dart';
import '../../widgets/app_buttons.dart';

/// 전화번호 SMS 인증(필수). 온보딩 완료 후 이 게이트를 통과해야 앱에 진입한다.
/// 성공 시 서버가 users.phone_verified_at 을 기록하고, 프로필을 무효화하면
/// 라우터 게이트가 홈으로 통과시킨다.
class VerifyPhoneScreen extends ConsumerStatefulWidget {
  const VerifyPhoneScreen({super.key});

  @override
  ConsumerState<VerifyPhoneScreen> createState() => _VerifyPhoneScreenState();
}

class _VerifyPhoneScreenState extends ConsumerState<VerifyPhoneScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();

  bool _busy = false;
  bool _sent = false; // 발송 완료 → 코드 입력 단계
  String? _error;
  int _cooldown = 0; // 재발송 쿨다운(초)
  Timer? _timer;

  static const _resendSeconds = 60;

  @override
  void initState() {
    super.initState();
    _phone.addListener(_onChanged);
    _code.addListener(_onChanged);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  int get _phoneDigits => _phone.text.replaceAll(RegExp(r'[^\d]'), '').length;
  bool get _phoneLooksValid => _phoneDigits >= 10;
  bool get _codeComplete => RegExp(r'^\d{6}$').hasMatch(_code.text);

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _send() async {
    if (_busy || !_phoneLooksValid || _cooldown > 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).sendOtp(_phone.text);
      if (!mounted) return;
      setState(() => _sent = true);
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('인증번호를 발송했습니다.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '인증번호 발송에 실패했습니다. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy || !_codeComplete) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).verifyOtp(_phone.text, _code.text);
      // 프로필을 새로 받아 phone_verified_at 반영 후 이동(게이트 재평가 레이스 방지).
      ref.invalidate(myProfileProvider);
      await ref.read(myProfileProvider.future);
      if (!mounted) return;
      context.go('/');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '인증에 실패했습니다. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      key: AllRoundE2EKeys.verifyPhoneScreen,
      appBar: AppBar(title: const Text('전화번호 인증')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('휴대폰 번호 인증', style: tt.headlineSmall),
              const SizedBox(height: 8),
              Text(
                '본인 확인을 위해 휴대폰 번호를 인증해 주세요. 인증번호가 문자로 발송됩니다.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              TextField(
                key: AllRoundE2EKeys.verifyPhoneNumberField,
                controller: _phone,
                enabled: !_sent && !_busy,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d\-+ ]')),
                ],
                decoration: const InputDecoration(
                  labelText: '휴대폰 번호',
                  hintText: '010-1234-5678',
                ),
              ),
              const SizedBox(height: 12),
              if (!_sent)
                AppPrimaryButton(
                  key: AllRoundE2EKeys.verifyPhoneSendButton,
                  label: '인증번호 받기',
                  loading: _busy,
                  onPressed: _phoneLooksValid ? _send : null,
                )
              else ...[
                TextField(
                  key: AllRoundE2EKeys.verifyPhoneCodeField,
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: '인증번호 6자리',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                AppPrimaryButton(
                  key: AllRoundE2EKeys.verifyPhoneConfirmButton,
                  label: '인증 완료',
                  loading: _busy,
                  onPressed: _codeComplete ? _verify : null,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: (_busy || _cooldown > 0) ? null : _send,
                  child: Text(
                    _cooldown > 0 ? '재발송 ($_cooldown초)' : '인증번호 재발송',
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.error_outline_rounded, size: 18, color: cs.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _error!,
                        style: tt.bodySmall?.copyWith(color: cs.error),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
