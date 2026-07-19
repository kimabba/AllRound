# AllRound Night Shift — 관찰 전용 QA 기반

## 목적

실제 개인정보나 운영 DB를 사용하지 않고, 고정된 합성 계정으로 인증·RLS·권한·개인정보 격리를 반복 검증한다. 이 단계는 실패 증거를 수집하지만 코드를 자동수정하거나 운영 환경에 배포하지 않는다.

## 안전 경계

- 모든 DB 명령은 `--local`을 명시한다.
- API와 DB 주소가 `127.0.0.1` 또는 `localhost`가 아니면 즉시 종료한다.
- 실제 회원 데이터를 로컬 fixture로 복사하지 않는다.
- service-role 키, anon 키, JWT, 비밀번호를 artifact에 기록하지 않는다.
- `artifacts/qa/`는 Git에서 제외한다.
- 운영 DB, 운영 Edge Function, 실제 이메일·푸시·OAuth는 이 러너의 범위 밖이다.

## 합성 계정

모든 이메일은 실제 전달이 불가능한 `.invalid` 예약 도메인을 사용한다.

| 계정 | 이메일 | 주요 상태 |
|---|---|---|
| QA-ADMIN | `qa-admin@allround.invalid` | 관리자 |
| QA-OWNER | `qa-owner@allround.invalid` | 테니스 클럽 owner |
| QA-MANAGER | `qa-manager@allround.invalid` | 테니스·풋살, club manager |
| QA-DELEGATE | `qa-delegate@allround.invalid` | 공지·일정 권한을 위임받은 member |
| QA-MEMBER | `qa-member@allround.invalid` | 양 종목 일반 member |
| QA-APPLICANT | `qa-applicant@allround.invalid` | 풋살 입문, 가입 신청 pending |
| QA-OFFENDER | `qa-offender@allround.invalid` | 제재·차단 대상 |
| QA-EMPTY | `qa-empty@allround.invalid` | 프로필·종목 미완성 |

비밀번호는 로컬 합성 계정 공통값 `QaLocal-Only-2026!`이다. 운영이나 스테이징 계정에 재사용하지 않는다.

## 실행

Docker Desktop은 앱 자체가 아니라 로컬 Supabase DB/Auth를 격리 실행하는 데 필요하다. 기본 실행은 DB를 현재 마이그레이션과 합성 seed로 완전히 초기화한다. 동시에 두 번 실행되지 않도록 프로세스 시작 시각까지 확인하는 로컬 잠금을 사용하고, 전체 실행은 기본 60분 안에 종료한다. 비정상 종료로 잠금이 남아도 소유 프로세스가 없거나 identity가 일치하지 않을 때만 다음 실행이 회수하며, 살아 있는 동일 실행의 잠금은 시간만으로 빼앗지 않는다.

웹 E2E를 처음 실행하기 전에는 설치된 Chrome과 같은 major의 ChromeDriver를 준비한다.

```bash
npx @puppeteer/browsers install chromedriver@150
```

위 숫자는 `Google Chrome --version`의 첫 번째 숫자에 맞춘다. 내려받은 `chromedriver/`는 Git에서 제외된다.

```bash
scripts/qa/night_shift_observe.sh
```

기존 로컬 DB를 유지하는 실행은 데이터 출처와 개인정보 포함 여부를 보장할 수 없으므로 수동 디버깅에서만 명시적으로 사용한다.

```bash
scripts/qa/night_shift_observe.sh --reuse-local-unsafe
```

실행 결과는 `artifacts/qa/<run-id>/summary.md`와 `events.jsonl`, 단계별 로그에 저장된다. 사용자 핵심·보조 화면과 가입 전 연령 확인 화면 18장의 390×844 PNG와 SHA-256 목록은 `screenshots/`에 저장한다. 검증기는 정확한 파일명 집합, PNG 헤더, 최소 용량, 해상도를 모두 확인한다. `manifest.json`은 commit·브랜치·working tree fingerprint·8개 persona 수·reset 요청/완료 여부를 기록한다. 첫 실패 단계의 fingerprint와 연속 반복 횟수는 `artifacts/qa/failure-state.json`에 다음 실행까지 유지된다.

Mac에서 실행하면 웹 E2E 뒤에 macOS 앱 E2E도 기본으로 수행한다. 앱 경로만 별도로 확인할 때는 다음처럼 실행할 수 있다.

