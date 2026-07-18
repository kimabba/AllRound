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

Docker Desktop이 필요하다. 기본 실행은 DB를 현재 마이그레이션과 seed로 완전히 초기화한다. 동시에 두 번 실행되지 않도록 로컬 잠금을 사용하고, 전체 실행은 기본 60분 안에 종료한다.

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

실행 결과는 `artifacts/qa/<run-id>/summary.md`와 `events.jsonl`, 단계별 로그에 저장된다.

Mac에서 실행하면 웹 E2E 뒤에 macOS 앱 E2E도 기본으로 수행한다. 앱 경로만 별도로 확인할 때는 다음처럼 실행할 수 있다.

```bash
scripts/qa/run_flutter_e2e.sh --device macos
```

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
10. Git에 노출될 수 있는 비밀키 패턴 검사
11. Supabase security advisor의 신규 경고·오류 회귀 검사
12. Chrome에서 일반 회원 로그인·주요 메뉴 이동·웹 관리자 권한 E2E
13. 새 합성 계정의 UI 회원가입과 기본 role=`user` 보장
14. 미완성 계정의 앱 온보딩 강제와 웹 라우팅 차이
15. macOS 앱의 실제 로그인·회원가입·온보딩 분기

## 알려진 기준선과 데이터 과제

- security advisor의 `extension_in_public_vector` 경고 1건은 현재 기준선으로만 허용한다. 이 항목 외의 새 보안 경고나 오류는 러너를 실패시킨다.
- `supabase/migrations/046b_seed_futsal_venues.sql`은 Supabase 파일명 규칙에 맞지 않아 로컬 reset에서 건너뛴다. 대량 실구장 데이터이며 단순히 이름만 바꾸면 운영 중복 삽입 위험이 있으므로, 보안 러너와 분리해 idempotent 데이터 마이그레이션으로 정리한다.

## 자율 실행 규칙

Codex의 `AllRound Night Shift` 자동 작업이 매일 새벽 2시에 실행된다. 현재 자동 작업은 로컬 프로젝트 실행만 지원하므로 다음 보호장치를 사용한다.

- 실행 시작 전 사용자의 미커밋 변경이 있으면 파일을 수정하지 않고 관찰·보고만 한다.
- 깨끗한 작업 폴더에서만 한 번에 독립적인 원인 하나나 작은 시나리오 하나를 수정한다.
- 관련 테스트, Night Shift 전체, 공통 하네스가 모두 통과해야 로컬 커밋을 만든다.
- 푸시·PR·배포·운영 데이터 접근은 하지 않는다.
- 같은 실패가 2회 반복되거나 실제 OAuth·카메라·알림 권한·비밀값이 필요하면 수정을 중단하고 보고한다.

## 참고 기준과 오픈소스

- 현재 앱·웹 UI 루프: [Flutter `integration_test` 공식 문서](https://docs.flutter.dev/testing/integration-tests)
- 데이터베이스 권한 회귀: [Supabase CLI pgTAP 테스트](https://supabase.com/docs/reference/cli/supabase-test-db)
- 웹 보안 점검 기준: [OWASP Web Security Testing Guide](https://owasp.org/www-project-web-security-testing-guide/)
- 모바일 보안 점검 기준: [OWASP MASVS/MASTG](https://mas.owasp.org/MASTG/0x03-Overview/)
- 향후 OAuth·권한 팝업·알림: [Patrol native automation](https://patrol.leancode.co/documentation/native/overview)
- 향후 로컬 웹 동적 스캔: [OWASP ZAP Automation Framework](https://www.zaproxy.org/docs/automate/automation-framework/)
- 향후 Android/iOS 정적·동적 점검: [MobSF](https://mobsf.github.io/docs/)

## 다음 단계

- 온보딩의 종목·지역·등급 입력을 완료하고 홈 콘텐츠까지 검증
- Storage 경로·업로드 권한과 EXIF 개인정보 검사
- Edge Function의 누락 JWT·타인 ID·관리자 사칭 테스트
- 실패 fingerprint, 영상·네트워크 trace, 독립 검증 에이전트 연결
- OAuth·카메라·알림 권한이 필요한 시점에 Patrol 네이티브 테스트 추가
