-- Migration 012: customer returns (against a bill) and supplier returns
-- (against a stock-in).
-- Run once in Supabase Dashboard > SQL Editor, after 011. Safe to re-run.
--
-- Money rules, for both kinds:
-- * A return is worth the returned lines' price, less their share of the
--   bill / stock-in discount, so it never exceeds what was charged.
-- * returned_total is added up on the bill / stock-in. What is still owed is
--   total - returned_total - amount_paid.
-- * If more was paid than the new total, the difference is refunded (to the
--   customer, or by the supplier) and amount_paid goes down by that much, so
--   amount_paid is always the money actually kept.

-- ---------- Columns on bills and stock-ins ----------

alter table public.bills
  add column if not exists returned_total numeric(12, 2) not null default 0;
alter table public.bills drop constraint if exists bills_returned_total_check;
alter table public.bills add constraint bills_returned_total_check
  check (returned_total >= 0 and returned_total <= total);

alter table public.bill_items
  add column if not exists returned_qty integer not null default 0;
alter table public.bill_items drop constraint if exists bill_items_returned_qty_check;
alter table public.bill_items add constraint bill_items_returned_qty_check
  check (returned_qty >= 0 and returned_qty <= quantity);

alter table public.purchases
  add column if not exists returned_total numeric(12, 2) not null default 0;
alter table public.purchases drop constraint if exists purchases_returned_total_check;
alter table public.purchases add constraint purchases_returned_total_check
  check (returned_total >= 0 and returned_total <= total);

alter table public.purchase_items
  add column if not exists returned_qty integer not null default 0;
alter table public.purchase_items drop constraint if exists purchase_items_returned_qty_check;
alter table public.purchase_items add constraint purchase_items_returned_qty_check
  check (returned_qty >= 0 and returned_qty <= quantity);

-- ---------- Return records ----------

create table if not exists public.bill_returns (
  id               uuid primary key default gen_random_uuid(),
  bill_id          uuid not null references public.bills (id) on delete cascade,
  branch_id        uuid not null references public.branches (id) on delete restrict,
  reason           text not null check (btrim(reason) <> ''),
  return_value     numeric(12, 2) not null check (return_value >= 0),
  -- Money given back to the customer (0 when it only reduced what they owed).
  refund_amount    numeric(12, 2) not null default 0 check (refund_amount >= 0),
  refund_method    text check (refund_method in ('cash', 'card', 'bank_transfer')),
  created_by       uuid references auth.users (id) default auth.uid(),
  created_by_email text,
  created_at       timestamptz not null default now()
);
create index if not exists bill_returns_bill_id_idx on public.bill_returns (bill_id);
create index if not exists bill_returns_branch_created_idx
  on public.bill_returns (branch_id, created_at desc);

create table if not exists public.bill_return_items (
  id           uuid primary key default gen_random_uuid(),
  return_id    uuid not null references public.bill_returns (id) on delete cascade,
  bill_item_id uuid not null references public.bill_items (id) on delete cascade,
  part_id      uuid references public.parts (id) on delete set null,
  part_name    text not null,
  part_no      text,
  quantity     integer not null check (quantity > 0),
  unit_price   numeric(12, 2) not null,
  value        numeric(12, 2) not null
);
create index if not exists bill_return_items_return_id_idx on public.bill_return_items (return_id);

create table if not exists public.purchase_returns (
  id               uuid primary key default gen_random_uuid(),
  purchase_id      uuid not null references public.purchases (id) on delete cascade,
  branch_id        uuid not null references public.branches (id) on delete restrict,
  reason           text not null check (btrim(reason) <> ''),
  return_value     numeric(12, 2) not null check (return_value >= 0),
  -- Money the supplier gave back (0 when it only reduced what was owed).
  refund_amount    numeric(12, 2) not null default 0 check (refund_amount >= 0),
  refund_method    text check (refund_method in ('cash', 'card', 'bank_transfer')),
  created_by       uuid references auth.users (id) default auth.uid(),
  created_by_email text,
  created_at       timestamptz not null default now()
);
create index if not exists purchase_returns_purchase_id_idx on public.purchase_returns (purchase_id);
create index if not exists purchase_returns_branch_created_idx
  on public.purchase_returns (branch_id, created_at desc);

