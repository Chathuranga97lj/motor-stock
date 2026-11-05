-- Migration 007: suppliers and stock-in (purchases), paid now or later.
-- Stock-ins are created and changed only through the functions below.
-- Run once in Supabase Dashboard > SQL Editor, after 006. Safe to re-run.

-- ---------- Suppliers ----------

create table if not exists public.suppliers (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (btrim(name) <> ''),
  phone      text,
  address    text,
  note       text,
  created_at timestamptz not null default now()
);
create unique index if not exists suppliers_name_key on public.suppliers (upper(btrim(name)));

alter table public.suppliers enable row level security;

-- Everyone with a role reads and adds suppliers (admins add one during a
-- stock-in); only super admin edits or deletes.
drop policy if exists "suppliers: read" on public.suppliers;
drop policy if exists "suppliers: insert" on public.suppliers;
drop policy if exists "suppliers: super admin update" on public.suppliers;
drop policy if exists "suppliers: super admin delete" on public.suppliers;
create policy "suppliers: read" on public.suppliers
  for select to authenticated using (public.has_role());
create policy "suppliers: insert" on public.suppliers
  for insert to authenticated with check (public.has_role());
create policy "suppliers: super admin update" on public.suppliers
  for update to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());
create policy "suppliers: super admin delete" on public.suppliers
  for delete to authenticated using (public.is_super_admin());

-- ---------- Purchases ----------

create table if not exists public.purchase_counters (
  branch_id uuid primary key references public.branches (id) on delete restrict,
  last_no   integer not null default 0
);
alter table public.purchase_counters enable row level security;

create table if not exists public.purchases (
  id               uuid primary key default gen_random_uuid(),
  branch_id        uuid not null references public.branches (id) on delete restrict,
  seq              integer not null,
  purchase_no      text not null,
  supplier_id      uuid not null references public.suppliers (id) on delete restrict,
  invoice_no       text,
  invoice_date     date not null default current_date,
  note             text,
  subtotal         numeric(12, 2) not null check (subtotal >= 0),
  discount         numeric(12, 2) not null default 0 check (discount >= 0),
  total            numeric(12, 2) not null check (total >= 0),
  payment_method   text not null check (payment_method in ('cash', 'card', 'bank_transfer', 'credit')),
  amount_paid      numeric(12, 2) not null default 0,
  payment_status   text not null default 'paid' check (payment_status in ('paid', 'partial', 'unpaid')),
  status           text not null default 'completed' check (status in ('completed', 'cancelled')),
  cancel_reason    text,
  cancelled_at     timestamptz,
  cancelled_by     uuid references auth.users (id),
  created_by       uuid references auth.users (id) default auth.uid(),
  created_by_email text,
  created_at       timestamptz not null default now(),
  unique (branch_id, seq),
  check (discount <= subtotal),
  check (amount_paid >= 0 and amount_paid <= total)
);
create index if not exists purchases_branch_created_idx on public.purchases (branch_id, created_at desc);
create index if not exists purchases_supplier_idx on public.purchases (supplier_id);
create index if not exists purchases_invoice_idx on public.purchases (supplier_id, upper(invoice_no));

create table if not exists public.purchase_items (
  id          uuid primary key default gen_random_uuid(),
  purchase_id uuid not null references public.purchases (id) on delete cascade,
  part_id     uuid references public.parts (id) on delete set null,
  part_name   text not null,
  part_no     text,
  quantity    integer not null check (quantity > 0),
  unit_cost   numeric(12, 2) not null check (unit_cost >= 0),
  line_total  numeric(12, 2) not null check (line_total >= 0),
  sort_order  integer not null default 0
);
create index if not exists purchase_items_purchase_id_idx on public.purchase_items (purchase_id);

create table if not exists public.purchase_payments (
  id               uuid primary key default gen_random_uuid(),
  purchase_id      uuid not null references public.purchases (id) on delete cascade,
  branch_id        uuid not null references public.branches (id) on delete restrict,
  amount           numeric(12, 2) not null check (amount > 0),
  method           text not null check (method in ('cash', 'card', 'bank_transfer')),
  note             text,
  created_by       uuid references auth.users (id) default auth.uid(),
  created_by_email text,
  created_at       timestamptz not null default now()
);
create index if not exists purchase_payments_purchase_id_idx on public.purchase_payments (purchase_id);
create index if not exists purchase_payments_branch_created_idx
  on public.purchase_payments (branch_id, created_at desc);

