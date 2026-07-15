# 스토어 제출 체크리스트 (Apple App Store + Google Play)

> **목적**: 출시 제출 전 빠뜨리기 쉬운 필수 요건을 한곳에. 리젝 → 재제출(1건당 1~3일 손실) 예방.
> **사용법**: 제출 직전 이 문서를 위→아래로 훑고 체크. 상태는 PR로 갱신.
> **전문가 관행**: "알아서" 하지 않는다. ① 이 체크리스트(release runbook) ② 스토어 콘솔 내장 프리런치 리포트 ③ QA 사인오프 ④ 심사용 데모 계정 — 이 4개를 항상 세트로 준비.
>
> 담당: 🤖 Play=kimabba · 🍎 Apple=백과장 · 에셋(아이콘/스크린샷)=백과장
> 리서치 출처는 문서 하단 참고.

## 현재 실행 순서 (2026-07-15)

1. **릴리스 준비 변경 확정** — 아이콘·권한 문구·지원/삭제 페이지·심사 문서를 PR에 반영하고 리뷰한다.
2. **PR #224 머지·운영 반영** — UGC/클럽 DB 마이그레이션과 Edge Function을 배포한 뒤 공개 약관·지원 URL을 확인한다.
3. **심사 계정 준비** — 이메일 인증 완료 일반 사용자 계정과 필요 시 관리자 계정을 만들고 종목·등급·지역·테스트 클럽을 준비한다.
4. **플랫폼 빌드 준비** — Mac 여유 공간을 최소 10GB 확보하고, Android SDK/JDK와 기존 업로드 키를 확보해 AAB를 만들고 Apple Developer 프로비저닝을 준비한다.
5. **실기기 E2E** — 로그인, AI, 대회, 클럽, 신고·차단, 외부 링크, 로그아웃, 회원 탈퇴와 케이블 분리 재실행을 검증한다.
6. **스크린샷·콘솔 입력** — 검증된 Release 앱으로 스크린샷을 촬영하고 Data Safety/App Privacy/IARC/연령등급/심사 노트를 입력한다.

> 1~3은 Apple 서명 전에도 진행할 수 있다. 4~6은 계정·키·스토어 콘솔 권한이 있어야 완료할 수 있다.

## 우리 앱 프로필 (요건 판단 근거)
- 로그인: **이메일 + 구글**(제3자) — 계정 생성 있음
- **UGC 있음**: 클럽 게시판·댓글·모임 + AI 코치 채팅
- **AI 생성 콘텐츠**: Google Gemini 기반 코치봇
- **광고 SDK 없음 / 트래킹 SDK 없음** (→ ATT 불필요, 데이터안전 단순)
- 위치정보 **수집 안 함** ("지역"은 사용자 선택 설정값)
- 결제/구독 **없음** (무료)
- 스피드건은 **스코프 아웃** (리스팅/스크린샷 제외)

---

## 🔴 A. 타임라인 블로커 (제일 먼저 확인 — 늦게 알면 출시 지연)

- [ ] **[Play] 개인 계정 비공개 테스트 요건** — 계정이 2023-11 이후 생성된 **개인 계정**이면, 프로덕션 전에 **테스터 12명 × 14일 연속** 비공개 테스트 필수. → 출시 최소 2주 리드타임. 조직 계정(D-U-N-S 인증)이면 면제. **kimabba: 계정 유형·생성일 지금 확인.**
- [ ] **[Apple] 유료 개발자 프로그램 가입** ($99/년) + 계약·세무·뱅킹 "Agreements, Tax, and Banking" 완료 (미완이면 제출 자체 불가)
- [ ] **[Play] 개발자 등록** ($25 1회) + 신원 확인(개인/사업자) 완료

---

## 🟢 B. 공통 선결 (양 플랫폼 동일)

### 법적·개인정보
- [x] **개인정보 처리방침 공개 URL** (렌더 O, 수정불가, 비-PDF) — GitHub Pages: `https://kimabba.github.io/AllRound/legal/privacy-policy.html` ✅
- [x] **이용약관 공개 URL** — `https://kimabba.github.io/AllRound/legal/terms-of-service.html` ✅
- [ ] **고객지원 URL** — `https://kimabba.github.io/AllRound/legal/support.html` 파일 준비 완료, PR 머지 후 공개 확인
- [ ] **계정 삭제 안내 URL** — `https://kimabba.github.io/AllRound/legal/account-deletion.html` 파일 준비 완료, PR 머지 후 공개 확인
- [x] 개인정보 방침 연락처 이메일 **실제 수신 가능** (`demian.772@gmail.com`) ✅
- [ ] 개인정보 방침 링크가 **앱 내부 + 스토어 리스팅 둘 다**에 노출 (앱 내부 = 더보기 화면 ✅, 스토어 = 제출 시 입력)
- [ ] **회원 탈퇴(계정 삭제)** 인앱 제공 + 실제 동작 (JY-112, 코드 완료 → **E2E 검증 필요**). Apple·Play 둘 다 필수.

