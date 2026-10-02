create extension if not exists pgcrypto;

create table if not exists public.profiles(
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,email text,
  role text not null default 'user' check(role in ('user','admin')),
  api_id text unique,
  api_key_hash text,
  api_key_last4 text,
  api_enabled boolean not null default true,
  created_at timestamptz default now()
);
alter table public.profiles add column if not exists api_enabled boolean not null default true;
alter table public.profiles add column if not exists api_key_last4 text;

create table if not exists public.wallets(user_id uuid primary key references public.profiles(id) on delete cascade,balance numeric(14,2) not null default 0,updated_at timestamptz default now());
create table if not exists public.categories(id uuid primary key default gen_random_uuid(),name text unique not null,slug text unique not null,is_active boolean default true,sort_order int default 0);
create table if not exists public.services(id uuid primary key default gen_random_uuid(),provider_service_id text unique not null,name text not null,type text default 'default',category_id uuid references public.categories(id),category text,provider_price numeric(14,4) default 0,markup_type text default 'percent' check(markup_type in ('percent','fixed')),markup_value numeric(14,4) default 0,sale_price numeric(14,4) default 0,min_qty bigint default 1,max_qty bigint default 1,refill boolean default false,description text,is_active boolean default true,sort_order int default 0,updated_at timestamptz default now());
create table if not exists public.deposits(id uuid primary key default gen_random_uuid(),user_id uuid references public.profiles(id) on delete cascade,amount numeric(14,2) not null,proof_path text,status text default 'pending' check(status in ('pending','approved','rejected')),reviewed_by uuid references public.profiles(id),reviewed_at timestamptz,created_at timestamptz default now());
create table if not exists public.orders(id uuid primary key default gen_random_uuid(),user_id uuid references public.profiles(id) on delete cascade,service_id uuid references public.services(id),target text not null,quantity bigint not null,comments text,sale_total numeric(14,2) not null,provider_cost numeric(14,2) not null,profit numeric(14,2) not null,provider_order_id text,provider_status text,status text default 'pending',error_message text,created_at timestamptz default now(),updated_at timestamptz default now());
alter table public.orders add column if not exists comments text;
create table if not exists public.transactions(id uuid primary key default gen_random_uuid(),user_id uuid references public.profiles(id) on delete set null,type text not null,amount numeric(14,2) not null,reference_id uuid,description text,created_at timestamptz default now());

-- Public/non-secret settings. Provider credentials are kept separately in providers.
create table if not exists public.panel_settings(
  key text primary key,
  value text,
  updated_at timestamptz default now(),
  updated_by uuid references public.profiles(id)
);

-- Provider credentials are server-side database data and are never included in GitHub/frontend config.
create table if not exists public.providers(
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  base_url text not null default 'https://fayupedia.id/api',
  api_id text,
  api_key text,
  is_active boolean not null default true,
  default_markup_type text not null default 'percent' check(default_markup_type in ('percent','fixed')),
  default_markup_value numeric(14,4) not null default 0,
  updated_at timestamptz default now(),
  updated_by uuid references public.profiles(id)
);

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$select exists(select 1 from public.profiles where id=auth.uid() and role='admin')$$;

alter table public.profiles enable row level security;
alter table public.wallets enable row level security;
alter table public.categories enable row level security;
alter table public.services enable row level security;
alter table public.deposits enable row level security;
alter table public.orders enable row level security;
alter table public.transactions enable row level security;
alter table public.panel_settings enable row level security;
alter table public.providers enable row level security;

