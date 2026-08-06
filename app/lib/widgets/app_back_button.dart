import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 이전 화면 기록이 없는 딥링크 진입에서도 사라지지 않는 뒤로가기.
class AppBackButton extends StatelessWidget {
  const AppBackButton({
    super.key,
    required this.fallbackLocation,
  });

  final String fallbackLocation;

  void _goBack(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    context.go(fallbackLocation);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: () => _goBack(context),
      icon: const BackButtonIcon(),
    );
  }
}
