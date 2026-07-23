export interface ClubEventReminder {
  id: string;
  clubId: string;
  title: string;
  clubName: string;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export function tomorrowKstBounds(now: Date): {
  start: string;
  end: string;
} {
  const kstNow = new Date(now.getTime() + 9 * 60 * 60 * 1000);
  const tomorrow = new Date(kstNow.getTime() + 24 * 60 * 60 * 1000);
  const date = tomorrow.toISOString().slice(0, 10);
  const start = new Date(`${date}T00:00:00+09:00`);
  const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
  return { start: start.toISOString(), end: end.toISOString() };
}

export function parseClubEventReminders(
  rows: unknown,
): ClubEventReminder[] {
  if (!Array.isArray(rows)) return [];
  const reminders: ClubEventReminder[] = [];
  for (const row of rows) {
    if (!isRecord(row)) continue;
    const clubRelation = row['clubs'];
    const club = Array.isArray(clubRelation) ? clubRelation[0] : clubRelation;
    if (
      typeof row['id'] !== 'string' ||
      typeof row['club_id'] !== 'string' ||
      typeof row['title'] !== 'string'
    ) {
      continue;
    }
    reminders.push({
      id: row['id'],
      clubId: row['club_id'],
      title: row['title'],
      clubName: isRecord(club) && typeof club['name'] === 'string' ? club['name'] : '클럽',
    });
  }
  return reminders;
}

export function parseUserIds(rows: unknown): string[] {
  if (!Array.isArray(rows)) return [];
  return rows
    .filter(isRecord)
    .map((row) => row['user_id'])
    .filter((userId): userId is string => typeof userId === 'string');
}
