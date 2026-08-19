-- 2026 공식 규칙 보강
--
-- 테니스: ITF Rules of Tennis 2026 및 2026 Amendments를 한국어 요약한다.
-- 풋살: 2026년 8월 현재 FIFA가 제공하는 현행 Futsal Laws of the Game
--         (2020/21 판본)을 기준으로 기존 누락·오류를 보완한다.
--
-- 원문 전체를 복제하지 않고 앱에서 상황별로 찾기 쉬운 요약만 저장한다.
-- 사용자가 직접 보강을 요청해 검수된 직접 시드이며, 각 글 본문에 공식 출처와
-- 대회별 로컬 규정 우선 안내를 함께 남긴다.

begin;

-- 기존 풋살 글에서 확인된 두 오류를 먼저 바로잡는다.
update public.rule_articles
set
  body = $body$풋살에서 자주 헷갈리는 골키퍼 재터치 제한을 정리합니다.

## 자기 진영 4초 제한
골키퍼는 자기 진영에서 손·팔 또는 발로 볼을 4초를 초과해 컨트롤할 수 없습니다. 손으로 잡을 수 있는 범위는 자기 페널티에어리어 안뿐이지만, 발로 컨트롤하는 경우에도 자기 진영에서는 같은 4초 제한이 적용됩니다.

## 동료가 다시 준 볼
골키퍼가 어느 위치에서든 한 번 플레이한 뒤, 상대 선수가 플레이하거나 터치하지 않은 상태에서 동료가 의도적으로 다시 준 볼을 자기 진영에서 재차 터치하면 간접 프리킥입니다. 볼이 하프라인을 먼저 넘어가야 한다는 조건은 없습니다.

## 손으로 잡을 수 없는 경우
동료가 발로 의도적으로 패스한 볼이나 동료의 킥인에서 직접 온 볼은 자기 페널티에어리어 안에서도 손·팔로 만질 수 없습니다.

※ FIFA Futsal Laws of the Game, Law 12 기준 요약입니다. 국내 동호인 대회는 별도 요강을 함께 확인하세요.
출처: https://digitalhub.fifa.com/m/696d0a3986700a31/original/smrcs2kmmsngmf5tf1fi-pdf.pdf$body$,
  embedding = null,
  embedding_updated_at = null
where sport = 'futsal'
  and title = '풋살 백패스 규칙';

update public.rule_articles
set
  body = $body$풋살의 직접·간접 프리킥 반칙, 누적 파울과 카드 제재를 정리합니다.

## 직접 프리킥과 누적 파울
차기, 걸기, 밀기, 잡기, 위험한 태클처럼 접촉을 수반하는 주요 반칙은 직접 프리킥 대상이며 팀의 누적 파울에 포함됩니다. 각 피리어드의 여섯 번째 누적 파울부터는 수비벽 없이 직접 프리킥을 실시합니다.

## 간접 프리킥
접촉 없이 상대의 진행을 방해하거나 위험한 방식으로 플레이한 경우, 또는 골키퍼가 자기 진영에서 4초 제한·재터치 제한을 위반한 경우에는 간접 프리킥이 주어질 수 있습니다.

## 옐로카드와 레드카드
옐로카드는 경고이며 그 자체로 2분 퇴장을 뜻하지 않습니다. 선수가 레드카드로 퇴장되면 해당 선수는 돌아올 수 없고, 팀은 원칙적으로 2분의 경기 시간이 지난 뒤 교체 선수를 투입할 수 있습니다. 2분 안에 득점이 발생한 경우의 조기 충원 여부는 양 팀의 선수 수 상황에 따라 달라집니다.

※ FIFA Futsal Laws of the Game, Laws 3·12·13 기준 요약입니다. 국내 동호인 대회는 별도 요강을 함께 확인하세요.
출처: https://digitalhub.fifa.com/m/696d0a3986700a31/original/smrcs2kmmsngmf5tf1fi-pdf.pdf$body$,
  embedding = null,
  embedding_updated_at = null
