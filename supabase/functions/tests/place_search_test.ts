import { assertEquals } from 'std/assert/mod.ts';
import {
  normalizePlaceQuery,
  parseJusoCoordinateResponse,
  parseJusoSearchResponse,
  toPlaceSearchResult,
} from '../place-search/juso.ts';

Deno.test('place search query is trimmed and bounded', () => {
  assertEquals(normalizePlaceQuery('  잠실   풋살장  '), '잠실 풋살장');
  assertEquals(normalizePlaceQuery('a'), null);
  assertEquals(normalizePlaceQuery('x'.repeat(81)), null);
  assertEquals(normalizePlaceQuery('서울 UNION SELECT'), null);
});

Deno.test('Juso address response is narrowed to safe typed fields', () => {
  assertEquals(
    parseJusoSearchResponse({
      results: {
        common: { errorCode: '0', errorMessage: '정상' },
        juso: [{
          bdMgtSn: '123',
          bdNm: '잠실 풋살장',
          jibunAddr: '서울 송파구 잠실동 1',
          roadAddr: '서울 송파구 올림픽로 1',
          admCd: '1171010100',
          rnMgtSn: '117103123001',
          udrtYn: '0',
          buldMnnm: '1',
          buldSlno: '0',
          ignored: 'provider-only',
        }],
      },
    }),
    {
      errorCode: '0',
      errorMessage: '정상',
      addresses: [{
        id: '123',
        name: '잠실 풋살장',
        address: '서울 송파구 잠실동 1',
        roadAddress: '서울 송파구 올림픽로 1',
        admCd: '1171010100',
        rnMgtSn: '117103123001',
        udrtYn: '0',
        buldMnnm: '1',
        buldSlno: '0',
      }],
    },
  );
});

Deno.test('Juso coordinate response and UTM-K conversion are parsed safely', () => {
  const parsed = parseJusoCoordinateResponse({
    results: {
      common: { errorCode: '0', errorMessage: '정상' },
      juso: [{ entX: '955632.08', entY: '1952038.47' }],
    },
  });
  assertEquals(
    parsed,
    {
      errorCode: '0',
      errorMessage: '정상',
      coordinate: { x: 955632.08, y: 1952038.47 },
    },
  );
  const place = toPlaceSearchResult({
    id: '123',
    name: '잠실 풋살장',
    address: '서울 송파구 잠실동 1',
    roadAddress: '서울 송파구 올림픽로 1',
    admCd: '1171010100',
    rnMgtSn: '117103123001',
    udrtYn: '0',
    buldMnnm: '1',
    buldSlno: '0',
  }, parsed.coordinate!);
  assertEquals(place?.id, '123');
  assertEquals(place !== null && place.latitude > 33 && place.latitude < 39, true);
  assertEquals(place !== null && place.longitude > 124 && place.longitude < 132, true);
});