alter table public.purchases enable row level security;
alter table public.purchase_items enable row level security;
alter table public.purchase_payments enable row level security;

-- Read only for the app; admins see their own branch.
drop policy if exists "purchases: read" on public.purchases;
create policy "purchases: read" on public.purchases
  for select to authenticated
  using (public.is_super_admin() or branch_id = public.my_branch_id());

drop policy if exists "purchase_items: read" on public.purchase_items;
create policy "purchase_items: read" on public.purchase_items
  for select to authenticated
  using (exists (select 1 from public.purchases p where p.id = purchase_id));

drop policy if exists "purchase_payments: read" on public.purchase_payments;
create policy "purchase_payments: read" on public.purchase_payments
  for select to authenticated
  using (public.is_super_admin() or branch_id = public.my_branch_id());

-- ---------- create_purchase ----------
-- p_items: [{"part_id": "...", "quantity": 10, "unit_cost": 450}, ...]
-- p_amount_paid: null = the full total. p_payment_method 'credit' = pay later.

create or replace function public.create_purchase(
  p_branch_id uuid,
  p_supplier_id uuid,
  p_items jsonb,
  p_invoice_no text default null,
  p_invoice_date date default null,
  p_discount numeric default 0,
  p_payment_method text default 'cash',
  p_amount_paid numeric default null,
  p_update_buy_price boolean default true,
  p_note text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line record;
  v_subtotal numeric(12, 2) := 0;
  v_discount numeric(12, 2) := round(coalesce(p_discount, 0), 2);
  v_total numeric(12, 2);
  v_paid numeric(12, 2);
  v_method text := p_payment_method;
  v_status text;
  v_seq integer;
  v_prefix text;
  v_id uuid;
begin
  if not public.has_role() then
    raise exception 'You do not have access';
  end if;
  if not public.is_super_admin() and p_branch_id is distinct from public.my_branch_id() then
    raise exception 'You can only stock in to your own branch';
  end if;
  if not exists (select 1 from suppliers where id = p_supplier_id) then
    raise exception 'Choose a supplier';
  end if;
  if v_method not in ('cash', 'card', 'bank_transfer', 'credit') then
    raise exception 'Choose a payment type';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Add at least one item';
  end if;

  drop table if exists _plines;
  create temp table _plines on commit drop as
    select (x ->> 'part_id')::uuid as part_id,
           (x ->> 'quantity')::integer as quantity,
           round((x ->> 'unit_cost')::numeric, 2) as unit_cost,
           ord
    from jsonb_array_elements(p_items) with ordinality as e (x, ord);

  if exists (select 1 from _plines where quantity is null or quantity <= 0) then
    raise exception 'Quantities must be more than 0';
  end if;
  if exists (select 1 from _plines where unit_cost is null or unit_cost < 0) then
    raise exception 'Costs cannot be negative';
  end if;
  if exists (select 1 from _plines l left join parts p on p.id = l.part_id where p.id is null) then
    raise exception 'A part on this stock-in no longer exists';
  end if;

  select coalesce(sum(round(quantity * unit_cost, 2)), 0) into v_subtotal from _plines;
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
  v_status := case when v_paid >= v_total then 'paid'
                   when v_paid > 0 then 'partial'
                   else 'unpaid' end;

  insert into purchase_counters (branch_id, last_no) values (p_branch_id, 1)
  on conflict (branch_id) do update set last_no = purchase_counters.last_no + 1
  returning last_no into v_seq;

  select coalesce(nullif(left(regexp_replace(upper(name), '[^A-Z]', '', 'g'), 3), ''), 'BR')
  into v_prefix
  from branches where id = p_branch_id;

  insert into purchases (branch_id, seq, purchase_no, supplier_id, invoice_no, invoice_date,
                         note, subtotal, discount, total, payment_method,
                         amount_paid, payment_status, created_by, created_by_email)
  values (p_branch_id, v_seq, 'PUR-' || v_prefix || '-' || lpad(v_seq::text, 6, '0'),
          p_supplier_id, nullif(btrim(p_invoice_no), ''), coalesce(p_invoice_date, current_date),
          nullif(btrim(p_note), ''), v_subtotal, v_discount, v_total, v_method,
          v_paid, v_status, auth.uid(), auth.jwt() ->> 'email')
  returning id into v_id;

  if v_paid > 0 then
    insert into purchase_payments (purchase_id, branch_id, amount, method,
                                   created_by, created_by_email)
    values (v_id, p_branch_id, v_paid, v_method, auth.uid(), auth.jwt() ->> 'email');
  end if;

  for v_line in
    select l.part_id, l.quantity, l.unit_cost, l.ord, p.name, p.part_no
    from _plines l join parts p on p.id = l.part_id
    order by l.ord
  loop
    insert into purchase_items (purchase_id, part_id, part_name, part_no, quantity,
                                unit_cost, line_total, sort_order)
    values (v_id, v_line.part_id, v_line.name, v_line.part_no, v_line.quantity,
            v_line.unit_cost, round(v_line.quantity * v_line.unit_cost, 2), v_line.ord);

    insert into stock_levels (part_id, branch_id, quantity)
    values (v_line.part_id, p_branch_id, v_line.quantity)
    on conflict (part_id, branch_id)
    do update set quantity = stock_levels.quantity + excluded.quantity, updated_at = now();

    -- Later lines win if the same part appears twice.
    if coalesce(p_update_buy_price, true) then
      update parts set buy_price = v_line.unit_cost where id = v_line.part_id;
    end if;
  end loop;

  return v_id;
end;
$$;

-- ---------- add_purchase_payment (super admin) ----------

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
  if v_amount > v_p.total - v_p.amount_paid then
    raise exception 'Amount is more than the balance of %', v_p.total - v_p.amount_paid;
  end if;

  insert into purchase_payments (purchase_id, branch_id, amount, method, note,
                                 created_by, created_by_email)
  values (p_purchase_id, v_p.branch_id, v_amount, p_method, nullif(btrim(p_note), ''),
          auth.uid(), auth.jwt() ->> 'email');

  v_paid := v_p.amount_paid + v_amount;
  update purchases
  set amount_paid = v_paid,
      payment_status = case when v_paid >= total then 'paid' else 'partial' end
  where id = p_purchase_id;
end;
$$;

-- ---------- cancel_purchase (super admin) ----------
-- Takes the stock back out, only if it is still there.

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
    select part_id, min(part_name) as part_name, sum(quantity) as quantity
    from purchase_items
    where purchase_id = p_purchase_id and part_id is not null
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

-- ---------- Duplicate invoice check (any branch) ----------
-- Returns the stock-in number that already used this supplier + invoice, or null.

create or replace function public.find_purchase_by_invoice(
  p_supplier_id uuid,
  p_invoice_no text
) returns text
language sql
stable
security definer
set search_path = public
as $$
  select purchase_no
  from purchases
  where public.has_role()
    and supplier_id = p_supplier_id
    and status = 'completed'
    and upper(btrim(invoice_no)) = upper(btrim(p_invoice_no))
  order by created_at desc
  limit 1;
$$;

revoke execute on function public.create_purchase(uuid, uuid, jsonb, text, date, numeric, text, numeric, boolean, text) from public, anon;
revoke execute on function public.add_purchase_payment(uuid, numeric, text, text) from public, anon;
revoke execute on function public.cancel_purchase(uuid, text) from public, anon;
revoke execute on function public.find_purchase_by_invoice(uuid, text) from public, anon;
grant execute on function public.create_purchase(uuid, uuid, jsonb, text, date, numeric, text, numeric, boolean, text) to authenticated;
grant execute on function public.add_purchase_payment(uuid, numeric, text, text) to authenticated;
grant execute on function public.cancel_purchase(uuid, text) to authenticated;
grant execute on function public.find_purchase_by_invoice(uuid, text) to authenticated;

notify pgrst, 'reload schema';
