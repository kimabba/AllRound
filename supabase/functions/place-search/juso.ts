import proj4 from 'npm:proj4@2.19.10';

export interface JusoAddress {
  id: string;
  name: string;
  address: string;
  roadAddress: string;
  admCd: string;
  rnMgtSn: string;
  udrtYn: string;
  buldMnnm: string;
  buldSlno: string;
}

export interface PlaceSearchResult {
  id: string;
  name: string;
  address: string;
  roadAddress: string;
  latitude: number;
  longitude: number;
  category: string;
  phone: string;
}

export interface JusoSearchResponse {
  errorCode: string;
  errorMessage: string;
  addresses: JusoAddress[];
}

export interface JusoCoordinateResponse {
  errorCode: string;
  errorMessage: string;
  coordinate: { x: number; y: number } | null;
}

const utmK = '+proj=tmerc +lat_0=38 +lon_0=127.5 +k=0.9996 +x_0=1000000 +y_0=2000000 ' +
  '+ellps=GRS80 +units=m +no_defs';
const wgs84 = '+proj=longlat +datum=WGS84 +no_defs';

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function stringField(value: Record<string, unknown>, key: string): string | null {
  const field = value[key];
  return typeof field === 'string' ? field : null;
}

function parseAddress(value: unknown): JusoAddress | null {
  if (!isRecord(value)) return null;
  const roadAddress = stringField(value, 'roadAddr')?.trim() ?? '';
  const address = stringField(value, 'jibunAddr')?.trim() ?? '';
  const admCd = stringField(value, 'admCd')?.trim() ?? '';
  const rnMgtSn = stringField(value, 'rnMgtSn')?.trim() ?? '';
  const udrtYn = stringField(value, 'udrtYn')?.trim() ?? '';
  const buldMnnm = stringField(value, 'buldMnnm')?.trim() ?? '';
  const buldSlno = stringField(value, 'buldSlno')?.trim() ?? '';
  if (!roadAddress || !admCd || !rnMgtSn || !udrtYn || !buldMnnm) return null;

  const buildingName = stringField(value, 'bdNm')?.trim() ?? '';
  const id = stringField(value, 'bdMgtSn')?.trim() ||
    `${admCd}:${rnMgtSn}:${udrtYn}:${buldMnnm}:${buldSlno}`;
  return {
    id,
    name: buildingName || roadAddress,
    address,
    roadAddress,
    admCd,
    rnMgtSn,
    udrtYn,
    buldMnnm,
    buldSlno,
  };
}

export function parseJusoSearchResponse(value: unknown): JusoSearchResponse {
  if (!isRecord(value) || !isRecord(value.results)) {
    return { errorCode: 'INVALID_RESPONSE', errorMessage: '잘못된 응답', addresses: [] };
  }
  const common = isRecord(value.results.common) ? value.results.common : {};
  const errorCode = stringField(common, 'errorCode') ?? 'INVALID_RESPONSE';
  const errorMessage = stringField(common, 'errorMessage') ?? '';
  const rawAddresses = Array.isArray(value.results.juso) ? value.results.juso : [];
  return {
    errorCode,
    errorMessage,
    addresses: rawAddresses.map(parseAddress).filter((address): address is JusoAddress =>
      address !== null
    ),
  };
}

export function parseJusoCoordinateResponse(value: unknown): JusoCoordinateResponse {
  if (!isRecord(value) || !isRecord(value.results)) {
    return { errorCode: 'INVALID_RESPONSE', errorMessage: '잘못된 응답', coordinate: null };
  }
  const common = isRecord(value.results.common) ? value.results.common : {};
  const errorCode = stringField(common, 'errorCode') ?? 'INVALID_RESPONSE';
  const errorMessage = stringField(common, 'errorMessage') ?? '';
  const rawCoordinates = Array.isArray(value.results.juso) ? value.results.juso : [];
  const first = rawCoordinates.find(isRecord);
  if (!first) return { errorCode, errorMessage, coordinate: null };

  const rawX = stringField(first, 'entX');
  const rawY = stringField(first, 'entY');
  if (rawX === null || rawY === null) return { errorCode, errorMessage, coordinate: null };
  const x = Number(rawX);
  const y = Number(rawY);
  return {
    errorCode,
    errorMessage,
    coordinate: Number.isFinite(x) && Number.isFinite(y) ? { x, y } : null,
  };
}

export function toPlaceSearchResult(
  address: JusoAddress,
  coordinate: { x: number; y: number },
): PlaceSearchResult | null {
  const converted = proj4(utmK, wgs84, [coordinate.x, coordinate.y]);
  const longitude = converted[0];
  const latitude = converted[1];
  if (
    !Number.isFinite(latitude) || !Number.isFinite(longitude) ||
    latitude < 33 || latitude > 39 || longitude < 124 || longitude > 132
  ) return null;

  return {
    id: address.id,
    name: address.name,
    address: address.address,
    roadAddress: address.roadAddress,
    latitude,
    longitude,
    category: '',
    phone: '',
  };
}

export function normalizePlaceQuery(raw: string | null): string | null {
  const query = raw?.replace(/\s+/g, ' ').trim() ?? '';
  if (query.length < 2 || query.length > 80 || /[%<>=]/.test(query)) return null;
  const blockedWord =
    /(^|\s)(select|insert|delete|update|create|drop|exec|union|fetch|declare|truncate)($|\s)/i;
  return blockedWord.test(query) ? null : query;
}
