import 'package:flutter/foundation.dart';

/// 앱·웹 E2E가 화면 문구 변경에 의존하지 않도록 제공하는 안정적인 locator 정본.
class AllRoundE2EKeys {
  const AllRoundE2EKeys._();

  static const loginScreen = Key('e2e-login-screen');
  static const emailFlowButton = Key('e2e-email-flow-button');
  static const emailField = Key('e2e-email-field');
  static const passwordField = Key('e2e-password-field');
  static const passwordConfirmField = Key('e2e-password-confirm-field');
  static const authSubmitButton = Key('e2e-auth-submit-button');
  static const authModeToggle = Key('e2e-auth-mode-toggle');

  static const onboardingScreen = Key('e2e-onboarding-screen');
  static const homeScreen = Key('e2e-home-screen');
  static const tournamentsScreen = Key('e2e-tournaments-screen');
  static const clubsScreen = Key('e2e-clubs-screen');
  static const moreScreen = Key('e2e-more-screen');
  static const adminScreen = Key('e2e-admin-screen');

  static const navCoach = Key('e2e-nav-coach');
  static const navTournaments = Key('e2e-nav-tournaments');
  static const navClubs = Key('e2e-nav-clubs');
  static const navMore = Key('e2e-nav-more');
}