```bash
scripts/qa/run_flutter_e2e.sh --device macos
```

iOS 시뮬레이터는 현재 Night Shift의 필수 단계가 아니다. 수동 preflight는
다음처럼 실행한다.

```bash
xcrun simctl boot 721FF19E-140D-417C-B899-B3C752F94FAD
xcrun simctl bootstatus 721FF19E-140D-417C-B899-B3C752F94FAD -b
scripts/qa/run_flutter_e2e.sh \
  --device 721FF19E-140D-417C-B899-B3C752F94FAD
```

2026-07-19 preflight에서는 앱 실행 전 Xcode 빌드가 중단됐다.
`ffmpeg_kit_flutter_new`에 Apple Silicon iOS 26+ 시뮬레이터가 요구하는
arm64 Simulator slice가 없기 때문이다. 의존성 교체나 스피드건을 제외한
QA flavor가 준비되고 반복 통과하기 전까지 환경 실패가 Night Shift 전체
결과를 가리지 않도록 수동 게이트로 유지한다.

## 현재 검증 범위

1. 고정 계정 8명의 실제 로컬 이메일 로그인
2. `users`, 종목, 협회, 즐겨찾기, 알림, AI 대화의 계정 간 격리
3. 신고 snapshot은 관리자만 조회 가능
4. 제재는 본인과 관리자만 조회 가능
5. role 자가 상승, 클럽 owner 탈취, 클럽 승인 우회 차단
6. 가입 신청의 applicant·manager·admin 권한 경계
7. 공개·draft·rejected 대회 노출 경계
8. public 테이블 전체 RLS 활성화 여부
9. 만 14세 경계의 서버 강제
10. 생년월일 미등록 계정의 종목·협회·AI 채팅·대회 제보와 클럽 생성·가입 차단
11. Git에 노출될 수 있는 비밀키 패턴 검사
12. 단계별 artifact의 키·토큰·JWT·Flutter debug URI 유출 검사
13. Supabase security advisor의 신규 경고·오류 회귀 검사
14. Chrome에서 8개 persona 실제 UI 로그인과 계정별 첫 화면 검증
15. 새 합성 계정의 UI 회원가입과 기본 role=`user` 보장
16. 미완성 계정의 앱 온보딩 강제와 웹 라우팅 차이
17. 오늘·대회·클럽·MY 4탭과 모든 화면의 전역 하단 채팅 노출
18. 하단 채팅 시트에서 전체 화면 전환 시 작성 중 draft 보존
19. 일반 회원의 직접 `/admin` 차단과 관리자 persona의 웹 관리자 진입
20. macOS 앱의 실제 로그인·회원가입 tap과 온보딩 분기
21. 공개 이미지의 JWT 기반 Storage 소유권, 타 계정 목록 차단, 미완성 계정 업로드 차단
22. 신고 증거 이미지의 비공개 상태와 신고자·관리자 외 조회 차단
23. 앱 업로드 이미지의 EXIF·PNG text metadata 제거와 공개 URL의 계정 UUID 비노출
24. 합성 계정의 실제 회원탈퇴 Edge 호출, 공개 사진 삭제, 개인정보 행 삭제, 재로그인 차단
25. 탈퇴 사용자가 경기 파트너·상대·운영 감사 기록에 참조돼도 익명화 후 삭제 가능
26. Flutter·Deno·정적 규칙·secret scan 공통 하네스 전체
27. 개인화 홈 추천 데이터 로드와 대회 목록→상세 화면 연결
28. 관심 대회 해제·복원 후 MY 기록에 다시 나타나는지 검증
29. 클럽 가입 신청자와 owner가 서로 다른 허용 화면만 보는지 검증
30. 대회 상세에서 AI 문맥이 기본 해제이고 사용자가 직접 연결하는지 검증
31. 홈부터 클럽 관리, 로그인 오류, 전체 채팅, MY 설정, 보조 화면, 대회 제보, 가입 전 연령 확인까지 390×844 PNG 18장 저장
32. 필수 스크린샷 이름·해상도·PNG 무결성·SHA-256 manifest 검증
33. 같은 물리 FCM 토큰의 계정 A→B 원자적 이전과 로그아웃 해제
34. 같은 질문·문맥의 AI 캐시 사용자별 격리, TTL 제외, 일일 만료 삭제 작업
35. 하단 채팅·4탭·문맥 토글·어두운 전체 채팅·출처 링크의 공식 Flutter
    레이블·대비·iOS 44px·Android 48px 접근성 기준

