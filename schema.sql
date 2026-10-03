create table tokens (
  id bigserial primary key,
  shop text not null,
  name text not null,
  status text not null default 'waiting',
  created_at timestamptz default now()
);

alter table tokens enable row level security;
create policy "anyone reads" on tokens for select using (true);
create policy "anyone adds" on tokens for insert with check (true);
create policy "anyone updates" on tokens for update using (true);
