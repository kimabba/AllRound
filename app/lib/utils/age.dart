// 만 나이 계산·가입 연령 게이트 (JY-133).
//
// 서버(users.birth_date 트리거)가 eligibility 의 source of truth 이고,
// 여기 클라이언트 게이트는 온보딩에서 즉시 안내·차단하기 위한 1차 방어다.

/// 개인정보보호법 §22의2 대응. 만 14세 미만 가입 불가(14세 이상은 본인 동의로 가입 가능).
const int kMinSignupAge = 14;

/// [birthDate] 의 [now] 기준 만 나이.
int ageOn(DateTime birthDate, DateTime now) {
  var age = now.year - birthDate.year;
  if (now.month < birthDate.month ||
      (now.month == birthDate.month && now.day < birthDate.day)) {
    age--;
  }
  return age;
}

/// [now] 기준 만 [kMinSignupAge]세 미만인가.
bool isUnderMinSignupAge(DateTime birthDate, DateTime now) =>
    ageOn(birthDate, now) < kMinSignupAge;
