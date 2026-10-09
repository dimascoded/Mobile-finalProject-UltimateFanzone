create table if not exists public.away_day_expenses (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  title text not null,
  amount_gbp double precision not null check (amount_gbp >= 0),
  amount_idr double precision not null check (amount_idr >= 0),
  currency_code text not null default 'GBP'
    check (currency_code in ('GBP', 'USD', 'EUR', 'IDR')),
  amount_foreign double precision not null default 0
    check (amount_foreign >= 0),
  category text not null,
  club_key text,
  created_at text not null,
  primary key (user_id, id)
);

alter table public.away_day_expenses
  add column if not exists currency_code text not null default 'GBP';
alter table public.away_day_expenses
  add column if not exists amount_foreign double precision not null default 0;
update public.away_day_expenses
set amount_foreign = amount_gbp
where currency_code = 'GBP' and amount_foreign = 0 and amount_gbp > 0;

create table if not exists public.score_predictions (
  user_id uuid not null references auth.users(id) on delete cascade,
  match_id bigint not null,
  home_score integer,
  away_score integer,
  salt text,
  commit_hash text not null,
  created_at text not null,
  primary key (user_id, match_id),
  check (
    (home_score is null and away_score is null and salt is null)
    or (home_score is not null and away_score is not null and salt is not null)
  )
);

create table if not exists public.passport_chain_blocks (
  user_id uuid not null references auth.users(id) on delete cascade,
  idx integer not null check (idx >= 0),
  timestamp bigint not null,
  type text not null,
  data jsonb not null,
  owner text not null,
  prev_hash text not null,
  nonce bigint not null check (nonce >= 0),
  hash text not null,
  primary key (user_id, idx)
);

create table if not exists public.sync_tombstones (
  user_id uuid not null references auth.users(id) on delete cascade,
  collection text not null check (collection = 'away_day_expenses'),
  item_id text not null,
  deleted_at timestamptz not null default now(),
  primary key (user_id, collection, item_id)
);

create or replace function public.prevent_passport_block_update()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Passport blocks are immutable';
end;
$$;

drop trigger if exists passport_blocks_are_immutable
  on public.passport_chain_blocks;
create trigger passport_blocks_are_immutable
before update on public.passport_chain_blocks
for each row execute function public.prevent_passport_block_update();

alter table public.away_day_expenses enable row level security;
alter table public.score_predictions enable row level security;
alter table public.passport_chain_blocks enable row level security;
alter table public.sync_tombstones enable row level security;

drop policy if exists "owner manages away day expenses"
  on public.away_day_expenses;
create policy "owner manages away day expenses"
on public.away_day_expenses for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "owner manages score predictions"
  on public.score_predictions;
create policy "owner manages score predictions"
on public.score_predictions for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "owner manages passport chain"
  on public.passport_chain_blocks;
drop policy if exists "owner reads passport chain"
  on public.passport_chain_blocks;
create policy "owner reads passport chain"
on public.passport_chain_blocks for select to authenticated
using (auth.uid() = user_id);

drop policy if exists "owner appends passport chain"
  on public.passport_chain_blocks;
create policy "owner appends passport chain"
on public.passport_chain_blocks for insert to authenticated
with check (auth.uid() = user_id);

drop policy if exists "owner reads sync tombstones"
  on public.sync_tombstones;
create policy "owner reads sync tombstones"
on public.sync_tombstones for select to authenticated
using (auth.uid() = user_id);

drop policy if exists "owner adds sync tombstones"
  on public.sync_tombstones;
create policy "owner adds sync tombstones"
on public.sync_tombstones for insert to authenticated
with check (auth.uid() = user_id);

grant select, insert, update, delete
on public.away_day_expenses, public.score_predictions to authenticated;
grant select, insert on public.passport_chain_blocks,
  public.sync_tombstones to authenticated;