export function numberParam(value: string | null): number | null {
  if (value === null || value.trim() === '') return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
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
