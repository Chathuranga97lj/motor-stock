-- Migration 013: totals for the Bills, Stock-ins and Returns screens,
-- added up in the database.
--
-- YOU MUST RUN THIS BY HAND: Supabase Dashboard > SQL Editor, after 012.
-- Safe to re-run. The app works without it, but then adds the totals up on
-- the phone from the downloaded rows, and the Supabase API sends at most
-- 1000 rows (500 for the bill / stock-in / return lists). Over 30 days or All
-- the Sales, Collected, Purchased, Paid and Returned cards then show too
-- little once a branch passes those numbers.
--
-- Each function follows the same rules as the tables' read policies: super
-- admin sees any branch, an admin only their own.

-- ---------- Bills: count, sales, parts, services, money collected ----------
-- Sales = total after returns of bills that are not cancelled.
-- Collected = payments received in the period less refunds given back for
-- returns, on bills that are not cancelled (as fetchCollected() did).

create or replace function public.bill_totals(
  p_branch_id uuid,
  p_from timestamptz default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_paid numeric(14, 2);
  v_refunded numeric(14, 2);
begin
  if not public.has_role() then
    raise exception 'You do not have access';
  end if;
  if not public.is_super_admin() and p_branch_id is distinct from public.my_branch_id() then
    raise exception 'You can only see your own branch';
  end if;

  select jsonb_build_object(
           'bills', count(*) filter (where status = 'completed'),
           'cancelled', count(*) filter (where status = 'cancelled'),
           'sales', coalesce(sum(total - returned_total) filter (where status = 'completed'), 0),
           'parts', coalesce(sum(parts_total) filter (where status = 'completed'), 0),
           'services', coalesce(sum(services_total) filter (where status = 'completed'), 0))
  into v_result
  from bills
  where branch_id = p_branch_id
    and (p_from is null or created_at >= p_from);

  select coalesce(sum(p.amount), 0) into v_paid
  from bill_payments p
  join bills b on b.id = p.bill_id
  where p.branch_id = p_branch_id
    and b.status = 'completed'
    and (p_from is null or p.created_at >= p_from);

  select coalesce(sum(r.refund_amount), 0) into v_refunded
  from bill_returns r
  join bills b on b.id = r.bill_id
  where r.branch_id = p_branch_id
    and b.status = 'completed'
    and (p_from is null or r.created_at >= p_from);

  return v_result || jsonb_build_object('collected', v_paid - v_refunded);
end;
$$;

-- ---------- Stock-ins: purchased and paid ----------
-- Purchased = total after returns of stock-ins that are not cancelled.
-- Paid = payments to suppliers in the period less refunds suppliers gave
-- back, on stock-ins that are not cancelled (as fetchPaid() did).
-- p_supplier_id: one supplier only, or null for all.

create or replace function public.purchase_totals(
  p_branch_id uuid,
  p_from timestamptz default null,
  p_supplier_id uuid default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_purchased numeric(14, 2);
  v_paid numeric(14, 2);
  v_refunded numeric(14, 2);
begin
  if not public.has_role() then
    raise exception 'You do not have access';
  end if;
  if not public.is_super_admin() and p_branch_id is distinct from public.my_branch_id() then
    raise exception 'You can only see your own branch';
  end if;

  select count(*), coalesce(sum(total - returned_total), 0)
  into v_count, v_purchased
  from purchases
  where branch_id = p_branch_id
    and status = 'completed'
    and (p_from is null or created_at >= p_from)
    and (p_supplier_id is null or supplier_id = p_supplier_id);

  select coalesce(sum(pp.amount), 0) into v_paid
  from purchase_payments pp
  join purchases p on p.id = pp.purchase_id
  where pp.branch_id = p_branch_id
    and p.status = 'completed'
    and (p_from is null or pp.created_at >= p_from)
    and (p_supplier_id is null or p.supplier_id = p_supplier_id);

  select coalesce(sum(r.refund_amount), 0) into v_refunded
  from purchase_returns r
  join purchases p on p.id = r.purchase_id
  where r.branch_id = p_branch_id
    and p.status = 'completed'
    and (p_from is null or r.created_at >= p_from)
    and (p_supplier_id is null or p.supplier_id = p_supplier_id);

  return jsonb_build_object(
    'stock_ins', v_count,
    'purchased', v_purchased,
    'paid', v_paid - v_refunded);
end;
$$;

-- ---------- Returns: count, value, refunds ----------
-- p_kind: 'customer' (bill returns) or 'supplier' (stock-in returns).

create or replace function public.return_totals(
  p_kind text,
  p_branch_id uuid,
  p_from timestamptz default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not public.has_role() then
    raise exception 'You do not have access';
  end if;
  if not public.is_super_admin() and p_branch_id is distinct from public.my_branch_id() then
    raise exception 'You can only see your own branch';
  end if;

  if p_kind = 'customer' then
    select jsonb_build_object(
             'returns', count(*),
             'value', coalesce(sum(return_value), 0),
             'refunded', coalesce(sum(refund_amount), 0))
    into v_result
    from bill_returns
    where branch_id = p_branch_id
      and (p_from is null or created_at >= p_from);
  elsif p_kind = 'supplier' then
    select jsonb_build_object(
             'returns', count(*),
             'value', coalesce(sum(return_value), 0),
             'refunded', coalesce(sum(refund_amount), 0))
    into v_result
    from purchase_returns
    where branch_id = p_branch_id
      and (p_from is null or created_at >= p_from);
  else
    raise exception 'Unknown return kind %', p_kind;
  end if;

  return v_result;
end;
$$;

-- ---------- Duplicate invoice check: use the index ----------
-- purchases_invoice_idx is on upper(invoice_no). create_purchase() always
-- saves invoice_no trimmed, so comparing upper(invoice_no) gives the same
-- answer as before and lets the index be used.

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
    and upper(invoice_no) = upper(btrim(p_invoice_no))
  order by created_at desc
  limit 1;
$$;

revoke execute on function public.bill_totals(uuid, timestamptz) from public, anon;
revoke execute on function public.purchase_totals(uuid, timestamptz, uuid) from public, anon;
revoke execute on function public.return_totals(text, uuid, timestamptz) from public, anon;
grant execute on function public.bill_totals(uuid, timestamptz) to authenticated;
grant execute on function public.purchase_totals(uuid, timestamptz, uuid) to authenticated;
grant execute on function public.return_totals(text, uuid, timestamptz) to authenticated;

notify pgrst, 'reload schema';
