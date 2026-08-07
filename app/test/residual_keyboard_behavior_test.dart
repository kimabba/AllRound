import 'dart:async';

import 'package:allround/models/club_event.dart';
import 'package:allround/models/moderation.dart';
import 'package:allround/models/tournament.dart';
import 'package:allround/screens/auth/onboarding_screen.dart';
import 'package:allround/screens/clubs/club_detail_screen.dart';
import 'package:allround/services/api.dart';
import 'package:allround/state/providers.dart';
import 'package:allround/testing/e2e_keys.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:allround/widgets/moderation/ugc_moderation_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _KeyboardApi extends ApiService {
  _KeyboardApi({this.club, this.monthlyFeeCompleter, this.reportCompleter})
      : super(
          SupabaseClient(
            'http://127.0.0.1:54321',
            'keyboard-test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final Club? club;
  final Completer<void>? monthlyFeeCompleter;
  final Completer<String>? reportCompleter;

  @override
  Future<Club> getClub(String clubId) async => club!;

  @override
  Future<List<ClubMember>> clubMembers(String clubId) async => const [];

  @override
  Future<List<ClubEvent>> clubEvents(String clubId) async => const [];

  @override
  Future<void> updateClubMonthlyFee(String clubId, int? monthlyFee) =>
      monthlyFeeCompleter?.future ?? Future<void>.value();

  @override
  Future<String> createUgcReport({
    required UgcTargetType targetType,
    required String targetId,
    required UgcReportReason reason,
    String? details,
    List<String> evidencePaths = const [],
  }) =>
      reportCompleter?.future ?? Future<String>.value('report-id');
}

void main() {
  testWidgets('월회비 저장을 시작하면 숫자 키패드를 즉시 닫는다', (tester) async {
    final saveCompleter = Completer<void>();
    final club = Club(
      id: 'keyboard-club',
      sport: 'tennis',
      name: '키보드 테스트 클럽',
      region: '서울',
      monthlyFee: 40000,
      myRole: 'owner',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiProvider.overrideWithValue(
            _KeyboardApi(club: club, monthlyFeeCompleter: saveCompleter),
          ),
          clubFavoriteIdsProvider.overrideWith((ref) async => const {}),
          currentUserProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: ClubDetailScreen(
            club: club,
            openManagement: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AllRoundE2EKeys.clubManagementTab));
    await tester.pumpAndSettle();

    final feeField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '월회비',
    );
    await tester.drag(
      find.byKey(AllRoundE2EKeys.clubManagementContent),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(feeField);
    await tester.tap(feeField);
    await tester.showKeyboard(feeField);
    await tester.enterText(feeField, '50000');
    expect(tester.testTextInput.isVisible, isTrue);

    final saveButton = find.widgetWithText(FilledButton, '저장');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(saveButton);

    expect(tester.testTextInput.isVisible, isFalse);

    saveCompleter.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('신고 접수를 시작하면 설명 입력 키보드를 즉시 닫는다', (tester) async {
    final reportCompleter = Completer<String>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiProvider.overrideWithValue(
            _KeyboardApi(reportCompleter: reportCompleter),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => FilledButton(
                onPressed: () => showUgcReportSheet(
                  context: context,
                  ref: ref,
                  targetType: UgcTargetType.club,
                  targetId: 'reported-club',
                ),
                child: const Text('신고 열기'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('신고 열기'));
    await tester.pumpAndSettle();
    final detailsField = find.widgetWithText(TextField, '상황 설명 (선택)');
    await tester.tap(detailsField);
    await tester.showKeyboard(detailsField);
    await tester.enterText(detailsField, '문제 상황 설명');
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.widgetWithText(FilledButton, '신고 접수'));

    expect(tester.testTextInput.isVisible, isFalse);

    reportCompleter.complete('report-id');
    await tester.pumpAndSettle();
  });

  testWidgets('온보딩 생년월일 피커를 열면 이름 입력 키보드를 닫는다', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => null),
          userSportsProvider.overrideWith((ref) async => const []),
          userTennisOrgsProvider.overrideWith((ref) async => const []),
          currentUserProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const OnboardingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nameField = find.byKey(AllRoundE2EKeys.onboardingNameField);
    final birthDate = find.byKey(AllRoundE2EKeys.onboardingBirthDate);
    await tester.ensureVisible(birthDate);
    await tester.tap(nameField);
    await tester.showKeyboard(nameField);
    await tester.enterText(nameField, '홍길동');
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(birthDate);

    expect(tester.testTextInput.isVisible, isFalse);
    await tester.pumpAndSettle();
    expect(find.text('생년월일 선택'), findsOneWidget);
  });
}
