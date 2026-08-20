-- 피치 글을 광고·시설 안내가 아니라 사용자가 바로 찾는 실제 경기장 규격 중심으로 바꾼다.

begin;

update public.rule_articles
set
  title = '풋살 경기장 크기',
  body = $body$풋살 경기장은 직사각형이며 터치라인이 골라인보다 길어야 합니다.

## 일반 경기 규격
- 길이: 25~42m
- 폭: 16~25m

## 국제 경기 규격
- 길이: 38~42m
- 폭: 20~25m

국제 경기에서 많이 사용하는 40×20m 경기장은 위 허용 범위에 포함됩니다.

## 골대 규격
- 골대 안쪽 너비: 3m
- 지면에서 크로스바 아래까지 높이: 2m

골대는 넘어지지 않도록 안정적으로 설치해야 합니다. 실제 이용 전에는 구장별 바닥과 안전 여유 공간도 함께 확인하세요.

※ FIFA Futsal Laws of the Game, Law 1 기준 요약입니다. 국내 대회는 별도 요강을 함께 확인하세요.
출처: https://digitalhub.fifa.com/m/696d0a3986700a31/original/smrcs2kmmsngmf5tf1fi-pdf.pdf$body$,
  embedding = null,
  embedding_updated_at = null
where sport = 'futsal'
  and title = '규칙 1 – 피치 (경기장)';

commit;
