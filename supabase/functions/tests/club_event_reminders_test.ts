import {
  parseClubEventReminders,
  parseUserIds,
  tomorrowKstBounds,
} from '../_shared/club_event_reminders.ts';

Deno.test('D-1 bounds use the next calendar day in Korea', () => {
  const bounds = tomorrowKstBounds(new Date('2026-07-23T14:59:00Z'));
  if (
    bounds.start !== '2026-07-23T15:00:00.000Z' ||
    bounds.end !== '2026-07-24T15:00:00.000Z'
  ) {
    throw new Error(`unexpected KST reminder bounds: ${JSON.stringify(bounds)}`);
  }
});

Deno.test('club event reminder parser accepts object and array club joins', () => {
  const reminders = parseClubEventReminders([
    {
      id: 'event-1',
      club_id: 'club-1',
      title: '정기 모임',
      clubs: { name: '올라운드' },
    },
    {
      id: 'event-2',
      club_id: 'club-2',
      title: '번개 모임',
      clubs: [{ name: '풋살 클럽' }],
    },
  ]);
  if (
    reminders.length !== 2 ||
    reminders[0].clubName !== '올라운드' ||
    reminders[1].clubName !== '풋살 클럽'
  ) {
    throw new Error('valid event reminder rows must be parsed');
  }
});

Deno.test('club event reminder parser drops malformed rows and user ids', () => {
  const reminders = parseClubEventReminders([
    { id: 'event-1', club_id: null, title: '잘못된 일정' },
  ]);
  const userIds = parseUserIds([
    { user_id: 'user-1' },
    { user_id: null },
    'invalid',
  ]);
  if (reminders.length !== 0 || userIds.join(',') !== 'user-1') {
    throw new Error('malformed reminder inputs must be ignored');
  }
});
