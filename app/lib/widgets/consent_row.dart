import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/in_app_browser_screen.dart';
import '../theme/tokens.dart';

/// 법정 고지 동의 체크박스. 가입 화면과 전화번호 인증 화면이 같은 모양을 쓴다
/// — 문구 규칙이 바뀌면 한 곳만 고치면 되도록 공용으로 둔다.
class ConsentRow extends StatelessWidget {
  const ConsentRow({
    super.key,
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

/// 약관·처리방침 원문으로 보내는 링크 버튼.
class LegalLinkButton extends StatelessWidget {
  const LegalLinkButton({super.key, required this.label, required this.url});

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
