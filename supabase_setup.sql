-- =====================================================================
--  Dar-ul-Sukun Donation in Kind (DIK) - Supabase setup
--  Supabase > SQL Editor > New query > poora paste karen > Run
--  (Dobara run karna safe hai)
-- =====================================================================

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text not null default '',
  role text not null default 'operator' check (role in ('operator','admin')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.settings (
  key text primary key,
  value text
);

create table if not exists public.donations (
  id bigserial primary key,
  code text unique not null,
  donation_date date not null,
  donor_name text not null,
  donor_mobile text not null,
  item text not null,
  quantity numeric,
  unit text,
  category text not null,
  est_value numeric,
  remarks text,
  status text not null default 'Active' check (status in ('Active','Cancelled')),
  cancel_reason text,
  entered_by uuid references auth.users(id),
  entered_by_name text,
  created_at timestamptz not null default now()
);
create index if not exists donations_date_idx on public.donations(donation_date);
create index if not exists donations_mobile_idx on public.donations(donor_mobile);

create table if not exists public.audit_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  user_id uuid,
  user_name text,
  action text not null,
  code text,
  old_value jsonb,
  new_value jsonb
);

create sequence if not exists public.dik_seq start 1;

-- ---------------------------------------------------------------- helpers
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin' and active);
$$;

create or replace function public.is_active_user() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and active);
$$;

-- naya Auth user banne par profile khud ban jaye (pehla user admin)
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, email, full_name, role, active)
  values (new.id, new.email,
          coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)),
          case when (select count(*) from profiles) = 0 then 'admin' else 'operator' end,
          true)
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------- RLS
alter table profiles  enable row level security;
alter table settings  enable row level security;
alter table donations enable row level security;
alter table audit_log enable row level security;

drop policy if exists p_sel on profiles;  create policy p_sel on profiles  for select to authenticated using (id = auth.uid() or is_admin());
drop policy if exists s_sel on settings;  create policy s_sel on settings  for select to authenticated using (is_active_user());
drop policy if exists d_sel on donations; create policy d_sel on donations for select to authenticated using (is_active_user());
drop policy if exists a_sel on audit_log; create policy a_sel on audit_log for select to authenticated using (is_admin());
-- insert/update/delete direct allow nahi: sab kuch neeche ke functions se hota hai

-- ---------------------------------------------------------------- functions
create or replace function public.create_donation(
  p_date date, p_name text, p_mobile text, p_item text, p_qty numeric, p_unit text,
  p_category text, p_value numeric, p_remarks text)
returns donations language plpgsql security definer set search_path = public as $$
declare me profiles; r donations;
begin
  select * into me from profiles where id = auth.uid() and active;
  if me.id is null then raise exception 'Account active nahi hai'; end if;
  if coalesce(trim(p_name),'') = '' or coalesce(trim(p_item),'') = '' then raise exception 'Donor name aur item zaroori hain'; end if;
  if p_mobile !~ '^03[0-9]{9}$' then raise exception 'Mobile number 03XXXXXXXXX format mein likhen'; end if;
  insert into donations (code, donation_date, donor_name, donor_mobile, item, quantity, unit, category, est_value, remarks, entered_by, entered_by_name)
  values ('DIK-' || lpad(nextval('dik_seq')::text, 4, '0'), p_date, trim(p_name), p_mobile, trim(p_item),
          p_qty, nullif(p_unit,''), p_category, p_value, nullif(p_remarks,''), me.id, me.full_name)
  returning * into r;
  insert into audit_log (user_id, user_name, action, code, new_value) values (me.id, me.full_name, 'create', r.code, to_jsonb(r));
  return r;
end $$;

create or replace function public.update_donation(
  p_code text, p_date date, p_name text, p_mobile text, p_item text, p_qty numeric, p_unit text,
  p_category text, p_value numeric, p_remarks text)
