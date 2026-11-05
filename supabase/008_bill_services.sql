-- Migration 008: bike service charges on bills.
-- A bill can hold parts, service lines, or both. Service lines do not touch stock.
-- Run once in Supabase Dashboard > SQL Editor, after 007. Safe to re-run.

-- ---------- Service list ----------

create table if not exists public.services (
  id            uuid primary key default gen_random_uuid(),
  name          text not null check (btrim(name) <> ''),
  default_price numeric(12, 2) not null default 0 check (default_price >= 0),
  active        boolean not null default true,
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now()
);
create unique index if not exists services_name_key on public.services (upper(btrim(name)));

alter table public.services enable row level security;

drop policy if exists "services: read" on public.services;
drop policy if exists "services: super admin write" on public.services;
create policy "services: read" on public.services
  for select to authenticated using (public.has_role());
create policy "services: super admin write" on public.services
  for all to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());

insert into public.services (name, default_price, sort_order) values
  ('Full service', 2500, 1),
  ('Oil change labour', 500, 2),
  ('Brake adjustment', 500, 3),
  ('Chain adjustment', 300, 4),
  ('Engine tune-up', 1500, 5),
  ('Washing', 500, 6)
on conflict do nothing;

-- ---------- Bills and bill items ----------

alter table public.bills
  add column if not exists bike_no text,
  add column if not exists parts_total numeric(12, 2),
  add column if not exists services_total numeric(12, 2);

-- Bills from before this migration were parts only.
update public.bills
set parts_total = subtotal, services_total = 0
where parts_total is null;

alter table public.bills alter column parts_total set default 0;
alter table public.bills alter column parts_total set not null;
alter table public.bills alter column services_total set default 0;
alter table public.bills alter column services_total set not null;

alter table public.bill_items
  add column if not exists item_type text not null default 'part',
  add column if not exists service_id uuid references public.services (id) on delete set null;

alter table public.bill_items drop constraint if exists bill_items_item_type_check;
alter table public.bill_items add constraint bill_items_item_type_check
  check (item_type in ('part', 'service'));

-- ---------- create_bill (parts and/or services) ----------

drop function if exists public.create_bill(uuid, jsonb, text, text, numeric, text, numeric);

