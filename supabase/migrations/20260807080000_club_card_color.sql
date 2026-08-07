alter table public.clubs
  add column if not exists card_color text not null default '#3156D8';

alter table public.clubs
  add constraint clubs_card_color_allowed
  check (
    card_color = any (
      array[
        '#18376D',
        '#3156D8',
        '#176B63',
        '#6941C6',
        '#C2413B',
        '#A15C08'
      ]::text[]
    )
  );
