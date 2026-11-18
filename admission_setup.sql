-- Admission module - supabase_setup.sql ke BAAD run karen
create table if not exists admission_store(id int primary key check (id=1), data jsonb not null default '{}', updated_at timestamptz default now());
alter table admission_store enable row level security;
drop policy if exists a_sel on admission_store; drop policy if exists a_ins on admission_store; drop policy if exists a_upd on admission_store;
create policy a_sel on admission_store for select to authenticated using (is_active_user());
create policy a_ins on admission_store for insert to authenticated with check (is_active_user());
create policy a_upd on admission_store for update to authenticated using (is_active_user());
