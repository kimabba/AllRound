# Android Release AAB 빌드

## 현재 프로젝트 설정

- application ID: `kr.allround.app`
- 앱 버전: `app/pubspec.yaml`의 `1.0.0+1`
- min SDK: 24
- compile SDK: Flutter 3.44 기본값 36
- target SDK: 35
- 업로드 키 별칭: `allround-upload`

Google Play 공식 현재 요구사항은 신규 앱과 업데이트가 Android 15(API 35) 이상을 타깃하는 것입니다. 프로젝트의 `targetSdk=35`는 이를 충족합니다.

공식 문서: https://developer.android.com/google/play/requirements/target-sdk

## 이 Mac에서 확인된 선행 조건

2026-07-15 점검 결과 다음 파일·도구가 없습니다.

- Android SDK / Android Studio JDK
- `app/android/key.properties`
- 업로드 키 `.jks`
- 기존 Release `.aab`

따라서 현재는 Play 업로드용 AAB를 만들 수 없습니다.

## 1. Android 도구 설치

0. Mac 여유 공간을 최소 10GB 확보합니다. Flutter/Xcode/Gradle 산출물이 수 GB를 사용합니다.
1. Android Studio를 설치합니다.
2. SDK Manager에서 Android SDK Platform 36, 최신 Build Tools, Command-line Tools를 설치합니다.
3. 터미널에서 `flutter doctor -v`의 Android toolchain이 통과하는지 확인합니다.
4. SDK를 자동 인식하지 못하면 설치 경로를 확인한 뒤 `flutter config --android-sdk <SDK 경로>`를 실행합니다.

## 2. 업로드 키 복구 또는 생성

먼저 Play Console에 이 앱의 AAB를 업로드한 적이 있는지 확인합니다.

- **업로드한 적이 있다면:** 당시 사용한 `.jks`와 비밀번호를 복구해야 합니다. 새 키를 임의 생성하지 않습니다. 분실했다면 Play Console의 업로드 키 재설정 절차를 사용합니다.
- **한 번도 업로드하지 않았다면:** `cd app/android && bash generate-keystore.sh`로 새 업로드 키를 생성할 수 있습니다.

생성·복구 후 `app/android/key.properties.example`을 참고해 `app/android/key.properties`를 만듭니다. 비밀번호, `key.properties`, `.jks`는 Git에 커밋하지 않습니다.

키 파일은 암호 관리자와 별도 보안 저장소에 백업합니다. 파일 경로와 별칭도 함께 기록합니다.

## 3. 빌드

저장소 루트에서 실행합니다.

```bash
make release-android
```

성공 결과:

```text
app/build/app/outputs/bundle/release/app-release.aab
```

## 4. 제출 전 확인

- `flutter analyze`와 `flutter test` 통과
- Release AAB의 application ID가 `kr.allround.app`
- versionCode가 Play Console의 기존 값보다 큼
- 업로드 인증서가 Play Console에 등록된 업로드 인증서와 일치
- 병합 매니페스트에 불필요한 위치·저장소 권한이 없음
- Play App Signing 활성화

## 금지

- 키와 비밀번호를 채팅, 이슈, PR, 커밋에 붙이지 않습니다.
- 기존 앱을 Play Console에 업로드한 적이 있다면 확인 없이 새 키를 만들지 않습니다.
- `key.properties`가 없을 때 생성되는 debug 서명 AAB를 업로드하지 않습니다.
