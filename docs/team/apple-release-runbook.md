# Apple App Store 릴리스 운영 기준

> 이 문서는 Apple App Store 업데이트의 기술 값·담당·순서를 공유하는 정본이다.
> App Store Connect의 실제 상태와 이 문서가 다르면, 다음 릴리스 전에 백과장과
> 값을 확인하고 이 문서를 먼저 갱신한다.

## 1. 현재 등록 정보

| 항목 | 정본 값 | 의미 |
|---|---|---|
| 앱 이름 | 올라운드 (AllRound) | App Store 앱 |
| Apple App ID | `6792671473` | App Store 제품 식별자 |
| iOS Bundle ID | `kr.jyoung.allround` | Xcode 서명·App Store 연결용. 변경 금지 |
| 딥링크 스킴 | `kr.allround.app` | 로그인·비밀번호 재설정 앱 복귀용. Bundle ID와 다름 |
| Apple Team ID | `NARLC9NNW6` | Xcode 서명 팀 |
| 현재 배포 버전 | `1.0.0 (5)` | 2026-08-04 한국 App Store 출시 |
| 제품 페이지 | <https://apps.apple.com/kr/app/id6792671473> | 공개 확인용 |

### 값의 소스

- 사용자에게 보이는 버전과 빌드번호: [`app/pubspec.yaml`](../../app/pubspec.yaml)
- 빌드 게이트의 빌드번호: [`app/lib/config.dart`](../../app/lib/config.dart)
- iOS Bundle ID·Team·서명 프로필: [`project.pbxproj`](../../app/ios/Runner.xcodeproj/project.pbxproj)
- App Store 설명·개인정보·심사 상태: App Store Connect
- 작업 진행 상태: Linear와 해당 PR

`kr.allround.app`를 iOS Bundle ID로 문서에 다시 쓰지 않는다. 현재 값은 로그인
콜백 스킴이며, iOS App Store Bundle ID는 `kr.jyoung.allround`이다. 두 값을 바꾸면
기존 설치 앱의 업데이트 연결이나 로그인 복귀가 깨질 수 있다.

## 2. 버전 번호 규칙

`pubspec.yaml`의 `version: 사용자버전+빌드번호`가 기준이다.

| 구분 | 예시 | 규칙 |
|---|---:|---|
| 사용자 버전 | `1.0.1` | 수정판은 마지막 숫자 증가, 기능 묶음은 가운데 숫자 증가 |
| 빌드번호 | `6` | 업로드할 때마다 이전 배포·테스트 빌드보다 크게 증가 |
| Flutter 표기 | `1.0.1+6` | 사용자 버전과 빌드번호를 함께 기록 |

다음 수정판은 특별한 제품 버전 결정이 없다면 `1.0.1+6`으로 시작한다.
`appBuildNumber`도 같은 `6`으로 맞춰야 하며, 회귀 테스트가 두 값을 검사한다.

## 3. 담당과 권한

| 역할 | 담당 | 책임 |
|---|---|---|
| 앱 코드·버전 PR | 드론/kimabba | 버전 변경, QA, IPA 빌드, PR·CI |
| App Store Connect 운영 | 백과장 | 새 버전 생성, 빌드 선택, 메타데이터, 심사 제출·출시 |
| 출시 승인 | kimabba + 백과장 | 실기기 QA와 출시 여부 확인 |

Apple 계정 비밀번호를 공유하지 않는다. 백과장이 App Store Connect의
`Users and Access`에서 개인 Apple 계정을 초대한다. 빌드 업로드만 필요하면
Developer, 새 버전 생성·빌드 선택·심사 제출까지 하려면 App Manager 또는 Admin
권한이 필요하다.

## 4. 업데이트 절차

### A. 코드에서 준비

1. 목표 버전과 빌드번호를 먼저 정한다. 예: `1.0.1+6`.
2. `app/pubspec.yaml`의 `version`을 변경한다.
3. `app/lib/config.dart`의 `appBuildNumber`를 같은 빌드번호로 변경한다.
4. Bundle ID, Team ID, 딥링크 스킴은 변경하지 않는다.
5. 다음 검사를 통과시킨다.

```bash
cd app
flutter analyze
flutter test
flutter build ipa --dart-define-from-file=.env.local
```

6. PR에 다음 세 줄을 포함한다.
   - 무엇이 달라지나
   - 왜 했나
   - 확인하는 법

### B. App Store Connect에서 처리

1. Apps → 올라운드 → iOS 옆 `+` → 새 버전 생성.
2. App Store 버전에 `1.0.1` 같은 사용자 버전을 입력한다.
3. IPA를 업로드하고 `TestFlight`에서 처리 완료를 기다린다.
4. 새 버전의 `Build`에서 처리 완료된 빌드번호를 선택한다.
5. 변경사항, 스크린샷, 심사 노트, 수출 규정 질문을 확인한다.
6. 실기기 QA가 끝나면 `심사 제출`한다.
7. 출시 방식은 자동 출시 또는 수동 출시 중 하나를 명시한다.
8. 출시 후 공개 제품 페이지와 실제 설치 업데이트를 확인한다.

처리 중인 빌드는 App Store Connect에 바로 보이지 않을 수 있다. `Complete`가
될 때까지 기다린 후 해당 버전을 선택한다.

## 5. 릴리스 이력

| 사용자 버전 | 빌드 | 상태 | 출시일 | PR/커밋 | 메모 |
|---|---:|---|---|---|---|
| `1.0.0` | `5` | 출시 완료 | 2026-08-04 | — | 첫 정식 출시 |
| `1.0.1` | `6` | 예정 | — | — | 다음 수정판 후보 |

새 빌드를 출시하면 위 표에 반드시 한 줄을 추가한다. 심사 반려·TestFlight
검증용 빌드도 빌드번호와 상태를 기록해 다음 번호를 누구나 알 수 있게 한다.

## 6. 출시 전 공유 메시지 양식

```text
[iOS 업데이트 준비]
버전: 1.0.1 (6)
변경:
코드: PR #___ / 커밋 ______
검증: flutter analyze / flutter test / 실기기 QA
IPA 업로드: 백과장 처리 필요
출시 방식: 자동 / 수동
```

## Apple 공식 참고

- [App Store Connect 계정과 역할](https://developer.apple.com/help/app-store-connect/manage-your-team/overview-of-accounts-and-roles)
- [새 버전 생성](https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version/)
- [빌드 업로드](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [제출할 빌드 선택](https://developer.apple.com/help/app-store-connect/manage-builds/choose-a-build-to-submit/)