웹과 macOS 모두 화면 문구가 아닌 고정 E2E key를 사용하며, 로그인·가입·온보딩·4탭·대회·클럽·MY·전역 채팅과 보조 라우트를 실제 pointer tap으로 검증한다. 비동기 보조 화면은 로딩이 끝난 ready key를 기다린다. 실제 데이터 소스가 없는 친구 일정 프리뷰는 출시 라우트와 시각 증거에서 제외하고, MY 화면·계정 설정을 대신 검증한다. OAuth·카메라·알림 권한처럼 운영체제 팝업이 필요한 흐름은 Patrol 계층에서 추가한다.

## 알려진 기준선과 데이터 과제

- security advisor의 `extension_in_public_vector` 경고 1건은 현재 기준선으로만 허용한다. 이 항목 외의 새 보안 경고나 오류는 러너를 실패시킨다.
- `supabase/migrations/046b_seed_futsal_venues.sql`은 Supabase 파일명 규칙에 맞지 않아 로컬 reset에서 건너뛴다. 대량 실구장 데이터이며 단순히 이름만 바꾸면 운영 중복 삽입 위험이 있으므로, 보안 러너와 분리해 idempotent 데이터 마이그레이션으로 정리한다.

## 무인 실행 규칙

이 스크립트는 사람이 없는 동안에도 반복 실행할 수 있지만 관찰·증거 수집만 한다. 자동 수정·커밋·푸시·PR·배포·운영 데이터 접근은 하지 않는다.

- 실행 시작 시 commit과 working tree fingerprint를 기록한다.
- 로컬 주소 확인을 통과하지 못하면 DB·E2E를 시작하지 않는다.
- 각 단계와 전체 실행에 시간 제한을 두고, 중단돼도 summary와 정리 작업을 남긴다.
- 같은 첫 실패는 `failure-state.json`의 fingerprint와 반복 횟수로 묶어 원인 없는 무한 재시도를 피한다.
- 실제 OAuth·카메라·알림 권한·비밀값이 필요한 경우 실패 증거만 남기고 운영 환경으로 확장하지 않는다.

## 참고 기준과 오픈소스

- 현재 앱·웹 UI 루프: [Flutter `integration_test` 공식 문서](https://docs.flutter.dev/testing/integration-tests)
- 데이터베이스 권한 회귀: [Supabase CLI pgTAP 테스트](https://supabase.com/docs/reference/cli/supabase-test-db)
- 파일 소유권 기준: [Supabase Storage ownership](https://supabase.com/docs/guides/storage/security/ownership)
- Storage RLS 기준: [Supabase Storage access control](https://supabase.com/docs/guides/storage/security/access-control)
- 웹 보안 점검 기준: [OWASP Web Security Testing Guide](https://owasp.org/www-project-web-security-testing-guide/)
- 모바일 보안 점검 기준: [OWASP MASVS/MASTG](https://mas.owasp.org/MASTG/0x03-Overview/)
- 향후 OAuth·권한 팝업·알림: [Patrol native automation](https://patrol.leancode.co/documentation/native/overview)
- 향후 로컬 웹 동적 스캔: [OWASP ZAP Automation Framework](https://www.zaproxy.org/docs/automate/automation-framework/)
- 향후 Android/iOS 정적·동적 점검: [MobSF](https://mobsf.github.io/docs/)

## 다음 단계

- 신고 증거 이미지의 보존 기간·삭제 기준을 법무 검토 후 자동 만료 작업으로 구현
- 운영 설정과 동일한 스테이징에서 누락 JWT·타인 ID·관리자 사칭 테스트
- 실제 모델을 격리한 red-team prompt injection 결과 평가
- 영상·네트워크 trace와 독립 검증 에이전트 연결
- OAuth·카메라·알림 권한이 필요한 시점에 Patrol 네이티브 테스트 추가
- arm64 Simulator 지원 ffmpeg 의존성 또는 스피드건 제외 QA flavor를 정한 뒤
  iOS E2E를 별도 예약 게이트로 승격