create table if not exists public.purchase_return_items (
  id               uuid primary key default gen_random_uuid(),
  return_id        uuid not null references public.purchase_returns (id) on delete cascade,
  purchase_item_id uuid not null references public.purchase_items (id) on delete cascade,
  part_id          uuid references public.parts (id) on delete set null,
  part_name        text not null,
  part_no          text,
  quantity         integer not null check (quantity > 0),
  unit_cost        numeric(12, 2) not null,
  value            numeric(12, 2) not null
);
create index if not exists purchase_return_items_return_id_idx
  on public.purchase_return_items (return_id);

-- Read only for the app; writes go through the functions below.
alter table public.bill_returns enable row level security;
alter table public.bill_return_items enable row level security;
alter table public.purchase_returns enable row level security;
alter table public.purchase_return_items enable row level security;

drop policy if exists "bill_returns: read" on public.bill_returns;
create policy "bill_returns: read" on public.bill_returns
  for select to authenticated
  using (public.is_super_admin() or branch_id = public.my_branch_id());

drop policy if exists "bill_return_items: read" on public.bill_return_items;
create policy "bill_return_items: read" on public.bill_return_items
  for select to authenticated
  using (exists (select 1 from public.bill_returns r where r.id = return_id));

drop policy if exists "purchase_returns: read" on public.purchase_returns;
create policy "purchase_returns: read" on public.purchase_returns
  for select to authenticated
  using (public.is_super_admin() or branch_id = public.my_branch_id());

drop policy if exists "purchase_return_items: read" on public.purchase_return_items;
create policy "purchase_return_items: read" on public.purchase_return_items
  for select to authenticated
  using (exists (select 1 from public.purchase_returns r where r.id = return_id));

-- ---------- return_bill_items ----------
-- p_items: [{"bill_item_id": "...", "quantity": 1}, ...]  (part lines only)
-- p_refund_method: how money is given back, if any is due.