drop policy if exists profiles_read on public.profiles;create policy profiles_read on public.profiles for select using(id=auth.uid() or public.is_admin());
drop policy if exists wallets_read on public.wallets;create policy wallets_read on public.wallets for select using(user_id=auth.uid() or public.is_admin());
drop policy if exists cat_read on public.categories;create policy cat_read on public.categories for select using(is_active or public.is_admin());
drop policy if exists svc_read on public.services;create policy svc_read on public.services for select using(is_active or public.is_admin());
drop policy if exists cat_admin_write on public.categories;create policy cat_admin_write on public.categories for all using(public.is_admin()) with check(public.is_admin());
drop policy if exists svc_admin_write on public.services;create policy svc_admin_write on public.services for all using(public.is_admin()) with check(public.is_admin());
drop policy if exists ord_admin_update on public.orders;create policy ord_admin_update on public.orders for update using(public.is_admin()) with check(public.is_admin());
drop policy if exists dep_read on public.deposits;create policy dep_read on public.deposits for select using(user_id=auth.uid() or public.is_admin());
drop policy if exists dep_insert on public.deposits;create policy dep_insert on public.deposits for insert with check(user_id=auth.uid());
drop policy if exists dep_update on public.deposits;create policy dep_update on public.deposits for update using(public.is_admin()) with check(public.is_admin());
drop policy if exists ord_read on public.orders;create policy ord_read on public.orders for select using(user_id=auth.uid() or public.is_admin());
drop policy if exists txn_read on public.transactions;create policy txn_read on public.transactions for select using(user_id=auth.uid() or public.is_admin());
-- Users can read public settings. Do not put secrets in this table.
drop policy if exists settings_read on public.panel_settings;create policy settings_read on public.panel_settings for select using(true);
drop policy if exists settings_admin_write on public.panel_settings;create policy settings_admin_write on public.panel_settings for all using(public.is_admin()) with check(public.is_admin());
-- Provider credentials are admin-only.
drop policy if exists provider_admin_all on public.providers;create policy provider_admin_all on public.providers for all using(public.is_admin()) with check(public.is_admin());

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$begin insert into public.profiles(id,full_name,email) values(new.id,coalesce(new.raw_user_meta_data->>'full_name','Member'),new.email);insert into public.wallets(user_id) values(new.id);return new;end$$;
drop trigger if exists on_auth_user_created on auth.users;create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.set_service_markup(p_service_id uuid,p_markup_type text,p_markup_value numeric) returns void language plpgsql security definer set search_path=public as $$declare p numeric;begin if not public.is_admin() then raise exception 'Akses ditolak';end if;select provider_price into p from public.services where id=p_service_id;if p is null then raise exception 'Service tidak ditemukan';end if;update public.services set markup_type=p_markup_type,markup_value=p_markup_value,sale_price=case when p_markup_type='percent' then p*(1+p_markup_value/100) else p+p_markup_value end,updated_at=now() where id=p_service_id;end$$;

create or replace function public.create_order(p_service_id uuid,p_target text,p_quantity bigint) returns uuid language plpgsql security definer set search_path=public as $$declare s public.services;bal numeric;total numeric;pc numeric;oid uuid;begin select * into s from public.services where id=p_service_id and is_active=true;if not found then raise exception 'Service tidak tersedia';end if;if p_quantity<s.min_qty or p_quantity>s.max_qty then raise exception 'Jumlah di luar batas';end if;total=round(s.sale_price/1000*p_quantity,2);pc=round(s.provider_price/1000*p_quantity,2);select balance into bal from public.wallets where user_id=auth.uid() for update;if bal<total then raise exception 'Saldo tidak mencukupi';end if;update public.wallets set balance=balance-total,updated_at=now() where user_id=auth.uid();insert into public.orders(user_id,service_id,target,quantity,sale_total,provider_cost,profit) values(auth.uid(),s.id,p_target,p_quantity,total,pc,total-pc) returning id into oid;insert into public.transactions(user_id,type,amount,reference_id,description) values(auth.uid(),'order',-total,oid,'Order layanan');return oid;end$$;