where sport = 'futsal'
  and title = '규칙 12 – 파울과 불법행위';

with official_rule_seed (
  sport,
  category,
  title,
  body,
  order_idx,
  published
) as (
  values
  -- ITF 2026 테니스 규칙: Rules 1-4
  ('tennis', '코트/장비', '2026 규칙 1·2 – 코트와 고정 시설물',
   $body$단식 코트는 길이 23.77m, 폭 8.23m이고 복식 코트 폭은 10.97m입니다. 네트 중앙 높이는 0.914m이며 네트 포스트 쪽 높이는 1.07m입니다.

라인은 그 선이 둘러싼 코트의 일부입니다. 관중석, 심판석, 볼퍼슨과 코트 주변·위의 시설은 고정 시설물에 포함됩니다. 단식 경기에서 복식 네트와 싱글스틱을 쓰면 싱글스틱 바깥의 네트와 포스트는 고정 시설물로 봅니다.

※ ITF Rules of Tennis 2026, Rules 1-2 요약. 대회별 코트 운영 요강을 함께 확인하세요.
출처: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
   1, true),

  ('tennis', '코트/장비', '2026 규칙 3·4 – 공과 라켓',
   $body$공과 라켓은 ITF가 승인한 규격을 충족해야 합니다. 대회는 사용할 공의 수와 교체 방식을 사전에 공지해야 하며, 경기 중 공이 실제로 파손되면 포인트를 다시 합니다. 단순히 공이 부드러워진 경우에는 포인트를 다시 하지 않습니다.

라켓의 타격면은 한 벌의 교차 스트링 패턴이어야 합니다. 진동 방지 장치는 교차 스트링 패턴 바깥에만 설치할 수 있고, 경기 중 동시에 두 개 이상의 라켓을 사용할 수 없습니다.

※ ITF Rules of Tennis 2026, Rules 3-4 요약.
출처: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
   2, true),

  -- Rules 5-7
  ('tennis', '점수/세트', '2026 규칙 5 – 게임 점수와 타이브레이크',
   $body$표준 게임은 서버의 점수를 먼저 부르며 러브, 15, 30, 40, 게임 순으로 진행합니다. 40-40은 듀스이며 한 선수가 연속 두 포인트를 얻어야 게임을 이깁니다.

표준 타이브레이크는 7점을 먼저 얻고 2점 차를 만들어야 끝납니다. 첫 서버가 1포인트를 서브한 뒤 상대가 2포인트, 이후 양쪽이 2포인트씩 번갈아 서브합니다.

※ ITF Rules of Tennis 2026, Rule 5 요약. 노애드 등 대체 방식은 대회가 사전에 공지할 수 있습니다.
출처: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
   1, true),

  ('tennis', '점수/세트', '2026 규칙 6·7 – 세트와 매치 승리',
   $body$어드밴티지 세트는 6게임을 먼저 얻고 2게임 차를 만들어야 이깁니다. 타이브레이크 세트는 6-6에서 타이브레이크 게임을 실시합니다. 어느 방식을 사용할지는 대회가 미리 공지해야 합니다.

매치는 일반적으로 3세트 중 2세트 또는 5세트 중 3세트를 먼저 얻은 선수·팀이 승리합니다. 동호인 대회가 사용하는 1세트 매치, 프로세트, 매치 타이브레이크는 공식 대체 득점 방식 또는 대회 요강을 확인해야 합니다.

※ ITF Rules of Tennis 2026, Rules 6-7 및 Appendix VI 요약.
출처: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
   2, true),

  -- Rules 8-15
  ('tennis', '경기 진행', '2026 규칙 8·9 – 서버·리시버와 토스',
   $body$서버는 첫 포인트를 시작하는 선수이고 리시버는 서브를 받아 넘길 준비를 하는 선수입니다. 리시버는 자기 쪽 코트 라인 안이나 밖 어느 위치에도 설 수 있습니다.

워밍업 전에 토스로 첫 게임의 서버·리시버 또는 코트 쪽을 정합니다. 토스 승자는 서브·리시브, 코트 쪽 선택, 또는 상대에게 먼저 선택하게 하는 것 중 하나를 고를 수 있습니다.

※ ITF Rules of Tennis 2026, Rules 8-9 요약.
출처: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
   1, true),

  ('tennis', '경기 진행', '2026 규칙 10~13 – 코트 교대와 볼 인플레이',
   $body$선수는 각 세트의 첫 번째, 세 번째 및 이후 홀수 게임이 끝날 때 코트를 바꿉니다. 타이브레이크에서는 6포인트마다 코트를 바꿉니다.

폴트나 렛이 선언되지 않으면 서버가 볼을 친 순간부터 포인트가 결정될 때까지 볼은 인플레이입니다. 볼이 라인에 닿으면 그 라인이 둘러싼 코트 안에 들어온 것으로 봅니다. 볼이 올바른 코트에 바운드된 뒤 고정 시설물에 맞으면 친 선수가 포인트를 얻지만, 바운드 전에 맞으면 잃습니다.

※ ITF Rules of Tennis 2026, Rules 10-13 요약.
출처: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
   2, true),

  ('tennis', '복식', '2026 규칙 14·15 – 복식 서브·리시브 순서',
   $body$복식에서는 각 세트 첫 게임에 서브할 선수를 팀이 정하고, 그 파트너가 같은 팀의 다음 서브 게임을 맡습니다. 이 순서는 세트가 끝날 때까지 유지됩니다.

리시브 팀도 각 세트 첫 리시브 게임에서 듀스·애드 코트의 리시버를 정하며 게임과 세트 동안 순서를 유지합니다. 리시버가 서브를 되돌린 뒤에는 어느 파트너든 다음 볼을 칠 수 있습니다. 한 명이 혼자 복식 팀으로 경기할 수는 없습니다.

※ ITF Rules of Tennis 2026, Rules 14-15 요약.
출처: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
   1, true),

  -- Rules 16-23 and 2026 foot-fault amendment
  ('tennis', '서브', '2026 규칙 16·17 – 올바른 서브 위치와 방향',
   $body$서버는 베이스라인 뒤, 센터마크와 사이드라인의 가상 연장선 사이에 두 발을 두고 정지한 상태에서 서브 동작을 시작합니다. 공을 손으로 어느 방향이든 놓은 뒤 땅에 닿기 전에 라켓으로 쳐야 합니다.

표준 게임은 오른쪽 코트에서 시작해 좌우를 번갈아 서브합니다. 타이브레이크도 오른쪽에서 시작하며, 서브는 네트를 넘어 대각선 맞은편 서비스 코트에 들어가야 합니다.

※ ITF Rules of Tennis 2026, Rules 16-17 요약.
출처: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
   1, true),

  ('tennis', '서브', '2026 개정 규칙 18 – 풋폴트',
   $body$서브 동작 중 걷거나 달려 위치를 바꾸거나, 발이 베이스라인·코트 안·사이드라인 바깥 가상 연장선·센터마크 가상 연장선을 건드리면 풋폴트입니다. 작은 발 움직임이나 발이 공중에 뜨는 것 자체는 허용됩니다.

2026 개정사항은 단식에서는 단식 사이드라인과 복식 사이드라인 사이 뒤쪽에서 서브할 수 없지만, 복식에서는 그 위치가 허용된다는 점을 명확히 했습니다.

※ ITF Rules of Tennis 2026, Rule 18 및 2026 Amendments 요약.
출처: https://www.itftennis.com/media/7224/2026-amendments-to-the-rules-of-tennis-and-beach-tennis.pdf$body$,
   2, true),

  ('tennis', '서브', '2026 규칙 19~23 – 서브 폴트·렛·리시버 준비',
   $body$서브 동작·위치 규칙을 위반하거나 공을 치려다 놓치고, 서브가 땅에 닿기 전에 고정 시설물·싱글스틱·네트 포스트 또는 서버·파트너에게 닿으면 폴트입니다. 토스한 공을 치지 않고 잡는 것은 폴트가 아닙니다.

첫 서브가 폴트면 같은 쪽에서 지체 없이 두 번째 서브를 합니다. 서버는 리시버가 준비될 때까지 서브하면 안 되지만, 리시버도 서버의 합리적인 속도에 맞춰 준비해야 합니다. 올바른 서브가 네트·스트랩·밴드를 건드리거나 준비되지 않은 리시버에게 서브되면 서비스 렛이며 그 서브만 다시 합니다. 일반 렛은 포인트 전체를 다시 합니다.

※ ITF Rules of Tennis 2026, Rules 19-23 요약.
출처: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
   3, true),

  -- Rules 24-26
  ('tennis', '득실점/판정', '2026 규칙 24 – 포인트를 잃는 경우',
   $body$더블폴트, 두 번 바운드 전에 리턴하지 못함, 올바른 코트 밖으로 보냄, 바운드 전에 고정 시설물에 맞힘, 리시버가 서브를 바운드 전에 침, 볼을 고의로 끌거나 두 번 침 등의 경우 포인트를 잃습니다.

볼이 인플레이일 때 선수·라켓·착용물이 네트나 상대 코트에 닿거나, 볼이 네트를 넘기 전에 치거나, 볼이 몸에 맞거나, 복식 파트너 두 명이 모두 볼을 건드려도 포인트를 잃습니다.

※ ITF Rules of Tennis 2026, Rule 24 요약.
출처: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
   1, true),

  ('tennis', '득실점/판정', '2026 규칙 25·26 – 유효한 리턴과 방해',
   $body$볼이 네트·포스트·싱글스틱·코드·스트랩·밴드를 건드린 뒤 올바른 코트에 들어가거나, 바람 때문에 네트 위로 되돌아간 볼을 규칙에 맞게 넘겨도 유효한 리턴이 될 수 있습니다.

상대의 고의적 방해를 받으면 방해받은 선수가 포인트를 얻고, 고의가 아닌 방해나 선수 통제 밖의 상황이면 보통 포인트를 다시 합니다. 관중 소음처럼 경기장 밖의 일반적 상황은 자동으로 방해 판정이 되지 않습니다.

※ ITF Rules of Tennis 2026, Rules 25-26 요약.
출처: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
   2, true),

  -- Rule 27 2026 amendment
  ('tennis', '득실점/판정', '2026 개정 규칙 27 – 순서·코트 오류 바로잡기',
   $body$서브 위치, 서버·리시버 순서, 코트 쪽 또는 득점 방식의 오류를 발견하면 원칙적으로 이미 끝난 포인트는 유지하고 가능한 즉시 올바른 상태로 고칩니다.

2026 개정사항은 타이브레이크 중 선수들이 잘못된 코트 쪽에 있다는 사실을 발견하기 전에 서브된 폴트는 유지되지 않는다는 점을 명확히 했습니다. 오류 발견 뒤에는 선수들이 즉시 올바른 코트 쪽으로 이동하고 해당 포인트를 올바르게 시작합니다.

※ ITF Rules of Tennis 2026, Rule 27 및 2026 Amendments 요약.
출처: https://www.itftennis.com/media/7224/2026-amendments-to-the-rules-of-tennis-and-beach-tennis.pdf$body$,
   3, true),

  -- Rules 28-31
  ('tennis', '경기 운영', '2026 규칙 28 – 코트 오피셜의 역할',
   $body$주심이 있는 경기에서는 주심이 경기 중 사실문제와 규칙문제에 대한 최종 권한을 가집니다. 라인 심판의 명백한 오류는 주심이 즉시 정정할 수 있으며, 규칙 적용에 관한 이의 제기는 정해진 절차로 레퍼리에게 제기할 수 있습니다.

선수가 셀프 콜로 진행하는 동호인 경기는 대회 요강과 셀프 저지 규정을 우선 확인해야 합니다.

※ ITF Rules of Tennis 2026, Rule 28 및 Appendix VII 요약.
출처: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
   1, true),

  ('tennis', '경기 운영', '2026 규칙 29 – 연속 경기와 휴식',
   $body$경기는 첫 서브부터 끝날 때까지 연속으로 진행하는 것이 원칙입니다. 포인트 사이, 코트 교대, 세트 사이의 허용 시간은 대회 규정에 따라 관리되며 선수는 체력 회복을 목적으로 임의 지연할 수 없습니다.

의복·신발·장비 문제, 부상 치료, 자연적인 체력 저하는 서로 다르게 취급됩니다. 메디컬 타임과 휴식은 해당 대회 요강 및 심판 지시를 따라야 합니다.

※ ITF Rules of Tennis 2026, Rule 29 요약.
출처: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
   2, true),

  ('tennis', '경기 운영', '2026 규칙 30·31 – 코칭과 선수 분석 기술',
   $body$코칭 허용 여부와 방식은 ITF Appendix IV와 대회 규정에 따릅니다. 팀 경기와 개인 경기, 코트 안팎 코칭, 전자기기 사용 가능 범위가 다를 수 있으므로 대회 공지를 확인해야 합니다.

선수 분석 기술 장치는 ITF가 승인한 범위에서 사용할 수 있으며, 경기 중 정보 접근·통신은 코칭 규정과 대회 규정을 함께 충족해야 합니다.

※ ITF Rules of Tennis 2026, Rules 30-31 및 Appendices III-IV 요약.
출처: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
   3, true),

  ('tennis', '참여/대체규정', '2026 휠체어 테니스 – 두 번 바운드와 혼합 경기',
   $body$휠체어 테니스 선수는 볼을 최대 두 번 바운드한 뒤 리턴할 수 있으며 두 번째 바운드는 코트 밖이어도 됩니다. 휠체어 선수와 비휠체어 선수가 함께 단식·복식을 할 때는 휠체어 선수에게만 두 번 바운드 규칙을 적용하고 비휠체어 선수는 한 번 바운드 규칙을 적용합니다.

서브와 휠체어 사용·접촉 규칙에는 별도 세부 기준이 있습니다.

※ ITF Rules of Tennis 2026, Rules of Wheelchair Tennis 요약.
출처: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
   1, true),

  ('tennis', '참여/대체규정', '2026 10세 이하와 대체 득점 방식',
   $body$10세 이하 경기는 연령과 단계에 맞는 레드·오렌지·그린 코트와 공을 사용할 수 있습니다. 대회는 노애드, 짧은 세트, 매치 타이브레이크 등 ITF가 승인한 대체 득점·운영 방식을 사전에 공지해 적용할 수 있습니다.

따라서 일반 규칙과 다른 형식으로 진행되더라도 대회 요강에 미리 명시되고 승인된 방식인지 확인하는 것이 중요합니다.

※ ITF Rules of Tennis 2026, Appendices VI·VIII 요약.
출처: https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf$body$,
   2, true),

  -- FIFA 현행 풋살 규칙에서 기존 DB에 빠진 항목
  ('futsal', '경기 진행', '현행 규칙 – 플라잉 교체 절차',
   $body$풋살은 대회 규정이 허용한 명단 안에서 교체 횟수에 제한 없이 경기 중에도 선수를 바꿀 수 있습니다.

교체 선수는 나가는 선수가 자기 팀 교체구역을 통해 완전히 피치를 벗어난 뒤 같은 교체구역으로 들어가야 합니다. 절차를 어기면 경고와 간접 프리킥 등 제재가 적용될 수 있습니다. 골키퍼와 필드 선수가 자리를 바꾸는 경우에도 유니폼·심판 통지 등 별도 절차를 지켜야 합니다.

※ FIFA Futsal Laws of the Game, Law 3 기준 요약. 대회 엔트리·교체 인원은 별도 요강을 확인하세요.
출처: https://digitalhub.fifa.com/m/696d0a3986700a31/original/smrcs2kmmsngmf5tf1fi-pdf.pdf$body$,
   31, true),

  ('futsal', '파울', '현행 규칙 – 퇴장 후 2분 수적 감소',
   $body$경기 시작 후 레드카드로 퇴장된 선수는 다시 경기에 들어올 수 없습니다. 팀은 원칙적으로 2분의 경기 시간이 흐른 뒤, 타임키퍼 또는 제3심판의 허가를 받아 교체 선수를 투입할 수 있습니다.

2분이 지나기 전에 득점이 발생하면 양 팀의 선수 수 관계에 따라 수가 적은 팀이 한 명을 조기에 보충할 수 있습니다. 수가 적은 팀이 득점한 경우에는 선수 수가 즉시 바뀌지 않습니다. 옐로카드는 경고이며 그 자체로 2분 수적 감소를 만들지 않습니다.

※ FIFA Futsal Laws of the Game, Law 3 기준 요약.
출처: https://digitalhub.fifa.com/m/696d0a3986700a31/original/smrcs2kmmsngmf5tf1fi-pdf.pdf$body$,
   32, true),

  ('futsal', '경기 진행', '현행 규칙 – 승부차기는 양 팀 5명부터',
   $body$승부차기로 경기 결과를 정할 때 양 팀은 번갈아 5번씩 킥합니다. 각 킥은 서로 다른 자격 있는 선수가 차며, 모든 자격 있는 선수가 한 번씩 차기 전에는 같은 선수가 두 번째 킥을 할 수 없습니다.

5번을 마치기 전에 한 팀이 상대가 따라잡을 수 없는 차이를 만들면 즉시 종료합니다. 5번씩 찬 뒤에도 같으면 같은 수의 킥을 실시했을 때 한 골 차이가 날 때까지 계속합니다.

※ FIFA Futsal Laws of the Game, Law 10 기준 요약. 2020 개정 전의 3명 방식과 혼동하지 마세요.
출처: https://digitalhub.fifa.com/m/696d0a3986700a31/original/smrcs2kmmsngmf5tf1fi-pdf.pdf$body$,
   33, true),

  ('futsal', '킥인/재개', '현행 규칙 – 드롭볼 재개',
   $body$심판이 규칙에 별도 재개 방법이 없는 이유로 경기를 멈췄다면 드롭볼로 재개합니다.

볼이 페널티에어리어 안에 있었거나 마지막 터치가 그 안에서 이뤄졌다면 수비 팀 골키퍼에게 드롭합니다. 그 밖의 위치에서는 경기가 멈추기 전 마지막으로 볼을 터치한 팀의 선수 한 명에게 드롭하고, 다른 선수들은 볼에서 2m 이상 떨어져야 합니다.

※ FIFA Futsal Laws of the Game, Law 8 기준 요약.
출처: https://digitalhub.fifa.com/m/696d0a3986700a31/original/smrcs2kmmsngmf5tf1fi-pdf.pdf$body$,
   34, true)
)
insert into public.rule_articles (
  sport,
  category,
  title,
  body,
  order_idx,
  published
)
select
  seed.sport::public.sport,
  seed.category,
  seed.title,
  seed.body,
  seed.order_idx,
  seed.published
from official_rule_seed as seed
where not exists (
  select 1
  from public.rule_articles as existing
  where existing.sport = seed.sport::public.sport
    and existing.title = seed.title
);

commit;
