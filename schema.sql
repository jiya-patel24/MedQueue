-- =====================================================================
-- MedQueue : database schema (Supabase / PostgreSQL)
--
-- Function bodies, the view definition, RLS status and the table columns
-- below come from the LIVE database (verified 2026-10-03).
-- Constraints, indexes and grants were verified as well. Section 9 holds
-- fixes that are NOT applied to the live database yet.
--
-- Run order for a fresh project:
--   extension -> tables -> RLS -> view -> helper -> RPC functions -> grants
-- Do NOT run this on the live project (the objects already exist).
-- =====================================================================

-- 1. Extension: crypt() / gen_salt() for hashing PINs ------------------
create extension if not exists pgcrypto with schema extensions;

-- 2. Tables -------------------------------------------------------------
create table shops (
  id           bigserial primary key,
  name         text not null,
  area         text not null,
  pin_hash     text not null,                 -- bcrypt hash, never the PIN
  fails        integer not null default 0,    -- wrong-PIN counter
  locked_until timestamptz,                   -- set after 5 wrong PINs
  created_at   timestamptz default now()
);

create table tokens (
  id         bigserial primary key,
  shop_id    bigint not null references shops(id) on delete cascade,
  num        integer not null,                -- per-shop number (#1, #2 ...)
  name       text not null check (char_length(name) between 1 and 40),
  status     text not null default 'waiting'
             check (status in ('waiting', 'called', 'left', 'done', 'cancelled')),
                                              -- the app only uses the first three
  created_at timestamptz default now(),
  unique (shop_id, num)
);

-- 3. Row Level Security -------------------------------------------------
-- Verified: RLS is ON for both tables and there are NO policies, so the
-- public key cannot read or write the tables directly. All access goes
-- through the security definer functions below.
alter table shops  enable row level security;
alter table tokens enable row level security;

-- 4. Public view for the shop dropdown (no pin_hash, no lock data) ------
create view shops_public as
  select id, name, area
  from shops;

-- 5. Internal helper: check a shop PIN, with lockout --------------------
-- Returns NULL if the PIN is right, otherwise an error message.
-- 5 wrong PINs in a row lock the shop for 5 minutes.
-- It RETURNS text (not raise) so the fails counter update is committed.
create or replace function public.auth_shop(p_shop bigint, p_pin text)
 returns text
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare s shops%rowtype;
begin
  select * into s from shops where id = p_shop for update;
  if not found then return 'Shop not found'; end if;
  if s.locked_until > now() then return 'Too many wrong PINs. Try again in 5 minutes.'; end if;
  if s.pin_hash = crypt(p_pin, s.pin_hash) then
    update shops set fails = 0, locked_until = null where id = p_shop;
    return null;
  end if;
  update shops set
    fails = case when fails >= 4 then 0 else fails + 1 end,
    locked_until = case when fails >= 4 then now() + interval '5 minutes' end
  where id = p_shop;
  return 'Wrong PIN';
end $function$;

-- 6. RPC functions called from index.html -------------------------------

create or replace function public.register_shop(p_name text, p_area text, p_pin text)
 returns bigint
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare sid bigint;
begin
  p_name := trim(p_name);
  p_area := initcap(trim(p_area));
  if char_length(p_name) not between 2 and 60 then raise exception 'Shop name must be 2-60 characters'; end if;
  if char_length(p_area) not between 2 and 60 then raise exception 'Area must be 2-60 characters'; end if;
  if p_pin !~ '^[0-9]{6}$' then raise exception 'PIN must be exactly 6 digits'; end if;
  if exists (select 1 from shops where lower(name) = lower(p_name) and area = p_area) then
    raise exception 'This shop is already registered in that area';
  end if;
  insert into shops(name, area, pin_hash)
  values (p_name, p_area, crypt(p_pin, gen_salt('bf'))) returning id into sid;
  return sid;
end $function$;

create or replace function public.join_queue(p_shop bigint, p_name text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare n int; tid bigint;
begin
  p_name := trim(p_name);
  if p_name = '' then raise exception 'Type your name first'; end if;
  perform pg_advisory_xact_lock(p_shop);          -- two people can't get the same number
  select coalesce(max(num), 0) + 1 into n from tokens where shop_id = p_shop;
  insert into tokens(shop_id, num, name) values (p_shop, n, left(p_name, 40)) returning id into tid;
  return jsonb_build_object('id', tid, 'num', n);
end $function$;

create or replace function public.my_token(p_id bigint)
 returns jsonb
 language sql
 security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object(
    'num', t.num, 'status', t.status, 'shop', s.name, 'area', s.area,
    'ahead', (select count(*) from tokens w
              where w.shop_id = t.shop_id and w.status = 'waiting' and w.id < t.id))
  from tokens t join shops s on s.id = t.shop_id where t.id = p_id;
$function$;

create or replace function public.leave_queue(p_id bigint)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  update tokens set status = 'left'
  where id = p_id and status = 'waiting';
  return found;
end $function$;

create or replace function public.staff_queue(p_shop bigint, p_pin text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare e text;
begin
  e := auth_shop(p_shop, p_pin);
  if e is not null then return jsonb_build_object('ok', false, 'msg', e); end if;
  return jsonb_build_object('ok', true, 'waiting', coalesce(
    (select jsonb_agg(jsonb_build_object('id', id, 'num', num, 'name', name) order by id)
     from tokens where shop_id = p_shop and status = 'waiting'), '[]'::jsonb));
end $function$;

create or replace function public.call_next(p_shop bigint, p_pin text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare e text;
begin
  e := auth_shop(p_shop, p_pin);
  if e is not null then return jsonb_build_object('ok', false, 'msg', e); end if;
  update tokens set status = 'called' where id = (
    select id from tokens where shop_id = p_shop and status = 'waiting'
    order by id limit 1 for update skip locked);
  return jsonb_build_object('ok', true);
end $function$;

-- 7. Permissions (verified live, except the view: see 9.1) -------------
-- The public key has no direct privileges on the tables.
revoke all on table shops, tokens from anon, authenticated;

-- The PIN checker is internal only (live: only postgres and service_role).
revoke execute on function auth_shop(bigint, text) from public, anon, authenticated;

-- The six functions the browser calls:
grant execute on function register_shop(text, text, text) to anon, authenticated;
grant execute on function join_queue(bigint, text)        to anon, authenticated;
grant execute on function my_token(bigint)                to anon, authenticated;
grant execute on function leave_queue(bigint)             to anon, authenticated;
grant execute on function staff_queue(bigint, text)       to anon, authenticated;
grant execute on function call_next(bigint, text)         to anon, authenticated;

-- The dropdown view: read only (live currently grants much more, see 9.1).
grant select on shops_public to anon, authenticated;

-- 8. Not part of this file ----------------------------------------------
-- public.rls_auto_enable() is an event trigger created by Supabase's
-- "automatically enable RLS" project setting. Supabase recreates it.
-- public.set_num() exists live but is an unused leftover (see section 9).

-- 9. FIXES NOT APPLIED TO THE LIVE DATABASE YET -------------------------

-- 9.1 shops_public is a simple one-table view, so Postgres treats it as
--     updatable. Live, anon and authenticated hold INSERT/UPDATE/DELETE on
--     it, and a view runs with its owner's rights, which skip RLS on `shops`.
--     The app only ever SELECTs from it, so remove everything else.
revoke all on shops_public from anon, authenticated;
grant select on shops_public to anon, authenticated;

-- 9.2 Remove the dead leftover (it references a column "shop" that no
--     longer exists and is not attached to any trigger).
-- drop function if exists public.set_num();