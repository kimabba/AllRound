import { REGION_LABELS, type RegionCode } from './enums.ts';

/**
 * 장소·제목 문자열에서 region_code 를 유도한다.
 *
 * 배경: KATO 같은 전국 소스는 crawl_sources.region 이 비어 있어 대회에 지역이 안 붙는다.
 *   지역 필터는 region_code 정확매칭이라, 코드가 없으면 그 대회는 어느 지역을 골라도
 *   나오지 않는다(2026-08-19 프로덕션 KATO 18건 전부 region_code=null).
 *   원문에 광역시도 이름은 없지만 장소에는 시·군·구가 그대로 들어 있다
 *   ("안성시립테니스코트 외", "임실군생활체육공원") → 시군구 표로 시도를 유도한다.
 *
 * 원칙: 오매칭은 누락보다 나쁘다(엉뚱한 지역 대회가 목록에 뜬다). 이름이 둘 이상의
 *   시도에 걸리면 매핑하지 않고 null 로 둔다 — AMBIGUOUS_NAMES 참조.
 */

// 키 규칙 (2026-08 기준 행정구역):
//  - 시·군은 접미사를 뗀 짧은 이름. 원문이 "문경 영강테니스장"처럼 접미사 없이 쓴다.
//  - 자치구는 '구'까지 포함. '유성'만으로 잡으면 주최자 "㈜유성"이 대전으로 오탐된다(실데이터).
//  - 일반명사와 겹치는 지명(완주·장수·영광·장성·진도·영양·고령·상주·음성·성주)도 접미사를
//    붙여 오탐을 막는다. "완주"(다 뜀)·"영광"(榮光)·"고령"(高齡) 같은 말이 대회명에 흔하다.
//  - 두 시도에 같은 이름이 있으면 넣지 않는다 → AMBIGUOUS_NAMES.
export const SIGUNGU_TO_REGION: Readonly<Record<string, RegionCode>> = {
  // 서울 (자치구 25 중 중구·강서구는 타 광역시와 중복이라 제외)
  종로구: 'seoul',
  용산구: 'seoul',
  성동구: 'seoul',
  광진구: 'seoul',
  동대문구: 'seoul',
  중랑구: 'seoul',
  성북구: 'seoul',
  강북구: 'seoul',
  도봉구: 'seoul',
  노원구: 'seoul',
  은평구: 'seoul',
  서대문구: 'seoul',
  마포구: 'seoul',
  양천구: 'seoul',
  구로구: 'seoul',
  금천구: 'seoul',
  영등포구: 'seoul',
  동작구: 'seoul',
  관악구: 'seoul',
  서초구: 'seoul',
  강남구: 'seoul',
  송파구: 'seoul',
  강동구: 'seoul',

  // 부산
  영도구: 'busan',
  부산진구: 'busan',
  동래구: 'busan',
  해운대구: 'busan',
  사하구: 'busan',
  금정구: 'busan',
  연제구: 'busan',
  수영구: 'busan',
  사상구: 'busan',
  기장군: 'busan', // '기장'만 두면 "보조경기장"의 '경기장'에 걸린다(실제로 테스트가 잡았다)

  // 대구 (군위군은 2023-07 경북에서 편입)
  수성구: 'daegu',
  달서구: 'daegu',
  달성: 'daegu',
  군위: 'daegu',

  // 인천
  미추홀구: 'incheon',
  연수구: 'incheon',
  남동구: 'incheon',
  부평구: 'incheon',
  계양구: 'incheon',
  강화: 'incheon',
  옹진: 'incheon',

  // 광주 (동·서·남·북구는 중복이라 광산구만 남는다)
  광산구: 'gwangju',

  // 대전
  유성구: 'daejeon',
  대덕구: 'daejeon',

  // 울산
  울주: 'ulsan',

  // 경기 (광주시는 광주광역시와 중의 → 제외)
  수원: 'gyeonggi',
  성남: 'gyeonggi',
  의정부: 'gyeonggi',
  안양: 'gyeonggi',
  부천: 'gyeonggi',
  광명: 'gyeonggi',
  평택: 'gyeonggi',
  동두천: 'gyeonggi',
  안산: 'gyeonggi',
  고양: 'gyeonggi',
  과천: 'gyeonggi',
  구리: 'gyeonggi',
  남양주: 'gyeonggi',
  오산: 'gyeonggi',
  시흥: 'gyeonggi',
  군포: 'gyeonggi',
  의왕: 'gyeonggi',
  하남: 'gyeonggi',
  용인: 'gyeonggi',
  파주: 'gyeonggi',
  이천: 'gyeonggi',
  안성: 'gyeonggi',
  김포: 'gyeonggi',
  화성: 'gyeonggi',
  양주: 'gyeonggi',
  포천: 'gyeonggi',
  여주: 'gyeonggi',
  연천: 'gyeonggi',
  가평: 'gyeonggi',
  양평: 'gyeonggi',

  // 강원 (고성군은 경남과 중복 → 제외)
  춘천: 'gangwon',
  원주: 'gangwon',
  강릉: 'gangwon',
  동해: 'gangwon',
  태백: 'gangwon',
  속초: 'gangwon',
  삼척: 'gangwon',
  홍천: 'gangwon',
  횡성: 'gangwon',
  영월: 'gangwon',
  평창: 'gangwon',
  정선: 'gangwon',
  철원: 'gangwon',
  화천: 'gangwon',
  양구: 'gangwon',
  인제: 'gangwon',
  양양: 'gangwon',

  // 충북
  청주: 'chungbuk',
  충주: 'chungbuk',
  제천: 'chungbuk',
  보은군: 'chungbuk',
  옥천: 'chungbuk',
  영동군: 'chungbuk', // '영동'은 영동고속도로·영동대로와 겹친다
  증평: 'chungbuk',
  진천: 'chungbuk',
  괴산: 'chungbuk',
  음성군: 'chungbuk',
  단양: 'chungbuk',

  // 충남
  천안: 'chungnam',
  공주: 'chungnam',
  보령: 'chungnam',
  아산: 'chungnam',
  서산: 'chungnam',
  논산: 'chungnam',
  계룡: 'chungnam',
  당진: 'chungnam',
  금산: 'chungnam',
  부여: 'chungnam',
  서천: 'chungnam',
  청양: 'chungnam',
  홍성: 'chungnam',
  예산군: 'chungnam',
  태안: 'chungnam',

  // 전북
  전주: 'jeonbuk',
  군산: 'jeonbuk',
  익산: 'jeonbuk',
  정읍: 'jeonbuk',
  남원: 'jeonbuk',
  김제: 'jeonbuk',
  완주군: 'jeonbuk',
  진안: 'jeonbuk',
  무주: 'jeonbuk',
  장수군: 'jeonbuk',
  임실: 'jeonbuk',
  순창: 'jeonbuk',
  고창: 'jeonbuk',
  부안: 'jeonbuk',

  // 전남
  목포: 'jeonnam',
  여수: 'jeonnam',
  순천: 'jeonnam',
  나주: 'jeonnam',
  광양: 'jeonnam',
  담양: 'jeonnam',
  곡성: 'jeonnam',
  구례: 'jeonnam',
  고흥: 'jeonnam',
  보성: 'jeonnam',
  화순: 'jeonnam',
  장흥: 'jeonnam',
  강진: 'jeonnam',
  해남: 'jeonnam',
  영암: 'jeonnam',
  무안: 'jeonnam',
  함평: 'jeonnam',
  영광군: 'jeonnam',
  장성군: 'jeonnam',
  완도: 'jeonnam',
  진도군: 'jeonnam',
  신안: 'jeonnam',

  // 경북
  포항: 'gyeongbuk',
  경주: 'gyeongbuk',
  김천: 'gyeongbuk',
  안동: 'gyeongbuk',
  구미: 'gyeongbuk',
  영주: 'gyeongbuk',
  영천: 'gyeongbuk',
  상주시: 'gyeongbuk',
  문경: 'gyeongbuk',
  경산: 'gyeongbuk',
  의성: 'gyeongbuk',
  청송: 'gyeongbuk',
  영양군: 'gyeongbuk',
  영덕: 'gyeongbuk',
  청도: 'gyeongbuk',
  고령군: 'gyeongbuk',
  성주군: 'gyeongbuk',
  칠곡: 'gyeongbuk',
  예천: 'gyeongbuk',
  봉화: 'gyeongbuk',
  울진: 'gyeongbuk',
  울릉: 'gyeongbuk',

  // 경남 (고성군은 강원과 중복 → 제외)
  창원: 'gyeongnam',
  진주: 'gyeongnam',
  통영: 'gyeongnam',
  사천: 'gyeongnam',
  김해: 'gyeongnam',
  밀양: 'gyeongnam',
  거제: 'gyeongnam',
  양산: 'gyeongnam',
  의령: 'gyeongnam',
  함안: 'gyeongnam',
  창녕: 'gyeongnam',
  남해: 'gyeongnam',
  하동: 'gyeongnam',
  산청: 'gyeongnam',
  함양: 'gyeongnam',
  거창군: 'gyeongnam',
  합천: 'gyeongnam',

  // 제주
  서귀포: 'jeju',
};

