import { assert, assertEquals } from 'std/assert/mod.ts';
import { isValidRegionCode, REGION_CODES } from '../_shared/enums.ts';
import { AMBIGUOUS_NAMES, regionCodeFromText, SIGUNGU_TO_REGION } from '../_shared/region_text.ts';

// 아래 문자열은 2026-08-19 프로덕션 tournaments 의 KATO 실데이터다(location / title 원문).
Deno.test('regionCodeFromText: KATO 실제 장소 문자열에서 시도를 유도한다', () => {
  assertEquals(regionCodeFromText('안성시립테니스코트 외'), 'gyeonggi');
  assertEquals(
    regionCodeFromText('임실군생활체육공원 테니스코트장외 전주완산체련공원테니스장'),
    'jeonbuk',
  );
  assertEquals(regionCodeFromText('공주시립테니스코트'), 'chungnam');
  assertEquals(regionCodeFromText('창원시립테니스코트외'), 'gyeongnam');
  assertEquals(regionCodeFromText('원주 치악 테니스장 및 보조경기장'), 'gangwon');
  assertEquals(regionCodeFromText('문경 영강테니스장, 문경국제정구장, 문경공고 등'), 'gyeongbuk');
  assertEquals(regionCodeFromText('천안종합운동장 실외테니스장 외 보조구장'), 'chungnam');
  assertEquals(regionCodeFromText('청양군공설테니스코트 외'), 'chungnam');
  assertEquals(regionCodeFromText('화성 볼리테니스장 외 외 1곳'), 'gyeonggi');
  assertEquals(regionCodeFromText('성남양지시립코트외 보조코트'), 'gyeonggi');
});

Deno.test('regionCodeFromText: 구장이 여러 개면 첫 구장이 주 개최지다', () => {
  // 오산(경기) → 충주(충북) → 순천(전남) 순으로 나열된 실데이터.
  assertEquals(
    regionCodeFromText('오산시립테니스장, 충주 탄금대 테니스장, 순천팔마코트외 보조코트'),
    'gyeonggi',
  );
  // 키 순회 순서가 아니라 등장 위치가 이긴다.
  assertEquals(regionCodeFromText('안성시립테니스코트 외 부산 보조구장'), 'gyeonggi');
});

Deno.test('regionCodeFromText: 장소가 비면 제목으로 유도한다', () => {
  // 요강이 아직 안 채워져 location 이 '.' 인 대회들(KATO 빈 요강).
  assertEquals(regionCodeFromText('.'), null);
  assertEquals(regionCodeFromText('제20회 군산새만금배 전국동호인 테니스대회'), 'jeonbuk');
  assertEquals(regionCodeFromText('제27회 수원화성배 전국동호인테니스대회'), 'gyeonggi');
});

Deno.test('regionCodeFromText: 중의적인 이름은 매핑하지 않는다', () => {
  // "광주 양벌테니스 돔구장"은 경기도 광주시다 — 광주광역시로 넣으면 오매칭이다.
  assertEquals(regionCodeFromText('광주 양벌테니스 돔구장및 보조경기장'), null);
  assertEquals(
    regionCodeFromText('제 12 회 광주시 테니스협회장배 여성 동호인 전국 테니스대회'),
    null,
  );
  // '경기'를 넣으면 "보조경기장"만으로 전 대회가 경기도가 된다.
  assertEquals(regionCodeFromText('종합운동장 보조경기장'), null);
  // 자치구는 '구'까지 있어야 매칭 — 주최자 "㈜유성"이 대전으로 오탐되면 안 된다.
  assertEquals(regionCodeFromText('㈜유성 정성욱대표'), null);
  // 강원 고성군 / 경남 고성군.
  assertEquals(regionCodeFromText('고성 테니스장'), null);
});

Deno.test('regionCodeFromText: 자치구는 구 접미사와 함께 매칭한다', () => {
  assertEquals(regionCodeFromText('강남구민체육공원 테니스장'), 'seoul');
  assertEquals(regionCodeFromText('유성구 테니스장'), 'daejeon');
});

Deno.test('regionCodeFromText: 긴 이름이 짧은 이름을 이긴다', () => {
  assertEquals(regionCodeFromText('남양주시립테니스장'), 'gyeonggi');
});

Deno.test('regionCodeFromText: 빈 입력은 null', () => {
  assertEquals(regionCodeFromText(null), null);
  assertEquals(regionCodeFromText(undefined), null);
  assertEquals(regionCodeFromText(''), null);
  assertEquals(regionCodeFromText('테니스대회'), null);
});

Deno.test('AMBIGUOUS_NAMES: 이유가 비어 있으면 안 된다', () => {
  for (const [name, reason] of Object.entries(AMBIGUOUS_NAMES)) {
    assert(reason.trim().length > 0, `${name} 의 제외 사유가 비었다`);
    assertEquals(regionCodeFromText(name), null, `${name} 는 매핑되면 안 된다`);
  }
});

Deno.test('표의 모든 값이 유효한 RegionCode 다', () => {
  // 표는 손으로 유지한다 — 오타난 코드가 들어가면 regions FK 위반으로 upsert 가 500 난다.
  for (const [name, code] of Object.entries(SIGUNGU_TO_REGION)) {
    assert(isValidRegionCode(code), `${name} → ${code} 는 유효한 RegionCode 가 아니다`);
    assert(name.length >= 2, `${name} 는 너무 짧아 오탐 위험이 크다`);
    assert(!(name in AMBIGUOUS_NAMES), `${name} 는 중의적이라 표에 있으면 안 된다`);
  }
});

Deno.test('지명이 아닌 흔한 문구에는 걸리지 않는다', () => {
  // 표에 이름을 추가할 때 이 목록이 방어선이다. '기장'을 넣었다가 "경기장"에 걸린 적이 있다.
  const NOT_PLACES = [
    '보조경기장',
    '종합운동장 보조구장',
    '실외테니스장 및 보조코트',
    '전국동호인테니스대회',
    '테니스코트 외 3곳',
    '참가비 30,000원',
    '남녀 혼합복식 국화부',
  ];
  for (const text of NOT_PLACES) {
    assertEquals(regionCodeFromText(text), null, `"${text}" 에서 지역이 유도되면 안 된다`);
  }
});

Deno.test('표가 17개 시도를 모두 덮는다', () => {
  // 특정 시도가 통째로 빠지면 그 지역 대회는 영구히 필터에서 사라진다.
  const covered = new Set(Object.values(SIGUNGU_TO_REGION));
  for (const code of REGION_CODES) {
    // 세종은 기초자치단체가 없어 시도 라벨로만 잡힌다.
    if (code === 'sejong') continue;
    assert(covered.has(code), `${code} 에 매핑된 시군구가 하나도 없다`);
  }
});
