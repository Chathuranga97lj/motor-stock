-- Migration 006: credit and part payments on bills.
-- Every payment is a row in bill_payments (including the one taken when the
-- bill is issued). bills.amount_paid and payment_status are kept in step by
-- create_bill() and add_bill_payment().
-- Run once in Supabase Dashboard > SQL Editor, after 005. Safe to re-run.

-- ---------- bills: paid amount and status ----------

alter table public.bills
  add column if not exists amount_paid numeric(12, 2),
  add column if not exists payment_status text;

-- "credit" = nothing paid when the bill was issued.
alter table public.bills drop constraint if exists bills_payment_method_check;
alter table public.bills add constraint bills_payment_method_check
  check (payment_method in ('cash', 'card', 'bank_transfer', 'credit'));

-- ---------- bill_payments ----------

create table if not exists public.bill_payments (
  id               uuid primary key default gen_random_uuid(),
  bill_id          uuid not null references public.bills (id) on delete cascade,
  branch_id        uuid not null references public.branches (id) on delete restrict,
  amount           numeric(12, 2) not null check (amount > 0),
  method           text not null check (method in ('cash', 'card', 'bank_transfer')),
  note             text,
  created_by       uuid references auth.users (id) default auth.uid(),
  created_by_email text,
  created_at       timestamptz not null default now()
);
create index if not exists bill_payments_bill_id_idx on public.bill_payments (bill_id);
create index if not exists bill_payments_branch_created_idx
  on public.bill_payments (branch_id, created_at desc);

alter table public.bill_payments enable row level security;

-- Read only for the app; writes go through the functions below.
drop policy if exists "bill_payments: read" on public.bill_payments;
create policy "bill_payments: read" on public.bill_payments
  for select to authenticated
  using (public.is_super_admin() or branch_id = public.my_branch_id());

-- ---------- Existing bills were paid in full ----------

insert into public.bill_payments (bill_id, branch_id, amount, method,
                                  created_by, created_by_email, created_at)
select b.id, b.branch_id, b.total, b.payment_method,
       b.created_by, b.created_by_email, b.created_at
from public.bills b
where b.amount_paid is null
  and b.total > 0
  and b.payment_method in ('cash', 'card', 'bank_transfer')
  and not exists (select 1 from public.bill_payments p where p.bill_id = b.id);

update public.bills
set amount_paid = total, payment_status = 'paid'
where amount_paid is null;

alter table public.bills alter column amount_paid set default 0;
alter table public.bills alter column amount_paid set not null;
alter table public.bills alter column payment_status set default 'paid';
alter table public.bills alter column payment_status set not null;

alter table public.bills drop constraint if exists bills_payment_status_check;
alter table public.bills add constraint bills_payment_status_check
  check (payment_status in ('paid', 'partial', 'unpaid'));
alter table public.bills drop constraint if exists bills_amount_paid_check;
alter table public.bills add constraint bills_amount_paid_check
  check (amount_paid >= 0 and amount_paid <= total);

create index if not exists bills_outstanding_idx
  on public.bills (branch_id, created_at)
  where payment_status <> 'paid' and status = 'completed';

-- ---------- create_bill (now with amount paid now) ----------

drop function if exists public.create_bill(uuid, jsonb, text, text, numeric, text);

-- p_amount_paid: null = the full total. Less than the total needs a customer
-- name and phone. p_payment_method 'credit' = nothing paid now.
create or replace function public.create_bill(
  p_branch_id uuid,
  p_items jsonb,
  p_customer_name text default null,
  p_customer_phone text default null,
  p_discount numeric default 0,
  p_payment_method text default 'cash',
  p_amount_paid numeric default null
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
  v_total numeric(12, 2);
  v_paid numeric(12, 2);
  v_method text := p_payment_method;
  v_status text;
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
  if v_method not in ('cash', 'card', 'bank_transfer', 'credit') then
    raise exception 'Choose a payment type';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Add at least one item';
  end if;

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
  v_total := v_subtotal - v_discount;

  -- How much is paid now.
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

  insert into bills (branch_id, seq, bill_no, customer_name, customer_phone,
                     subtotal, discount, total, payment_method,
                     amount_paid, payment_status,
                     created_by, created_by_email)
  values (p_branch_id, v_seq, v_prefix || '-' || lpad(v_seq::text, 6, '0'),
          nullif(btrim(p_customer_name), ''), nullif(btrim(p_customer_phone), ''),
          v_subtotal, v_discount, v_total, v_method,
          v_paid, v_status,
          auth.uid(), auth.jwt() ->> 'email')
  returning id into v_bill_id;

  if v_paid > 0 then
    insert into bill_payments (bill_id, branch_id, amount, method,
                               created_by, created_by_email)
    values (v_bill_id, p_branch_id, v_paid, v_method,
            auth.uid(), auth.jwt() ->> 'email');
  end if;

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

-- ---------- add_bill_payment ----------

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
  if v_amount > v_bill.total - v_bill.amount_paid then
    raise exception 'Amount is more than the balance of %', v_bill.total - v_bill.amount_paid;
  end if;

  insert into bill_payments (bill_id, branch_id, amount, method, note,
                             created_by, created_by_email)
  values (p_bill_id, v_bill.branch_id, v_amount, p_method, nullif(btrim(p_note), ''),
          auth.uid(), auth.jwt() ->> 'email');

  v_paid := v_bill.amount_paid + v_amount;
  update bills
  set amount_paid = v_paid,
      payment_status = case when v_paid >= total then 'paid' else 'partial' end
  where id = p_bill_id;
end;
$$;

revoke execute on function public.create_bill(uuid, jsonb, text, text, numeric, text, numeric) from public, anon;
revoke execute on function public.add_bill_payment(uuid, numeric, text, text) from public, anon;
grant execute on function public.create_bill(uuid, jsonb, text, text, numeric, text, numeric) to authenticated;
grant execute on function public.add_bill_payment(uuid, numeric, text, text) to authenticated;

notify pgrst, 'reload schema';
