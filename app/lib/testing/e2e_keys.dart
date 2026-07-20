import 'package:flutter/foundation.dart';

/// 앱·웹 E2E가 화면 문구 변경에 의존하지 않도록 제공하는 안정적인 locator 정본.
class AllRoundE2EKeys {
  const AllRoundE2EKeys._();

  static const loginScreen = Key('e2e-login-screen');
  static const emailFlowButton = Key('e2e-email-flow-button');
  static const emailField = Key('e2e-email-field');
  static const passwordField = Key('e2e-password-field');
  static const passwordConfirmField = Key('e2e-password-confirm-field');
  static const signupBirthDate = Key('e2e-signup-birth-date');
  static const authSubmitButton = Key('e2e-auth-submit-button');
  static const authModeToggle = Key('e2e-auth-mode-toggle');
  static const googleExistingLoginButton =
      Key('e2e-google-existing-login-button');
  static const googleExistingLoginConfirm =
      Key('e2e-google-existing-login-confirm');
  static const googleEmailSignupAction = Key('e2e-google-email-signup-action');

  static const onboardingScreen = Key('e2e-onboarding-screen');
  static const onboardingNameField = Key('e2e-onboarding-name-field');
  static const onboardingNicknameField = Key('e2e-onboarding-nickname-field');
  static const onboardingBirthDate = Key('e2e-onboarding-birth-date');
  static const onboardingPrimaryAction = Key('e2e-onboarding-primary-action');
  static const homeScreen = Key('e2e-home-screen');
  static const homeLoadingState = Key('e2e-home-loading-state');
  static const homeEmptyState = Key('e2e-home-empty-state');
  static const homeErrorState = Key('e2e-home-error-state');
  static const homeTournamentList = Key('e2e-home-tournament-list');
  static const tournamentsScreen = Key('e2e-tournaments-screen');
  static const tournamentDetailScreen = Key('e2e-tournament-detail-screen');
  static const tournamentFavoriteSaved = Key('e2e-tournament-favorite-saved');
  static const tournamentFavoriteUnsaved =
      Key('e2e-tournament-favorite-unsaved');
  static const clubsScreen = Key('e2e-clubs-screen');
  static const moreScreen = Key('e2e-more-screen');
  static const notificationsScreen = Key('e2e-notifications-screen');
  static const notificationsReady = Key('e2e-notifications-ready');
  static const favoritesScreen = Key('e2e-favorites-screen');
  static const favoritesReady = Key('e2e-favorites-ready');
  static const friendScheduleScreen = Key('e2e-friend-schedule-screen');
  static const rulesScreen = Key('e2e-rules-screen');
  static const rulesReady = Key('e2e-rules-ready');
  static const blockedUsersScreen = Key('e2e-blocked-users-screen');
  static const blockedUsersReady = Key('e2e-blocked-users-ready');
  static const tournamentSubmitScreen = Key('e2e-tournament-submit-screen');
  static const clubDetailScreen = Key('e2e-club-detail-screen');
  static const clubFavoriteSaved = Key('e2e-club-favorite-saved');
  static const clubFavoriteUnsaved = Key('e2e-club-favorite-unsaved');
  static const clubJoinPendingAction = Key('e2e-club-join-pending-action');
  static const clubJoinAvailableAction = Key('e2e-club-join-available-action');
  static const clubIntroTab = Key('e2e-club-intro-tab');
  static const clubMembersTab = Key('e2e-club-members-tab');
  static const clubEventsTab = Key('e2e-club-events-tab');
  static const clubPostsTab = Key('e2e-club-posts-tab');
  static const clubManagementTab = Key('e2e-club-management-tab');
  static const clubManagementContent = Key('e2e-club-management-content');
  static const profileScreen = Key('e2e-profile-screen');
  static const profileAppearanceSection = Key('e2e-profile-appearance-section');
  static const adminScreen = Key('e2e-admin-screen');

  static const globalChatDock = Key('e2e-global-chat-dock');
  static const embeddedChatSheet = Key('e2e-embedded-chat-sheet');
  static const fullChatScreen = Key('e2e-full-chat-screen');
  static const chatExpandButton = Key('e2e-chat-expand-button');
  static const chatInput = Key('e2e-chat-input');
  static const chatContextToggle = Key('e2e-chat-context-toggle');
  static const chatContextDetached = Key('e2e-chat-context-detached');
  static const chatContextAttached = Key('e2e-chat-context-attached');
  static const latestAssistantMessage = Key('e2e-latest-assistant-message');

  static const navToday = Key('e2e-nav-today');
  static const navTournaments = Key('e2e-nav-tournaments');
  static const navClubs = Key('e2e-nav-clubs');
  static const navProfile = Key('e2e-nav-profile');

  static Key onboardingRegion(String code) =>
      ValueKey<String>('e2e-onboarding-region-$code');

  static Key onboardingGrade(String sport, String grade) =>
      ValueKey<String>('e2e-onboarding-grade-$sport-$grade');

  static Key tournamentCard(String tournamentId) =>
      ValueKey<String>('e2e-tournament-card-$tournamentId');
}