### 콘텐츠·심사 정책
- [ ] **UGC 안전장치** (JY-115): 신고·차단·필터·관리자 제재·명시적 EULA 코드 완료. **DB 마이그레이션/함수 배포 + 실기기 E2E 검증 대기.**
- [ ] **AI 생성 콘텐츠 고지** — AI 생성 표시와 답변별 신고 경로 코드 완료. **실기기 E2E 검증 대기.**
- [ ] **연령 등급** — Play IARC 설문 / Apple 연령등급 설문. UGC·채팅 있으면 등급 상향 요인.
- [ ] 앱 내 **모든 외부 링크 동작** (개인정보/약관/지원)

### 심사 대응 (리젝 예방 핵심)
- [ ] **심사용 데모 계정** 제공 (이메일 로그인 계정). 종목/등급/지역 세팅되어 핵심 기능(대회 추천·클럽·채팅) 바로 보이게. 어드민 기능 있으면 역할별 계정.
- [ ] **심사 노트(Review Notes)** — `docs/store-review-notes.md` 초안 완료. 데모 계정 이메일·비밀번호 입력 후 콘솔 등록
- [ ] 크래시/빈화면 없이 **첫 실행~핵심 플로우** 통과 (실기기)

---

## 🤖 C. Google Play 전용

### 빌드·기술
- [x] **타깃 API 레벨** — Google Play 공식 현재 기준 신규앱/업데이트는 Android 15 **API 35 이상**. `targetSdk=35` ✅ (참고: `android-release-build.md`)
- [ ] **AAB** 업로드 (APK 아님) + **Play 앱 서명** 활성화 (최초 업로드 시 설정) — 키스토어 alias `allround-upload`
- [x] `minSdk=24` 확인 ✅
- [ ] 앱 소스 매니페스트에는 INTERNET만 선언, 위치/저장소 권한 없음. **Release AAB 생성 후 병합 매니페스트 재확인 필요**

### 스토어 콘텐츠
- [ ] 앱 이름/짧은설명/전체설명 입력 (`docs/store-listing.md` 사용) ✅ 텍스트 준비됨
- [ ] **그래픽 에셋**: 앱 아이콘(512²)·피처 그래픽(1024×500) 준비 완료 (`docs/store-assets/`). 폰 스크린샷 최소 2장(권장 4~8장) 촬영 대기 — 스피드건 제외
- [ ] 카테고리(스포츠), 태그, 연락처 정보

### 정책 폼 (제출 게이트)
- [ ] **데이터 안전(Data Safety) 폼** — `docs/legal/play-data-safety.md` 답변 확정본 준비. Play Console 입력 대기
- [ ] **콘텐츠 등급**(IARC) 설문
- [ ] **광고 포함 여부** = 아니오 (광고 SDK 없음)
- [ ] **정부/금융/건강/뉴스** 해당 없음 확인
- [ ] 대상 고객층·아동 정책(Families) — 만 14세+ 타깃, 아동 대상 아님

### 출시 트랙
- [ ] 내부 테스트 → (개인계정) 비공개 테스트 12명/14일 → 프로덕션. A항목 참고.

---

## 🍎 D. Apple App Store 전용

### 로그인·계정
- [ ] **Sign in with Apple 필요성 판단** — 제3자(구글) 로그인을 쓰면 원칙상 Sign in with Apple 병행 필요. **단 자체 이메일 로그인(이름+이메일만 수집)도 제공하면 면제 소지.** 우리는 Supabase 이메일 로그인 있음 → 면제 주장 가능하나 **리젝 단골 포인트라 심사노트에 명시**. (애플 로그인 자체는 스킵 결정 — `START-HERE` §7)
- [ ] 계정 삭제 인앱 제공 (공통 B와 동일, JY-112)

### 개인정보
- [ ] **App Privacy(영양성분표)** — App Store Connect에 입력. 제3자 SDK 관행 포함. `play-data-safety.md`의 Apple 매핑 참고. 제출 게이트.
- [ ] **ATT(앱 추적 투명성)** = 불필요 (트래킹 SDK 없음) — 확인만
- [x] `Info.plist` 카메라·사진 보관함 usage description을 실제 프로필/클럽/신고 이미지 용도로 정합화 ✅

### 심사 정책
- [ ] **UGC 1.2** — 공통 B의 신고/차단/필터/EULA (2026-02 애플이 채팅을 1.2로 명확화). AI 채팅 포함.
- [ ] **가이드라인 4.2 최소 기능성** — 웹래퍼/빈껍데기로 안 보이게, 네이티브 가치 명확히
- [ ] **5.1.1 데이터 수집** — 필요 최소, 로그인 강제 최소화
- [ ] 딥링크/OAuth 콜백 스킴 정상 (`kr.allround.app://login-callback/`) — Redirect URL 등록 확인