create or replace function public.return_bill_items(
  p_bill_id uuid,
  p_items jsonb,
  p_reason text,
  p_refund_method text default 'cash'
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bill bills%rowtype;
  v_line record;
  v_ratio numeric;
  v_value numeric(12, 2) := 0;
  v_line_value numeric(12, 2);
  v_new_returned numeric(12, 2);
  v_net numeric(12, 2);
  v_refund numeric(12, 2);
  v_paid numeric(12, 2);
  v_id uuid;
begin
  if not public.has_role() then
    raise exception 'You do not have access';
  end if;

  select * into v_bill from bills where id = p_bill_id for update;
  if not found then
    raise exception 'Bill not found';
  end if;
  if not public.is_super_admin() and v_bill.branch_id is distinct from public.my_branch_id() then
    raise exception 'You can only take returns for your own branch';
  end if;
  if v_bill.status = 'cancelled' then
    raise exception 'This bill is cancelled';
  end if;
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'Enter the reason for the return';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Choose at least one part to return';
  end if;

  drop table if exists _ret;
  create temp table _ret on commit drop as
    select (x ->> 'bill_item_id')::uuid as item_id,
           sum((x ->> 'quantity')::integer) as quantity
    from jsonb_array_elements(p_items) as e (x)
    group by 1;

  if exists (select 1 from _ret where quantity is null or quantity <= 0) then
    raise exception 'Quantities must be more than 0';
  end if;

  -- Share of the bill discount taken off each returned line.
  v_ratio := case when v_bill.subtotal > 0 then 1 - v_bill.discount / v_bill.subtotal else 1 end;

  insert into bill_returns (bill_id, branch_id, reason, return_value,
                            created_by, created_by_email)
  values (p_bill_id, v_bill.branch_id, btrim(p_reason), 0, auth.uid(), auth.jwt() ->> 'email')
  returning id into v_id;

  for v_line in
    select r.item_id, r.quantity, i.id, i.bill_id, i.part_id, i.part_name, i.part_no,
           i.quantity as sold, i.returned_qty, i.unit_price,
           coalesce(i.item_type, 'part') as item_type
    from _ret r
    left join bill_items i on i.id = r.item_id
    order by i.sort_order
  loop
    if v_line.id is null or v_line.bill_id <> p_bill_id then
      raise exception 'A returned line is not on this bill';
    end if;
    if v_line.item_type <> 'part' then
      raise exception 'Service charges cannot be returned';
    end if;
    if v_line.part_id is null then
      raise exception '% was deleted from the app, so it cannot go back into stock', v_line.part_name;
    end if;
    if v_line.quantity > v_line.sold - v_line.returned_qty then
      raise exception 'Only % of % can still be returned',
        v_line.sold - v_line.returned_qty, v_line.part_name;
    end if;

    v_line_value := round(v_line.unit_price * v_line.quantity * v_ratio, 2);
    v_value := v_value + v_line_value;

    insert into bill_return_items (return_id, bill_item_id, part_id, part_name, part_no,
                                   quantity, unit_price, value)
    values (v_id, v_line.id, v_line.part_id, v_line.part_name, v_line.part_no,
            v_line.quantity, v_line.unit_price, v_line_value);

    update bill_items set returned_qty = returned_qty + v_line.quantity where id = v_line.id;

    insert into stock_levels (part_id, branch_id, quantity)
    values (v_line.part_id, v_bill.branch_id, v_line.quantity)
    on conflict (part_id, branch_id)
    do update set quantity = stock_levels.quantity + excluded.quantity, updated_at = now();
  end loop;

  -- Everything returned: take the whole remaining total so no cents are left.
  if not exists (select 1 from bill_items
                 where bill_id = p_bill_id
                   and (coalesce(item_type, 'part') <> 'part' or returned_qty < quantity)) then
    v_value := v_bill.total - v_bill.returned_total;
  end if;
  v_value := least(v_value, v_bill.total - v_bill.returned_total);

  v_new_returned := v_bill.returned_total + v_value;
  v_net := v_bill.total - v_new_returned;
  v_refund := greatest(v_bill.amount_paid - v_net, 0);
  if v_refund > 0 and coalesce(p_refund_method, '') not in ('cash', 'card', 'bank_transfer') then
    raise exception 'Choose how the money is given back';
  end if;
  v_paid := v_bill.amount_paid - v_refund;

  update bill_returns
  set return_value = v_value,
      refund_amount = v_refund,
      refund_method = case when v_refund > 0 then p_refund_method end
  where id = v_id;

  update bills
  set returned_total = v_new_returned,
      amount_paid = v_paid,
      payment_status = case when v_paid >= v_net then 'paid'
                            when v_paid > 0 then 'partial'
                            else 'unpaid' end
  where id = p_bill_id;

  return v_id;
end;
$$;

-- ---------- return_purchase_items ----------
-- p_items: [{"purchase_item_id": "...", "quantity": 1}, ...]
-- p_refund_method: how the supplier gives money back, if any is due.

create or replace function public.return_purchase_items(
  p_purchase_id uuid,
  p_items jsonb,
  p_reason text,
  p_refund_method text default 'cash'
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_p purchases%rowtype;
  v_line record;
  v_available integer;
  v_ratio numeric;
  v_value numeric(12, 2) := 0;
  v_line_value numeric(12, 2);
  v_new_returned numeric(12, 2);
  v_net numeric(12, 2);
  v_refund numeric(12, 2);
  v_paid numeric(12, 2);
  v_id uuid;
begin
  if not public.has_role() then
    raise exception 'You do not have access';
  end if;

  select * into v_p from purchases where id = p_purchase_id for update;
  if not found then
    raise exception 'Stock-in not found';
  end if;
  if not public.is_super_admin() and v_p.branch_id is distinct from public.my_branch_id() then
    raise exception 'You can only return stock from your own branch';
  end if;
  if v_p.status = 'cancelled' then
    raise exception 'This stock-in is cancelled';
  end if;
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'Enter the reason for the return';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Choose at least one part to return';
  end if;

  drop table if exists _pret;
  create temp table _pret on commit drop as
    select (x ->> 'purchase_item_id')::uuid as item_id,
           sum((x ->> 'quantity')::integer) as quantity
    from jsonb_array_elements(p_items) as e (x)
    group by 1;

  if exists (select 1 from _pret where quantity is null or quantity <= 0) then
    raise exception 'Quantities must be more than 0';
  end if;

  v_ratio := case when v_p.subtotal > 0 then 1 - v_p.discount / v_p.subtotal else 1 end;

  insert into purchase_returns (purchase_id, branch_id, reason, return_value,
                                created_by, created_by_email)
  values (p_purchase_id, v_p.branch_id, btrim(p_reason), 0, auth.uid(), auth.jwt() ->> 'email')
  returning id into v_id;

  for v_line in
    select r.item_id, r.quantity, i.id, i.purchase_id, i.part_id, i.part_name, i.part_no,
           i.quantity as received, i.returned_qty, i.unit_cost
    from _pret r
    left join purchase_items i on i.id = r.item_id
    order by i.sort_order
  loop
    if v_line.id is null or v_line.purchase_id <> p_purchase_id then
      raise exception 'A returned line is not on this stock-in';
    end if;
    if v_line.part_id is null then
      raise exception '% was deleted from the app, so its stock cannot be taken out', v_line.part_name;
    end if;
    if v_line.quantity > v_line.received - v_line.returned_qty then
      raise exception 'Only % of % can still be returned',
        v_line.received - v_line.returned_qty, v_line.part_name;
    end if;

    select quantity into v_available
    from stock_levels
    where part_id = v_line.part_id and branch_id = v_p.branch_id
    for update;
    if coalesce(v_available, 0) < v_line.quantity then
      raise exception 'Only % of % in stock at this branch', coalesce(v_available, 0), v_line.part_name;
    end if;

    v_line_value := round(v_line.unit_cost * v_line.quantity * v_ratio, 2);
    v_value := v_value + v_line_value;

    insert into purchase_return_items (return_id, purchase_item_id, part_id, part_name, part_no,
                                       quantity, unit_cost, value)
    values (v_id, v_line.id, v_line.part_id, v_line.part_name, v_line.part_no,
            v_line.quantity, v_line.unit_cost, v_line_value);

    update purchase_items set returned_qty = returned_qty + v_line.quantity where id = v_line.id;

    update stock_levels
    set quantity = quantity - v_line.quantity, updated_at = now()
    where part_id = v_line.part_id and branch_id = v_p.branch_id;
  end loop;

  if not exists (select 1 from purchase_items
                 where purchase_id = p_purchase_id and returned_qty < quantity) then
    v_value := v_p.total - v_p.returned_total;
  end if;
  v_value := least(v_value, v_p.total - v_p.returned_total);

  v_new_returned := v_p.returned_total + v_value;
  v_net := v_p.total - v_new_returned;
  v_refund := greatest(v_p.amount_paid - v_net, 0);
  if v_refund > 0 and coalesce(p_refund_method, '') not in ('cash', 'card', 'bank_transfer') then
    raise exception 'Choose how the supplier gives the money back';
  end if;
  v_paid := v_p.amount_paid - v_refund;

  update purchase_returns
  set return_value = v_value,
      refund_amount = v_refund,
      refund_method = case when v_refund > 0 then p_refund_method end
  where id = v_id;

  update purchases
  set returned_total = v_new_returned,
      amount_paid = v_paid,
      payment_status = case when v_paid >= v_net then 'paid'
                            when v_paid > 0 then 'partial'
                            else 'unpaid' end
  where id = p_purchase_id;

  return v_id;
end;
$$;

-- ---------- Payments now allow for returns ----------

create or replace function public.add_bill_payment(
  p_bill_id uuid,
  p_amount numeric,
  p_method text,
  p_note text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bill bills%rowtype;
  v_amount numeric(12, 2) := round(coalesce(p_amount, 0), 2);
  v_paid numeric(12, 2);
  v_due numeric(12, 2);
begin
  if not public.has_role() then
    raise exception 'You do not have access';
  end if;

  select * into v_bill from bills where id = p_bill_id for update;
  if not found then
    raise exception 'Bill not found';
  end if;
  if not public.is_super_admin() and v_bill.branch_id is distinct from public.my_branch_id() then
    raise exception 'You can only take payments for your own branch';
  end if;
  if v_bill.status = 'cancelled' then
    raise exception 'This bill is cancelled';
  end if;
  if p_method not in ('cash', 'card', 'bank_transfer') then
    raise exception 'Choose a payment method';
  end if;
  if v_amount <= 0 then
    raise exception 'Amount must be more than 0';
  end if;
  v_due := v_bill.total - v_bill.returned_total - v_bill.amount_paid;
  if v_amount > v_due then
    raise exception 'Amount is more than the balance of %', v_due;
  end if;

  insert into bill_payments (bill_id, branch_id, amount, method, note,
                             created_by, created_by_email)
  values (p_bill_id, v_bill.branch_id, v_amount, p_method, nullif(btrim(p_note), ''),
          auth.uid(), auth.jwt() ->> 'email');

  v_paid := v_bill.amount_paid + v_amount;
  update bills
  set amount_paid = v_paid,
      payment_status = case when v_paid >= total - returned_total then 'paid' else 'partial' end
  where id = p_bill_id;
end;
$$;

create or replace function public.add_purchase_payment(
  p_purchase_id uuid,
  p_amount numeric,
  p_method text,
  p_note text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_p purchases%rowtype;
  v_amount numeric(12, 2) := round(coalesce(p_amount, 0), 2);
  v_paid numeric(12, 2);
  v_due numeric(12, 2);
begin
  if not public.is_super_admin() then
    raise exception 'Only a super admin can record supplier payments';
  end if;

  select * into v_p from purchases where id = p_purchase_id for update;
  if not found then
    raise exception 'Stock-in not found';
  end if;
  if v_p.status = 'cancelled' then
    raise exception 'This stock-in is cancelled';
  end if;
  if p_method not in ('cash', 'card', 'bank_transfer') then
    raise exception 'Choose a payment method';
  end if;
  if v_amount <= 0 then
    raise exception 'Amount must be more than 0';
  end if;
  v_due := v_p.total - v_p.returned_total - v_p.amount_paid;
  if v_amount > v_due then
    raise exception 'Amount is more than the balance of %', v_due;
  end if;

  insert into purchase_payments (purchase_id, branch_id, amount, method, note,
                                 created_by, created_by_email)
  values (p_purchase_id, v_p.branch_id, v_amount, p_method, nullif(btrim(p_note), ''),
          auth.uid(), auth.jwt() ->> 'email');

  v_paid := v_p.amount_paid + v_amount;
  update purchases
  set amount_paid = v_paid,
      payment_status = case when v_paid >= total - returned_total then 'paid' else 'partial' end
  where id = p_purchase_id;
end;
$$;

-- ---------- Cancelling skips what was already returned ----------

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
  select part_id, v_bill.branch_id, sum(quantity - returned_qty)
  from bill_items
  where bill_id = p_bill_id and part_id is not null and quantity > returned_qty
  group by part_id
  on conflict (part_id, branch_id)
  do update set quantity = stock_levels.quantity + excluded.quantity, updated_at = now();
end;
$$;

create or replace function public.cancel_purchase(
  p_purchase_id uuid,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_p purchases%rowtype;
  v_line record;
  v_available integer;
begin
  if not public.is_super_admin() then
    raise exception 'Only a super admin can cancel a stock-in';
  end if;

  select * into v_p from purchases where id = p_purchase_id for update;
  if not found then
    raise exception 'Stock-in not found';
  end if;
  if v_p.status = 'cancelled' then
    raise exception 'This stock-in is already cancelled';
  end if;

  for v_line in
    select part_id, min(part_name) as part_name, sum(quantity - returned_qty) as quantity
    from purchase_items
    where purchase_id = p_purchase_id and part_id is not null and quantity > returned_qty
    group by part_id
  loop
    select quantity into v_available
    from stock_levels
    where part_id = v_line.part_id and branch_id = v_p.branch_id
    for update;

    if coalesce(v_available, 0) < v_line.quantity then
      raise exception 'Cannot cancel: only % of % left in stock (some was sold or moved)',
        coalesce(v_available, 0), v_line.part_name;
    end if;

    update stock_levels
    set quantity = quantity - v_line.quantity, updated_at = now()
    where part_id = v_line.part_id and branch_id = v_p.branch_id;
  end loop;

  update purchases
  set status = 'cancelled',
      cancel_reason = nullif(btrim(p_reason), ''),
      cancelled_at = now(),
      cancelled_by = auth.uid()
  where id = p_purchase_id;
end;
$$;

revoke execute on function public.return_bill_items(uuid, jsonb, text, text) from public, anon;
revoke execute on function public.return_purchase_items(uuid, jsonb, text, text) from public, anon;
grant execute on function public.return_bill_items(uuid, jsonb, text, text) to authenticated;
grant execute on function public.return_purchase_items(uuid, jsonb, text, text) to authenticated;

notify pgrst, 'reload schema';
