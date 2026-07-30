export function numberParam(value: string | null): number | null {
  if (value === null || value.trim() === '') return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

/** 반경을 감싸는 위경도 사각형. DB 질의를 좁히는 용도(정확한 반경은 distanceKm 로 다시 거른다). */
export function boundingBox(
  latitude: number,
  longitude: number,
  radiusKm: number,
): {
  minLatitude: number;
  maxLatitude: number;
  minLongitude: number;
  maxLongitude: number;
} {
  const latDelta = radiusKm / 111.32;
  // 극지방에서 cos 이 0 에 수렴해 폭이 발산하므로 하한을 둔다.
  const cosLatitude = Math.max(Math.cos(latitude * Math.PI / 180), 0.01);
  const lonDelta = radiusKm / (111.32 * cosLatitude);
  return {
    minLatitude: Math.max(latitude - latDelta, -90),
    maxLatitude: Math.min(latitude + latDelta, 90),
    minLongitude: Math.max(longitude - lonDelta, -180),
    maxLongitude: Math.min(longitude + lonDelta, 180),
  };
}

export function distanceKm(
  latitude: number,
  longitude: number,
  clubLatitude: number,
  clubLongitude: number,
): number {
  const radians = (degrees: number) => degrees * Math.PI / 180;
  const latDelta = radians(clubLatitude - latitude);
  const lngDelta = radians(clubLongitude - longitude);
  const a = Math.sin(latDelta / 2) ** 2 +
    Math.cos(radians(latitude)) * Math.cos(radians(clubLatitude)) *
      Math.sin(lngDelta / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
