# iOS 첫 출시 확인 기록

> 2026-08-04 첫 출시 직후 코드와 App Store 상태를 맞춰 본 기록이다.
> 현재 운영 값과 다음 배포 절차는
> [`apple-release-runbook.md`](apple-release-runbook.md)를 정본으로 사용한다.

- 확인일: 2026-08-05
- 확인 담당: 드론·백과장
- App Store Connect의 비밀번호와 심사 계정 비밀번호는 저장소에 기록하지 않는다.

## 확인된 출시 상태

| 항목 | 확인 결과 |
|---|---|
| 상태 | 한국 App Store 정식 출시 완료 |
| 출시 버전 | `1.0.0 (5)` |
| 빌드 기준 커밋 | `7b1fc40` |
| Apple App ID | `6792671473` |
| iOS Bundle ID | `kr.jyoung.allround` |
| 제품 페이지 | <https://apps.apple.com/kr/app/id6792671473> |
| 심사 이력 | 2026-07-30 미통과 1회, 재제출 후 2026-08-04 승인·배포 |
| 연령 등급 | 한국 12+, 대부분 국가 13+ |
| 개인정보 처리방침 | <https://kimabba.github.io/AllRound/legal/privacy-policy.html> |

심사 계정은 App Store Connect에 등록됐다. 심사 노트에는 대회·클럽의 사용자 작성
콘텐츠, 신고·차단, AI 코치, 회원 탈퇴, 법적 문서 경로를 적었다. App Privacy에는
이름·이메일·사용자 ID·기기 ID·사진/비디오·기타 사용자 콘텐츠·기타 데이터 유형을
신고했다.

## 출시본과 현재 코드의 차이

출시본은 `7b1fc40`에서 만든 고정 바이너리다. 이후 `main`에 들어간 수정은 새 버전을
올리기 전까지 기존 설치 앱에 반영되지 않는다.

### 랭킹 화면의 개인정보 연락처

빌드 5의 협회 랭킹 화면은 삭제·정정 요청 주소로 개인 메일
`demian.772@gmail.com`을 표시한다.

```bash
git show 7b1fc40:app/lib/screens/rankings/rankings_screen.dart \
  | grep _kPrivacyContactEmail
```

현재 코드는 #389에서 `play@jyoungad.kr`로 고쳤고 공개 개인정보 처리방침과도
일치한다. 하지만 빌드 5의 화면은 바뀌지 않으므로 다음 버전이 출시될 때까지 두 주소로
들어오는 요청을 모두 놓치지 않아야 한다. 처리 방법은
[`RUNBOOK-org-ranking-deletion-request.md`](RUNBOOK-org-ranking-deletion-request.md)를 따른다.

### 최소 지원 빌드 안내

현재 코드에는 #386의 최소 지원 빌드 안내가 있지만 빌드 5에는 이 기능이 없다.
따라서 서버 설정의 최소 빌드 값을 올려도 빌드 5 사용자를 업데이트 화면으로 보낼 수
없다. 이 장치는 해당 코드가 포함된 다음 앱 버전부터 작동한다.

## 다음 배포 전 확인할 것

1. `play@jyoungad.kr`로 보낸 시험 메일을 실제로 열어 수신을 확인한다.
2. 다음 iOS 버전과 빌드번호, 업로드 담당과 일정을 정한다.
3. 실기기에서 로그인, 회원 탈퇴, 사용자 작성 콘텐츠 신고·차단, AI 고지를 확인한다.
4. 빌드 5와 호환되지 않는 서버 변경 전에는 앱의 RPC·테이블 사용처를 먼저 대조한다.

새 버전이 출시되면 이 기록을 현재 상태처럼 덮어쓰지 않는다. 실제 운영 값과 릴리스
이력은 `apple-release-runbook.md`에 추가한다.
