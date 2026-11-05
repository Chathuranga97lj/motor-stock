-- Migration 005: bills (sales).
-- Bills are created and cancelled only through create_bill() / cancel_bill(),
-- which check stock and permissions and calculate prices on the server.
-- Run once in Supabase Dashboard > SQL Editor, after 004. Safe to re-run.

-- ---------- Branch details printed on bills ----------

alter table public.branches
  add column if not exists address text,
  add column if not exists phone text;

-- ---------- Tables ----------

-- Last bill number used per branch.
create table if not exists public.bill_counters (
  branch_id uuid primary key references public.branches (id) on delete restrict,
  last_no   integer not null default 0
);

create table if not exists public.bills (
  id               uuid primary key default gen_random_uuid(),
  branch_id        uuid not null references public.branches (id) on delete restrict,
  seq              integer not null,
  bill_no          text not null,
  customer_name    text,
  customer_phone   text,
  subtotal         numeric(12, 2) not null check (subtotal >= 0),
  discount         numeric(12, 2) not null default 0 check (discount >= 0),
  total            numeric(12, 2) not null check (total >= 0),
  payment_method   text not null check (payment_method in ('cash', 'card', 'bank_transfer')),
  status           text not null default 'completed' check (status in ('completed', 'cancelled')),
  cancel_reason    text,
  cancelled_at     timestamptz,
  cancelled_by     uuid references auth.users (id),
  created_by       uuid references auth.users (id) default auth.uid(),
  created_by_email text,
  created_at       timestamptz not null default now(),
  unique (branch_id, seq),
  check (discount <= subtotal)
);
create index if not exists bills_branch_created_idx on public.bills (branch_id, created_at desc);

create table if not exists public.bill_items (
  id         uuid primary key default gen_random_uuid(),
  bill_id    uuid not null references public.bills (id) on delete cascade,
  -- Kept as a copy so old bills still read correctly if the part changes.
  part_id    uuid references public.parts (id) on delete set null,
  part_name  text not null,
  part_no    text,
  quantity   integer not null check (quantity > 0),
  unit_price numeric(12, 2) not null check (unit_price >= 0),
  line_total numeric(12, 2) not null check (line_total >= 0),
  sort_order integer not null default 0
);
create index if not exists bill_items_bill_id_idx on public.bill_items (bill_id);

-- ---------- Row Level Security ----------
-- Read only for the app. All writes go through the functions below.

alter table public.bill_counters enable row level security;
alter table public.bills enable row level security;
alter table public.bill_items enable row level security;

drop policy if exists "bills: read" on public.bills;
create policy "bills: read" on public.bills
  for select to authenticated
  using (public.is_super_admin() or branch_id = public.my_branch_id());

drop policy if exists "bill_items: read" on public.bill_items;
create policy "bill_items: read" on public.bill_items
  for select to authenticated
  using (exists (select 1 from public.bills b where b.id = bill_id));

-- ---------- create_bill ----------
-- p_items: [{"part_id": "...", "quantity": 2}, ...]
-- Prices come from parts.sell_price. Stock is taken from p_branch_id.

