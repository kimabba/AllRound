# 클럽 관리 시스템

## 워크플로우

```
사용자 → clubs-create → clubs.status='pending'
                          + club_members에 owner 자동 등록
                          ↓
어드민 → clubs-approve → status='approved' 또는 'rejected'
                          ↓ (approved)
다른 사용자 → clubs-join(action:'request') → club_join_requests.status='pending'
                          ↓
owner/manager → clubs-review-join → 'approved' → club_members에 member 추가
                                    'rejected' → 신청 거절
```

## 역할 체계

| 역할 | 권한 |
|---|---|
| owner | 가입 신청 승인/거절, 클럽 정보 관리 (탈퇴 불가) |
| manager | 가입 신청 승인/거절 |
| member | 일반 멤버 (탈퇴 가능) |

## Edge Functions

### clubs-create
- `POST { sport, name, region?, address?, contact?, website?, description?, logo_url?, intro_image_urls?, meeting_days?, monthly_fee?, gender_preference? }`
- 인증: requireUser
- website는 비어 있거나 `http://`/`https://` URL이어야 함
- monthly_fee는 0 이상의 정수이며 intro_image_urls는 최대 5개
- clubs에 status='pending'으로 insert + club_members에 owner 등록

### clubs-join
- `POST { club_id, action: 'request'|'cancel'|'leave', message? }`
- request: 승인된 클럽에만, 이미 멤버면 409
- request: 기존 pending 신청은 중복 알림 없이 멱등 처리
- cancel: pending 신청만 삭제하며 앱에서 신청일·승인 대기 상태·취소 버튼 제공
- leave: owner는 불가 ("Transfer ownership first")

### clubs-review-join
- `POST { request_id, action: 'approve'|'reject' }`
- 인증: owner/manager 또는 admin
- approve → club_members에 member 추가

### clubs-approve
- `POST { club_id, action: 'approve'|'reject', reason? }`
- 인증: requireAdmin
- reject 시 status_reason 저장

### clubs-search
- `GET ?sport=&region=&q=&mine=true`
- 일반: status='approved' 클럽만
- mine=true: serviceClient로 club_members 조회 → 내가 멤버이거나 생성한 클럽 + role 정보 주입

## Flutter UI

- `clubs_screen.dart` — "내 클럽" / "클럽 찾기" 탭 + FAB(클럽 만들기)
  - 목록 카드에 현재 `member_count`를 `총 n명`으로 표시
  - 상세 화면에서 돌아오거나 목록을 당겨 새로고침하면 최신 회원 수 재조회
- `clubs/club_create_screen.dart` — 3단계 클럽 생성 폼
  - 입력 내용과 현재 단계를 사용자별로 기기에 자동 저장하고 다음 진입 때 복원
  - 사진은 용량·개인정보 보호를 위해 임시 저장에서 제외하며 복원 시 재선택 안내
  - HEIC/HEIF 사진을 JPEG로 변환한 뒤 업로드하며 업로드·생성 진행 상태 표시
  - 웹사이트 URL과 월회비를 클라이언트에서 먼저 검증
- `admin_screen.dart` — "클럽 승인" 4번째 탭 (pending 클럽 목록)
- `clubs/club_detail_screen.dart` — 가입 승인·탈퇴·강퇴 후 상세 회원 목록과 총인원 즉시 갱신

## 멤버 수 자동 갱신
club_members의 INSERT/UPDATE/DELETE 시 `update_club_member_count` 트리거가 clubs.member_count를 자동 갱신

## 팀원 모집

- `club_recruiting_posts`에 승인된 클럽의 공개 모집 조건·인원·일정·마감 상태를 저장
- 로그인 사용자는 승인된 클럽의 모집글을 조회할 수 있고, owner/manager만 자기 클럽 글을 작성·마감 가능
- 풋살은 필드/키퍼 인원을 구분하고 테니스는 전체 모집 인원을 표시
- 참여 신청은 별도 문의 테이블을 만들지 않고 `clubs-join`의 가입 신청을 재사용하며, 신청 메시지에 모집글 제목을 포함
- 운영진 승인 전에는 클럽 상세에서 신청 상태와 취소 기능을 제공
