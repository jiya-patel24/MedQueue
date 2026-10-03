-- MedQueue database (Supabase). Matches the live database.
-- Don't run this on the live project, the tables already exist.

create extension if not exists pgcrypto with schema extensions;

create table shops (
  id bigserial primary key,
  name text not null,
  area text not null,
  pin_hash text not null,
  fails integer not null default 0,
  locked_until timestamptz,
  created_at timestamptz default now()
);

create table tokens (
  id bigserial primary key,
  shop_id bigint not null references shops(id) on delete cascade,
  num integer not null,
  name text not null check (char_length(name) between 1 and 40),
  status text not null default 'waiting'
    check (status in ('waiting', 'called', 'left', 'done', 'cancelled')),
  -- random secret returned only to the customer who joined,
  -- needed to read or cancel that token (ids alone are guessable)
  secret uuid not null default gen_random_uuid(),
  created_at timestamptz default now(),
  unique (shop_id, num)
);

-- RLS is on and there are no policies on purpose,
-- so the tables can only be used through the functions below
alter table shops enable row level security;
alter table tokens enable row level security;

-- the dropdown reads this view, so the PIN is never sent to the browser
create view shops_public as
  select id, name, area from shops;

-- checks a shop's PIN, 5 wrong tries locks the shop for 5 minutes
-- it returns the error text instead of raising it, otherwise the
-- wrong-try count would be rolled back and never saved
create or replace function auth_shop(p_shop bigint, p_pin text)
returns text
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare shop_row shops%rowtype;
begin
  select * into shop_row from shops where id = p_shop for update;
  if not found then return 'Shop not found'; end if;
  if shop_row.locked_until > now() then
    return 'Too many wrong PINs. Try again in 5 minutes.';
  end if;
  if shop_row.pin_hash = crypt(p_pin, shop_row.pin_hash) then
    update shops set fails = 0, locked_until = null where id = p_shop;
    return null;
  end if;
  update shops set
    fails = case when fails >= 4 then 0 else fails + 1 end,
    locked_until = case when fails >= 4 then now() + interval '5 minutes' end
  where id = p_shop;
  return 'Wrong PIN';
end
$$;

create or replace function register_shop(p_name text, p_area text, p_pin text)
returns bigint
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare new_id bigint;
begin
  p_name := trim(p_name);
  p_area := initcap(trim(p_area));
  if char_length(p_name) not between 2 and 60 then
    raise exception 'Shop name must be 2-60 characters';
  end if;
  if char_length(p_area) not between 2 and 60 then
    raise exception 'Area must be 2-60 characters';
  end if;
  if p_pin !~ '^[0-9]{6}$' then
    raise exception 'PIN must be exactly 6 digits';
  end if;
  if exists (select 1 from shops where lower(name) = lower(p_name) and area = p_area) then
    raise exception 'This shop is already registered in that area';
  end if;
  insert into shops(name, area, pin_hash)
  values (p_name, p_area, crypt(p_pin, gen_salt('bf')))
  returning id into new_id;
  return new_id;
end
$$;

create or replace function join_queue(p_shop bigint, p_name text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare new_num int; new_token_id bigint; new_secret uuid;
begin
  p_name := trim(p_name);
  if p_name = '' then raise exception 'Type your name first'; end if;
  if not exists (select 1 from shops where id = p_shop) then
    raise exception 'Shop not found';
  end if;
  -- lock so two people can't get the same number
  perform pg_advisory_xact_lock(p_shop);
  select coalesce(max(num), 0) + 1 into new_num from tokens where shop_id = p_shop;
  insert into tokens(shop_id, num, name)
  values (p_shop, new_num, left(p_name, 40))
  returning id, secret into new_token_id, new_secret;
  return jsonb_build_object('id', new_token_id, 'secret', new_secret, 'num', new_num);
end
$$;

create or replace function my_token(p_id bigint, p_secret uuid)
returns jsonb
language sql
security definer
set search_path to 'public'
as $$
  select jsonb_build_object(
    'num', t.num,
    'status', t.status,
    'shop', s.name,
    'area', s.area,
    'ahead', (select count(*) from tokens w
              where w.shop_id = t.shop_id and w.status = 'waiting' and w.id < t.id)
  )
  from tokens t join shops s on s.id = t.shop_id
  where t.id = p_id and t.secret = p_secret;
$$;

create or replace function leave_queue(p_id bigint, p_secret uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  update tokens set status = 'left'
  where id = p_id and secret = p_secret and status = 'waiting';
  return found;
end
$$;

create or replace function staff_queue(p_shop bigint, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare error_text text;
begin
  error_text := auth_shop(p_shop, p_pin);
  if error_text is not null then
    return jsonb_build_object('ok', false, 'msg', error_text);
  end if;
  return jsonb_build_object('ok', true, 'waiting', coalesce(
    (select jsonb_agg(jsonb_build_object('id', id, 'num', num, 'name', name) order by id)
     from tokens where shop_id = p_shop and status = 'waiting'),
    '[]'::jsonb));
end
$$;

create or replace function call_next(p_shop bigint, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare error_text text;
begin
  error_text := auth_shop(p_shop, p_pin);
  if error_text is not null then
    return jsonb_build_object('ok', false, 'msg', error_text);
  end if;
  update tokens set status = 'called' where id = (
    select id from tokens
    where shop_id = p_shop and status = 'waiting'
    order by id limit 1
    for update skip locked);
  return jsonb_build_object('ok', true);
end
$$;

-- permissions
revoke all on table shops, tokens from anon, authenticated;
revoke execute on function auth_shop(bigint, text) from public, anon, authenticated;

grant execute on function register_shop(text, text, text) to anon, authenticated;
grant execute on function join_queue(bigint, text) to anon, authenticated;
grant execute on function my_token(bigint, uuid) to anon, authenticated;
grant execute on function leave_queue(bigint, uuid) to anon, authenticated;
grant execute on function staff_queue(bigint, text) to anon, authenticated;
grant execute on function call_next(bigint, text) to anon, authenticated;

-- a new view gets write access by default, so remove it and keep SELECT only
revoke all on shops_public from anon, authenticated;
grant select on shops_public to anon, authenticated;