returns void language plpgsql security definer set search_path = public as $$
declare me profiles; o donations; n donations;
begin
  if not is_admin() then raise exception 'Sirf admin edit kar sakta hai'; end if;
  select * into me from profiles where id = auth.uid();
  select * into o from donations where code = p_code;
  if o.id is null then raise exception 'Entry nahi mili'; end if;
  if p_mobile !~ '^03[0-9]{9}$' then raise exception 'Mobile number 03XXXXXXXXX format mein likhen'; end if;
  update donations set donation_date = p_date, donor_name = trim(p_name), donor_mobile = p_mobile, item = trim(p_item),
    quantity = p_qty, unit = nullif(p_unit,''), category = p_category, est_value = p_value, remarks = nullif(p_remarks,'')
  where code = p_code returning * into n;
  insert into audit_log (user_id, user_name, action, code, old_value, new_value)
  values (me.id, me.full_name, 'edit', p_code,
    jsonb_build_object('donation_date',o.donation_date,'donor_name',o.donor_name,'donor_mobile',o.donor_mobile,'item',o.item,'quantity',o.quantity,'unit',o.unit,'category',o.category,'est_value',o.est_value,'remarks',o.remarks),
    jsonb_build_object('donation_date',n.donation_date,'donor_name',n.donor_name,'donor_mobile',n.donor_mobile,'item',n.item,'quantity',n.quantity,'unit',n.unit,'category',n.category,'est_value',n.est_value,'remarks',n.remarks));
end $$;

create or replace function public.cancel_donation(p_code text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare me profiles;
begin
  if not is_admin() then raise exception 'Sirf admin cancel kar sakta hai'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'Cancel ki wajah likhna zaroori hai'; end if;
  select * into me from profiles where id = auth.uid();
  update donations set status = 'Cancelled', cancel_reason = trim(p_reason) where code = p_code and status = 'Active';
  if not found then raise exception 'Entry nahi mili ya pehle se cancel hai'; end if;
  insert into audit_log (user_id, user_name, action, code, new_value)
  values (me.id, me.full_name, 'cancel', p_code, jsonb_build_object('cancel_reason', trim(p_reason)));
end $$;

create or replace function public.set_setting(p_key text, p_value text)
returns void language plpgsql security definer set search_path = public as $$
declare me profiles; old text;
begin
  if not is_admin() then raise exception 'Sirf admin'; end if;
  select * into me from profiles where id = auth.uid();
  select value into old from settings where key = p_key;
  insert into settings (key, value) values (p_key, p_value)
    on conflict (key) do update set value = excluded.value;
  insert into audit_log (user_id, user_name, action, code, old_value, new_value)
  values (me.id, me.full_name, 'setting', p_key, to_jsonb(old), to_jsonb(p_value));
end $$;

create or replace function public.set_user_role(p_user uuid, p_role text)
returns void language plpgsql security definer set search_path = public as $$
declare me profiles;
begin
  if not is_admin() then raise exception 'Sirf admin'; end if;
  if p_role not in ('operator','admin') then raise exception 'Ghalat role'; end if;
  if p_user = auth.uid() then raise exception 'Apna role khud nahi badal sakte'; end if;
  select * into me from profiles where id = auth.uid();
  update profiles set role = p_role where id = p_user;
  insert into audit_log (user_id, user_name, action, new_value) values (me.id, me.full_name, 'user_role', to_jsonb(p_role));
end $$;

create or replace function public.set_user_active(p_user uuid, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
declare me profiles;
begin
  if not is_admin() then raise exception 'Sirf admin'; end if;
  if p_user = auth.uid() then raise exception 'Apna account khud disable nahi kar sakte'; end if;
  select * into me from profiles where id = auth.uid();
  update profiles set active = p_active where id = p_user;
  insert into audit_log (user_id, user_name, action, new_value) values (me.id, me.full_name, 'user_active', to_jsonb(p_active));
end $$;

create or replace function public.set_user_name(p_user uuid, p_name text)
returns void language plpgsql security definer set search_path = public as $$
declare me profiles;
begin
  if not is_admin() then raise exception 'Sirf admin'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'Naam khali nahi ho sakta'; end if;
  select * into me from profiles where id = auth.uid();
  update profiles set full_name = trim(p_name) where id = p_user;
  insert into audit_log (user_id, user_name, action, new_value) values (me.id, me.full_name, 'user_name', to_jsonb(trim(p_name)));
end $$;

grant execute on function public.create_donation, public.update_donation, public.cancel_donation,
  public.set_setting, public.set_user_role, public.set_user_active, public.set_user_name to authenticated;

-- ---------------------------------------------------------------- default settings
insert into settings (key, value) values
  ('categories',  'Zakat,Sadaqa,Donation,Fitrana,Qurbani,Khairat'),
  ('units',       'Pcs,Kg,Bag,Box,Packet,Carton,Liter'),
  ('org_name',    'Dar-ul-Sukun'),
  ('org_tagline', 'Donation in Kind'),
  ('org_address', 'Head Office, Kashmir Road, Karachi')
on conflict (key) do nothing;
