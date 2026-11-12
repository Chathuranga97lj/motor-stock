-- Migration 011: import parts, prices and opening stock from a sheet.
-- Run once in Supabase Dashboard > SQL Editor, after 010.
-- Safe to re-run.

-- The tidy-up used to compare names and part numbers:
-- trimmed, single spaces, upper case. Empty when null.
create or replace function public.import_key(p text)
returns text language sql immutable as $$
  select upper(regexp_replace(btrim(coalesce(p, '')), '\s+', ' ', 'g'));
$$;

-- Finds an existing part by name quickly during an import.
create index if not exists parts_import_key_idx on public.parts (public.import_key(name));

-- Imports parts from the rows of a sheet. Super admin only.
--
-- p_rows: [{ row, name, part_no, barcode, category, brand, model,
--            buy_price, sell_price, low_stock_level,
--            stock: { "<branch id>": quantity, ... } }, ...]
--   Blank cells are sent as null (or left out of stock).
-- p_dry_run: true = check only and report what would happen, save nothing.
-- p_update_stock: also set the stock of parts that are already in the app.
--
-- A row matches an existing part when the name and part no are the same
-- (ignoring case and extra spaces). A matched part gets the row's prices and
-- details (blank cells keep the current value); its stock changes only with
-- p_update_stock. A row with no match becomes a new part with the row's
-- quantities as opening stock. Unknown categories, brands and models are
-- added. Rows with a problem are skipped and reported; the rest are saved
-- together, or nothing is saved if the database stops with an error.
--
-- Returns { created, updated, skipped,
--           rows: [{ row, action: new|update|skip, message }],
--           new_categories, new_brands, new_models }.
create or replace function public.import_parts(
  p_rows jsonb,
  p_dry_run boolean default true,
  p_update_stock boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r jsonb;
  s record;
  v_row int;
  v_name text;
  v_part_no text;
  v_barcode text;
  v_cat text;
  v_brand text;
  v_model text;
  v_buy numeric;
  v_sell numeric;
  v_low int;
  v_key text;
  v_part_id uuid;
  v_part_brand uuid;
  v_cat_id uuid;
  v_brand_id uuid;
  v_model_id uuid;
  v_other text;
  v_message text;
  v_has_stock boolean;
  v_branches jsonb;
  v_seen jsonb := '{}';
  v_seen_codes jsonb := '{}';
  v_results jsonb[] := '{}';
  v_new_cats text[] := '{}';
  v_new_brands text[] := '{}';
  v_new_models text[] := '{}';
  v_created int := 0;
  v_updated int := 0;
  v_skipped int := 0;
begin
  if not public.is_super_admin() then
    raise exception 'Only the super admin can import parts';
  end if;
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'No rows to import';
  end if;
  if jsonb_array_length(p_rows) > 2000 then
    raise exception 'Import at most 2000 rows at a time';
  end if;

  select coalesce(jsonb_object_agg(id::text, name), '{}') into v_branches from branches;

  for r in select value from jsonb_array_elements(p_rows) loop
    v_row := (r->>'row')::int;
    v_message := null;
    v_part_id := null;
    v_cat_id := null;
    v_brand_id := null;
    v_model_id := null;

    v_name := nullif(regexp_replace(btrim(coalesce(r->>'name', '')), '\s+', ' ', 'g'), '');
    v_part_no := nullif(public.import_key(r->>'part_no'), '');
    v_barcode := nullif(btrim(coalesce(r->>'barcode', '')), '');
    v_cat := nullif(public.import_key(r->>'category'), '');
    v_brand := nullif(public.import_key(r->>'brand'), '');
    v_model := nullif(public.import_key(r->>'model'), '');
    v_buy := round((r->>'buy_price')::numeric, 2);
    v_sell := round((r->>'sell_price')::numeric, 2);
    v_low := (r->>'low_stock_level')::int;

    -- ---------- Checks (a failed check skips the row) ----------
    if v_name is null then
      v_message := 'No name';
    elsif v_model is not null and v_brand is null then
      v_message := 'Bike model needs a bike brand';
    elsif coalesce(v_buy, 0) < 0 or coalesce(v_sell, 0) < 0 then
      v_message := 'Price cannot be below 0';
    elsif coalesce(v_low, 0) < 0 then
      v_message := 'Low stock level cannot be below 0';
    end if;

    if v_message is null then
      for s in select key, value from jsonb_each(coalesce(r->'stock', '{}')) loop
        if not v_branches ? s.key then
          raise exception 'Branch not found. Close the import and open it again.';
        end if;
        if (s.value #>> '{}')::int < 0 then
          v_message := 'Quantity cannot be below 0';
        end if;
      end loop;
    end if;

    if v_message is null then
      v_key := public.import_key(v_name) || '|' || coalesce(v_part_no, '');
      if v_seen ? v_key then
        v_message := 'Same name and part no as row ' || (v_seen->>v_key);
      end if;
    end if;

    if v_message is null then
      select id, brand_id into v_part_id, v_part_brand
      from parts
      where public.import_key(name) = public.import_key(v_name)
        and public.import_key(part_no) = coalesce(v_part_no, '')
      order by created_at
      limit 1;

      if v_barcode is not null then
        if v_seen_codes ? v_barcode then
          v_message := 'Same barcode as row ' || (v_seen_codes->>v_barcode);
        else
          select name into v_other
          from parts
          where btrim(barcode) = v_barcode and id is distinct from v_part_id
          limit 1;
          if found then
            v_message := 'Barcode already used by ' || v_other;
          end if;
        end if;
      end if;
    end if;

    if v_message is not null then
      v_skipped := v_skipped + 1;
      v_results := array_append(v_results, jsonb_build_object(
        'row', v_row, 'action', 'skip', 'message', v_message));
      continue;
    end if;

    v_seen := v_seen || jsonb_build_object(v_key, v_row);
    if v_barcode is not null then
      v_seen_codes := v_seen_codes || jsonb_build_object(v_barcode, v_row);
    end if;

    -- ---------- Lists: find, or add (only when saving) ----------
    if v_cat is not null then
      select id into v_cat_id from categories where name = v_cat;
      if v_cat_id is null then
        if not v_cat = any (v_new_cats) then
          v_new_cats := v_new_cats || v_cat;
        end if;
        if not p_dry_run then
          insert into categories (name) values (v_cat)
          on conflict (name) do update set name = excluded.name
          returning id into v_cat_id;
        end if;
      end if;
    end if;

    if v_brand is not null then
      select id into v_brand_id from brands where name = v_brand;
      if v_brand_id is null then
        if not v_brand = any (v_new_brands) then
          v_new_brands := v_new_brands || v_brand;
        end if;
        if not p_dry_run then
          insert into brands (name) values (v_brand)
          on conflict (name) do update set name = excluded.name
          returning id into v_brand_id;
        end if;
      end if;
    end if;

    if v_model is not null then
      if v_brand_id is not null then
        select id into v_model_id from bike_models
        where brand_id = v_brand_id and name = v_model;
      end if;
      if v_model_id is null then
        if not (v_brand || ' ' || v_model) = any (v_new_models) then
          v_new_models := v_new_models || (v_brand || ' ' || v_model);
        end if;
        if not p_dry_run then
          insert into bike_models (brand_id, name) values (v_brand_id, v_model)
          on conflict (brand_id, name) do update set name = excluded.name
          returning id into v_model_id;
        end if;
      end if;
    end if;

    v_has_stock := exists (select 1 from jsonb_each(coalesce(r->'stock', '{}')));

    -- ---------- Save ----------
    if v_part_id is null then
      v_created := v_created + 1;
      if not p_dry_run then
        insert into parts (name, part_no, barcode, category_id, brand_id, bike_model_id,
                           buy_price, sell_price, low_stock_level)
        values (v_name, v_part_no, v_barcode, v_cat_id, v_brand_id, v_model_id,
                coalesce(v_buy, 0), coalesce(v_sell, 0), coalesce(v_low, 2))
        returning id into v_part_id;

        insert into stock_levels (part_id, branch_id, quantity)
        select v_part_id, key::uuid, (value #>> '{}')::int
        from jsonb_each(coalesce(r->'stock', '{}'))
        where (value #>> '{}')::int > 0;
      end if;
      v_results := array_append(v_results, jsonb_build_object('row', v_row, 'action', 'new'));
    else
      v_updated := v_updated + 1;
      if not p_dry_run then
        update parts set
          barcode = coalesce(v_barcode, barcode),
          category_id = coalesce(v_cat_id, category_id),
          brand_id = coalesce(v_brand_id, brand_id),
          -- A new brand without a model clears a model of the old brand.
          bike_model_id = case
            when v_model_id is not null then v_model_id
            when v_brand_id is not null and v_brand_id is distinct from v_part_brand then null
            else bike_model_id
          end,
          buy_price = coalesce(v_buy, buy_price),
          sell_price = coalesce(v_sell, sell_price),
          low_stock_level = coalesce(v_low, low_stock_level)
        where id = v_part_id;

        if p_update_stock then
          insert into stock_levels (part_id, branch_id, quantity)
          select v_part_id, key::uuid, (value #>> '{}')::int
          from jsonb_each(coalesce(r->'stock', '{}'))
          on conflict (part_id, branch_id)
          do update set quantity = excluded.quantity, updated_at = now();
        end if;
      end if;
      v_results := array_append(v_results, jsonb_build_object(
        'row', v_row, 'action', 'update',
        'message', case
          when v_has_stock and not p_update_stock then 'Already in the app: stock not changed'
          when v_has_stock then 'Already in the app: stock set from the sheet'
          else 'Already in the app'
        end));
    end if;
  end loop;

  return jsonb_build_object(
    'created', v_created,
    'updated', v_updated,
    'skipped', v_skipped,
    'rows', to_jsonb(v_results),
    'new_categories', to_jsonb(v_new_cats),
    'new_brands', to_jsonb(v_new_brands),
    'new_models', to_jsonb(v_new_models)
  );
end;
$$;

revoke execute on function public.import_parts(jsonb, boolean, boolean) from public, anon;
grant execute on function public.import_parts(jsonb, boolean, boolean) to authenticated;

notify pgrst, 'reload schema';
