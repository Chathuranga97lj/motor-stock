-- Migration 010: barcode / QR code on parts, for scanning.
-- Run once in Supabase Dashboard > SQL Editor, after 009. Safe to re-run.

alter table public.parts add column if not exists barcode text;

-- Blank codes are stored as null; one code belongs to one part.
update public.parts set barcode = null where btrim(barcode) = '';
create unique index if not exists parts_barcode_key
  on public.parts (btrim(barcode))
  where barcode is not null;

notify pgrst, 'reload schema';
