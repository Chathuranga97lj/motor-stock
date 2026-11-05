-- Motor Stock schema. Run once in Supabase Dashboard > SQL Editor.

-- ---------- Tables ----------

create table if not exists public.parts (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  part_no         text,
  brand           text,
  bike_model      text,
  category        text,
  quantity        integer not null default 0 check (quantity >= 0),
  buy_price       numeric(12, 2) not null default 0,
  sell_price      numeric(12, 2) not null default 0,
  low_stock_level integer not null default 2 check (low_stock_level >= 0),
  created_by      uuid references auth.users (id) default auth.uid(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists parts_name_idx on public.parts (name);
create index if not exists parts_part_no_idx on public.parts (part_no);

create table if not exists public.part_images (
  id           uuid primary key default gen_random_uuid(),
  part_id      uuid not null references public.parts (id) on delete cascade,
  storage_path text not null,
  sort_order   integer not null default 0,
  created_at   timestamptz not null default now()
);

create index if not exists part_images_part_id_idx on public.part_images (part_id);

-- ---------- Triggers ----------

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists parts_touch_updated_at on public.parts;
create trigger parts_touch_updated_at
  before update on public.parts
  for each row execute function public.touch_updated_at();

-- Hard limit of 3 images per part, even if the app is bypassed.
create or replace function public.check_part_image_limit()
returns trigger language plpgsql as $$
begin
  if (select count(*) from public.part_images where part_id = new.part_id) >= 3 then
    raise exception 'A part can have at most 3 images';
  end if;
  return new;
end;
$$;

drop trigger if exists part_images_limit on public.part_images;
create trigger part_images_limit
  before insert on public.part_images
  for each row execute function public.check_part_image_limit();

-- ---------- Row Level Security ----------
-- Only signed-in users can read or change stock.

alter table public.parts enable row level security;
alter table public.part_images enable row level security;

drop policy if exists "parts: signed-in full access" on public.parts;
create policy "parts: signed-in full access" on public.parts
  for all to authenticated using (true) with check (true);

drop policy if exists "part_images: signed-in full access" on public.part_images;
create policy "part_images: signed-in full access" on public.part_images
  for all to authenticated using (true) with check (true);

-- ---------- Storage ----------
-- Public bucket so images load by URL; only signed-in users can upload or delete.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('part-images', 'part-images', true, 2097152,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

drop policy if exists "part-images: signed-in read" on storage.objects;
create policy "part-images: signed-in read" on storage.objects
  for select to authenticated using (bucket_id = 'part-images');

drop policy if exists "part-images: signed-in upload" on storage.objects;
create policy "part-images: signed-in upload" on storage.objects
  for insert to authenticated with check (bucket_id = 'part-images');

drop policy if exists "part-images: signed-in update" on storage.objects;
create policy "part-images: signed-in update" on storage.objects
  for update to authenticated using (bucket_id = 'part-images');

drop policy if exists "part-images: signed-in delete" on storage.objects;
create policy "part-images: signed-in delete" on storage.objects
  for delete to authenticated using (bucket_id = 'part-images');