### 빌드·에셋
- [ ] 최종 Archive/TestFlight 빌드 전 Mac 여유 공간 최소 10GB 확보 (점검 중 129MB까지 감소해 빌드·시뮬레이터 설치가 한 차례 실패함)
- [x] `.env.local` 포함, 코드서명 없는 iPhoneOS Release 컴파일 성공 — `Runner.app` arm64, 번들 ID `kr.allround.app`, 버전 `1.0.0 (1)` ✅
- [x] `ffmpeg_kit_flutter_new` 4.4.2로 갱신 — iOS simulator arm64, FFmpeg 보안 수정, Android Release JNI/흰 화면 수정 반영 ✅
- [x] iPhone 17 Pro / iOS 26.5 시뮬레이터 빌드·설치·첫 실행·종료 후 재실행 성공. 로그인 화면 정상 렌더, 프로세스 유지, 치명 로그 없음 ✅
- [x] iPhone 13 Pro / iOS 26.5 실기기에 `.env.local` 포함 Release 앱 설치 성공. 무료 테스트 ID `kr.allround.app.localtest`로 첫 실행·완전 종료 후 재실행·Wi-Fi 해제 후 셀룰러 실행까지 흰 화면/튕김 없이 통과 ✅ (로컬 프로파일 만료: 2026-07-21 18:40 KST, 조직 서명/TestFlight는 별도 진행)
- [ ] Xcode 최신 SDK 빌드, TestFlight 업로드 → 내부 테스트
- [ ] 스크린샷: 6.7"/6.9" 필수 세트 (+ iPad 지원 시 iPad). 스피드건 제외
- [x] 앱 아이콘 1024², 알파 없음 확인 ✅. 이름/부제/키워드/설명은 `store-listing.md` 준비
- [ ] **수출 규정(Export Compliance)** — 표준 HTTPS만 사용이면 면제 신고

---

## ✅ E. 제출 직전 최종 게이트 (양쪽 공통, 마지막에)
- [ ] 실기기에서 로그인→핵심기능→로그아웃→**회원탈퇴** 전체 1회 통과
- [ ] 개인정보/약관 링크 실기기에서 **렌더 확인** (소스노출 X)
- [ ] 데모 계정 로그인 되는지 재확인 (심사관이 못 들어가면 즉시 리젝)
- [ ] 버전코드/버전명 최종 확정. `docs/release-notes/1.0.0.md` 초안 완료
- [ ] 개인정보 폼 ↔ 실제 수집 ↔ 개인정보 방침 **3자 일치**
- [ ] 스토어 리스팅에 개인정보 URL 입력 완료

## 🚫 흔한 리젝 사유 (예방 관점)
- 계정 삭제 경로 없음/안 보임 → **B 회원탈퇴**
- 개인정보 URL이 404/PDF/소스노출 → **B 법적** (우리가 Supabase→Pages 전환한 이유)
- UGC 신고/차단 없음 → **JY-115**
- 데이터안전/영양성분표 ↔ 실제 ↔ 방침 불일치 → **최종 게이트**
- 데모 계정 미제공/로그인 불가 → **심사 대응**
- (Play) 개인계정 12/14 테스트 미이행 → **A 타임라인**

---

## 상태 요약 (2026-07-15 기준)
| 항목 | 상태 |
|---|---|
| 개인정보/약관 호스팅(렌더) | ✅ GitHub Pages 완료 (#199) |
| 회원 탈퇴 코드 | ✅ JY-112 (E2E 검증 대기) |
| 데이터안전/영양성분표 답변 시트 | ✅ `play-data-safety.md` 정합화 완료, 콘솔 입력 대기 |
| 스토어 리스팅 텍스트 | ✅ `store-listing.md` |
| 심사 노트/릴리스 노트 | ✅ 초안 완료, 데모 계정 정보만 입력 대기 |
| UGC 신고·차단·EULA | ⏳ JY-115 |
| 아이콘·피처 그래픽 | ✅ 올라운드 마크로 교체·규격 검증 완료 |
| 스토어 스크린샷 | ⏳ 실제 앱 화면 촬영 대기 |
| iOS 무서명 Release 컴파일 | ✅ iPhoneOS arm64 `Runner.app` 생성, 번들/버전/권한 문구 확인 |
| iOS 시뮬레이터 QA | ✅ iPhone 17 Pro 첫 실행·재실행 정상, 흰 화면/즉시 종료 없음 |
| iOS 실기기 Release QA | ✅ iPhone 13 Pro에서 첫 실행·재실행·셀룰러 실행 정상 (`localtest`, 2026-07-21 만료) |
| Android SDK/JDK·Release AAB | ⏳ 이 Mac에 SDK/JDK·업로드 키가 없어 빌드 대기 (`targetSdk=35` 설정은 확인) |
| Play 개인계정 12/14 테스트 | ⏳ 계정유형 확인 필요 |
| 심사용 데모 계정·노트 | ⏳ |

## 참고 (리서치 출처)
- [Play Console — 앱 심사 준비](https://support.google.com/googleplay/android-developer/answer/9859455)
- [Play — 타깃 API 레벨 요건](https://developer.android.com/google/play/requirements/target-sdk)
- [Apple — App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Apple — 계정 삭제 제공](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
- [Apple — 제출 가이드](https://developer.apple.com/app-store/submitting/)