-- p_items: parts   {"type":"part","part_id":"...","quantity":2}
--          service {"type":"service","service_id":"..." (optional),"name":"Full service","price":2500,"quantity":1}
-- Part prices come from parts.sell_price; service prices are taken as sent.
create or replace function public.create_bill(
  p_branch_id uuid,
  p_items jsonb,
  p_customer_name text default null,
  p_customer_phone text default null,
  p_discount numeric default 0,
  p_payment_method text default 'cash',
  p_amount_paid numeric default null,
  p_bike_no text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line record;
  v_available integer;
  v_parts numeric(12, 2) := 0;
  v_services numeric(12, 2) := 0;
  v_subtotal numeric(12, 2);
  v_discount numeric(12, 2) := round(coalesce(p_discount, 0), 2);
  v_total numeric(12, 2);
  v_paid numeric(12, 2);
  v_method text := p_payment_method;
  v_status text;
  v_seq integer;
  v_prefix text;
  v_bill_id uuid;
begin
  if not public.has_role() then
    raise exception 'You do not have access';
  end if;
  if not public.is_super_admin() and p_branch_id is distinct from public.my_branch_id() then
    raise exception 'You can only issue bills for your own branch';
  end if;
  if v_method not in ('cash', 'card', 'bank_transfer', 'credit') then
    raise exception 'Choose a payment type';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Add at least one part or service';
  end if;

  -- Parts: repeated parts are combined.
  drop table if exists _lines;
  create temp table _lines on commit drop as
    select (x ->> 'part_id')::uuid as part_id,
           sum((x ->> 'quantity')::integer) as quantity,
           min(ord) as ord
    from jsonb_array_elements(p_items) with ordinality as e (x, ord)
    where coalesce(x ->> 'type', 'part') = 'part'
    group by 1;

  -- Services: kept line by line.
  drop table if exists _svc;
  create temp table _svc on commit drop as
    select nullif(x ->> 'service_id', '')::uuid as service_id,
           btrim(coalesce(x ->> 'name', '')) as name,
           round((x ->> 'price')::numeric, 2) as price,
           coalesce((x ->> 'quantity')::integer, 1) as quantity,
           ord
    from jsonb_array_elements(p_items) with ordinality as e (x, ord)
    where x ->> 'type' = 'service';

  if exists (select 1 from _lines where quantity is null or quantity <= 0)
     or exists (select 1 from _svc where quantity <= 0) then
    raise exception 'Quantities must be more than 0';
  end if;
  if exists (select 1 from _svc where name = '') then
    raise exception 'Every service needs a description';
  end if;
  if exists (select 1 from _svc where price is null or price < 0) then
    raise exception 'Service charges cannot be negative';
  end if;

  for v_line in
    select l.part_id, l.quantity, p.name, p.sell_price
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

    v_parts := v_parts + round(v_line.sell_price * v_line.quantity, 2);
  end loop;

  select coalesce(sum(round(price * quantity, 2)), 0) into v_services from _svc;
  v_subtotal := v_parts + v_services;

  if v_discount < 0 or v_discount > v_subtotal then
    raise exception 'Discount must be between 0 and the subtotal';
  end if;
  v_total := v_subtotal - v_discount;

  v_paid := case when v_method = 'credit' then 0
                 else round(coalesce(p_amount_paid, v_total), 2) end;
  if v_paid < 0 or v_paid > v_total then
    raise exception 'Amount paid must be between 0 and the total';
  end if;
  if v_paid = 0 and v_total > 0 then
    v_method := 'credit';
  end if;
  if v_paid < v_total
     and (coalesce(btrim(p_customer_name), '') = '' or coalesce(btrim(p_customer_phone), '') = '') then
    raise exception 'Enter the customer name and phone for a bill that is not fully paid';
  end if;
  v_status := case when v_paid >= v_total then 'paid'
                   when v_paid > 0 then 'partial'
                   else 'unpaid' end;

  insert into bill_counters (branch_id, last_no) values (p_branch_id, 1)
  on conflict (branch_id) do update set last_no = bill_counters.last_no + 1
  returning last_no into v_seq;

  select coalesce(nullif(left(regexp_replace(upper(name), '[^A-Z]', '', 'g'), 3), ''), 'BIL')
  into v_prefix
  from branches where id = p_branch_id;

  insert into bills (branch_id, seq, bill_no, customer_name, customer_phone, bike_no,
                     subtotal, parts_total, services_total, discount, total, payment_method,
                     amount_paid, payment_status, created_by, created_by_email)
  values (p_branch_id, v_seq, v_prefix || '-' || lpad(v_seq::text, 6, '0'),
          nullif(btrim(p_customer_name), ''), nullif(btrim(p_customer_phone), ''),
          nullif(upper(btrim(p_bike_no)), ''),
          v_subtotal, v_parts, v_services, v_discount, v_total, v_method,
          v_paid, v_status, auth.uid(), auth.jwt() ->> 'email')
  returning id into v_bill_id;

  if v_paid > 0 then
    insert into bill_payments (bill_id, branch_id, amount, method,
                               created_by, created_by_email)
    values (v_bill_id, p_branch_id, v_paid, v_method,
            auth.uid(), auth.jwt() ->> 'email');
  end if;

  for v_line in
    select l.part_id, l.quantity, l.ord, p.name, p.part_no, p.sell_price
    from _lines l
    join parts p on p.id = l.part_id
  loop
    insert into bill_items (bill_id, item_type, part_id, part_name, part_no, quantity,
                            unit_price, line_total, sort_order)
    values (v_bill_id, 'part', v_line.part_id, v_line.name, v_line.part_no, v_line.quantity,
            v_line.sell_price, round(v_line.sell_price * v_line.quantity, 2), v_line.ord);

    update stock_levels
    set quantity = quantity - v_line.quantity, updated_at = now()
    where part_id = v_line.part_id and branch_id = p_branch_id;
  end loop;

  insert into bill_items (bill_id, item_type, service_id, part_name, quantity,
                          unit_price, line_total, sort_order)
  select v_bill_id, 'service', service_id, name, quantity,
         price, round(price * quantity, 2), ord
  from _svc;

  return v_bill_id;
end;
$$;

revoke execute on function public.create_bill(uuid, jsonb, text, text, numeric, text, numeric, text) from public, anon;
grant execute on function public.create_bill(uuid, jsonb, text, text, numeric, text, numeric, text) to authenticated;

notify pgrst, 'reload schema';
