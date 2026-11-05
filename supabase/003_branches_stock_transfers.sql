-- Migration 003: shop branches, stock per branch and stock transfers.
-- Run once in Supabase Dashboard > SQL Editor, after 002.
-- Safe to re-run.

-- ---------- Branches ----------

create table if not exists public.branches (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (name = upper(btrim(name)) and name <> ''),
  is_main    boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index if not exists branches_name_key on public.branches (name);
-- At most one main branch.
create unique index if not exists branches_one_main on public.branches (is_main) where is_main;

insert into public.branches (name, is_main) values
  ('IBBAGAMUWA', true),
  ('MELSIRIPURA', false)
on conflict do nothing;

-- ---------- Stock per branch ----------
-- A missing row means 0 in stock at that branch.

create table if not exists public.stock_levels (
  part_id    uuid not null references public.parts (id) on delete cascade,
  branch_id  uuid not null references public.branches (id) on delete restrict,
  quantity   integer not null default 0 check (quantity >= 0),
  updated_at timestamptz not null default now(),
  primary key (part_id, branch_id)
);
create index if not exists stock_levels_branch_id_idx on public.stock_levels (branch_id);

-- ---------- Transfer history ----------

create table if not exists public.stock_transfers (
  id             uuid primary key default gen_random_uuid(),
  part_id        uuid not null references public.parts (id) on delete cascade,
  from_branch_id uuid not null references public.branches (id) on delete restrict,
  to_branch_id   uuid not null references public.branches (id) on delete restrict,
  quantity       integer not null check (quantity > 0),
  note           text,
  created_by     uuid references auth.users (id) default auth.uid(),
  created_at     timestamptz not null default now(),
  check (from_branch_id <> to_branch_id)
);
create index if not exists stock_transfers_created_at_idx on public.stock_transfers (created_at desc);
create index if not exists stock_transfers_part_id_idx on public.stock_transfers (part_id);

-- ---------- Row Level Security ----------

alter table public.branches enable row level security;
alter table public.stock_levels enable row level security;
alter table public.stock_transfers enable row level security;

drop policy if exists "branches: signed-in full access" on public.branches;
create policy "branches: signed-in full access" on public.branches
  for all to authenticated using (true) with check (true);

drop policy if exists "stock_levels: signed-in full access" on public.stock_levels;
create policy "stock_levels: signed-in full access" on public.stock_levels
  for all to authenticated using (true) with check (true);

-- History is append-only: read and insert, no edits or deletes.
drop policy if exists "stock_transfers: signed-in read" on public.stock_transfers;
create policy "stock_transfers: signed-in read" on public.stock_transfers
  for select to authenticated using (true);

drop policy if exists "stock_transfers: signed-in insert" on public.stock_transfers;
create policy "stock_transfers: signed-in insert" on public.stock_transfers
  for insert to authenticated with check (true);

-- ---------- Move existing quantities to the main branch ----------

do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'parts' and column_name = 'quantity') then
    insert into public.stock_levels (part_id, branch_id, quantity)
    select p.id, b.id, p.quantity
    from public.parts p
    cross join (select id from public.branches where is_main) b
    on conflict (part_id, branch_id) do nothing;

    alter table public.parts drop column quantity;
  end if;
end;
$$;

-- ---------- Functions (called from the app) ----------

-- Moves stock between branches in one transaction and logs it.
create or replace function public.transfer_stock(
  p_part_id uuid,
  p_from_branch_id uuid,
  p_to_branch_id uuid,
  p_quantity integer,
  p_note text default null
) returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_available integer;
  v_id uuid;
begin
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be more than 0';
  end if;
  if p_from_branch_id = p_to_branch_id then
    raise exception 'Choose two different branches';
  end if;

  select quantity into v_available
  from stock_levels
  where part_id = p_part_id and branch_id = p_from_branch_id
  for update;

  if coalesce(v_available, 0) < p_quantity then
    raise exception 'Only % in stock at the sending branch', coalesce(v_available, 0);
  end if;

  update stock_levels
  set quantity = quantity - p_quantity, updated_at = now()
  where part_id = p_part_id and branch_id = p_from_branch_id;

  insert into stock_levels (part_id, branch_id, quantity)
  values (p_part_id, p_to_branch_id, p_quantity)
  on conflict (part_id, branch_id)
  do update set quantity = stock_levels.quantity + excluded.quantity, updated_at = now();

  insert into stock_transfers (part_id, from_branch_id, to_branch_id, quantity, note)
  values (p_part_id, p_from_branch_id, p_to_branch_id, p_quantity, nullif(btrim(p_note), ''))
  returning id into v_id;

  return v_id;
end;
$$;

-- Adds delta (may be negative) to one branch's stock, never below 0.
create or replace function public.adjust_stock(
  p_part_id uuid,
  p_branch_id uuid,
  p_delta integer
) returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_quantity integer;
begin
  insert into stock_levels (part_id, branch_id, quantity)
  values (p_part_id, p_branch_id, greatest(p_delta, 0))
  on conflict (part_id, branch_id)
  do update set quantity = greatest(0, stock_levels.quantity + p_delta), updated_at = now()
  returning quantity into v_quantity;
  return v_quantity;
end;
$$;

revoke execute on function public.transfer_stock(uuid, uuid, uuid, integer, text) from public, anon;
revoke execute on function public.adjust_stock(uuid, uuid, integer) from public, anon;
grant execute on function public.transfer_stock(uuid, uuid, uuid, integer, text) to authenticated;
grant execute on function public.adjust_stock(uuid, uuid, integer) to authenticated;

notify pgrst, 'reload schema';