/**
 * 매핑하지 않는 이름과 그 이유. 지우기 전에 왜 위험한지 먼저 확인할 것.
 * (자치구 중구·동구·서구·남구·북구·강서구 등은 여러 광역시에 동시에 존재해 표 자체에서 뺐다.)
 */
export const AMBIGUOUS_NAMES: Readonly<Record<string, string>> = {
  경기: '"보조경기장"·"종합경기장"과 겹쳐, 넣으면 거의 모든 대회가 gyeonggi 로 오염된다',
  광주: '광주광역시 / 경기도 광주시 중의. 실제로 "광주 양벌테니스 돔구장"은 경기도 광주시다',
  고성: '강원 고성군 / 경남 고성군',
};

// 시도 라벨 자체도 단서다("서울시립테니스장"). 중의적인 것만 뺀다.
const SIDO_LOOKUP: Readonly<Record<string, RegionCode>> = Object.fromEntries(
  (Object.entries(REGION_LABELS) as Array<[RegionCode, string]>)
    .filter(([, label]) => !(label in AMBIGUOUS_NAMES))
    .map(([code, label]) => [label, code]),
);

const LOOKUP: Readonly<Record<string, RegionCode>> = { ...SIGUNGU_TO_REGION, ...SIDO_LOOKUP };
const LOOKUP_KEYS = Object.keys(LOOKUP);

/**
 * 텍스트에서 시군구·시도 이름을 찾아 RegionCode 로 변환한다. 못 찾으면 null.
 *
 * ponytail: 부분문자열 스캔이다. 구장이 여러 개 나열되면("오산시립테니스장, 충주 탄금대
 * 테니스장, 순천팔마코트") 첫 구장이 주 개최지이므로 **가장 앞선 매치**를 쓰고, 같은
 * 위치에서 겹치면 긴 이름을 쓴다('남양주' > '양주'). 주소 파싱이 필요해지면 그때 올린다.
 */
export function regionCodeFromText(text: string | null | undefined): RegionCode | null {
  if (!text) return null;
  let best: RegionCode | null = null;
  let bestPos = Number.POSITIVE_INFINITY;
  let bestLen = 0;
  for (const key of LOOKUP_KEYS) {
    const pos = text.indexOf(key);
    if (pos < 0) continue;
    if (pos < bestPos || (pos === bestPos && key.length > bestLen)) {
      best = LOOKUP[key];
      bestPos = pos;
      bestLen = key.length;
    }
  }
  return best;
}
