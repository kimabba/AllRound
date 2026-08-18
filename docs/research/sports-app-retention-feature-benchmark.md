# 스포츠 앱 리텐션 기능 벤치마크

> 조사 범위: 러닝/사이클링(Strava, Nike Run Club), 골프(스마트스코어, 카카오VX), 국내 동호인 스포츠 커뮤니티(배드민턴/탁구/당구), 해외 아마추어 리그·래더 플랫폼(TeamSnap, LeagueApps, USTA TennisLink, PlayYourCourt, Tennis Ladder 계열).
> 이미 조사된 국내 테니스/풋살 경쟁작(스매시, 베이스라인, 테친소, KTR, 플랩풋볼, 아이엠그라운드)은 `docs/superpowers/specs/2026-05-29-strategy-and-roadmap-design.md`에 있어 본 문서에서는 다루지 않는다.
> 조사일: 2026-08-17. 1차 출처(공식 사이트/스토어/헬프센터)를 우선했고, 2차 출처(블로그·뉴스)는 "1차 출처 아님"으로 표시했다.

## 1. 러닝/사이클링

### Strava

**핵심 리텐션 기능**
- **세그먼트(Segment) + 리더보드**: 특정 도로/트레일 구간(보통 400m~1km)을 사용자가 직접 만들거나 기존 것에 참여하면, GPS 매칭으로 자동 기록·순위가 매겨진다. 최고기록 보유자에게 디지털 왕관(Crown), Top10 진입자에게 트로피, 개인 최고기록에 메달, 90일간 가장 많이 완주한 사람에게 "Local Legend"(월계관)를 부여한다. ([Strava for Business - Segments](https://business.strava.com/resources/segments-brands))
- **Kudos**: 다른 사람의 활동/업적/배지에 원클릭으로 보내는 소셜 인정 신호. ([Strava Help Center](https://support.strava.com/en-us/articles/15402054-what-is-kudos))
- **Clubs**: 그룹 단위 커뮤니티·경쟁 공간.
- **업적/배지**: 개인 최고기록, 챌린지 달성에 대한 뱃지·트로피.

**왜 재방문을 만드는가 (심리적 메커니즘)**
- 세그먼트/리더보드는 "지역 한정 순위"라는 좁은 경쟁 풀을 만들어 누구나 상위권에 들 가능성을 열어준다(전체 순위가 아니라 그 구간을 뛴 사람들 사이에서만 경쟁) — 성취 가능성이 재방문을 유도.
- Kudos는 저비용 소셜 인정(사회적 승인 desire)으로, 활동을 올릴 때마다 즉각적 피드백 루프를 만든다. 학술 연구에서도 Kudos가 동료 러너 간 상호 영향을 만든다는 것이 확인됨. ([ScienceDirect, "Kudos make you run!"](https://www.sciencedirect.com/science/article/pii/S0378873322000909))
- 소셜 기능이 있는 앱의 평균 스트릭(연속 사용) 길이는 5.69일로, 없는 앱(4.25일)보다 길다는 벤치마크 분석 존재 — 사회적 가시성이 꾸준함의 심리를 바꾼다는 설명. (2차 출처, [trophy.so Strava 케이스 스터디](https://trophy.so/blog/strava-gamification-case-study))

**최소 필요 데이터/인프라**
- GPS 트랙(위치 시계열) — Match-up에는 없는 데이터 종류.
- 세그먼트 매칭 알고리즘(경로-구간 비교) — 상당한 엔지니어링.
- Kudos/Clubs는 좋아요·그룹 테이블 수준으로 가벼움.
- → **결론**: 세그먼트류 기능은 GPS 인프라가 전제라 Match-up(대회 정보/클럽 앱)에는 직접 이식 어려움. Kudos·업적류는 이식 가능.

### Nike Run Club (NRC)

**핵심 리텐션 기능**
- **Challenges**: "화요일까지 3마일 뛰기"처럼 친구·가족·동료를 초대하는 개인 챌린지, 또는 커뮤니티 전체가 참여하는 Community Challenge, 월간 마일리지 목표 설정. ([Nike Help - NRC Challenges](https://www.nike.com/help/a/nrc-challenges))
- **마일스톤 배지/트로피**: 개인 최고기록(5K 최速, 최장거리 등) 달성 시 부여. ([Nike.com - NRC App](https://www.nike.com/nrc-app))
- **친구와 연결 + 러닝 중 응원(Cheers)**: 친구·타 러너와 연결하고, 달리는 중 실시간 음성 응원을 받을 수 있음. ([Nike Newsroom](https://about.nike.com/en/newsroom/releases/nike-run-club-app-new-features))

**왜 재방문을 만드는가**
- 배지·챌린지·리더보드가 만드는 "가시적 성취감"이 단순 트래커보다 강한 동기부여를 만든다는 것이 강조됨(2차 출처, [StriveCloud 게이미피케이션 사례](https://www.strivecloud.io/blog/gamification-examples-nike-run-club)).
- 소셜 초대형 챌린지는 "함께 하는 약속"을 만들어 이탈을 어렵게 함(커밋먼트 장치).

**최소 필요 데이터/인프라**
- 거리/시간 등 활동 기록(Match-up에는 없음), 챌린지 참가자/진행률 테이블, 배지 규칙 엔진.
- → 챌린지·배지 개념 자체는 "대회 신청·참가" 대신 "출석/방문/모임 참여" 같은 Match-up이 이미 갖고 있는 행동 데이터에도 적용 가능(아래 종합 섹션 참조).

## 2. 골프

### 스마트스코어 (SmartScore)

**핵심 리텐션 기능**
- 전국 370여 골프장과 연동해 라운드 중 홀별 파/스트로크/퍼트를 자동 기록. 골프장 태블릿에 사용자 등록만 하면 스코어와 라운드 중 촬영 사진이 앱으로 자동 전송됨. ([스마트스코어 공식](https://www.smartscore.kr/golf/), [Google Play 설명](https://play.google.com/store/apps/details?id=com.smartscore.rawady.smartscore))
- 부킹(예약)·마켓·투어·골프장정보까지 원스톱 제공, 360만+ 골퍼 활동 데이터 기반 맞춤 추천.

**왜 재방문을 만드는가**
- "내가 직접 입력하지 않아도 기록이 쌓인다"는 자동화가 마찰을 없애 기록 습관을 만든다(기록 자체가 목적이 아니라 부산물이 됨).
- 스코어 히스토리가 쌓일수록 "내 실력 추이"를 보고 싶은 욕구(자기 비교)가 재방문 동기가 됨 — 다만 공식 페이지에서 랭킹/소셜 비교 기능에 대한 명시적 설명은 확인되지 않음(라운드 기록·부킹 편의성이 핵심으로 확인됨).

**최소 필요 데이터/인프라**
- 골프장 태블릿/스코어 입력 시스템과의 하드웨어 연동 — Match-up 맥락(대회 검색 앱)에는 없는 인프라. 이식 난이도 높음.

### 카카오VX (프렌즈 스크린 / 버디스쿼드)

**핵심 리텐션 기능**
- 스크린골프 매장 체인 "프렌즈 스크린" — 카카오프렌즈 캐릭터, '프렌즈 캠', '리플레이' 등으로 젊은 층 유입, 스크린골프 시장 점유율 2위. ([머니S](https://moneys.mt.co.kr/news/mwView.php?no=2021081921388047904), 2차 출처)
- **버디스쿼드(BuddySquad)**: 골프 팬 대상 NFT 기반 커뮤니티. 좋아하는 프로 선수에게 응원톡·하트·후원을 보내고, 선수 카드로 팀을 구성해 "응원 대결"을 하는 기능. 응원 성과에 따라 포인트(BDP)를 받아 래플(추첨 이벤트) 응모에 사용. ([ZDNet Korea](https://zdnet.co.kr/view/?no=20231204134612), 2차 출처)

**왜 재방문을 만드는가**
- 캐릭터 IP(친숙함)와 소셜 경쟁(응원 대결)을 결합해 실력과 무관한 참여 동기를 만듦 — 골프 실력이 없어도 "내가 미는 선수"를 응원하며 매일 들어올 이유가 생김.

**최소 필요 데이터/인프라**
- NFT/포인트 이코노미(버디스쿼드), 프로선수 성적 데이터 연동 — Match-up과는 도메인이 달라(팬 커뮤니티 vs 동호인 참가) 직접 이식 대상은 아님. 단 "응원/포인트 기반 팀 경쟁" 아이디어 자체는 참고할 만함.

## 3. 국내 동호인 스포츠 커뮤니티 (배드민턴/탁구/당구)

### 배드민턴 — 배프(배드민턴 프렌즈)

전국 대회 정보를 통합 조회·신청하고 실시간 대회 점수를 확인할 수 있는 앱. 캘린더 뷰 일정 관리, 배프 커머스(용품 쇼핑)를 제공하며, 향후 커뮤니티·코칭 영상·용품 리뷰 기능을 예고하고 있다. App Store 페이지에서는 랭킹·클럽·친구찾기 기능에 대한 구체적 설명은 확인되지 않았다. ([App Store](https://apps.apple.com/kr/app/%EB%B0%B0%ED%94%84-%EB%B0%B0%EB%93%9C%EB%AF%BC%ED%84%B4-%ED%94%84%EB%A0%8C%EC%A6%88/id1617658125))

### 탁구 — 티티알클럽(TTR Club), 고고탁

- **티티알클럽**: "탁구 클럽을 위한 멤버 매치와 순위 관리 웹앱" — "매치를 만들고, 순위를 올려보세요"가 핵심 슬로건. 랭킹 산정 알고리즘·매치 신청 절차·결제 여부는 로그인 후에만 확인 가능해 상세 파악은 못했다. ([playttr.com](https://playttr.com/))
- **고고탁**: 대회별 공지, 결과, 동호인 영상, 지역/전국 오픈대회 알림을 제공하는 커뮤니티 게시판형 사이트. ([gogotak.com](https://gogotak.com/bbs/board.php?bo_table=pingpong))

### 당구 — 비쿠(BeeKU), 대대당구, KBF DIVISION

- **비쿠**: "게임매칭" 기능으로 주변 당구 동호인과 매치를 잡고, 경기 결과를 기록해 남기는 "경기기록" 기능 제공. 코치 정보/상담 연결도 지원. ([App Store](https://apps.apple.com/kr/app/%EB%B9%84%EC%BF%A0-%EB%8B%B9%EA%B5%AC%EB%8F%99%ED%98%B8%EC%9D%B8%EC%9D%84-%EC%9C%84%ED%95%9C-%ED%95%B5%EC%9D%B8%EC%8B%B8-%EC%95%B1/id1458453639))
- **대대당구**: 아마추어 당구인이 대회 정보를 확인하고 실시간으로 대회를 개최·참가할 수 있으며, 참가자 정보 기반으로 대진표를 자동 생성. ([Google Play](https://play.google.com/store/apps/details?id=com.quickcar.dddg&hl=ko))
- **KBF DIVISION**: 대한당구연맹(KBF)의 공식 개인/팀 디비전 리그 앱. 지역별 리그 참가 신청, 연도·리그별 개인 승패·기록 조회, 팀 생성/가입/탈퇴 및 팀원 기록 관리, 라운드별 일정·구장 확인, 팀리그 출전 선수 오더 입력, 그리고 **LIVE 관전**(진행 중인 구장 검색 + 실시간 스코어/영상 관전)까지 제공한다. ([App Store](https://apps.apple.com/kr/app/kbf-division/id1566819599), [KBF 공식 리그 페이지](https://www.kbfnow.or.kr/league/), [결과 및 순위](https://kbfnow.or.kr/result/))

**왜 재방문을 만드는가 (공통 메커니즘)**
- KBF DIVISION은 협회 공인 "디비전(등급) 승격제"를 앱으로 운영 — 등급 안에서 경쟁하고 승격 여부가 시즌마다 갱신되는 구조라, Match-up의 등급 기반 대회 필터와 철학이 가장 가깝다. 성취 가능한 눈높이 경쟁 + 시즌제 갱신이 재방문을 만든다.
- 비쿠·대대당구는 "경기 기록을 남긴다"는 행위 자체를 앱 안에 가두어(기록이 앱에만 있으므로) 다음 경기 후에도 다시 열게 만듦.

**최소 필요 데이터/인프라**
- 매치 결과 self-report 테이블(승/패, 상대, 날짜) + 팀/리그 구조 — 협회 계약이나 결제 없이도 구현 가능한 수준. LIVE 관전만 별도 인프라(영상 스트리밍) 필요.

## 4. 해외 아마추어 리그·래더 운영 플랫폼

### TeamSnap / LeagueApps (참고용 — 결제·조직 운영 중심)

두 플랫폼 모두 "청소년/성인 스포츠 클럽·리그 운영자"를 위한 등록비 결제, 스케줄링, 커뮤니케이션, 팀 관리 SaaS다. TeamSnap ONE은 등록·결제·라이브스트리밍·공식 스코어 입력(관리자가 입력하면 코치/부모가 입력한 점수를 대체하는 "공식 기록"이 됨)을 통합 제공. ([TeamSnap Features](https://www.teamsnap.com/teams/features), [TeamSnap ONE](https://www.teamsnap.com/one)) LeagueApps는 등록·결제·정산·웹사이트·모바일 앱을 포함한 리그 운영 플랫폼. ([LeagueApps](https://leagueapps.com/))

**시사점**: 두 플랫폼의 핵심 가치는 "결제·정산·조직 운영"에 있어 Match-up이 의도적으로 미룬 영역(협회 계약, PG 연동)과 겹친다. 리텐션 기능이라기보다 오퍼레이션 툴에 가까워 **직접 참고 대상은 아님** — 다만 "공식 기록"(admin이 입력하면 확정되는 스코어) 개념은 신뢰도 장치로 참고할 만함.

### USTA TennisLink / USTA League

- **NTRP 등급 시스템**: 1.5~7.0의 자기평가(Self-Rate) 또는 컴퓨터 산정(Computer Rating) 등급으로 선수를 분류하며, USTA 계정만 있으면 멤버십 없이도 셀프레이트가 가능. 등급은 2년간 유효하거나 동적/컴퓨터 등급으로 대체될 때까지 유지된다. ([USTA Self-Rate 안내](https://customercare.usta.com/hc/en-us/articles/4402364646036-Adult-NTRP-Self-Rate))
- **팀 매치 포맷**: 등급별로 단식 2+복식 3(3.0~4.5), 단식 1+복식 2(2.5, 5.0) 등 표준화된 팀 매치 규정. ([USTA League Regulations PDF](https://www.usta.com/content/dam/usta/2025-pdfs/2026-national-regulations-interpretations.pdf))

**왜 재방문을 만드는가**
- 등급(NTRP)이 "내가 이길 수 있는 상대"를 보장해주는 구조적 장치 — Match-up의 "내 등급" 필터와 철학적으로 가장 가까운 사례. 등급 재산정이 주기적으로 이뤄져 "다음 시즌엔 어디 속할까"라는 재방문 동기를 만든다.

**최소 필요 데이터/인프라**
- 자기평가(Self-Rate) + 경기 결과 누적을 통한 동적 등급 재산정 로직. Match-up은 이미 등급 시스템(division_fallback 등, 메모리 참조)이 있어 매치 결과를 등급 재산정에 반영하는 로직만 추가하면 확장 가능.

### PlayYourCourt

- 가입 시 초기 레이팅 부여, 매치 결과에 따라 레이팅 조정 → 비슷한 실력끼리 자동 매칭. **Challenge League**: 스케줄된 매치 + 랭킹 시스템으로, 상위 랭커를 이기면 순위가 역전된다. 코칭 영상, VIP 커뮤니티 특가도 함께 제공. ([PlayYourCourt 공식](https://www.playyourcourt.com/), [MWM 앱 소개](https://mwm.ai/apps/playyourcourt-play-tennis/1525178013))

**시사점**: "상위 랭커에게 도전해서 이기면 순위가 바뀐다"는 챌린지 래더의 전형. 결제 요소(코칭·VIP 특가)는 부가 서비스일 뿐 랭킹 시스템 자체는 무료로 작동.

### Tennis Ladder 계열 (OpenLadder, iTennisLadder, Global Tennis Network, Rival Tennis Ladder)

**OpenLadder** — 완전 무료 래더 운영 방식이 가장 구체적으로 확인됨:
- 참가자가 가능한 시간·장소를 담아 "매치 제안(proposal)"을 올리거나, 다른 사람의 제안을 수락하거나, 특정 상대에게 직접 도전(challenge)을 보낸다.
- **승자가 스코어를 직접 입력(self-report)** → 즉시 포인트 반영 → 순위 실시간 갱신.
- 포인트는 "결과 + 상대방 순위"를 함께 반영(강한 상대를 이기면 더 많은 포인트).
- "회원비 없음, 매치당 수수료 없음, 유료화 벽 없음"을 명시 — 유료 서비스의 무료 대안을 표방.
- 시즌 20경기 이상을 채운 상위 8/12/16명은 시즌 말 단판 토너먼트에 진출. ([OpenLadder](https://playopenladder.com/))

**iTennisLadder** — 래더 운영자를 위한 셀프서비스 소프트웨어. 선수가 서로 도전하고, 직접 매치 스코어를 제출하며, 실시간으로 순위 변화를 확인. 네이티브 모바일 앱 제공. ([iTennisLadder](https://itennisladder.com/))

**Global Tennis Network / Rival Tennis Ladder / TennisRungs** — 유사한 "챌린지 래더"(도전 후 self-report) 모델. Rival은 시즌(10주) 단위로 참가비를 받는 유료 모델이라는 차이가 있음. ([검색 결과 정리](https://www.globaltennisnetwork.com/ladder-leagues/learn-more), [tennis-ladder.com](https://tennis-ladder.com/))

**왜 재방문을 만드는가**
- "도전 → 결과 자가 보고 → 즉시 순위 반영"이라는 루프가 매우 짧고 저마찰이라, 협회의 공식 대회 없이도 동호인들 스스로 경쟁 서사를 만들어낸다.
- 순위가 상시 유동적이므로("이기면 바로 역전") 다음 도전을 걸 이유가 항상 존재 — Strava 세그먼트의 "지역 한정 경쟁"과 유사한 심리(내가 이길 수 있는 좁은 경쟁 풀).

**최소 필요 데이터/인프라**
- 매치 도전/수락 테이블, 승자 self-report 스코어 입력 폼, 포인트 계산 로직(승패 + 상대 순위 가중치). **결제·협회 계약 불필요** — Match-up이 이미 가진 클럽/모임 인프라 위에 얹기 가장 쉬운 모델.

## 5. 종합: Match-up에 적용 가능한 기능 후보 (우선순위순)

Match-up 맥락: 등급 기반 대회정보 검색 + 클럽/모임 + AI챗봇, **결제·참가신청 기능 없음**, 지역(전남/광주) 동호인 타겟, 설치 100+/WAU 30+ 목표의 초기 단계. 아래는 협회 계약·PG 연동 없이 만들 수 있는 것 위주로 우선순위를 매겼다. "필요 인프라"는 기존 코드베이스를 직접 확인하지 않은 리서치 단계 평가이므로, 실제 착수 전 코드 확인이 필요하다.

| # | 기능 | 참고 사례 | 필요 인프라 | 왜 적합한가 / 왜 안 맞는가 |
|---|------|-----------|-------------|---------------------------|
| 1 | **클럽 내 등급별 래더(챌린지) 랭킹전** — 클럽원끼리 도전 신청 → 결과 self-report → 포인트/순위 실시간 갱신 | OpenLadder, iTennisLadder, PlayYourCourt Challenge League, KBF DIVISION | 신규: 도전/매치 테이블, self-report 폼, 포인트 계산(승패+상대순위). 기존 클럽/모임 인프라 위에 얹을 수 있음. 결제·협회 계약 불필요 | 가장 적합. Match-up이 이미 가진 "등급"·"클럽" 개념과 정확히 맞물리고, 참가신청·결제 기능이 없어도 동호인들 스스로 경쟁을 만들어낼 수 있는 유일한 카테고리(1번의 핵심 발견) |
| 2 | **개인 전적/기록 히스토리 페이지** ("내 전적") | 스마트스코어(자동 기록), 비쿠·대대당구(경기기록), KBF DIVISION(연도별 개인기록) | 신규: 매치/모임 참여 기록 테이블(1번과 공유 가능). 자동화(태블릿 연동 등)는 불필요, self-report로 충분 | 1번의 부산물로 거의 무료로 얻을 수 있음. "내 실력 추이"를 보고 싶은 욕구가 재방문을 만듦 |
| 3 | **업적/배지 시스템** (마감임박 알림 확인, 대회 검색, 모임 참석 등 행동 기반) | Strava 뱃지/크라운, NRC 마일스톤 배지 | 신규: user_badges 테이블 + 규칙 엔진(가벼움) | 이식 난이도 최저. GPS 등 특수 데이터 불필요, 기존 이벤트(즐겨찾기, 모임 출석, 챗봇 질의 등)에 바로 걸 수 있음 |
| 4 | **클럽 대항전 / 팀 리그** | KBF DIVISION(팀 디비전 리그), TeamSnap(팀 관리) | 신규: club_match 테이블(클럽 vs 클럽), 팀 오더 입력 UI | 클럽 인프라가 이미 있어 확장 자연스러움. 다만 팀 대항전은 오프라인 조율 부담이 커 1번(개인 래더)보다 우선순위 낮음 |
| 5 | **소셜 인정(Kudos형) — 모임/전적에 응원·좋아요** | Strava Kudos | 기존 클럽 모임 댓글/좋아요 기능이 있다면 확장, 없으면 신규(가벼움) | 저비용 고효과. 다만 커뮤니티 크기(WAU 30+)가 작을 때는 효과가 제한적일 수 있어 중간 우선순위 |
| 6 | **시즌제 + 시즌말 미니 토너먼트** | OpenLadder(시즌 20경기 이상 상위 8/12/16명 토너먼트) | 1번 래더 위에 시즌 리셋 로직만 추가 | 1번이 자리잡은 뒤 자연스러운 다음 단계. 초기엔 우선순위 낮음(참가자 풀이 작으면 토너먼트 의미 약함) |
| 7 | **AI챗봇에 "내 전적/랭킹" 질의 응답 연동** | (해당 사례 없음, Match-up 고유 결합 아이디어) | 기존 RAG 챗봇 + 2번의 개인 기록 데이터를 그라운딩 소스로 추가 | 이미 있는 챗봇 자산을 재활용하는 저비용 확장. 단 2번이 먼저 존재해야 의미 있음 |
| 8 | 참고만: NFT/포인트 팬 경쟁(버디스쿼드), GPS 세그먼트(Strava), 골프장 하드웨어 연동(스마트스코어) | 카카오VX, Strava, 스마트스코어 | 특수 인프라(NFT/포인트 이코노미, GPS 매칭, 하드웨어 연동) 신규 구축 필요 | 부적합 — Match-up 도메인·규모에 맞지 않거나 투자 대비 효과 불확실. 벤치마크 참고 이상의 가치는 낮음 |

**핵심 결론**: 결제·협회 계약 없이 실행 가능한 리텐션 기능 중 가장 강력한 신호는 "챌린지 래더(도전-셀프리포트-즉시순위갱신)" 패턴이다. 해외에는 이를 전담하는 무료 서비스(OpenLadder 등)까지 존재하고, 국내에서는 KBF DIVISION이 협회 공인 등급제로 유사한 구조를 운영 중이다. Match-up은 이미 클럽·등급 인프라가 있으므로 1→2→3 순서로 얹으면 초기 단계에서 가장 적은 신규 인프라로 재방문 동기를 만들 수 있다.

## 출처 목록

- [Strava for Business - What Is a Strava Segment](https://business.strava.com/resources/segments-brands)
- [Strava Help Center - What is Kudos?](https://support.strava.com/en-us/articles/15402054-what-is-kudos)
- [ScienceDirect - "Kudos make you run!"](https://www.sciencedirect.com/science/article/pii/S0378873322000909)
- [trophy.so - Strava Gamification Case Study](https://trophy.so/blog/strava-gamification-case-study) (2차 출처)
- [Nike Help - What Are Challenges in the NRC App?](https://www.nike.com/help/a/nrc-challenges)
- [Nike.com - Nike Run Club App](https://www.nike.com/nrc-app)
- [Nike Newsroom - NRC App New Features](https://about.nike.com/en/newsroom/releases/nike-run-club-app-new-features)
- [StriveCloud - Nike Run Club Gamification Examples](https://www.strivecloud.io/blog/gamification-examples-nike-run-club) (2차 출처)
- [스마트스코어 공식](https://www.smartscore.kr/golf/)
- [스마트스코어 Google Play](https://play.google.com/store/apps/details?id=com.smartscore.rawady.smartscore)
- [머니S - 스크린골프 왕좌 골프존 vs 카카오VX](https://moneys.mt.co.kr/news/mwView.php?no=2021081921388047904) (2차 출처)
- [ZDNet Korea - 카카오VX 버디스쿼드](https://zdnet.co.kr/view/?no=20231204134612) (2차 출처)
- [배프(배드민턴 프렌즈) App Store](https://apps.apple.com/kr/app/%EB%B0%B0%ED%94%84-%EB%B0%B0%EB%93%9C%EB%AF%BC%ED%84%B4-%ED%94%84%EB%A0%8C%EC%A6%88/id1617658125)
- [티티알클럽(TTR Club)](https://playttr.com/)
- [고고탁](https://gogotak.com/bbs/board.php?bo_table=pingpong)
- [비쿠(BeeKU) App Store](https://apps.apple.com/kr/app/%EB%B9%84%EC%BF%A0-%EB%8B%B9%EA%B5%AC%EB%8F%99%ED%98%B8%EC%9D%B8%EC%9D%84-%EC%9C%84%ED%95%9C-%ED%95%B5%EC%9D%B8%EC%8B%B8-%EC%95%B1/id1458453639)
- [대대당구 Google Play](https://play.google.com/store/apps/details?id=com.quickcar.dddg&hl=ko)
- [KBF DIVISION App Store](https://apps.apple.com/kr/app/kbf-division/id1566819599)
- [KBF 공식 리그 페이지](https://www.kbfnow.or.kr/league/)
- [KBF 결과 및 순위](https://kbfnow.or.kr/result/)
- [TeamSnap Features](https://www.teamsnap.com/teams/features)
- [TeamSnap ONE](https://www.teamsnap.com/one)
- [LeagueApps](https://leagueapps.com/)
- [USTA - Adult NTRP Self-Rate](https://customercare.usta.com/hc/en-us/articles/4402364646036-Adult-NTRP-Self-Rate)
- [USTA - 2026 League Regulations PDF](https://www.usta.com/content/dam/usta/2025-pdfs/2026-national-regulations-interpretations.pdf)
- [PlayYourCourt 공식](https://www.playyourcourt.com/)
- [MWM - PlayYourCourt 앱 소개](https://mwm.ai/apps/playyourcourt-play-tennis/1525178013)
- [OpenLadder](https://playopenladder.com/)
- [iTennisLadder](https://itennisladder.com/)
- [Global Tennis Network - Ladder Leagues](https://www.globaltennisnetwork.com/ladder-leagues/learn-more)
- [Rival Tennis Ladder](https://tennis-ladder.com/)
