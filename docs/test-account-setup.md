# 테스트 계정 만들기 (개발용)

> 실제 사용자처럼 앱을 테스트하기 위해 테스트 계정을 만드는 방법입니다.
> 옛 "Dev 어드민 로그인" 버튼은 보안 위험으로 제거됐습니다 (아래 배경 참고).

## 배경 — 왜 바뀌었나

예전엔 로그인 화면에 **"Dev 어드민 로그인"** 버튼이 있어서 비번 없이 바로 admin으로 들어갈 수 있었습니다.
이 기능(`dev-auth` 함수)은 **공개된 anon 키만 알면 누구나 아무 이메일로 로그인**할 수 있는 백도어라, 외부인이 admin 계정을 탈취할 수 있었습니다. 그래서 제거했습니다.

대신 **실제 계정을 만들어** 진짜 사용자/관리자처럼 테스트합니다. (실제 가입·권한·RLS 경로를 그대로 타므로 테스트 품질도 더 좋습니다.)

---

## 방법 A — 앱에서 직접 가입 (추천)

1. 앱 로그인 화면에서 **이메일 / 비밀번호로 회원가입**합니다.
2. (이메일 인증이 막히면) 가입한 **이메일을 개발자에게 알려주세요.** → 아래 [SQL](#sql-실행-supabase-sql-editor)로 인증을 처리합니다.
3. **관리자 기능**을 테스트해야 하면, 같은 SQL로 admin 권한을 부여받습니다.

## 방법 B — Supabase 대시보드에서 생성 (앱 안 거치고)

1. Supabase 대시보드 → **Authentication → Users → "Add user"**
2. 이메일·비밀번호 입력 + **"Auto Confirm User" 체크** → Create
3. 관리자 권한이 필요하면 아래 SQL로 부여

---

## SQL 실행 (Supabase SQL Editor)

> 프로젝트 소유자 권한(대시보드의 SQL Editor)에서 실행하세요. 아래 `테스트이메일` 을 실제 가입 이메일로 바꿉니다.

### 1) 이메일 인증 처리 (가입 후 로그인이 안 될 때)

```sql
update auth.users
set email_confirmed_at = now()
where email = '테스트이메일';
```

### 2) 관리자(admin) 권한 부여

`public.users.role` 을 `admin` 으로 바꿉니다. 단, 본인이 스스로 role을 못 바꾸게 막는 트리거(`users_prevent_role_self_update`)가 있어, **일시적으로 끄고** 바꾼 뒤 **다시 켭니다.**

```sql
alter table public.users disable trigger users_prevent_role_self_update;
update public.users set role = 'admin' where email = '테스트이메일';
alter table public.users enable trigger users_prevent_role_self_update;
```

### 3) 확인

```sql
select email, role from public.users where email = '테스트이메일';
-- role 이 admin 으로 나오면 성공
```

---

## 목업(테스트) 데이터 넣기

- 테스트할 화면(대회 신청 / 클럽 / 매치 기록 등)에 맞춰 SQL로 데이터를 넣습니다.
- **RLS** 때문에 데이터의 소유자(`user_id` 등)를 **본인 테스트 계정 id로** 맞춰야 앱에서 보입니다.
  - 내 user id 확인: `select id, email, role from public.users where email = '테스트이메일';`
- 어떤 화면을 테스트할지 알려주면 개발자가 인서트 SQL을 만들어 드립니다.

---

## ⚠️ 주의

- 현재는 **프로덕션 DB**에서 테스트하므로 테스트 데이터가 실데이터에 섞입니다.
- 테스트 계정/데이터는 **알아보기 쉽게**(예: 이메일에 `+test`) 두고, 끝나면 **정리(삭제)** 합니다.
- admin 권한은 강력하므로, 테스트가 끝난 계정은 `role='user'` 로 되돌리거나 계정을 삭제하세요.