-- Same order logic for the public API, where the request is authenticated by api_id/api_key instead of a Supabase user JWT.
create or replace function public.create_api_order(p_user_id uuid,p_service_id uuid,p_target text,p_quantity bigint,p_comments text default null) returns uuid language plpgsql security definer set search_path=public as $$declare s public.services;bal numeric;total numeric;pc numeric;oid uuid;begin select * into s from public.services where id=p_service_id and is_active=true;if not found then raise exception 'Service tidak tersedia';end if;if p_quantity<s.min_qty or p_quantity>s.max_qty then raise exception 'Jumlah di luar batas';end if;total=round(s.sale_price/1000*p_quantity,2);pc=round(s.provider_price/1000*p_quantity,2);select balance into bal from public.wallets where user_id=p_user_id for update;if bal<total then raise exception 'Saldo tidak mencukupi';end if;update public.wallets set balance=balance-total,updated_at=now() where user_id=p_user_id;insert into public.orders(user_id,service_id,target,quantity,comments,sale_total,provider_cost,profit) values(p_user_id,s.id,p_target,p_quantity,p_comments,total,pc,total-pc) returning id into oid;insert into public.transactions(user_id,type,amount,reference_id,description) values(p_user_id,'order',-total,oid,'Order API');return oid;end$$;

create or replace function public.set_user_api_key(p_user_id uuid,p_api_id text,p_api_key text) returns void language plpgsql security definer set search_path=public as $$begin if not public.is_admin() then raise exception 'Akses ditolak';end if;update public.profiles set api_id=p_api_id,api_key_hash=encode(digest(p_api_key,'sha256'),'hex'),api_key_last4=right(p_api_key,4),api_enabled=true where id=p_user_id;if not found then raise exception 'User tidak ditemukan';end if;end$$;

create or replace function public.set_provider_settings(p_id uuid,p_name text,p_base_url text,p_api_id text,p_api_key text,p_markup_type text,p_markup_value numeric,p_active boolean) returns void language plpgsql security definer set search_path=public as $$begin if not public.is_admin() then raise exception 'Akses ditolak';end if;update public.providers set name=p_name,base_url=p_base_url,api_id=p_api_id,api_key=p_api_key,default_markup_type=p_markup_type,default_markup_value=p_markup_value,is_active=p_active,updated_at=now(),updated_by=auth.uid() where id=p_id;if not found then insert into public.providers(name,base_url,api_id,api_key,default_markup_type,default_markup_value,is_active,updated_by) values(p_name,p_base_url,p_api_id,p_api_key,p_markup_type,p_markup_value,p_active,auth.uid());end if;end$$;

create or replace function public.review_deposit(p_deposit_id uuid,p_approve boolean) returns void language plpgsql security definer set search_path=public as $$declare d public.deposits;begin if not public.is_admin() then raise exception 'Akses ditolak';end if;select * into d from public.deposits where id=p_deposit_id for update;if d.status<>'pending' then raise exception 'Deposit sudah diproses';end if;if p_approve then update public.deposits set status='approved',reviewed_by=auth.uid(),reviewed_at=now() where id=d.id;update public.wallets set balance=balance+d.amount,updated_at=now() where user_id=d.user_id;insert into public.transactions(user_id,type,amount,reference_id,description) values(d.user_id,'deposit',d.amount,d.id,'Deposit disetujui');else update public.deposits set status='rejected',reviewed_by=auth.uid(),reviewed_at=now() where id=d.id;end if;end$$;

-- Default public settings. Change these from Admin > Settings later.
insert into public.panel_settings(key,value) values
('panel_name','WSID SMM PANEL'),('owner_name','Witama Store.ID'),('dana_number',''),('dana_name','Witama Store.ID'),('qris_image_url',''),('support_whatsapp',''),('support_telegram',''),('support_instagram',''),('api_enabled','true')
on conflict(key) do nothing;

insert into public.providers(name,base_url,default_markup_type,default_markup_value,is_active)
values('FAYUPEDIA','https://fayupedia.id/api','percent',0,true)
on conflict(name) do nothing;

-- After creating the admin account:
-- update public.profiles set role='admin' where email='EMAIL_ADMIN_KAMU';
