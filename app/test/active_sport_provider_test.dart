import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:allround/models/tournament.dart';
import 'package:allround/state/providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('primarySportFrom returns the primary registered sport', () {
    final sports = [
      UserSport(sport: 'tennis', grade: 'div4'),
      UserSport(sport: 'futsal', grade: 'intermediate', isPrimary: true),
    ];

    expect(primarySportFrom(sports), 'futsal');
  });

  test('primarySportFrom falls back to the first sport when no primary exists',
      () {
    final sports = [
      UserSport(sport: 'tennis', grade: 'div4'),
      UserSport(sport: 'futsal', grade: 'intermediate'),
    ];

    expect(primarySportFrom(sports), 'tennis');
  });

  // 화면에서 고른 종목이 로그아웃 후에도 남으면, 다음 로그인 계정이 남의 종목으로
  // 등급·추천·룰북·클럽 필터를 보게 된다.
  test('로그아웃하면 화면에서 고른 종목이 비워진다', () async {
    final auth = StreamController<AuthState>.broadcast();
    addTearDown(auth.close);

    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => auth.stream),
      ],
    );
    addTearDown(container.dispose);

    // listen 이 걸리도록 provider 를 구독 상태로 둔다.
    container.listen(activeSportProvider, (_, __) {});

    container.read(sportOverrideProvider.notifier).select('tennis');
    expect(container.read(activeSportProvider), 'tennis');

    auth.add(AuthState(AuthChangeEvent.signedOut, null));
    await Future<void>.delayed(Duration.zero);

    expect(container.read(sportOverrideProvider), isNull);
    expect(container.read(activeSportProvider), isNot('tennis'));
  });
}
