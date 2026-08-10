export interface KakaoPlace {
  id: string;
  name: string;
  address: string;
  roadAddress: string;
  latitude: number;
  longitude: number;
  category: string;
  phone: string;
}

interface KakaoDocument {
  id: string;
  place_name: string;
  address_name: string;
  road_address_name: string;
  y: string;
  x: string;
  category_name: string;
  phone: string;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function stringField(value: Record<string, unknown>, key: string): string | null {
  const field = value[key];
  return typeof field === 'string' ? field : null;
}

function parseDocument(value: unknown): KakaoPlace | null {
  if (!isRecord(value)) return null;
  const id = stringField(value, 'id');
  const name = stringField(value, 'place_name');
  const address = stringField(value, 'address_name');
  const roadAddress = stringField(value, 'road_address_name');
  const rawLatitude = stringField(value, 'y');
  const rawLongitude = stringField(value, 'x');
  if (!id || !name || !address || rawLatitude === null || rawLongitude === null) return null;

  const latitude = Number(rawLatitude);
  const longitude = Number(rawLongitude);
  if (
    !Number.isFinite(latitude) || !Number.isFinite(longitude) ||
    latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180
  ) return null;

  return {
    id,
    name,
    address,
    roadAddress: roadAddress ?? '',
    latitude,
    longitude,
    category: stringField(value, 'category_name') ?? '',
    phone: stringField(value, 'phone') ?? '',
  };
}

export function parseKakaoPlaces(value: unknown): KakaoPlace[] {
  if (!isRecord(value) || !Array.isArray(value.documents)) return [];
  return value.documents.map(parseDocument).filter((place): place is KakaoPlace => place !== null);
}

export function normalizePlaceQuery(raw: string | null): string | null {
  const query = raw?.replace(/\s+/g, ' ').trim() ?? '';
  return query.length >= 2 && query.length <= 80 ? query : null;
}