create or replace function public.create_bill(
  p_branch_id uuid,
  p_items jsonb,
  p_customer_name text default null,
  p_customer_phone text default null,
  p_discount numeric default 0,
  p_payment_method text default 'cash'
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line record;
  v_available integer;
  v_subtotal numeric(12, 2) := 0;
  v_discount numeric(12, 2) := round(coalesce(p_discount, 0), 2);
  v_seq integer;
  v_prefix text;
  v_bill_id uuid;
  v_order integer := 0;
begin
  if not public.has_role() then
    raise exception 'You do not have access';
  end if;
  if not public.is_super_admin() and p_branch_id is distinct from public.my_branch_id() then
    raise exception 'You can only issue bills for your own branch';
  end if;
  if p_payment_method not in ('cash', 'card', 'bank_transfer') then
    raise exception 'Choose a payment type';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Add at least one item';
  end if;

  -- Combine repeated parts, then lock and check stock for each.
  drop table if exists _lines;
  create temp table _lines on commit drop as
    select (x ->> 'part_id')::uuid as part_id,
           sum((x ->> 'quantity')::integer) as quantity,
           min(ord) as ord
    from jsonb_array_elements(p_items) with ordinality as e (x, ord)
    group by 1;

  if exists (select 1 from _lines where quantity is null or quantity <= 0) then
    raise exception 'Quantities must be more than 0';
  end if;

  for v_line in
    select l.part_id, l.quantity, p.name, p.part_no, p.sell_price
    from _lines l
    left join parts p on p.id = l.part_id
    order by l.ord
  loop
    if v_line.name is null then
      raise exception 'A part on this bill no longer exists';
    end if;

    select quantity into v_available
    from stock_levels
    where part_id = v_line.part_id and branch_id = p_branch_id
    for update;

    if coalesce(v_available, 0) < v_line.quantity then
      raise exception 'Only % of % in stock', coalesce(v_available, 0), v_line.name;
    end if;

    v_subtotal := v_subtotal + round(v_line.sell_price * v_line.quantity, 2);
  end loop;

  if v_discount < 0 or v_discount > v_subtotal then
    raise exception 'Discount must be between 0 and the subtotal';
  end if;

  -- Next bill number for this branch, e.g. MEL-000042.
  insert into bill_counters (branch_id, last_no) values (p_branch_id, 1)
  on conflict (branch_id) do update set last_no = bill_counters.last_no + 1
  returning last_no into v_seq;

  select coalesce(nullif(left(regexp_replace(upper(name), '[^A-Z]', '', 'g'), 3), ''), 'BIL')
  into v_prefix
  from branches where id = p_branch_id;

  insert into bills (branch_id, seq, bill_no, customer_name, customer_phone,
                     subtotal, discount, total, payment_method,
                     created_by, created_by_email)
  values (p_branch_id, v_seq, v_prefix || '-' || lpad(v_seq::text, 6, '0'),
          nullif(btrim(p_customer_name), ''), nullif(btrim(p_customer_phone), ''),
          v_subtotal, v_discount, v_subtotal - v_discount, p_payment_method,
          auth.uid(), auth.jwt() ->> 'email')
  returning id into v_bill_id;

  for v_line in
    select l.part_id, l.quantity, p.name, p.part_no, p.sell_price
    from _lines l
    join parts p on p.id = l.part_id
    order by l.ord
  loop
    insert into bill_items (bill_id, part_id, part_name, part_no, quantity,
                            unit_price, line_total, sort_order)
    values (v_bill_id, v_line.part_id, v_line.name, v_line.part_no, v_line.quantity,
            v_line.sell_price, round(v_line.sell_price * v_line.quantity, 2), v_order);
    v_order := v_order + 1;

    update stock_levels
    set quantity = quantity - v_line.quantity, updated_at = now()
    where part_id = v_line.part_id and branch_id = p_branch_id;
  end loop;

  return v_bill_id;
end;
$$;

-- ---------- cancel_bill ----------
-- Super admin only. Marks the bill cancelled and returns its stock.

create or replace function public.cancel_bill(
  p_bill_id uuid,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bill bills%rowtype;
begin
  if not public.is_super_admin() then
    raise exception 'Only a super admin can cancel bills';
  end if;

  select * into v_bill from bills where id = p_bill_id for update;
  if not found then
    raise exception 'Bill not found';
  end if;
  if v_bill.status = 'cancelled' then
    raise exception 'This bill is already cancelled';
  end if;

  update bills
  set status = 'cancelled',
      cancel_reason = nullif(btrim(p_reason), ''),
      cancelled_at = now(),
      cancelled_by = auth.uid()
  where id = p_bill_id;

  insert into stock_levels (part_id, branch_id, quantity)
  select part_id, v_bill.branch_id, sum(quantity)
  from bill_items
  where bill_id = p_bill_id and part_id is not null
  group by part_id
  on conflict (part_id, branch_id)
  do update set quantity = stock_levels.quantity + excluded.quantity, updated_at = now();
end;
$$;

revoke execute on function public.create_bill(uuid, jsonb, text, text, numeric, text) from public, anon;
revoke execute on function public.cancel_bill(uuid, text) from public, anon;
grant execute on function public.create_bill(uuid, jsonb, text, text, numeric, text) to authenticated;
grant execute on function public.cancel_bill(uuid, text) to authenticated;

notify pgrst, 'reload schema';
