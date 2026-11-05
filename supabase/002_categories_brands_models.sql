-- Migration 002: dropdown lists for Category, Bike Brand and Bike Model.
-- Run once in Supabase Dashboard > SQL Editor, after schema.sql.
-- Safe to re-run.

-- ---------- Lookup tables ----------

create table if not exists public.categories (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (name = upper(btrim(name)) and name <> ''),
  created_at timestamptz not null default now()
);
create unique index if not exists categories_name_key on public.categories (name);

create table if not exists public.brands (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (name = upper(btrim(name)) and name <> ''),
  created_at timestamptz not null default now()
);
create unique index if not exists brands_name_key on public.brands (name);

-- Each model belongs to one brand. Deleting a brand deletes its models.
create table if not exists public.bike_models (
  id         uuid primary key default gen_random_uuid(),
  brand_id   uuid not null references public.brands (id) on delete cascade,
  name       text not null check (name = upper(btrim(name)) and name <> ''),
  created_at timestamptz not null default now()
);
create unique index if not exists bike_models_brand_name_key
  on public.bike_models (brand_id, name);

alter table public.categories enable row level security;
alter table public.brands enable row level security;
alter table public.bike_models enable row level security;

drop policy if exists "categories: signed-in full access" on public.categories;
create policy "categories: signed-in full access" on public.categories
  for all to authenticated using (true) with check (true);

drop policy if exists "brands: signed-in full access" on public.brands;
create policy "brands: signed-in full access" on public.brands
  for all to authenticated using (true) with check (true);

drop policy if exists "bike_models: signed-in full access" on public.bike_models;
create policy "bike_models: signed-in full access" on public.bike_models
  for all to authenticated using (true) with check (true);

-- ---------- Seed data ----------

insert into public.categories (name) values
  ('ENGINE PARTS'), ('BODY PARTS'), ('CONSUMABLES ITEMS'), ('ELECTRICAL PARTS')
on conflict do nothing;

insert into public.brands (name) values
  ('HONDA'), ('HERO'), ('BAJAJ'), ('YAMAHA')
on conflict do nothing;

insert into public.bike_models (brand_id, name)
select b.id, m.name
from (values
  ('HONDA', 'DIO OLD'),
  ('HONDA', 'DIO BS2'),
  ('HONDA', 'DIO BS3'),
  ('HONDA', 'DIO BS4'),
  ('HONDA', 'DIO BS5'),
  ('HONDA', 'DIO BS6'),
  ('HONDA', 'ACTIVA'),
  ('HERO',  'PLEASURE OLD'),
  ('HERO',  'PLEASURE NEW'),
  ('BAJAJ', 'CT 100 OLD'),
  ('BAJAJ', 'CT 100 NEW'),
  ('BAJAJ', 'DISCOVER 100CC OLD'),
  ('BAJAJ', 'DISCOVER 100CC NEW'),
  ('BAJAJ', 'DISCOVER 125CC OLD'),
  ('BAJAJ', 'DISCOVER 125CC NEW'),
  ('BAJAJ', 'DISCOVER 125 GOV'),
  ('BAJAJ', 'DISCOVER 135CC'),
  ('BAJAJ', 'DISCOVER 150')
) as m (brand, name)
join public.brands b on b.name = m.brand
on conflict do nothing;

-- ---------- Link parts to the lists ----------

alter table public.parts
  add column if not exists category_id   uuid references public.categories (id) on delete set null,
  add column if not exists brand_id      uuid references public.brands (id) on delete set null,
  add column if not exists bike_model_id uuid references public.bike_models (id) on delete set null;

create index if not exists parts_category_id_idx on public.parts (category_id);
create index if not exists parts_brand_id_idx on public.parts (brand_id);
create index if not exists parts_bike_model_id_idx on public.parts (bike_model_id);

-- Move any free-text values typed before this migration into the lists,
-- then drop the old text columns.
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'parts' and column_name = 'category') then

    insert into public.categories (name)
    select distinct upper(btrim(category)) from public.parts
    where coalesce(btrim(category), '') <> ''
    on conflict do nothing;

    insert into public.brands (name)
    select distinct upper(btrim(brand)) from public.parts
    where coalesce(btrim(brand), '') <> ''
    on conflict do nothing;

    update public.parts p set category_id = c.id
    from public.categories c where c.name = upper(btrim(p.category));

    update public.parts p set brand_id = b.id
    from public.brands b where b.name = upper(btrim(p.brand));

    insert into public.bike_models (brand_id, name)
    select distinct p.brand_id, upper(btrim(p.bike_model)) from public.parts p
    where p.brand_id is not null and coalesce(btrim(p.bike_model), '') <> ''
    on conflict do nothing;

    update public.parts p set bike_model_id = m.id
    from public.bike_models m
    where m.brand_id = p.brand_id and m.name = upper(btrim(p.bike_model));

    alter table public.parts drop column category;
    alter table public.parts drop column brand;
    alter table public.parts drop column bike_model;
  end if;
end;
$$;

-- A part's model must belong to the part's brand.
create or replace function public.check_part_model_brand()
returns trigger language plpgsql as $$
begin
  if new.bike_model_id is not null and not exists (
    select 1 from public.bike_models
    where id = new.bike_model_id and brand_id = new.brand_id
  ) then
    raise exception 'Bike model does not belong to the selected brand';
  end if;
  return new;
end;
$$;

drop trigger if exists parts_model_brand on public.parts;
create trigger parts_model_brand
  before insert or update of brand_id, bike_model_id on public.parts
  for each row execute function public.check_part_model_brand();

-- Make PostgREST pick up the new columns and relationships immediately.
notify pgrst, 'reload schema';
