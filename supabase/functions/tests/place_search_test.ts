import { assertEquals } from 'std/assert/mod.ts';
import { normalizePlaceQuery, parseKakaoPlaces } from '../place-search/kakao.ts';

Deno.test('place search query is trimmed and bounded', () => {
  assertEquals(normalizePlaceQuery('  잠실   풋살장  '), '잠실 풋살장');
  assertEquals(normalizePlaceQuery('a'), null);
  assertEquals(normalizePlaceQuery('x'.repeat(81)), null);
});

Deno.test('Kakao place response is narrowed to safe typed fields', () => {
  assertEquals(
    parseKakaoPlaces({
      documents: [{
        id: '123',
        place_name: '잠실 풋살장',
        address_name: '서울 송파구 잠실동 1',
        road_address_name: '서울 송파구 올림픽로 1',
        y: '37.5',
        x: '127.1',
        category_name: '스포츠 > 풋살장',
        phone: '02-123-4567',
        ignored: 'provider-only',
      }],
    }),
    [{
      id: '123',
      name: '잠실 풋살장',
      address: '서울 송파구 잠실동 1',
      roadAddress: '서울 송파구 올림픽로 1',
      latitude: 37.5,
      longitude: 127.1,
      category: '스포츠 > 풋살장',
      phone: '02-123-4567',
    }],
  );
});

Deno.test('malformed coordinates are excluded', () => {
  assertEquals(
    parseKakaoPlaces({
      documents: [{
        id: 'bad',
        place_name: '잘못된 장소',
        address_name: '주소',
        road_address_name: '',
        y: 'not-a-number',
        x: '127.1',
        category_name: '',
        phone: '',
      }],
    }),
    [],
  );
});
