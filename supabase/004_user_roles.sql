-- Migration 004: user roles.
--   super_admin: everything, all branches.
--   admin:       one branch only. Can add and update parts and see/change
--                that branch's stock. Cannot delete parts, transfer stock,
--                see other branches, or manage lists, branches and users.
-- Users without a role can sign in but see nothing.
-- Run once in Supabase Dashboard > SQL Editor, after 003. Safe to re-run.

-- ---------- Profiles ----------

create table if not exists public.profiles (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  role       text not null check (role in ('super_admin', 'admin')),
  branch_id  uuid references public.branches (id) on delete restrict,
  updated_at timestamptz not null default now(),
  check (role = 'super_admin' or branch_id is not null)
);

alter table public.profiles enable row level security;

-- ---------- Helper functions used by the policies ----------
-- security definer so they can read profiles regardless of its own policies.

create or replace function public.has_role()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where user_id = auth.uid());
$$;

create or replace function public.is_super_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where user_id = auth.uid() and role = 'super_admin');
$$;

create or replace function public.my_branch_id()
returns uuid language sql stable security definer set search_path = public as $$
  select branch_id from profiles where user_id = auth.uid();
$$;

-- ---------- Policies ----------

-- profiles: read your own row; super admin reads all. Changes go through set_user_role().
drop policy if exists "profiles: read" on public.profiles;
create policy "profiles: read" on public.profiles
  for select to authenticated
  using (user_id = auth.uid() or public.is_super_admin());

-- parts: everyone with a role reads, adds and updates; only super admin deletes.
drop policy if exists "parts: signed-in full access" on public.parts;
drop policy if exists "parts: read" on public.parts;
drop policy if exists "parts: insert" on public.parts;
drop policy if exists "parts: update" on public.parts;
drop policy if exists "parts: delete" on public.parts;
create policy "parts: read" on public.parts
  for select to authenticated using (public.has_role());
create policy "parts: insert" on public.parts
  for insert to authenticated with check (public.has_role());
create policy "parts: update" on public.parts
  for update to authenticated using (public.has_role()) with check (public.has_role());
create policy "parts: delete" on public.parts
  for delete to authenticated using (public.is_super_admin());

-- part_images: anyone with a role (admins add and remove photos when editing).
drop policy if exists "part_images: signed-in full access" on public.part_images;
drop policy if exists "part_images: role access" on public.part_images;
create policy "part_images: role access" on public.part_images
  for all to authenticated using (public.has_role()) with check (public.has_role());

-- Dropdown lists: everyone with a role reads; only super admin changes.
do $$
declare t text;
begin
  foreach t in array array['categories', 'brands', 'bike_models'] loop
    execute format('drop policy if exists "%1$s: signed-in full access" on public.%1$I', t);
    execute format('drop policy if exists "%1$s: read" on public.%1$I', t);
    execute format('drop policy if exists "%1$s: super admin write" on public.%1$I', t);
    execute format('create policy "%1$s: read" on public.%1$I for select to authenticated using (public.has_role())', t);
    execute format('create policy "%1$s: super admin write" on public.%1$I for all to authenticated '
                   'using (public.is_super_admin()) with check (public.is_super_admin())', t);
  end loop;
end;
$$;

-- branches: admin sees only their own branch; only super admin changes.
drop policy if exists "branches: signed-in full access" on public.branches;
drop policy if exists "branches: read" on public.branches;
drop policy if exists "branches: super admin write" on public.branches;
create policy "branches: read" on public.branches
  for select to authenticated
  using (public.is_super_admin() or id = public.my_branch_id());
create policy "branches: super admin write" on public.branches
  for all to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());

-- stock_levels: admin reads and changes only their own branch.
drop policy if exists "stock_levels: signed-in full access" on public.stock_levels;
drop policy if exists "stock_levels: read" on public.stock_levels;
drop policy if exists "stock_levels: insert" on public.stock_levels;
drop policy if exists "stock_levels: update" on public.stock_levels;
drop policy if exists "stock_levels: delete" on public.stock_levels;
create policy "stock_levels: read" on public.stock_levels
  for select to authenticated
  using (public.is_super_admin() or branch_id = public.my_branch_id());
