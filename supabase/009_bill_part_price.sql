-- Migration 009: the price of a part can be changed on a bill.
-- The app sends each part line's price (it starts at parts.sell_price).
-- A part line without a price still uses parts.sell_price.
-- Run once in Supabase Dashboard > SQL Editor, after 008. Safe to re-run.

-- p_items: parts   {"type":"part","part_id":"...","quantity":2,"price":1950}
--          service {"type":"service","service_id":"..." (optional),"name":"Full service","price":2500,"quantity":1}
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

  -- Part lines as sent, each with its own price (sell price when not sent).
  drop table if exists _lines;
  create temp table _lines on commit drop as
    select (x ->> 'part_id')::uuid as part_id,
           (x ->> 'quantity')::integer as quantity,
           round(coalesce((x ->> 'price')::numeric, p.sell_price), 2) as price,
           p.name, p.part_no,
           ord
    from jsonb_array_elements(p_items) with ordinality as e (x, ord)
    left join parts p on p.id = (x ->> 'part_id')::uuid
    where coalesce(x ->> 'type', 'part') = 'part';

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
  if exists (select 1 from _lines where name is null) then
    raise exception 'A part on this bill no longer exists';
  end if;
  if exists (select 1 from _lines where price is null or price < 0) then
    raise exception 'Part prices cannot be negative';
  end if;
  if exists (select 1 from _svc where name = '') then
    raise exception 'Every service needs a description';
  end if;
  if exists (select 1 from _svc where price is null or price < 0) then
    raise exception 'Service charges cannot be negative';
  end if;

  -- Stock check per part (a part could be on more than one line).
  for v_line in
    select l.part_id, sum(l.quantity) as quantity, min(l.name) as name
    from _lines l
    group by l.part_id
  loop
    select quantity into v_available
    from stock_levels
    where part_id = v_line.part_id and branch_id = p_branch_id
    for update;

    if coalesce(v_available, 0) < v_line.quantity then
      raise exception 'Only % of % in stock', coalesce(v_available, 0), v_line.name;
    end if;
  end loop;

  select coalesce(sum(round(price * quantity, 2)), 0) into v_parts from _lines;
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

  insert into bill_items (bill_id, item_type, part_id, part_name, part_no, quantity,
                          unit_price, line_total, sort_order)
  select v_bill_id, 'part', part_id, name, part_no, quantity,
         price, round(price * quantity, 2), ord
  from _lines;

  update stock_levels s
  set quantity = s.quantity - l.quantity, updated_at = now()
  from (select part_id, sum(quantity) as quantity from _lines group by part_id) l
  where s.part_id = l.part_id and s.branch_id = p_branch_id;

  insert into bill_items (bill_id, item_type, service_id, part_name, quantity,
                          unit_price, line_total, sort_order)
  select v_bill_id, 'service', service_id, name, quantity,
         price, round(price * quantity, 2), ord
  from _svc;

  return v_bill_id;
end;
$$;

notify pgrst, 'reload schema';
