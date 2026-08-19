-- 풋살 룰북을 경기 중 바로 참고할 수 있는 규칙·운영 정보 중심으로 정리한다.
-- 홍보·훈련·건강 가이드는 게시 해제해 기존 클릭 기록과 복구 가능성은 보존한다.

begin;

update public.rule_articles
set
  title = '풋살과 축구의 주요 차이',
  body = $body$풋살과 축구는 경기 인원과 재개 방식, 경기 시간, 교체 규칙이 다릅니다.

## 선수 수와 경기장
- 풋살: 골키퍼를 포함해 팀당 5명이 작은 피치에서 경기합니다.
- 축구: 골키퍼를 포함해 팀당 최대 11명이 넓은 필드에서 경기합니다.

## 공과 경기 시간
- 풋살: 반발력이 낮은 4호 공을 사용하고 전·후반 각 20분을 기본으로 합니다. 공식 경기에서는 볼이 아웃되면 경기 시간이 멈추는 클린타임을 적용합니다.
- 축구: 일반적으로 5호 공을 사용하고 전·후반 각 45분을 경기하며 중단된 시간은 추가시간으로 보충합니다.

## 터치라인 재개와 오프사이드
- 풋살: 볼이 터치라인을 넘으면 발로 킥인하며 오프사이드가 없습니다.
- 축구: 볼이 터치라인을 넘으면 손으로 스로인하며 오프사이드 규칙이 있습니다.

## 교체와 누적 파울
- 풋살: 지정된 교체구역에서 플라잉 방식으로 반복 교체할 수 있습니다. 한 피리어드의 직접 프리킥성 파울이 누적되며 여섯 번째부터 수비벽 없는 직접 프리킥이 적용됩니다.
- 축구: 공식 대회는 대회 규정이 정한 수만큼 경기 중단 때 교체하며, 풋살과 같은 팀 누적 파울 제도는 없습니다.

※ FIFA Futsal Laws of the Game 및 IFAB Laws of the Game 2026/27 기준 요약입니다. 실제 경기는 대회별 요강을 함께 확인하세요.
출처: https://digitalhub.fifa.com/m/696d0a3986700a31/original/smrcs2kmmsngmf5tf1fi-pdf.pdf
축구 규칙: https://www.theifab.com/laws/latest/$body$,
  embedding = null,
  embedding_updated_at = null
where sport = 'futsal'
  and title = '1. 풋살 vs 축구, 뭐가 다를까? 인원·공·규칙 6가지 차이 정리';

update public.rule_articles
set
  title = '풋살 포지션',
  body = $body$풋살은 네 포지션을 기본으로 설명하지만 경기 중에는 상황에 따라 계속 자리를 바꿉니다.

## 골레이로
골문을 지키는 골키퍼입니다. 슈팅을 막고 골 클리어런스와 패스로 공격을 시작합니다.

## 픽소
수비의 중심입니다. 상대 피보를 견제하고 뒤 공간을 지키며 공격 전개를 조율합니다.

## 아라
측면에서 공격과 수비를 모두 담당합니다. 패스 연결, 돌파, 압박과 수비 복귀가 주요 역할입니다.

## 피보
상대 골문 가까이에서 공을 받아 지켜내고 동료에게 연결하거나 직접 슈팅합니다.

포지션은 고정 자리가 아니라 팀의 움직임을 설명하는 역할 구분입니다. 선수들은 공격과 수비가 바뀔 때 서로의 빈자리를 채워야 합니다.$body$,
  embedding = null,
  embedding_updated_at = null
where sport = 'futsal'
  and title = '풋살 포지션 완벽 정리 | 피보·알라·픽소·골레이로';

-- 표준 표기인 '아라'로 기존 데이터 전체를 통일한다.
update public.rule_articles
set
  title = replace(title, '알라', '아라'),
  body = replace(body, '알라', '아라'),
  embedding = null,
  embedding_updated_at = null
where sport = 'futsal'
  and (title like '%알라%' or body like '%알라%');

-- 룰북 범위에서 벗어난 홍보·훈련·건강 콘텐츠는 사용자 화면에서 제외한다.
update public.rule_articles
set
  published = false,
  embedding = null,
  embedding_updated_at = null
where sport = 'futsal'
  and published
  and (
    category = '부상/컨디션'
    or title in (
      '풋살 시작, 당신의 인생을 재발견할 5가지 핵심 포인트!',
      '글로 배우는 풋살 잘하는 방법',
      '풋살 후 근육통 완화 및 빠른 회복 전략'
    )
  );

commit;