create policy "stock_levels: insert" on public.stock_levels
  for insert to authenticated
  with check (public.is_super_admin() or branch_id = public.my_branch_id());
create policy "stock_levels: update" on public.stock_levels
  for update to authenticated
  using (public.is_super_admin() or branch_id = public.my_branch_id())
  with check (public.is_super_admin() or branch_id = public.my_branch_id());
create policy "stock_levels: delete" on public.stock_levels
  for delete to authenticated using (public.is_super_admin());

-- stock_transfers: super admin only.
drop policy if exists "stock_transfers: signed-in read" on public.stock_transfers;
drop policy if exists "stock_transfers: signed-in insert" on public.stock_transfers;
drop policy if exists "stock_transfers: super admin read" on public.stock_transfers;
drop policy if exists "stock_transfers: super admin insert" on public.stock_transfers;
create policy "stock_transfers: super admin read" on public.stock_transfers
  for select to authenticated using (public.is_super_admin());
create policy "stock_transfers: super admin insert" on public.stock_transfers
  for insert to authenticated with check (public.is_super_admin());

-- Photo storage: only users with a role.
drop policy if exists "part-images: signed-in read" on storage.objects;
drop policy if exists "part-images: signed-in upload" on storage.objects;
drop policy if exists "part-images: signed-in update" on storage.objects;
drop policy if exists "part-images: signed-in delete" on storage.objects;
create policy "part-images: signed-in read" on storage.objects
  for select to authenticated using (bucket_id = 'part-images' and public.has_role());
create policy "part-images: signed-in upload" on storage.objects
  for insert to authenticated with check (bucket_id = 'part-images' and public.has_role());
create policy "part-images: signed-in update" on storage.objects
  for update to authenticated using (bucket_id = 'part-images' and public.has_role());
create policy "part-images: signed-in delete" on storage.objects
  for delete to authenticated using (bucket_id = 'part-images' and public.has_role());

-- ---------- Transfers: super admin only ----------

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
  if not public.is_super_admin() then
    raise exception 'Only a super admin can transfer stock';
  end if;
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

-- ---------- User management (super admin) ----------

-- All sign-in accounts with their role and branch.
create or replace function public.list_users()
returns table (
  user_id uuid,
  email text,
  role text,
  branch_id uuid,
  branch_name text,
  last_sign_in_at timestamptz
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Only a super admin can manage users';
  end if;
  return query
    select u.id, u.email::text, p.role, p.branch_id, b.name, u.last_sign_in_at
    from auth.users u
    left join profiles p on p.user_id = u.id
    left join branches b on b.id = p.branch_id
    order by u.email;
end;
$$;

-- Sets a user's role. p_role null removes their access.
create or replace function public.set_user_role(
  p_user_id uuid,
  p_role text,
  p_branch_id uuid default null
) returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Only a super admin can manage users';
  end if;
  if p_user_id = auth.uid() and p_role is distinct from 'super_admin' then
    raise exception 'You cannot change your own role';
  end if;
  if p_role = 'admin' and p_branch_id is null then
    raise exception 'Choose a branch for the admin';
  end if;

  if p_role is null then
    delete from profiles where user_id = p_user_id;
  else
    insert into profiles (user_id, role, branch_id, updated_at)
    values (p_user_id, p_role,
            case when p_role = 'admin' then p_branch_id end, now())
    on conflict (user_id) do update
      set role = excluded.role, branch_id = excluded.branch_id, updated_at = now();
  end if;
end;
$$;

revoke execute on function public.list_users() from public, anon;
revoke execute on function public.set_user_role(uuid, text, uuid) from public, anon;
grant execute on function public.list_users() to authenticated;
grant execute on function public.set_user_role(uuid, text, uuid) to authenticated;

-- ---------- First super admin ----------
-- After running this file, make yourself super admin with ONE line in the
-- SQL Editor (put your own login email):
--
--   insert into public.profiles (user_id, role)
--   select id, 'super_admin' from auth.users where email = 'you@example.com'
--   on conflict (user_id) do update set role = 'super_admin', branch_id = null;

notify pgrst, 'reload schema';
