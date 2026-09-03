# Google Play 출시 상태

- 확인일: 2026-08-19
- 상태: **Play Console 앱 생성 완료** — 내부 테스트 업로드 준비 단계
- 앱 이름: 올라운드 — 테니스·풋살 동호인
- Android Application ID: `kr.allround.android` (2026-08-19 변경 — 아래 참고)
- 앱 버전: `1.1.0+7`

## Play Console 현재 상태 (2026-08-19)

- 개발자 계정: 제이영컨설팅 **조직 계정 생성 완료** (계정 ID `8500472001670685013`, 2026-08-17 생성). DUNS 주소 문제 해소됨.
- 로그인 계정: **`play@jyoungad.kr`만 사용** (Demian.772 개인 계정 아님).
- 앱 생성 완료: 앱 ID `4973115702477050979`, 이름 `올라운드 — 테니스·풋살 동호인`, 한국어(ko-KR), 앱/무료.
- 대시보드: https://play.google.com/console/u/1/developers/8500472001670685013/app/4973115702477050979/app-dashboard

## ⚠️ 패키지 이름 변경 (2026-08-19 결정)

- 기존 `kr.allround.app`은 **외부의 다른 개발자 계정이 이미 선점**(스토어 비공개 초안, 우리 팀 것 아님 — Commander 확인)해서 사용 불가.
- 새 패키지 이름: **`kr.allround.android`** (Commander 확정, Play Console 사용 가능 실측 확인).
- iOS 번들 ID(`kr.allround.app`)와 달라도 문제 없음. 딥링크 scheme(`kr.allround.app://`)도 패키지 이름과 무관하므로 유지.
- **남은 코드 작업** (AAB 업로드 전 필수):
  1. Firebase 프로젝트 `allround-f2260`(백과장 소유)에 Android 앱 `kr.allround.android` 추가 등록 + 새 `google-services.json` 발급 — 백과장 협조 필요
  2. `app/android/app/build.gradle.kts`의 `applicationId`를 `kr.allround.android`로 변경 (namespace는 유지 가능)
  3. `app/android/app/google-services.json` 교체
  4. Google 로그인용 SHA-1/SHA-256을 Firebase 새 앱에 등록

## 로컬 준비 상태

| 항목 | 상태 | 메모 |
|---|---|---|
| 스토어 등록 문구 | 준비 | `docs/store-listing.md` |
| 개인정보·약관 URL | 준비 | 앱은 새 도메인 `https://all-round.it.kr/privacy/`·`/terms/` 사용(2026-09-03). Play Console 등록 시 이 주소로 넣어야 함(옛 GitHub Pages 주소는 그대로 남아 있음) |
| Play 데이터 안전 답변 | 초안 | 본인확인 도입 시 전화번호·CI 흐름을 반영해 다시 작성 필요 |
| 앱 아이콘 | 원본 준비 | `app/assets/branding/app_icon_master.png`, 1024×1024 |
| 피처 그래픽 | 미확인 | 1024×500 파일을 찾지 못함 |
| 휴대전화 스크린샷 | 미확인 | Play 제출용 세트를 찾지 못함 |
| 업로드 서명 설정 | 현재 작업공간에 없음 | `android/key.properties`와 업로드 키 저장 위치 확인 필요 |
| AAB | 검증 빌드 완료·업로드본 대기 | API 36 release AAB 생성 성공. 현재는 디버그 키 서명이라 Play 업로드 금지 |
| Target API | 준비 | `compileSdk`와 `targetSdk` 36, release 병합 매니페스트까지 확인 |
| Application ID | 준비 | `kr.allround.app` |

## 앱 설정 체크리스트 진행 (2026-08-19)

| 항목 | 상태 |
|---|---|
| 개인정보처리방침 URL | ✅ 저장 |
| 광고 (없음) | ✅ 저장 |
| 정부 앱 (아니요) | ✅ 저장 |
| 금융 기능 (없음) | ✅ 저장 |
| 건강 (없음) | ✅ 저장 |
| 앱 카테고리 (스포츠) + 연락처 (play@jyoungad.kr) | ✅ 저장 |
| 콘텐츠 등급 (IARC 설문) | ✅ 제출됨 — 전체이용가/PEGI 3, 사용자 상호작용 표기 |
| 데이터 보안 | 🟡 설문 전부 입력(12개 유형: 위치2·개인정보3·메시지·사진·UGC·크래시2·기기ID). 최종 제출은 타겟층 완료가 선행 조건 |
| 스토어 등록정보 | 🟡 이름·짧은/전체 설명·아이콘(512px) 입력, 임시보관함 저장. 피처 그래픽 1024×500·휴대전화 스크린샷 2~8장 필요(백과장) |
| 로그인 세부정보 | ⬜ 심사 계정 아이디·비밀번호 필요 (Commander만 보유, 저장소 기록 금지) |
| 타겟층 | ⬜ 로그인 세부정보 완료 후 진행 가능 |

데이터 보안 신고 요지: 제3자 공유 없음 / 전송 암호화 / 계정·데이터 삭제 URL = 개인정보처리방침 / 위치는 임시 처리·선택.

## 다음 순서

1. ~~개발자 계정 생성~~ ✅ 완료 (2026-08-17, 조직 계정)
2. ~~Play Console에서 새 앱 생성~~ ✅ 완료 (2026-08-19)
3. 백과장에게 Firebase `allround-f2260`에 Android 앱 `kr.allround.android` 등록 + `google-services.json` 요청.
4. `applicationId` 변경 + `google-services.json` 교체 PR.
5. Android 16 실기기 또는 에뮬레이터에서 edge-to-edge·뒤로가기·핵심 동선을 확인한다.
6. 기존 업로드 키 위치를 확인한다. 없을 때만 새 업로드 키를 생성하고 안전하게 백업한다.
7. 릴리스 AAB를 빌드해 내부 테스트 트랙에 업로드한다.
8. 스토어 문구·아이콘·피처 그래픽·스크린샷·콘텐츠 등급·데이터 안전 폼을 완료한다.

## 공식 자료

- [Google Play 개발자 계정 유형 선택](https://support.google.com/googleplay/android-developer/answer/13634885?hl=ko)
- [Play Console 개발자 계정 생성에 필요한 정보](https://support.google.com/googleplay/android-developer/answer/13628312?hl=ko)
- [새 개인 개발자 계정의 테스트 요구사항](https://support.google.com/googleplay/android-developer/answer/14151465?hl=ko)
- [Google Play Target API 요구사항](https://developer.android.com/google/play/requirements/target-sdk)
