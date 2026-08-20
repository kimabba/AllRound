import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('로컬 시드는 프리뷰와 같은 클럽·멤버십·모집글을 제공한다', () {
    final seed = File('../supabase/seed.sql').readAsStringSync();

    final tennisClubIds = RegExp(
      "'10000000-0000-4000-8000-0000000000\\d{2}'",
    ).allMatches(seed).map((match) => match.group(0)).toSet();
    final futsalClubIds = RegExp(
      "'20000000-0000-4000-8000-0000000000\\d{2}'",
    ).allMatches(seed).map((match) => match.group(0)).toSet();
    final recruitingPostIds = RegExp(
      "'30000000-0000-4000-8000-0000000000\\d{2}'",
    ).allMatches(seed).map((match) => match.group(0)).toSet();

    expect(tennisClubIds, hasLength(10));
    expect(futsalClubIds, hasLength(10));
    expect(recruitingPostIds, hasLength(4));
    expect(seed, contains('insert into public.club_members'));
    expect(seed, contains("where email = 'local-admin@allround.invalid'"));
    expect(
      RegExp("v_local_user_id, '(owner|member)', 'active'").allMatches(seed),
      hasLength(4),
    );
    expect(seed, contains('insert into public.user_sports'));
    expect(seed, contains('insert into public.club_posts'));
    expect(seed, contains('insert into public.venues'));
    expect(seed, contains('insert into public.org_rankings'));
    expect(seed, contains('insert into public.org_player_results'));
    expect(
      seed,
      contains(
        "asset://assets/images/clubs/tennis-logo.png",
      ),
    );
    expect(
      seed,
      contains(
        "asset://assets/images/clubs/futsal-logo.png",
      ),
    );
  });
}
